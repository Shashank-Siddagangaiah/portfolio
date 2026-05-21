-- ============================================================
-- Self Service Account Report — EDW/AWM Rewrite
-- BIM equivalent: online_accounts_bim_Self_Service_Account.sql
-- Source: AWM.DBO.USER_EVENT_DETAIL, AWM active account chain → DWM.EDW views
--
-- Sections:
--   1. Activation  — EVENT_TYPE = 'Activation' (validated vs BIM, delta <1%)
--   2. Initiation  — EVENT_TYPE = 'Creation'   (validated vs BIM, delta <2% post-2021)
--   3. Inforce     — Active accounts with inforce policy as of today
--   4. DriverOnly  — Inforce accounts where CifId holds only DR policy role
--
-- NOTE: AWM Initiation data pre-2021 is ~5-11% lower than BIM (incomplete history).
--       Use 2021-01 onward as the reliable window for Initiation comparisons.
--
-- Employee/Supervisor dimensions:
--   CSR path  : account_csr_full_name, account_csr_supervisor_name (USER_EVENT_DETAIL)
--   Fallback  : account_creation_completed_csr (username) when CSR name fields not populated.
--   ECOMM1    : account_creation_completed_csr LIKE 'ECOMM1%' treated as Customer Self Service (web channel id, not a human CSR).
--   Note      : Agent path (community_agent) removed — agency-level values, not the enrolling person.
--
-- Performance optimisation (vs original):
--   Sections 1 & 2 : single USER_EVENT_DETAIL scan via MIN() OVER + ROW_NUMBER() CTE
--                    (was: two scans — one for MIN subquery, one for the main join)
--   Sections 3 & 4 : active-inforce join chain and Creation CSR pre-computed once
--                    into temp tables (#inforce_base, #creation_csr) before the
--                    final UNION ALL.  Both sections then read the cheap temp tables
--                    instead of re-running the cross-db EDW joins twice.
-- ============================================================


-- ============================================================
-- Temp-table setup (drop any leftovers from a prior run)
-- ============================================================
IF OBJECT_ID('tempdb..#inforce_base') IS NOT NULL DROP TABLE #inforce_base;
IF OBJECT_ID('tempdb..#creation_csr')  IS NOT NULL DROP TABLE #creation_csr;
IF OBJECT_ID('tempdb..#csr_name_map')  IS NOT NULL DROP TABLE #csr_name_map;


-- ============================================================
-- Pre-compute 1: Active accounts with at least one inforce policy today.
-- One row per distinct (party_anchor_id, user_name, party_key).
-- Shared by Section 3 (Inforce) and Section 4 (DriverOnly).
-- ============================================================
SELECT DISTINCT
    pual.party_anchor_id
    , uad.user_name
    , pil.party_anchor_id_master                 AS party_key
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
-- Pre-compute 2: CSR info from earliest Creation event per user.
-- Shared by Section 3 (Inforce) and Section 4 (DriverOnly).
-- ============================================================
SELECT
    DATA_1
    , ISNULL(account_creation_completed_csr, '') AS account_creation_completed_csr
    , ISNULL(account_csr_department, '')          AS account_csr_department
    , ISNULL(account_csr_full_name, '')           AS account_csr_full_name
    , ISNULL(account_csr_supervisor_name, '')     AS account_csr_supervisor_name
INTO #creation_csr
FROM (
    SELECT
        DATA_1
        , account_creation_completed_csr
        , account_csr_department
        , account_csr_full_name
        , account_csr_supervisor_name
        , ROW_NUMBER() OVER (PARTITION BY DATA_1 ORDER BY EVENT_DATE ASC) AS rn
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Creation'
) t
WHERE rn = 1;


-- ============================================================
-- Pre-compute 3: Username → full name map (AWM-only).
-- MAX(account_csr_full_name) per username across all event types.
-- Resolves usernames that fall back to raw text in Employee when
-- account_csr_full_name is NULL on the specific activation/creation row.
-- Usernames with no name in any event (e.g. AAABRA) remain NULL here
-- and fall through to the UPPER(username) fallback.
-- ============================================================
SELECT
    account_creation_completed_csr
    , MAX(account_csr_full_name) AS resolved_full_name
INTO #csr_name_map
FROM AWM.DBO.USER_EVENT_DETAIL
WHERE NULLIF(account_csr_full_name, '') IS NOT NULL
GROUP BY account_creation_completed_csr;


-- ============================================================
-- Final report
-- Sections 1 & 2 use CTEs (single scan each).
-- Sections 3 & 4 read from the pre-computed temp tables.
-- ============================================================
WITH ActivationCTE AS (
    -- One scan of USER_EVENT_DETAIL for Activation events.
    -- MIN() OVER gives earliest date; ROW_NUMBER DESC picks the latest event's CSR info.
    SELECT
        DATA_1                                                              AS UserName
        , ISNULL(account_creation_completed_csr, '')                       AS account_creation_completed_csr
        , ISNULL(account_csr_department, '')                               AS account_csr_department
        , ISNULL(account_csr_full_name, '')                                AS account_csr_full_name
        , ISNULL(account_csr_supervisor_name, '')                          AS account_csr_supervisor_name
        , CAST(MIN(EVENT_DATE) OVER (PARTITION BY DATA_1) AS DATE)         AS ActivationDate
        , ROW_NUMBER() OVER (PARTITION BY DATA_1 ORDER BY EVENT_DATE DESC) AS rn
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Activation'
),
InitiationCTE AS (
    -- One scan of USER_EVENT_DETAIL for Creation events.
    -- ROW_NUMBER ASC picks the earliest event row per user.
    SELECT
        DATA_1
        , CAST(EVENT_DATE AS DATE)                                         AS EventDate
        , ISNULL(account_creation_completed_csr, '')                       AS account_creation_completed_csr
        , ISNULL(account_csr_department, '')                               AS account_csr_department
        , ISNULL(account_csr_full_name, '')                                AS account_csr_full_name
        , ISNULL(account_csr_supervisor_name, '')                          AS account_csr_supervisor_name
        , ROW_NUMBER() OVER (PARTITION BY DATA_1 ORDER BY EVENT_DATE ASC)  AS rn
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Creation'
      AND EVENT_DATE > '2018-01-01'
)

-- ============================================================
-- SECTION 1: Activation
-- One row per user (DATA_1) using earliest activation date.
-- Validated: delta vs BIM < 1% across all months.
-- ============================================================
SELECT
    ActivationDate                               AS Date
    , 'Activation'                               AS DateType
    , CASE
        WHEN ActivationCTE.account_creation_completed_csr <> ''
          AND ActivationCTE.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN CASE
                    WHEN ActivationCTE.account_csr_department = '' THEN 'Community Agents & Other'
                    ELSE ActivationCTE.account_csr_department
                 END
        ELSE 'Customer Self Service'
      END                                        AS CostCenter
    , CASE
        WHEN ActivationCTE.account_creation_completed_csr <> ''
          AND ActivationCTE.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(
                     NULLIF(ActivationCTE.account_csr_full_name, '')
                     , nm.resolved_full_name
                     , UPPER(LTRIM(RTRIM(ActivationCTE.account_creation_completed_csr)))
                 )
        ELSE 'Customer Self Service'
      END                                        AS Employee
    , CASE
        WHEN ActivationCTE.account_creation_completed_csr <> ''
          AND ActivationCTE.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(NULLIF(ActivationCTE.account_csr_supervisor_name, ''), 'OTHER')
        ELSE 'Customer Self Service'
      END                                        AS Supervisor
    , COUNT(*)                                   AS Total
FROM ActivationCTE
LEFT JOIN #csr_name_map nm
    ON nm.account_creation_completed_csr = ActivationCTE.account_creation_completed_csr
WHERE rn = 1
  AND ActivationDate > '2018-01-01'
GROUP BY
    ActivationDate
    , ActivationCTE.account_creation_completed_csr
    , ActivationCTE.account_csr_department
    , ActivationCTE.account_csr_full_name
    , ActivationCTE.account_csr_supervisor_name
    , nm.resolved_full_name

UNION ALL

-- ============================================================
-- SECTION 2: Initiation
-- One row per user (DATA_1) using first creation event date.
-- Validated: delta vs BIM < 2% from 2021-01 onward.
-- Pre-2021 AWM history is incomplete (~5-11% lower than BIM).
-- ============================================================
SELECT
    EventDate                                    AS Date
    , 'Initiation'                               AS DateType
    , CASE
        WHEN InitiationCTE.account_creation_completed_csr <> ''
          AND InitiationCTE.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN CASE
                    WHEN InitiationCTE.account_csr_department = '' THEN 'Community Agents & Other'
                    ELSE InitiationCTE.account_csr_department
                 END
        ELSE 'Customer Self Service'
      END                                        AS CostCenter
    , CASE
        WHEN InitiationCTE.account_creation_completed_csr <> ''
          AND InitiationCTE.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(
                     NULLIF(InitiationCTE.account_csr_full_name, '')
                     , nm.resolved_full_name
                     , UPPER(LTRIM(RTRIM(InitiationCTE.account_creation_completed_csr)))
                 )
        ELSE 'Customer Self Service'
      END                                        AS Employee
    , CASE
        WHEN InitiationCTE.account_creation_completed_csr <> ''
          AND InitiationCTE.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(NULLIF(InitiationCTE.account_csr_supervisor_name, ''), 'OTHER')
        ELSE 'Customer Self Service'
      END                                        AS Supervisor
    , COUNT(*)                                   AS Total
FROM InitiationCTE
LEFT JOIN #csr_name_map nm
    ON nm.account_creation_completed_csr = InitiationCTE.account_creation_completed_csr
WHERE rn = 1
GROUP BY
    EventDate
    , InitiationCTE.account_creation_completed_csr
    , InitiationCTE.account_csr_department
    , InitiationCTE.account_csr_full_name
    , InitiationCTE.account_csr_supervisor_name
    , nm.resolved_full_name

UNION ALL

-- ============================================================
-- SECTION 3: Inforce
-- Active online accounts with inforce policy as of today.
-- Reads from pre-computed #inforce_base and #creation_csr.
-- ============================================================
SELECT
    CAST(GETDATE() AS DATE)                      AS Date
    , 'Inforce'                                  AS DateType
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
        ELSE 'Customer Self Service'
      END                                        AS CostCenter
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(
                     NULLIF(ued.account_csr_full_name, '')
                     , nm.resolved_full_name
                     , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                 )
        ELSE 'Customer Self Service'
      END                                        AS Employee
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(NULLIF(ued.account_csr_supervisor_name, ''), 'OTHER')
        ELSE 'Customer Self Service'
      END                                        AS Supervisor
    , COUNT(DISTINCT ib.party_anchor_id)         AS Total
FROM #inforce_base ib
LEFT JOIN #creation_csr ued ON ued.DATA_1 = ib.user_name
LEFT JOIN #csr_name_map nm  ON nm.account_creation_completed_csr = ued.account_creation_completed_csr
GROUP BY
    CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
        ELSE 'Customer Self Service'
    END
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(
                     NULLIF(ued.account_csr_full_name, '')
                     , nm.resolved_full_name
                     , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                 )
        ELSE 'Customer Self Service'
      END
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(NULLIF(ued.account_csr_supervisor_name, ''), 'OTHER')
        ELSE 'Customer Self Service'
      END

UNION ALL

-- ============================================================
-- SECTION 4: DriverOnly
-- Same as Inforce but restricted to parties whose only policy
-- role is DR (no NI/ANI roles).
-- Known delta vs BIM: ~43% lower (vw_policy_driver coverage gap).
-- See CLAUDE.md Continuous Learning for full root cause.
-- Reads from pre-computed #inforce_base and #creation_csr.
-- ============================================================
SELECT
    CAST(GETDATE() AS DATE)                      AS Date
    , 'DriverOnly'                               AS DateType
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
        ELSE 'Customer Self Service'
      END                                        AS CostCenter
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(
                     NULLIF(ued.account_csr_full_name, '')
                     , nm.resolved_full_name
                     , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                 )
        ELSE 'Customer Self Service'
      END                                        AS Employee
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(NULLIF(ued.account_csr_supervisor_name, ''), 'OTHER')
        ELSE 'Customer Self Service'
      END                                        AS Supervisor
    , COUNT(DISTINCT ib.party_anchor_id)         AS Total
FROM #inforce_base ib
LEFT JOIN #creation_csr ued ON ued.DATA_1 = ib.user_name
LEFT JOIN #csr_name_map nm  ON nm.account_creation_completed_csr = ued.account_creation_completed_csr
-- DriverOnly filter: require a positive DR signal in vw_policy_driver.
-- NOT EXISTS was tested but over-counts: parties absent from vw_policy_driver are NOT
-- necessarily DR — vw_policy_driver has ~13% coverage gap vs CIFDM.fact_person_coverage.
-- Known delta vs BIM: ~43% lower. Root cause: 3,971 BIM DR parties have no row in
-- vw_policy_driver (coverage gap), 128 show as NIN and 51 as ANI in EDW (definition diff).
-- Additional: 39,002 NULL policyholder_type_code parties pass HAVING (NULL ≠ NIN/ANI) — role unknown.
-- Gap under active investigation. No EDW view fully equivalent to dim_policy_role.
INNER JOIN (
    SELECT party_key
    FROM DWM.EDW.vw_policy_driver
    WHERE driver_inforce_indicator = 1
      AND effective_from_date <= CAST(GETDATE() AS DATE)
      AND effective_to_date   >  CAST(GETDATE() AS DATE)
    GROUP BY party_key
    HAVING SUM(CASE WHEN policyholder_type_code IN ('NIN', 'ANI') THEN 1 ELSE 0 END) = 0
) DriverOnly ON DriverOnly.party_key = ib.party_key
GROUP BY
    CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
        ELSE 'Customer Self Service'
    END
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(
                     NULLIF(ued.account_csr_full_name, '')
                     , nm.resolved_full_name
                     , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                 )
        ELSE 'Customer Self Service'
      END
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
          AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(NULLIF(ued.account_csr_supervisor_name, ''), 'OTHER')
        ELSE 'Customer Self Service'
      END
