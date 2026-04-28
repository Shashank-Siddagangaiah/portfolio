-- ============================================================
-- Online Accounts — Active Accounts by State & Product (EDW)
-- TABLEAU CUSTOM SQL VERSION — nested subqueries, no CTEs
-- (CTEs are invalid inside Tableau's wrapping SELECT * FROM (...))
-- Equivalent to: online_account_bim_Active_Accounts.sql
--
-- Output grain : one row per risk_state_code
-- ============================================================

SELECT
    risk_state_code                                                             AS PrimaryState,
    SUM(has_auto)                                                               AS Auto,
    SUM(has_home)                                                               AS Home,
    SUM(has_condo)                                                              AS Condo,
    SUM(has_renter)                                                             AS Renter,
    SUM(has_dp)                                                                 AS DP,
    SUM(has_ma)                                                                 AS Boat,
    SUM(has_umb)                                                                AS Umbrella,
    SUM(has_mh)                                                                 AS MH
FROM (
    -- customer_state: one row per (party, state), flagging which products they hold
    SELECT
        party_anchor_id
        , risk_state_code
        , MAX(CASE WHEN policy_symbol = 'CA'  AND product = 'Auto'              THEN 1 ELSE 0 END) AS has_auto
        , MAX(CASE WHEN policy_symbol = 'HO'  AND product = 'Home'              THEN 1 ELSE 0 END) AS has_home
        , MAX(CASE WHEN policy_symbol = 'HO'  AND product = 'Condo'             THEN 1 ELSE 0 END) AS has_condo
        , MAX(CASE WHEN policy_symbol = 'HO'  AND product = 'Renter'            THEN 1 ELSE 0 END) AS has_renter
        , MAX(CASE WHEN policy_symbol = 'DP'  AND product = 'Dwelling Property' THEN 1 ELSE 0 END) AS has_dp
        , MAX(CASE WHEN policy_symbol = 'MA'  AND product = 'Mariner'           THEN 1 ELSE 0 END) AS has_ma
        , MAX(CASE WHEN policy_symbol = 'UMB' AND product = 'Umbrella'          THEN 1 ELSE 0 END) AS has_umb
        , MAX(CASE WHEN policy_symbol = 'MH'  AND product = 'Mobile Home'       THEN 1 ELSE 0 END) AS has_mh
    FROM (
        -- inforce_online: active account parties with their inforce policies
        SELECT
            aa.party_anchor_id
            , vp.risk_state_code
            , vp.policy_symbol
            , vp.product
        FROM (
            -- active_accounts: latest active record per link_id
            -- is_up_and_running_indicator = 255 (tinyint all-bits-set = active, NOT 1)
            SELECT pual.party_anchor_id
            FROM (
                SELECT
                    party_user_account_link_id
                    , ROW_NUMBER() OVER (
                        PARTITION BY party_user_account_link_id
                        ORDER BY valid_from_date DESC, valid_to_date DESC
                    ) AS rn
                FROM AWM.dbo.asp_user_account_detail
                WHERE is_up_and_running_indicator = 255
            ) uad
            INNER JOIN AWM.dbo.party_user_account_link pual
                ON pual.party_user_account_link_id = uad.party_user_account_link_id
            WHERE uad.rn = 1
        ) aa
        -- party_anchor_id in party_user_account_link is the AWM DUPLICATE anchor;
        -- party_id_same_as_link maps it to the EDW MASTER party_key
        INNER JOIN AWM.dbo.party_id_same_as_link pil
            ON pil.party_anchor_id_duplicate = aa.party_anchor_id
        INNER JOIN DWM.EDW.vw_policyholder vph
            ON vph.party_key = pil.party_anchor_id_master
        INNER JOIN DWM.EDW.vw_policy vp
            ON vp.policy_term_key = vph.policy_term_key
        WHERE vp.policy_inforce_indicator = 1
          AND vp.effective_from_date <= CAST(GETDATE() AS DATE)
          AND vp.effective_to_date    >  CAST(GETDATE() AS DATE)
    ) inforce_online
    GROUP BY party_anchor_id, risk_state_code
) customer_state
GROUP BY risk_state_code
