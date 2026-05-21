-- ============================================================
-- DriverOnly gap — individual-level diagnostic
-- Goal: find BIM DriverOnly records missing from AWM so specific
--       parties can be looked up in source systems.
--
-- Bridge: UserName (BIM email) = user_name (AWM) — confirmed 274/274 match rate
-- CifId bridge was abandoned (only 103/3,117 = 3.3% match rate)
--
-- Confirmed results (run 2026-05-07):
--   Total BIM DriverOnly:  3,117
--   Total AWM DriverOnly:    274
--   Gap records:           2,843
--     1a - Never in AWM:       0  (all emails DO exist in AWM)
--     1b - Inactive/lapsed: 2,542
--      2 - Missing from vw_policy_driver: 2
--      3 - Classification diff (BIM=DR, EDW=NIN/ANI): 299
-- ============================================================

DROP TABLE IF EXISTS #bim_driveronly;
DROP TABLE IF EXISTS #awm_driveronly;
DROP TABLE IF EXISTS #inforce_base;
DROP TABLE IF EXISTS #creation_csr;
DROP TABLE IF EXISTS #csr_name_map;
GO


-- ============================================================
-- Step 1: BIM DriverOnly — one row per CifId
-- Same role filter as Section 4A of the main report.
-- Bridge key: u2.UserName (email) matches AWM asp_user_account_detail.user_name
-- ============================================================
SELECT DISTINCT
    u2.CifId
    , u2.UserName                                              AS bim_username
INTO #bim_driveronly
FROM ASPMembership_PRX..users u2 (NOLOCK)
INNER JOIN ASPMembership_PRX.dbo.UserAccountDetails uad (NOLOCK)
    ON uad.CifId = u2.CifId
INNER JOIN BIM_Reporting_Weekly.CIFDM.dim_person p (NOLOCK)
    ON p.psnd_clt_id_cif = u2.CifId
INNER JOIN BIM_Reporting_Weekly.CIFDM.fact_person_coverage pc (NOLOCK)
    ON pc.pcvf_psnd_id = p.psnd_id
INNER JOIN BIM_Reporting_Weekly.CIFDM.dim_policy_role pr (NOLOCK)
    ON pr.prld_id = pc.pcvf_prld_id
WHERE pc.pcvf_run_effective_date_td_id = (
    SELECT MAX(td_id) FROM BIM_Reporting_Weekly.CIFDM.dim_time
)
  AND uad.IsUpAndRunning = 1
  AND ((uad.CSRCompletedAccountCreation = 'true' AND uad.AgreeTC = 1)
       OR (uad.CSRCompletedAccountCreation = 'false'
           AND uad.KBAIdentificationStatus IN ('UserCompleted', 'NotAttemptedIgnore')))
GROUP BY u2.CifId, u2.UserName
HAVING SUM(CASE WHEN pr.prld_code IN ('NI', 'ANI') THEN 1 ELSE 0 END) = 0
   AND SUM(CASE WHEN pr.prld_code = 'DR'           THEN 1 ELSE 0 END) > 0;


-- ============================================================
-- Step 2: AWM inforce_base — same logic as main report
-- ============================================================
SELECT DISTINCT
    pual.party_anchor_id
    , uad.user_name
    , pil.party_anchor_id_master                            AS party_key
INTO #inforce_base
FROM (
    SELECT
        party_user_account_link_id
        , user_name
        , ROW_NUMBER() OVER (
            PARTITION BY party_user_account_link_id
            ORDER BY valid_from_date DESC, valid_to_date DESC
          ) AS rn
    FROM AWM.dbo.asp_user_account_detail
    WHERE is_up_and_running_indicator = 255
) uad
INNER JOIN AWM.dbo.party_user_account_link pual
    ON pual.party_user_account_link_id = uad.party_user_account_link_id
   AND uad.rn = 1
INNER JOIN AWM.dbo.party_id_same_as_link pil
    ON pil.party_anchor_id_duplicate = pual.party_anchor_id
INNER JOIN DWM.EDW.vw_policyholder vph
    ON vph.party_key = pil.party_anchor_id_master
INNER JOIN DWM.EDW.vw_policy vp
    ON vp.policy_term_key = vph.policy_term_key
   AND vp.policy_inforce_indicator = 1
   AND vp.effective_from_date <= CAST(GETDATE() AS DATE)
   AND vp.effective_to_date   >  CAST(GETDATE() AS DATE);


-- ============================================================
-- Step 3: AWM DriverOnly — one row per party_anchor_id
-- Same filter as Section 4 of the main report.
-- ============================================================
SELECT DISTINCT
    ib.party_anchor_id
    , ib.user_name                                          AS awm_username
    , ib.party_key
INTO #awm_driveronly
FROM #inforce_base ib
INNER JOIN (
    SELECT party_key
    FROM DWM.EDW.vw_policy_driver
    WHERE driver_inforce_indicator = 1
      AND effective_from_date <= CAST(GETDATE() AS DATE)
      AND effective_to_date   >  CAST(GETDATE() AS DATE)
    GROUP BY party_key
    HAVING SUM(CASE WHEN policyholder_type_code IN ('NIN', 'ANI') THEN 1 ELSE 0 END) = 0
) DriverOnly ON DriverOnly.party_key = ib.party_key;


-- ============================================================
-- Final: BIM DriverOnly records NOT in AWM DriverOnly
-- Bridge: b.bim_username (email) = ib.user_name (AWM)
-- gap_reason explains why AWM misses each record — useful for
-- pinpointing whether the issue is the bridge, coverage, or
-- a classification difference (DR in BIM vs NIN/ANI in EDW).
-- ============================================================
SELECT
    b.CifId
    , b.bim_username
    , ib.party_anchor_id                                    AS awm_party_anchor_id
    , ib.user_name                                          AS awm_username
    , CASE
        WHEN ib.party_anchor_id IS NULL AND raw_awm.user_name IS NULL
                                         THEN '1a - Email not in AWM at all (never enrolled)'
        WHEN ib.party_anchor_id IS NULL AND raw_awm.user_name IS NOT NULL
                                         THEN '1b - Email in AWM but not active/inforce (account inactive or policy lapsed)'
        WHEN pd.party_key      IS NULL   THEN '2 - In AWM inforce but absent from vw_policy_driver (coverage gap)'
        WHEN pd_ni.party_key   IS NOT NULL THEN '3 - In vw_policy_driver with NIN/ANI role (classification diff: BIM=DR, EDW=NIN/ANI)'
        ELSE                                  '4 - Other / investigate manually'
      END                                                   AS gap_reason
FROM #bim_driveronly b
LEFT JOIN #awm_driveronly a
    ON  a.awm_username = b.bim_username                     -- email bridge
LEFT JOIN #inforce_base ib
    ON  ib.user_name   = b.bim_username                     -- email bridge
LEFT JOIN (SELECT DISTINCT user_name FROM AWM.dbo.asp_user_account_detail) raw_awm
    ON  raw_awm.user_name = b.bim_username                  -- any AWM record, active or not
LEFT JOIN (
    SELECT DISTINCT ib2.party_key
    FROM #inforce_base ib2
    INNER JOIN DWM.EDW.vw_policy_driver pd2
        ON pd2.party_key = ib2.party_key
    WHERE pd2.driver_inforce_indicator = 1
      AND pd2.effective_from_date <= CAST(GETDATE() AS DATE)
      AND pd2.effective_to_date   >  CAST(GETDATE() AS DATE)
) pd     ON pd.party_key    = ib.party_key
LEFT JOIN (
    SELECT DISTINCT ib3.party_key
    FROM #inforce_base ib3
    INNER JOIN DWM.EDW.vw_policy_driver pd3
        ON pd3.party_key = ib3.party_key
    WHERE pd3.driver_inforce_indicator = 1
      AND pd3.effective_from_date <= CAST(GETDATE() AS DATE)
      AND pd3.effective_to_date   >  CAST(GETDATE() AS DATE)
      AND pd3.policyholder_type_code IN ('NIN', 'ANI')
) pd_ni  ON pd_ni.party_key = ib.party_key
WHERE a.awm_username IS NULL                                -- missing from AWM DriverOnly
ORDER BY gap_reason, b.CifId;


-- ============================================================
-- Reason 3 drill-down: 299 parties where BIM=DR but EDW=NIN/ANI
-- Shows exactly which policyholder_type_code EDW assigns and on
-- which policy — use awm_party_anchor_id to look up in source systems.
-- Escalate to EDW team as role classification discrepancy.
-- ============================================================
SELECT
    b.CifId
    , b.bim_username
    , ib.party_anchor_id                                      AS awm_party_anchor_id
    , pd3.policy_term_key
    , pd3.policyholder_type_code                              AS edw_role_code
    , pd3.effective_from_date                                 AS edw_role_from
    , pd3.effective_to_date                                   AS edw_role_to
FROM #bim_driveronly b
INNER JOIN #inforce_base ib
    ON  ib.user_name = b.bim_username
INNER JOIN DWM.EDW.vw_policy_driver pd3
    ON  pd3.party_key = ib.party_key
WHERE pd3.driver_inforce_indicator = 1
  AND pd3.effective_from_date <= CAST(GETDATE() AS DATE)
  AND pd3.effective_to_date   >  CAST(GETDATE() AS DATE)
  AND pd3.policyholder_type_code IN ('NIN', 'ANI')
  AND NOT EXISTS (
      SELECT 1
      FROM DWM.EDW.vw_policy_driver pd_check
      WHERE pd_check.party_key = ib.party_key
        AND pd_check.driver_inforce_indicator = 1
        AND pd_check.effective_from_date <= CAST(GETDATE() AS DATE)
        AND pd_check.effective_to_date   >  CAST(GETDATE() AS DATE)
        AND pd_check.policyholder_type_code NOT IN ('NIN', 'ANI')
  )
ORDER BY b.CifId, pd3.policy_term_key;
