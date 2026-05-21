--==========================================================================================================
-- TABLEAU USAGE
--   Initial SQL  : everything below up to and including the #Online_Accounts_Report step
--   Custom SQL   : SELECT * FROM #Online_Accounts_Report ORDER BY DateType, Date
--
-- Source of truth: online_accounts_edw_Self.sql  (CTE version)
-- Sections: Activation | Initiation | Inforce | DriverOnly
-- Note: CTEs are invalid in Tableau Custom SQL — this version replaces them with temp tables.
--==========================================================================================================

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Drop temp tables from any prior run
----------------------------------------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#csr_name_map')          IS NOT NULL DROP TABLE #csr_name_map;
IF OBJECT_ID('tempdb..#inforce_base')           IS NOT NULL DROP TABLE #inforce_base;
IF OBJECT_ID('tempdb..#creation_csr')           IS NOT NULL DROP TABLE #creation_csr;
IF OBJECT_ID('tempdb..#activation_events')      IS NOT NULL DROP TABLE #activation_events;
IF OBJECT_ID('tempdb..#initiation_events')      IS NOT NULL DROP TABLE #initiation_events;
IF OBJECT_ID('tempdb..#Online_Accounts_Report') IS NOT NULL DROP TABLE #Online_Accounts_Report;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Username → full name map (all event types)
-- Used in all four sections to resolve CSR usernames missing account_csr_full_name
-- on a specific event row (e.g., AAABRA returns NULL here and falls to UPPER(username) fallback).
----------------------------------------------------------------------------------------------------------

SELECT
    account_creation_completed_csr
    , MAX(account_csr_full_name)    AS resolved_full_name
INTO #csr_name_map
FROM AWM.DBO.USER_EVENT_DETAIL
WHERE NULLIF(account_csr_full_name, '') IS NOT NULL
GROUP BY account_creation_completed_csr;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Active online accounts with at least one inforce policy today
-- One row per (party_anchor_id, user_name, party_key).
-- Shared by Inforce (Section 3) and DriverOnly (Section 4).
----------------------------------------------------------------------------------------------------------

SELECT DISTINCT
    pual.party_anchor_id
    , uad.user_name
    , pil.party_anchor_id_master    AS party_key
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

----------------------------------------------------------------------------------------------------------
-- Initial SQL: CSR info from earliest Creation event per user
-- Shared by Inforce (Section 3) and DriverOnly (Section 4).
----------------------------------------------------------------------------------------------------------

SELECT
    DATA_1
    , ISNULL(account_creation_completed_csr, '')    AS account_creation_completed_csr
    , ISNULL(account_csr_department, '')             AS account_csr_department
    , ISNULL(account_csr_full_name, '')              AS account_csr_full_name
    , ISNULL(account_csr_supervisor_name, '')        AS account_csr_supervisor_name
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

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Section 1 — Activation
-- Date = earliest activation per user; CSR info from latest activation event.
-- Validated: delta vs BIM < 1%.
----------------------------------------------------------------------------------------------------------

SELECT
    raw.ActivationDate                                                   AS Date
    , 'Activation'                                                       AS DateType
    , CASE
        WHEN raw.account_creation_completed_csr <> ''
          AND raw.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN CASE
                    WHEN raw.account_csr_department = '' THEN 'Community Agents & Other'
                    ELSE raw.account_csr_department
                 END
        ELSE 'Customer Self Service'
      END                                                                AS CostCenter
    , CASE
        WHEN raw.account_creation_completed_csr <> ''
          AND raw.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(
                     NULLIF(raw.account_csr_full_name, '')
                     , nm.resolved_full_name
                     , UPPER(LTRIM(RTRIM(raw.account_creation_completed_csr)))
                 )
        ELSE 'Customer Self Service'
      END                                                                AS Employee
    , CASE
        WHEN raw.account_creation_completed_csr <> ''
          AND raw.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(NULLIF(raw.account_csr_supervisor_name, ''), 'OTHER')
        ELSE 'Customer Self Service'
      END                                                                AS Supervisor
    , COUNT(*)                                                           AS Total
INTO #activation_events
FROM (
    SELECT
        DATA_1                                                                      AS UserName
        , ISNULL(account_creation_completed_csr, '')                               AS account_creation_completed_csr
        , ISNULL(account_csr_department, '')                                        AS account_csr_department
        , ISNULL(account_csr_full_name, '')                                         AS account_csr_full_name
        , ISNULL(account_csr_supervisor_name, '')                                   AS account_csr_supervisor_name
        , CAST(MIN(EVENT_DATE) OVER (PARTITION BY DATA_1) AS DATE)                 AS ActivationDate
        , ROW_NUMBER() OVER (PARTITION BY DATA_1 ORDER BY EVENT_DATE DESC)         AS rn
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Activation'
) raw
LEFT JOIN #csr_name_map nm
    ON nm.account_creation_completed_csr = raw.account_creation_completed_csr
WHERE raw.rn = 1
  AND raw.ActivationDate > '2018-01-01'
GROUP BY
    raw.ActivationDate
    , raw.account_creation_completed_csr
    , raw.account_csr_department
    , raw.account_csr_full_name
    , raw.account_csr_supervisor_name
    , nm.resolved_full_name;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Section 2 — Initiation
-- Date = first Creation event per user.
-- Validated: delta vs BIM < 2% from 2021-01 onward. Pre-2021 AWM history is incomplete (~5-11% lower).
----------------------------------------------------------------------------------------------------------

SELECT
    raw.EventDate                                                        AS Date
    , 'Initiation'                                                       AS DateType
    , CASE
        WHEN raw.account_creation_completed_csr <> ''
          AND raw.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN CASE
                    WHEN raw.account_csr_department = '' THEN 'Community Agents & Other'
                    ELSE raw.account_csr_department
                 END
        ELSE 'Customer Self Service'
      END                                                                AS CostCenter
    , CASE
        WHEN raw.account_creation_completed_csr <> ''
          AND raw.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(
                     NULLIF(raw.account_csr_full_name, '')
                     , nm.resolved_full_name
                     , UPPER(LTRIM(RTRIM(raw.account_creation_completed_csr)))
                 )
        ELSE 'Customer Self Service'
      END                                                                AS Employee
    , CASE
        WHEN raw.account_creation_completed_csr <> ''
          AND raw.account_creation_completed_csr NOT LIKE 'ECOMM1%'
            THEN COALESCE(NULLIF(raw.account_csr_supervisor_name, ''), 'OTHER')
        ELSE 'Customer Self Service'
      END                                                                AS Supervisor
    , COUNT(*)                                                           AS Total
INTO #initiation_events
FROM (
    SELECT
        DATA_1
        , CAST(EVENT_DATE AS DATE)                                                 AS EventDate
        , ISNULL(account_creation_completed_csr, '')                               AS account_creation_completed_csr
        , ISNULL(account_csr_department, '')                                        AS account_csr_department
        , ISNULL(account_csr_full_name, '')                                         AS account_csr_full_name
        , ISNULL(account_csr_supervisor_name, '')                                   AS account_csr_supervisor_name
        , ROW_NUMBER() OVER (PARTITION BY DATA_1 ORDER BY EVENT_DATE ASC)          AS rn
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Creation'
      AND EVENT_DATE > '2018-01-01'
) raw
LEFT JOIN #csr_name_map nm
    ON nm.account_creation_completed_csr = raw.account_creation_completed_csr
WHERE raw.rn = 1
GROUP BY
    raw.EventDate
    , raw.account_creation_completed_csr
    , raw.account_csr_department
    , raw.account_csr_full_name
    , raw.account_csr_supervisor_name
    , nm.resolved_full_name;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Final report — UNION ALL of all four sections into one temp table
----------------------------------------------------------------------------------------------------------

SELECT
    Date
    , DateType
    , CostCenter
    , Employee
    , Supervisor
    , Total
INTO #Online_Accounts_Report
FROM (

    -- Section 1: Activation
    SELECT Date, DateType, CostCenter, Employee, Supervisor, Total
    FROM #activation_events

    UNION ALL

    -- Section 2: Initiation
    SELECT Date, DateType, CostCenter, Employee, Supervisor, Total
    FROM #initiation_events

    UNION ALL

    -- Section 3: Inforce
    -- Active online accounts with at least one inforce policy as of today.
    SELECT
        CAST(GETDATE() AS DATE)                                                  AS Date
        , 'Inforce'                                                              AS DateType
        , CASE
            WHEN ued.account_creation_completed_csr <> ''
              AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
                THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
            ELSE 'Customer Self Service'
          END                                                                    AS CostCenter
        , CASE
            WHEN ued.account_creation_completed_csr <> ''
              AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
                THEN COALESCE(
                         NULLIF(ued.account_csr_full_name, '')
                         , nm.resolved_full_name
                         , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                     )
            ELSE 'Customer Self Service'
          END                                                                    AS Employee
        , CASE
            WHEN ued.account_creation_completed_csr <> ''
              AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
                THEN COALESCE(NULLIF(ued.account_csr_supervisor_name, ''), 'OTHER')
            ELSE 'Customer Self Service'
          END                                                                    AS Supervisor
        , COUNT(DISTINCT ib.party_anchor_id)                                     AS Total
    FROM #inforce_base ib
    LEFT JOIN #creation_csr ued ON ued.DATA_1 = ib.user_name
    LEFT JOIN #csr_name_map nm  ON nm.account_creation_completed_csr = ued.account_creation_completed_csr
    GROUP BY
        CASE
            WHEN ued.account_creation_completed_csr <> ''
              AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
                THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
            ELSE 'Customer Self Service'
        END
        , CASE
            WHEN ued.account_creation_completed_csr <> ''
              AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
                THEN COALESCE(
                         NULLIF(ued.account_csr_full_name, '')
                         , nm.resolved_full_name
                         , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                     )
            ELSE 'Customer Self Service'
          END
        , CASE
            WHEN ued.account_creation_completed_csr <> ''
              AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
                THEN COALESCE(NULLIF(ued.account_csr_supervisor_name, ''), 'OTHER')
            ELSE 'Customer Self Service'
          END

    UNION ALL

    -- Section 4: DriverOnly
    -- Inforce accounts where the party holds only DR role (no NIN/ANI).
    -- Known delta vs BIM: ~43% lower — vw_policy_driver coverage gap (accepted structural difference).
    SELECT
        CAST(GETDATE() AS DATE)                                                  AS Date
        , 'DriverOnly'                                                           AS DateType
        , CASE
            WHEN ued.account_creation_completed_csr <> ''
              AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
                THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
            ELSE 'Customer Self Service'
          END                                                                    AS CostCenter
        , CASE
            WHEN ued.account_creation_completed_csr <> ''
              AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
                THEN COALESCE(
                         NULLIF(ued.account_csr_full_name, '')
                         , nm.resolved_full_name
                         , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                     )
            ELSE 'Customer Self Service'
          END                                                                    AS Employee
        , CASE
            WHEN ued.account_creation_completed_csr <> ''
              AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
                THEN COALESCE(NULLIF(ued.account_csr_supervisor_name, ''), 'OTHER')
            ELSE 'Customer Self Service'
          END                                                                    AS Supervisor
        , COUNT(DISTINCT ib.party_anchor_id)                                     AS Total
    FROM #inforce_base ib
    LEFT JOIN #creation_csr ued ON ued.DATA_1 = ib.user_name
    LEFT JOIN #csr_name_map nm  ON nm.account_creation_completed_csr = ued.account_creation_completed_csr
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
            WHEN ued.account_creation_completed_csr <> ''
              AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
                THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
            ELSE 'Customer Self Service'
        END
        , CASE
            WHEN ued.account_creation_completed_csr <> ''
              AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
                THEN COALESCE(
                         NULLIF(ued.account_csr_full_name, '')
                         , nm.resolved_full_name
                         , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                     )
            ELSE 'Customer Self Service'
          END
        , CASE
            WHEN ued.account_creation_completed_csr <> ''
              AND ued.account_creation_completed_csr NOT LIKE 'ECOMM1%'
                THEN COALESCE(NULLIF(ued.account_csr_supervisor_name, ''), 'OTHER')
            ELSE 'Customer Self Service'
          END

) all_sections;

--==========================================================================================================
-- Custom SQL (paste into Tableau Custom SQL dialog):
--   SELECT * FROM #Online_Accounts_Report ORDER BY DateType, Date
--==========================================================================================================
