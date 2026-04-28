-- ============================================================
-- Online Accounts — Active Accounts by State & Product (EDW)
-- Equivalent to: online_account_bim_Active_Accounts.sql
--
-- Output grain : one row per risk_state_code
-- Customer grain: counts distinct party_anchor_id (AWM)
--   who have is_up_and_running_indicator = 255 (active)
--   AND have at least one inforce policy of each product type
--
-- Sources:
--   AWM.dbo.asp_user_account_detail  → active account filter
--   AWM.dbo.party_user_account_link  → online account party_anchor_id (AWM-side)
--   AWM.dbo.party_id_same_as_link    → maps AWM party_anchor_id → EDW party_key
--   DWM.EDW.vw_policyholder          → links EDW party_key to policy_term_key
--   DWM.EDW.vw_policy                → product, state, inforce flag
--
-- JOIN STRATEGY (sourced from Paperless_report/new_paper_final.sql):
--   The online account party_anchor_id in party_user_account_link is the AWM DUPLICATE anchor.
--   party_id_same_as_link maps it back to the EDW MASTER party_key (party_anchor_id_master).
--   From there, vw_policyholder.party_key reaches vw_policy.policy_term_key.
--   This avoids policy_party_link / policy_anchor which only cover a small subset of policies.
-- ============================================================

DECLARE @as_of_date DATE = CAST(GETDATE() AS DATE);

-- -------------------------------------------------------
-- Step 1: Active online account holders → EDW party_key
--   Merged former Steps 1 & 2: asp_user_account_detail dedup +
--   party_user_account_link + party_id_same_as_link in one pass.
--   is_up_and_running_indicator = 255 → tinyint all-bits-set = active (NOT 1)
--   party_user_account_link.party_anchor_id  = the DUPLICATE anchor (AWM-side)
--   party_id_same_as_link.party_anchor_id_master = the MASTER anchor (EDW party_key)
-- -------------------------------------------------------
DROP TABLE IF EXISTS #party_edw;

SELECT
    pual.party_anchor_id,
    pil.party_anchor_id_master              AS edw_party_key
INTO #party_edw
FROM (
    SELECT
        party_user_account_link_id,
        ROW_NUMBER() OVER (
            PARTITION BY party_user_account_link_id
            ORDER BY valid_from_date DESC, valid_to_date DESC
        ) AS rn
    FROM AWM.dbo.asp_user_account_detail
    WHERE is_up_and_running_indicator = 255   -- 255 = all-bits-set = active
) uad
INNER JOIN AWM.dbo.party_user_account_link pual
    ON pual.party_user_account_link_id = uad.party_user_account_link_id
   AND uad.rn = 1
INNER JOIN AWM.dbo.party_id_same_as_link pil
    ON pil.party_anchor_id_duplicate = pual.party_anchor_id;

-- -------------------------------------------------------
-- Step 3: Link EDW party_key to inforce policies
--   vw_policyholder.party_key → policy_term_key → vw_policy
-- -------------------------------------------------------
DROP TABLE IF EXISTS #inforce_online;

SELECT
    pe.party_anchor_id,
    vp.risk_state_code,
    vp.policy_symbol,
    vp.product
INTO #inforce_online
FROM #party_edw pe
INNER JOIN DWM.EDW.vw_policyholder vph
    ON vph.party_key = pe.edw_party_key
INNER JOIN DWM.EDW.vw_policy vp
    ON vp.policy_term_key = vph.policy_term_key
WHERE vp.policy_inforce_indicator = 1
  AND vp.effective_from_date <= @as_of_date
  AND vp.effective_to_date    >  @as_of_date;

-- -------------------------------------------------------
-- Step 4: Pivot to customer+state grain
--   MAX(CASE ...) flags whether each customer has a given product inforce
--   vw_policy.product handles Home/Condo/Renter natively
--   (no dwelling form code join needed, unlike BIM)
-- -------------------------------------------------------
DROP TABLE IF EXISTS #customer_state;

SELECT
    party_anchor_id,
    risk_state_code,
    MAX(CASE WHEN policy_symbol = 'CA'  AND product = 'Auto'              THEN 1 ELSE 0 END) AS has_auto,
    MAX(CASE WHEN policy_symbol = 'HO'  AND product = 'Home'              THEN 1 ELSE 0 END) AS has_home,
    MAX(CASE WHEN policy_symbol = 'HO'  AND product = 'Condo'             THEN 1 ELSE 0 END) AS has_condo,
    MAX(CASE WHEN policy_symbol = 'HO'  AND product = 'Renter'            THEN 1 ELSE 0 END) AS has_renter,
    MAX(CASE WHEN policy_symbol = 'DP'  AND product = 'Dwelling Property' THEN 1 ELSE 0 END) AS has_dp,
    MAX(CASE WHEN policy_symbol = 'MA'  AND product = 'Mariner'           THEN 1 ELSE 0 END) AS has_ma,
    MAX(CASE WHEN policy_symbol = 'UMB' AND product = 'Umbrella'          THEN 1 ELSE 0 END) AS has_umb,
    MAX(CASE WHEN policy_symbol = 'MH'  AND product = 'Mobile Home'       THEN 1 ELSE 0 END) AS has_mh
INTO #customer_state
FROM #inforce_online
GROUP BY party_anchor_id, risk_state_code;

-- -------------------------------------------------------
-- VALIDATION: Step-by-step row counts
--   active_parties      ~295K expected
--   parties_with_edw_key: how many AWM parties map to an EDW party_key
--   parties_with_policy : should be in the 100K+ range if join is correct
-- -------------------------------------------------------
SELECT
    (SELECT COUNT(DISTINCT party_anchor_id) FROM #party_edw)        AS active_parties,
    (SELECT COUNT(DISTINCT party_anchor_id) FROM #inforce_online)   AS parties_with_inforce_policy,
    (SELECT COUNT(*)                        FROM #customer_state)   AS customer_state_rows;

-- -------------------------------------------------------
-- Final: Count customers per state per product
--   SUM(has_x) = count of customers with that product inforce
--   Matches BIM outer: SUM(CASE WHEN InforceX > 0 THEN 1 ...)
-- -------------------------------------------------------
SELECT
    risk_state_code AS PrimaryState,
    SUM(has_auto)   AS Auto,
    SUM(has_home)   AS Home,
    SUM(has_condo)  AS Condo,
    SUM(has_renter) AS Renter,
    SUM(has_dp)     AS DP,
    SUM(has_ma)     AS Boat,
    SUM(has_umb)    AS Umbrella,
    SUM(has_mh)     AS MH
FROM #customer_state
GROUP BY risk_state_code
ORDER BY risk_state_code;
