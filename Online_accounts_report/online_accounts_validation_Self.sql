-- ============================================================
-- Self Service Account — AWM vs BIM Validation
-- Run each section independently, then compare delta
-- ============================================================


-- ============================================================
-- SECTION 1A: BIM — Activation counts by Month + CostCenter bucket
-- ============================================================

SELECT
    FORMAT(CAST(ActivateDates.ActivateDate AS DATE), 'yyyy-MM')     AS YearMonth
    , CASE
        WHEN ISNULL(d.CSRCompletedAccountCreationCSR, '') <> '' THEN 'CSR'
        ELSE 'Customer Self Service'
      END                                                             AS CostCenterBucket
    , COUNT(DISTINCT e.CifId)                                         AS BIM_Count
FROM ASPMembership_PRX..UserEvents e (NOLOCK)
LEFT JOIN ASPMembership_PRX..UserEventDetails d (NOLOCK) ON e.Id = d.UserEventId
INNER JOIN (
    SELECT Data1, MIN(TimeStamp) AS ActivateDate
    FROM ASPMembership_PRX..UserEvents
    WHERE EventType = 'Activation'
    GROUP BY Data1
) AS ActivateDates ON ActivateDates.Data1 = e.Data1
WHERE e.EventType = 'Activation'
  AND ActivateDates.ActivateDate > '2018-01-01'
GROUP BY
    FORMAT(CAST(ActivateDates.ActivateDate AS DATE), 'yyyy-MM')
    , CASE
        WHEN ISNULL(d.CSRCompletedAccountCreationCSR, '') <> '' THEN 'CSR'
        ELSE 'Customer Self Service'
      END
ORDER BY YearMonth, CostCenterBucket;


-- ============================================================
-- SECTION 1B: AWM — Activation counts by Month + CostCenter bucket
-- ============================================================

SELECT
    FORMAT(CAST(ActivateDates.ActivateDate AS DATE), 'yyyy-MM')     AS YearMonth
    , CASE
        WHEN ISNULL(e.account_creation_completed_csr, '') <> ''
          AND e.account_creation_completed_csr NOT LIKE 'ECOMM1%'
          THEN 'CSR'
        ELSE 'Customer Self Service'
      END                                                             AS CostCenterBucket
    , COUNT(DISTINCT e.DATA_1)                                        AS AWM_Count
FROM AWM.DBO.USER_EVENT_DETAIL e
INNER JOIN (
    SELECT DATA_1, MIN(EVENT_DATE) AS ActivateDate
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Activation'
    GROUP BY DATA_1
) AS ActivateDates ON ActivateDates.DATA_1 = e.DATA_1
WHERE e.EVENT_TYPE = 'Activation'
  AND ActivateDates.ActivateDate > '2018-01-01'
GROUP BY
    FORMAT(CAST(ActivateDates.ActivateDate AS DATE), 'yyyy-MM')
    , CASE
        WHEN ISNULL(e.account_creation_completed_csr, '') <> ''
          AND e.account_creation_completed_csr NOT LIKE 'ECOMM1%'
          THEN 'CSR'
        ELSE 'Customer Self Service'
      END
ORDER BY YearMonth, CostCenterBucket;


-- ============================================================
-- SECTION 1C: Delta — AWM vs BIM Activation side by side
-- Paste results from 1A and 1B into temp tables, then run this
-- ============================================================

/*
DROP TABLE IF EXISTS #bim_activation;
SELECT
    FORMAT(CAST(ActivateDates.ActivateDate AS DATE), 'yyyy-MM')     AS YearMonth
    , CASE
        WHEN ISNULL(d.CSRCompletedAccountCreationCSR, '') <> '' THEN 'CSR'
        ELSE 'Customer Self Service'
      END                                                             AS CostCenterBucket
    , COUNT(DISTINCT e.CifId)                                         AS BIM_Count
INTO #bim_activation
FROM ASPMembership_PRX..UserEvents e (NOLOCK)
LEFT JOIN ASPMembership_PRX..UserEventDetails d (NOLOCK) ON e.Id = d.UserEventId
INNER JOIN (
    SELECT Data1, MIN(TimeStamp) AS ActivateDate
    FROM ASPMembership_PRX..UserEvents
    WHERE EventType = 'Activation'
    GROUP BY Data1
) AS ActivateDates ON ActivateDates.Data1 = e.Data1
WHERE e.EventType = 'Activation'
  AND ActivateDates.ActivateDate > '2018-01-01'
GROUP BY
    FORMAT(CAST(ActivateDates.ActivateDate AS DATE), 'yyyy-MM')
    , CASE
        WHEN ISNULL(d.CSRCompletedAccountCreationCSR, '') <> '' THEN 'CSR'
        ELSE 'Customer Self Service'
      END;

DROP TABLE IF EXISTS #awm_activation;
SELECT
    FORMAT(CAST(ActivateDates.ActivateDate AS DATE), 'yyyy-MM')     AS YearMonth
    , CASE
        WHEN ISNULL(e.account_creation_completed_csr, '') <> ''
          AND e.account_creation_completed_csr NOT LIKE 'ECOMM1%'
          THEN 'CSR'
        ELSE 'Customer Self Service'
      END                                                             AS CostCenterBucket
    , COUNT(DISTINCT e.DATA_1)                                        AS AWM_Count
INTO #awm_activation
FROM AWM.DBO.USER_EVENT_DETAIL e
INNER JOIN (
    SELECT DATA_1, MIN(EVENT_DATE) AS ActivateDate
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Activation'
    GROUP BY DATA_1
) AS ActivateDates ON ActivateDates.DATA_1 = e.DATA_1
WHERE e.EVENT_TYPE = 'Activation'
  AND ActivateDates.ActivateDate > '2018-01-01'
GROUP BY
    FORMAT(CAST(ActivateDates.ActivateDate AS DATE), 'yyyy-MM')
    , CASE
        WHEN ISNULL(e.account_creation_completed_csr, '') <> ''
          AND e.account_creation_completed_csr NOT LIKE 'ECOMM1%'
          THEN 'CSR'
        ELSE 'Customer Self Service'
      END;

-- Delta comparison
SELECT
    COALESCE(b.YearMonth, a.YearMonth)              AS YearMonth
    , COALESCE(b.CostCenterBucket, a.CostCenterBucket) AS CostCenterBucket
    , ISNULL(b.BIM_Count, 0)                        AS BIM_Count
    , ISNULL(a.AWM_Count, 0)                        AS AWM_Count
    , ISNULL(a.AWM_Count, 0) - ISNULL(b.BIM_Count, 0) AS Delta
    , CASE
        WHEN ISNULL(b.BIM_Count, 0) = 0 THEN NULL
        ELSE CAST(100.0 * (ISNULL(a.AWM_Count, 0) - ISNULL(b.BIM_Count, 0)) / b.BIM_Count AS DECIMAL(6,2))
      END                                           AS Delta_Pct
FROM #bim_activation b
FULL OUTER JOIN #awm_activation a
    ON a.YearMonth = b.YearMonth
    AND a.CostCenterBucket = b.CostCenterBucket
ORDER BY YearMonth, CostCenterBucket;
*/


-- NOTE: AWM Initiation data is incomplete before 2020-12.
-- Pre-2021 AWM counts are ~5-11% lower than BIM (systematic gap, not a query bug).
-- AWM USER_EVENT_DETAIL was likely not fully populated for historical Creation events.
-- Post-2021 variance is <2% — AWM is the reliable source from 2021-01 onward.
-- For reporting purposes, treat 2021+ as the valid comparison window.

-- ============================================================
-- SECTION 2A: BIM — Initiation counts by Month + CostCenter bucket
-- EventType = 'Creation', first event per user, date = event timestamp
-- ============================================================

SELECT
    FORMAT(CAST(e.TimeStamp AS DATE), 'yyyy-MM')                    AS YearMonth
    , CASE
        WHEN ISNULL(d.CSRCompletedAccountCreationCSR, '') <> '' THEN 'CSR'
        ELSE 'Customer Self Service'
      END                                                             AS CostCenterBucket
    , COUNT(DISTINCT e.Data1)                                         AS BIM_Count
FROM ASPMembership_PRX..UserEvents e (NOLOCK)
LEFT JOIN ASPMembership_PRX..UserEventDetails d (NOLOCK) ON e.Id = d.UserEventId
INNER JOIN (
    -- First creation event per user
    SELECT Data1, MIN(TimeStamp) AS FirstCreated
    FROM ASPMembership_PRX..UserEvents
    WHERE EventType = 'Creation'
    GROUP BY Data1
) AS FirstEvent ON FirstEvent.Data1 = e.Data1
                AND FirstEvent.FirstCreated = e.TimeStamp
WHERE e.EventType = 'Creation'
  AND e.TimeStamp > '2018-01-01'
GROUP BY
    FORMAT(CAST(e.TimeStamp AS DATE), 'yyyy-MM')
    , CASE
        WHEN ISNULL(d.CSRCompletedAccountCreationCSR, '') <> '' THEN 'CSR'
        ELSE 'Customer Self Service'
      END
ORDER BY YearMonth, CostCenterBucket;


-- ============================================================
-- SECTION 2B: AWM — Initiation counts by Month + CostCenter bucket
-- EVENT_TYPE = 'Creation', first event per user
-- ============================================================

SELECT
    FORMAT(CAST(e.EVENT_DATE AS DATE), 'yyyy-MM')                   AS YearMonth
    , CASE
        WHEN ISNULL(e.account_creation_completed_csr, '') <> ''
          AND e.account_creation_completed_csr NOT LIKE 'ECOMM1%'
          THEN 'CSR'
        ELSE 'Customer Self Service'
      END                                                             AS CostCenterBucket
    , COUNT(DISTINCT e.DATA_1)                                        AS AWM_Count
FROM AWM.DBO.USER_EVENT_DETAIL e
INNER JOIN (
    -- First creation event per user
    SELECT DATA_1, MIN(EVENT_DATE) AS FirstCreated
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Creation'
    GROUP BY DATA_1
) AS FirstEvent ON FirstEvent.DATA_1 = e.DATA_1
               AND FirstEvent.FirstCreated = e.EVENT_DATE
WHERE e.EVENT_TYPE = 'Creation'
  AND e.EVENT_DATE > '2018-01-01'
GROUP BY
    FORMAT(CAST(e.EVENT_DATE AS DATE), 'yyyy-MM')
    , CASE
        WHEN ISNULL(e.account_creation_completed_csr, '') <> ''
          AND e.account_creation_completed_csr NOT LIKE 'ECOMM1%'
          THEN 'CSR'
        ELSE 'Customer Self Service'
      END
ORDER BY YearMonth, CostCenterBucket;


-- ============================================================
-- SECTION 2C: Delta — AWM vs BIM Initiation side by side
-- Uncomment and run after 2A and 2B look reasonable
-- ============================================================

/*
DROP TABLE IF EXISTS #bim_initiation;
SELECT
    FORMAT(CAST(e.TimeStamp AS DATE), 'yyyy-MM')                    AS YearMonth
    , CASE
        WHEN ISNULL(d.CSRCompletedAccountCreationCSR, '') <> '' THEN 'CSR'
        ELSE 'Customer Self Service'
      END                                                             AS CostCenterBucket
    , COUNT(DISTINCT e.Data1)                                         AS BIM_Count
INTO #bim_initiation
FROM ASPMembership_PRX..UserEvents e (NOLOCK)
LEFT JOIN ASPMembership_PRX..UserEventDetails d (NOLOCK) ON e.Id = d.UserEventId
INNER JOIN (
    SELECT Data1, MIN(TimeStamp) AS FirstCreated
    FROM ASPMembership_PRX..UserEvents
    WHERE EventType = 'Creation'
    GROUP BY Data1
) AS FirstEvent ON FirstEvent.Data1 = e.Data1
                AND FirstEvent.FirstCreated = e.TimeStamp
WHERE e.EventType = 'Creation'
  AND e.TimeStamp > '2018-01-01'
GROUP BY
    FORMAT(CAST(e.TimeStamp AS DATE), 'yyyy-MM')
    , CASE
        WHEN ISNULL(d.CSRCompletedAccountCreationCSR, '') <> '' THEN 'CSR'
        ELSE 'Customer Self Service'
      END;

DROP TABLE IF EXISTS #awm_initiation;
SELECT
    FORMAT(CAST(e.EVENT_DATE AS DATE), 'yyyy-MM')                   AS YearMonth
    , CASE
        WHEN ISNULL(e.account_creation_completed_csr, '') <> ''
          AND e.account_creation_completed_csr NOT LIKE 'ECOMM1%'
          THEN 'CSR'
        ELSE 'Customer Self Service'
      END                                                             AS CostCenterBucket
    , COUNT(DISTINCT e.DATA_1)                                        AS AWM_Count
INTO #awm_initiation
FROM AWM.DBO.USER_EVENT_DETAIL e
INNER JOIN (
    SELECT DATA_1, MIN(EVENT_DATE) AS FirstCreated
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Creation'
    GROUP BY DATA_1
) AS FirstEvent ON FirstEvent.DATA_1 = e.DATA_1
               AND FirstEvent.FirstCreated = e.EVENT_DATE
WHERE e.EVENT_TYPE = 'Creation'
  AND e.EVENT_DATE > '2018-01-01'
GROUP BY
    FORMAT(CAST(e.EVENT_DATE AS DATE), 'yyyy-MM')
    , CASE
        WHEN ISNULL(e.account_creation_completed_csr, '') <> ''
          AND e.account_creation_completed_csr NOT LIKE 'ECOMM1%'
          THEN 'CSR'
        ELSE 'Customer Self Service'
      END;

-- Delta comparison
SELECT
    COALESCE(b.YearMonth, a.YearMonth)                  AS YearMonth
    , COALESCE(b.CostCenterBucket, a.CostCenterBucket)  AS CostCenterBucket
    , ISNULL(b.BIM_Count, 0)                            AS BIM_Count
    , ISNULL(a.AWM_Count, 0)                            AS AWM_Count
    , ISNULL(a.AWM_Count, 0) - ISNULL(b.BIM_Count, 0)  AS Delta
    , CASE
        WHEN ISNULL(b.BIM_Count, 0) = 0 THEN NULL
        ELSE CAST(100.0 * (ISNULL(a.AWM_Count, 0) - ISNULL(b.BIM_Count, 0)) / b.BIM_Count AS DECIMAL(6,2))
      END                                               AS Delta_Pct
FROM #bim_initiation b
FULL OUTER JOIN #awm_initiation a
    ON a.YearMonth = b.YearMonth
    AND a.CostCenterBucket = b.CostCenterBucket
ORDER BY YearMonth, CostCenterBucket;
*/


-- ============================================================
-- SECTION 3A: BIM — Inforce total (snapshot as of today)
-- UserAccountDetails WHERE IsUpAndRunning=1 + Inforce_Pol join
-- ============================================================

SELECT
    'Inforce'                                                           AS DateType
    , CASE
        WHEN u.CSRCompletedAccountCreation = 'true' THEN 'CSR'
        ELSE 'Customer Self Service'
      END                                                               AS CostCenterBucket
    , COUNT(DISTINCT u.CifId)                                           AS BIM_Count
FROM ASPMembership_PRX.dbo.UserAccountDetails u (NOLOCK)
INNER JOIN BIM_Reporting_Daily.MEM.Inforce_Pol ip (NOLOCK) ON ip.CifId = u.CifId
WHERE u.IsUpAndRunning = 1
  AND ((u.CSRCompletedAccountCreation = 'true' AND u.AgreeTC = 1)
       OR (u.CSRCompletedAccountCreation = 'false'
           AND u.KBAIdentificationStatus IN ('UserCompleted', 'NotAttemptedIgnore')))
GROUP BY
    CASE
        WHEN u.CSRCompletedAccountCreation = 'true' THEN 'CSR'
        ELSE 'Customer Self Service'
    END
ORDER BY CostCenterBucket;


-- ============================================================
-- SECTION 3B: AWM — Inforce total (snapshot as of today)
-- ============================================================

SELECT
    'Inforce'                                                           AS DateType
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
          THEN 'CSR'
        ELSE 'Customer Self Service'
      END                                                               AS CostCenterBucket
    , COUNT(DISTINCT pual.party_anchor_id)                              AS AWM_Count
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
   AND vp.effective_to_date > CAST(GETDATE() AS DATE)
LEFT JOIN (
    SELECT
        DATA_1
        , account_creation_completed_csr
        , ROW_NUMBER() OVER (PARTITION BY DATA_1 ORDER BY EVENT_DATE ASC) AS rn
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Creation'
) ued ON ued.DATA_1 = uad.user_name
      AND ued.rn = 1
GROUP BY
    CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
          THEN 'CSR'
        ELSE 'Customer Self Service'
    END
ORDER BY CostCenterBucket;


-- ============================================================
-- SECTION 3C: Delta — AWM vs BIM Inforce
-- ============================================================

/*
DROP TABLE IF EXISTS #bim_inforce;
-- paste 3A query with INTO #bim_inforce

DROP TABLE IF EXISTS #awm_inforce;
-- paste 3B query with INTO #awm_inforce

SELECT
    COALESCE(b.CostCenterBucket, a.CostCenterBucket)    AS CostCenterBucket
    , ISNULL(b.BIM_Count, 0)                            AS BIM_Count
    , ISNULL(a.AWM_Count, 0)                            AS AWM_Count
    , ISNULL(a.AWM_Count, 0) - ISNULL(b.BIM_Count, 0)  AS Delta
    , CASE
        WHEN ISNULL(b.BIM_Count, 0) = 0 THEN NULL
        ELSE CAST(100.0 * (ISNULL(a.AWM_Count, 0) - ISNULL(b.BIM_Count, 0)) / b.BIM_Count AS DECIMAL(6,2))
      END                                               AS Delta_Pct
FROM #bim_inforce b
FULL OUTER JOIN #awm_inforce a ON a.CostCenterBucket = b.CostCenterBucket;
*/


-- ============================================================
-- SECTION 4A: BIM — DriverOnly total (snapshot as of today)
-- Parties with DR role only (no NI/ANI) from CIFDM
-- ============================================================

SELECT
    'DriverOnly'                                                          AS DateType
    , CASE
        WHEN u.CSRCompletedAccountCreation = 'true' THEN 'CSR'
        ELSE 'Customer Self Service'
      END                                                                 AS CostCenterBucket
    , COUNT(DISTINCT u.CifId)                                             AS BIM_Count
FROM ASPMembership_PRX.dbo.UserAccountDetails u (NOLOCK)
INNER JOIN BIM_Reporting_Daily.MEM.Inforce_Pol ip (NOLOCK) ON ip.CifId = u.CifId
INNER JOIN (
    SELECT CifId
    FROM (
        SELECT u2.CifId
            , SUM(CASE WHEN pr.prld_code IN ('NI', 'ANI') THEN 1 ELSE 0 END) AS NI_ANI_COUNT
            , SUM(CASE WHEN pr.prld_code = 'DR'           THEN 1 ELSE 0 END) AS DR_COUNT
        FROM ASPMembership_PRX..users u2 (NOLOCK)
        JOIN BIM_Reporting_Weekly.CIFDM.dim_person p (NOLOCK)
            ON u2.CifId = p.psnd_clt_id_cif
        JOIN BIM_Reporting_Weekly.CIFDM.fact_person_coverage pc (NOLOCK)
            ON p.psnd_id = pc.pcvf_psnd_id
        JOIN BIM_Reporting_Weekly.CIFDM.dim_policy_role pr (NOLOCK)
            ON pc.pcvf_prld_id = pr.prld_id
        WHERE pc.pcvf_run_effective_date_td_id = (
            SELECT MAX(td_id) FROM BIM_Reporting_Weekly.CIFDM.dim_time
        )
        GROUP BY u2.CifId
    ) roles
    WHERE NI_ANI_COUNT = 0
      AND DR_COUNT > 0
) dr ON dr.CifId = u.CifId
WHERE u.IsUpAndRunning = 1
  AND ((u.CSRCompletedAccountCreation = 'true' AND u.AgreeTC = 1)
       OR (u.CSRCompletedAccountCreation = 'false'
           AND u.KBAIdentificationStatus IN ('UserCompleted', 'NotAttemptedIgnore')))
GROUP BY
    CASE
        WHEN u.CSRCompletedAccountCreation = 'true' THEN 'CSR'
        ELSE 'Customer Self Service'
    END
ORDER BY CostCenterBucket;


-- ============================================================
-- SECTION 4B: AWM — DriverOnly total (snapshot as of today)
-- Parties inforce on a policy but never as NIN or ANI = driver-only
-- ============================================================

SELECT
    'DriverOnly'                                                          AS DateType
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
          THEN 'CSR'
        ELSE 'Customer Self Service'
      END                                                                 AS CostCenterBucket
    , COUNT(DISTINCT pual.party_anchor_id)                                AS AWM_Count
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
   AND vp.effective_to_date > CAST(GETDATE() AS DATE)
LEFT JOIN (
    SELECT
        DATA_1
        , account_creation_completed_csr
        , ROW_NUMBER() OVER (PARTITION BY DATA_1 ORDER BY EVENT_DATE ASC) AS rn
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Creation'
) ued ON ued.DATA_1 = uad.user_name
      AND ued.rn = 1
-- INNER JOIN (positive signal required): NOT EXISTS was tested but inflates count 17x.
-- vw_policy_driver has ~13% coverage gap — absence from view ≠ driver-only.
-- Known delta vs BIM ~43% lower; accepted and documented. See CLAUDE.md.
INNER JOIN (
    SELECT party_key
    FROM DWM.EDW.vw_policy_driver
    WHERE driver_inforce_indicator = 1
      AND effective_from_date <= CAST(GETDATE() AS DATE)
      AND effective_to_date > CAST(GETDATE() AS DATE)
    GROUP BY party_key
    HAVING SUM(CASE WHEN policyholder_type_code IN ('NIN', 'ANI') THEN 1 ELSE 0 END) = 0
) DriverOnly ON DriverOnly.party_key = pil.party_anchor_id_master
GROUP BY
    CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
          THEN 'CSR'
        ELSE 'Customer Self Service'
    END
ORDER BY CostCenterBucket;


-- ============================================================
-- SECTION 4C: Delta — AWM vs BIM DriverOnly
-- ============================================================

/*
DROP TABLE IF EXISTS #bim_driveronly;
-- paste 4A query with INTO #bim_driveronly (remove ORDER BY)

DROP TABLE IF EXISTS #awm_driveronly;
-- paste 4B query with INTO #awm_driveronly (remove ORDER BY)

SELECT
    COALESCE(b.CostCenterBucket, a.CostCenterBucket)    AS CostCenterBucket
    , ISNULL(b.BIM_Count, 0)                            AS BIM_Count
    , ISNULL(a.AWM_Count, 0)                            AS AWM_Count
    , ISNULL(a.AWM_Count, 0) - ISNULL(b.BIM_Count, 0)  AS Delta
    , CASE
        WHEN ISNULL(b.BIM_Count, 0) = 0 THEN NULL
        ELSE CAST(100.0 * (ISNULL(a.AWM_Count, 0) - ISNULL(b.BIM_Count, 0)) / b.BIM_Count AS DECIMAL(6,2))
      END                                               AS Delta_Pct
FROM #bim_driveronly b
FULL OUTER JOIN #awm_driveronly a ON a.CostCenterBucket = b.CostCenterBucket;
*/
