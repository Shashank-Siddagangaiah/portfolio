-- ============================================================
-- Employee / Supervisor Dimension Validation
-- Compares AWM rewrite vs BIM for Employee and Supervisor output
-- across Inforce and DriverOnly sections.
--
-- Run order:
--   Step 1 — Section 3S: AWM sanity check (quick, run first)
--   Step 2 — Section 3A: BIM Inforce grouped by 3 dimensions
--   Step 3 — Section 3B: AWM Inforce grouped by 3 dimensions
--   Step 4 — Section 3C: Delta (uncomment temp table block)
--   Step 5 — Repeat 4A / 4B / 4C for DriverOnly
-- ============================================================


-- ============================================================
-- SECTION 0: AWM USER_EVENT_DETAIL — CSR Field Population Diagnostic
-- Run this first to understand why AWM has fewer cost centers and
-- why employee/supervisor values differ from BIM.
--
-- Root cause: when account_csr_full_name / account_csr_department /
-- account_csr_supervisor_name are NULL, the AWM query falls back to
-- community_agent.agent_name / territory_manager — completely different
-- values from the actual employee BIM reads from its XML + employee table.
-- ============================================================

-- Part A: Fill rate for each CSR field on Creation events
SELECT
    COUNT(*)                                                                            AS total_csr_creation_events
    , COUNT(CASE WHEN NULLIF(account_csr_full_name,       '') IS NOT NULL THEN 1 END)  AS has_full_name
    , COUNT(CASE WHEN NULLIF(account_csr_supervisor_name, '') IS NOT NULL THEN 1 END)  AS has_supervisor_name
    , COUNT(CASE WHEN NULLIF(account_csr_department,      '') IS NOT NULL THEN 1 END)  AS has_department
    , CAST(100.0 * COUNT(CASE WHEN NULLIF(account_csr_full_name,       '') IS NOT NULL THEN 1 END) / COUNT(*) AS DECIMAL(5,1)) AS pct_has_full_name
    , CAST(100.0 * COUNT(CASE WHEN NULLIF(account_csr_supervisor_name, '') IS NOT NULL THEN 1 END) / COUNT(*) AS DECIMAL(5,1)) AS pct_has_supervisor
    , CAST(100.0 * COUNT(CASE WHEN NULLIF(account_csr_department,      '') IS NOT NULL THEN 1 END) / COUNT(*) AS DECIMAL(5,1)) AS pct_has_department
FROM AWM.DBO.USER_EVENT_DETAIL
WHERE EVENT_TYPE = 'Creation'
  AND NULLIF(account_creation_completed_csr, '') IS NOT NULL;   -- CSR-created accounts only


-- Part B: Breakdown of which fallback path AWM uses per account
-- Shows how many accounts use name from XML vs agent fallback vs username
SELECT
    CASE
        WHEN NULLIF(ued.account_csr_full_name, '') IS NOT NULL     THEN '1-XML full name'
        WHEN AgentInfo.agent_name IS NOT NULL                      THEN '2-Agent fallback'
        ELSE                                                             '3-Username only'
    END                                                             AS employee_source
    , CASE
        WHEN NULLIF(ued.account_csr_supervisor_name, '') IS NOT NULL THEN '1-XML supervisor name'
        WHEN AgentInfo.territory_manager IS NOT NULL               THEN '2-Territory manager fallback'
        ELSE                                                             '3-OTHER'
    END                                                             AS supervisor_source
    , CASE
        WHEN NULLIF(ued.account_csr_department, '') IS NOT NULL    THEN '1-XML department'
        ELSE                                                             '2-Community Agents & Other'
    END                                                             AS department_source
    , COUNT(DISTINCT pual.party_anchor_id)                          AS party_count
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
        , account_csr_department
        , account_csr_full_name
        , account_csr_supervisor_name
        , ROW_NUMBER() OVER (PARTITION BY DATA_1 ORDER BY EVENT_DATE ASC) AS rn
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Creation'
) ued ON ued.DATA_1 = uad.user_name
      AND ued.rn = 1
LEFT JOIN (
    SELECT
        pac.policy_term_anchor_id
        , ca.agent_name
        , ca.territory_manager
        , ROW_NUMBER() OVER (
            PARTITION BY pac.policy_term_anchor_id
            ORDER BY pac.valid_from_date DESC
          ) AS rn
    FROM AWM.dbo.policy_agent_commission pac
    JOIN AWM.dbo.agent agt
        ON agt.agent_number = pac.agent_number
       AND agt.agency_party_role_anchor_id IS NOT NULL
       AND agt.valid_to_date = '9999-12-31'
    JOIN AWM.dbo.community_agent ca
        ON ca.agent_number = SUBSTRING(agt.agent_number, 4, 3)
       AND ca.valid_to_date = '9999-12-31'
       AND ca.account_status = 'Active'
    WHERE pac.valid_to_date = '9999-12-31'
) AgentInfo ON AgentInfo.policy_term_anchor_id = vp.policy_term_key
           AND AgentInfo.rn = 1
WHERE NULLIF(ued.account_creation_completed_csr, '') IS NOT NULL  -- CSR-created only
GROUP BY
    CASE
        WHEN NULLIF(ued.account_csr_full_name, '') IS NOT NULL     THEN '1-XML full name'
        WHEN AgentInfo.agent_name IS NOT NULL                      THEN '2-Agent fallback'
        ELSE                                                             '3-Username only'
    END
    , CASE
        WHEN NULLIF(ued.account_csr_supervisor_name, '') IS NOT NULL THEN '1-XML supervisor name'
        WHEN AgentInfo.territory_manager IS NOT NULL               THEN '2-Territory manager fallback'
        ELSE                                                             '3-OTHER'
    END
    , CASE
        WHEN NULLIF(ued.account_csr_department, '') IS NOT NULL    THEN '1-XML department'
        ELSE                                                             '2-Community Agents & Other'
    END
ORDER BY party_count DESC;


-- ============================================================
-- SECTION 3S: AWM Inforce — Sanity Check
-- Run this first. Verify no NULLs, check 'Customer Self Service'
-- rows have consistent Employee/Supervisor, confirm agent path
-- is contributing values (agent_name / territory_manager rows).
-- ============================================================

SELECT
    CostCenter
    , Employee
    , Supervisor
    , SUM(Total)    AS Total
FROM (
    SELECT
        CAST(GETDATE() AS DATE)                     AS Date
        , 'Inforce'                                 AS DateType
        , CASE
            WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
                THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
            ELSE 'Customer Self Service'
          END                                       AS CostCenter
        , CASE
            WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
                THEN COALESCE(
                         NULLIF(ued.account_csr_full_name, '')
                         , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                     )
            ELSE 'Customer Self Service'
          END                                       AS Employee
        , CASE
            WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
                THEN COALESCE(
                         NULLIF(ued.account_csr_supervisor_name, '')
                         , 'OTHER'
                     )
            ELSE 'Customer Self Service'
          END                                       AS Supervisor
        , COUNT(DISTINCT pual.party_anchor_id)      AS Total
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
            , account_csr_department
            , account_csr_full_name
            , account_csr_supervisor_name
            , ROW_NUMBER() OVER (PARTITION BY DATA_1 ORDER BY EVENT_DATE ASC) AS rn
        FROM AWM.DBO.USER_EVENT_DETAIL
        WHERE EVENT_TYPE = 'Creation'
    ) ued ON ued.DATA_1 = uad.user_name
          AND ued.rn = 1
    GROUP BY
        CASE
            WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
                THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
            ELSE 'Customer Self Service'
        END
        , CASE
            WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
                THEN COALESCE(
                         NULLIF(ued.account_csr_full_name, '')
                         , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                     )
            ELSE 'Customer Self Service'
          END
        , CASE
            WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
                THEN COALESCE(
                         NULLIF(ued.account_csr_supervisor_name, '')
                         , 'OTHER'
                     )
            ELSE 'Customer Self Service'
          END
) x
GROUP BY CostCenter, Employee, Supervisor
ORDER BY SUM(Total) DESC;


-- ============================================================
-- SECTION 3A: BIM — Inforce grouped by CostCenter + Employee + Supervisor
-- ============================================================

SELECT
    CASE
        WHEN CSRCompletedAccountCreation = 'true'
            THEN COALESCE(CostCenter, 'Community Agents & Other')
        ELSE 'Customer Self Service'
    END                                             AS CostCenter
    , CASE
        WHEN CSRCompletedAccountCreation = 'true' AND ProducerName IS NULL
            THEN COALESCE(Employee, CSRCompletedAccountCreationCSR)
        WHEN CSRCompletedAccountCreation = 'true' AND ProducerName IS NOT NULL
            THEN COALESCE(Employee, ProducerName)
        ELSE 'Customer Self Service'
    END                                             AS Employee
    , CASE
        WHEN CSRCompletedAccountCreation = 'true' AND AgencyName IS NULL
            THEN COALESCE(Supervisor, 'OTHER')
        WHEN CSRCompletedAccountCreation = 'true' AND AgencyName IS NOT NULL
            THEN COALESCE(Supervisor, AgencyName)
        ELSE 'Customer Self Service'
    END                                             AS Supervisor
    , COUNT(*)                                      AS BIM_Total
FROM (
    SELECT DISTINCT
        u.CifId
        , u.UserName
        , u.CSRCompletedAccountCreation
        , u.CSRCompletedAccountCreationCSR
        , CASE
            WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountFullName)[1]', 'varchar(50)'), '') <> ''
                THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountFullName)[1]', 'varchar(50)')
            ELSE e.pfsEmp_First_Last_Nm
          END                                       AS Employee
        , CASE
            WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountSupervisorName)[1]', 'varchar(50)'), '') <> ''
                THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountSupervisorName)[1]', 'varchar(50)')
            ELSE e.pfsEmp_Supervisor_First_Nm + ' ' + e.pfsEmp_Supervisor_Last_Nm
          END                                       AS Supervisor
        , CASE
            WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountDepartment)[1]', 'varchar(50)'), '') <> ''
                THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountDepartment)[1]', 'varchar(50)')
            ELSE e.pfsEmp_pfsCostCtr_Nm
          END                                       AS CostCenter
        , ROW_NUMBER() OVER (
            PARTITION BY u.CifId
            ORDER BY CASE
                WHEN u.CSRCompletedAccountCreation = 'true'
                    THEN DATEADD(day, DATEDIFF(day, 0, u.AgreeTCDate), 0)
                ELSE LEFT(u.KBAIdentificationDate, 21)
            END DESC
          )                                         AS rn
    FROM ASPMembership_PRX.dbo.UserAccountDetails u (NOLOCK)
    LEFT JOIN [BIM_Reporting_Daily].OneSource.pfs_Employee_new e (NOLOCK)
        ON u.CSRCompletedAccountCreationCSR = e.pfsEmp_Logon_Id
    LEFT JOIN [BIM_Reporting_Daily].MEM.Inforce_Pol ip (NOLOCK)
        ON ip.CifId = u.CifId
    WHERE ISNULL(ip.CifId, '') <> ''
      AND u.IsUpAndRunning = 1
      AND ((u.CSRCompletedAccountCreation = 'true' AND u.AgreeTC = 1)
           OR (u.CSRCompletedAccountCreation = 'false'
               AND u.KBAIdentificationStatus IN ('UserCompleted', 'NotAttemptedIgnore')))
) Detail
LEFT JOIN (
    SELECT
        REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', '')         AS AgencyName
        , RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM)     AS ProducerName
        , SU.SEC_USR_ID
    FROM Exceed_Reporting.XCD.SEC_USRS SU
    LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C1 (NOLOCK)
        ON C1.CLIENT_ID = SU.SEC_USR_CLT_ID
    LEFT JOIN Exceed_Reporting.XCD.CCM_PRODUCER CP (NOLOCK)
        ON CP.CPR_PDC_CLIENT_ID = C1.CLIENT_ID
    LEFT JOIN Exceed_Reporting.XCD.CCM_AGC_PRODUCER CAP (NOLOCK)
        ON CAP.CCM_PRODUCER_ID = CP.CCM_PRODUCER_ID
    LEFT JOIN Exceed_Reporting.XCD.CCM_CONTRACT CT (NOLOCK)
        ON CAP.CCM_AGENCY_ID = CT.CCM_AGENCY_ID
       AND CAP.CCM_PRODUCER_NBR = CT.CTT_CONTRACT_NBR
       AND CAP.HISTORY_VLD_NBR = 0
    LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C (NOLOCK)
        ON C.CLIENT_ID = CT.CTT_CTT_CLT_ID
    WHERE (C1.CICL_EXP_DT = '9999-12-31' OR C1.CICL_EXP_DT IS NULL)
      AND (C.CICL_EXP_DT  = '9999-12-31' OR C.CICL_EXP_DT IS NULL)
      AND (CT.CTT_CTT_EXP_DT > GETDATE() OR CT.CTT_CTT_EXP_DT IS NULL)
      AND CT.CCM_CONTRACT_ID IS NOT NULL
    GROUP BY
        REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', '')
        , RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM)
        , SU.SEC_USR_ID
) AgentDetail
    ON Detail.CSRCompletedAccountCreationCSR = AgentDetail.SEC_USR_ID
   AND ISNULL(Detail.Supervisor, '') = ''
WHERE rn = 1
GROUP BY
    CSRCompletedAccountCreation
    , CostCenter
    , Employee
    , CSRCompletedAccountCreationCSR
    , Supervisor
    , ProducerName
    , AgencyName
    , SEC_USR_ID
ORDER BY COUNT(*) DESC;


-- ============================================================
-- SECTION 3B: AWM — Inforce grouped by CostCenter + Employee + Supervisor
-- ============================================================

SELECT
    CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
            THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
        ELSE 'Customer Self Service'
    END                                             AS CostCenter
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
            THEN COALESCE(
                     NULLIF(ued.account_csr_full_name, '')
                     , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                 )
        ELSE 'Customer Self Service'
    END                                             AS Employee
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
            THEN COALESCE(
                     NULLIF(ued.account_csr_supervisor_name, '')
                     , 'OTHER'
                 )
        ELSE 'Customer Self Service'
    END                                             AS Supervisor
    , COUNT(DISTINCT pual.party_anchor_id)          AS AWM_Total
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
        , account_csr_department
        , account_csr_full_name
        , account_csr_supervisor_name
        , ROW_NUMBER() OVER (PARTITION BY DATA_1 ORDER BY EVENT_DATE ASC) AS rn
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Creation'
) ued ON ued.DATA_1 = uad.user_name
      AND ued.rn = 1
GROUP BY
    CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
            THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
        ELSE 'Customer Self Service'
    END
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
            THEN COALESCE(
                     NULLIF(ued.account_csr_full_name, '')
                     , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                 )
        ELSE 'Customer Self Service'
      END
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
            THEN COALESCE(
                     NULLIF(ued.account_csr_supervisor_name, '')
                     , 'OTHER'
                 )
        ELSE 'Customer Self Service'
      END
ORDER BY COUNT(DISTINCT pual.party_anchor_id) DESC;


-- ============================================================
-- SECTION 3C: Delta — BIM vs AWM Inforce by Employee + Supervisor
-- Uncomment the full block, run as one batch.
-- ============================================================

/*
DROP TABLE IF EXISTS #bim_inforce_emp;
SELECT
    CASE
        WHEN CSRCompletedAccountCreation = 'true'
            THEN COALESCE(CostCenter, 'Community Agents & Other')
        ELSE 'Customer Self Service'
    END                                             AS CostCenter
    , CASE
        WHEN CSRCompletedAccountCreation = 'true' AND ProducerName IS NULL
            THEN COALESCE(Employee, CSRCompletedAccountCreationCSR)
        WHEN CSRCompletedAccountCreation = 'true' AND ProducerName IS NOT NULL
            THEN COALESCE(Employee, ProducerName)
        ELSE 'Customer Self Service'
    END                                             AS Employee
    , CASE
        WHEN CSRCompletedAccountCreation = 'true' AND AgencyName IS NULL
            THEN COALESCE(Supervisor, 'OTHER')
        WHEN CSRCompletedAccountCreation = 'true' AND AgencyName IS NOT NULL
            THEN COALESCE(Supervisor, AgencyName)
        ELSE 'Customer Self Service'
    END                                             AS Supervisor
    , COUNT(*)                                      AS BIM_Total
INTO #bim_inforce_emp
FROM (
    SELECT DISTINCT u.CifId, u.UserName, u.CSRCompletedAccountCreation, u.CSRCompletedAccountCreationCSR
        , CASE WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountFullName)[1]', 'varchar(50)'), '') <> '' THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountFullName)[1]', 'varchar(50)') ELSE e.pfsEmp_First_Last_Nm END AS Employee
        , CASE WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountSupervisorName)[1]', 'varchar(50)'), '') <> '' THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountSupervisorName)[1]', 'varchar(50)') ELSE e.pfsEmp_Supervisor_First_Nm + ' ' + e.pfsEmp_Supervisor_Last_Nm END AS Supervisor
        , CASE WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountDepartment)[1]', 'varchar(50)'), '') <> '' THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountDepartment)[1]', 'varchar(50)') ELSE e.pfsEmp_pfsCostCtr_Nm END AS CostCenter
        , ROW_NUMBER() OVER (PARTITION BY u.CifId ORDER BY CASE WHEN u.CSRCompletedAccountCreation = 'true' THEN DATEADD(day, DATEDIFF(day, 0, u.AgreeTCDate), 0) ELSE LEFT(u.KBAIdentificationDate, 21) END DESC) AS rn
    FROM ASPMembership_PRX.dbo.UserAccountDetails u (NOLOCK)
    LEFT JOIN [BIM_Reporting_Daily].OneSource.pfs_Employee_new e (NOLOCK) ON u.CSRCompletedAccountCreationCSR = e.pfsEmp_Logon_Id
    LEFT JOIN [BIM_Reporting_Daily].MEM.Inforce_Pol ip (NOLOCK) ON ip.CifId = u.CifId
    WHERE ISNULL(ip.CifId, '') <> ''
      AND u.IsUpAndRunning = 1
      AND ((u.CSRCompletedAccountCreation = 'true' AND u.AgreeTC = 1)
           OR (u.CSRCompletedAccountCreation = 'false' AND u.KBAIdentificationStatus IN ('UserCompleted', 'NotAttemptedIgnore')))
) Detail
LEFT JOIN (
    SELECT REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', '') AS AgencyName, RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM) AS ProducerName, SU.SEC_USR_ID
    FROM Exceed_Reporting.XCD.SEC_USRS SU
    LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C1 (NOLOCK) ON C1.CLIENT_ID = SU.SEC_USR_CLT_ID
    LEFT JOIN Exceed_Reporting.XCD.CCM_PRODUCER CP (NOLOCK) ON CP.CPR_PDC_CLIENT_ID = C1.CLIENT_ID
    LEFT JOIN Exceed_Reporting.XCD.CCM_AGC_PRODUCER CAP (NOLOCK) ON CAP.CCM_PRODUCER_ID = CP.CCM_PRODUCER_ID
    LEFT JOIN Exceed_Reporting.XCD.CCM_CONTRACT CT (NOLOCK) ON CAP.CCM_AGENCY_ID = CT.CCM_AGENCY_ID AND CAP.CCM_PRODUCER_NBR = CT.CTT_CONTRACT_NBR AND CAP.HISTORY_VLD_NBR = 0
    LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C (NOLOCK) ON C.CLIENT_ID = CT.CTT_CTT_CLT_ID
    WHERE (C1.CICL_EXP_DT = '9999-12-31' OR C1.CICL_EXP_DT IS NULL) AND (C.CICL_EXP_DT = '9999-12-31' OR C.CICL_EXP_DT IS NULL)
      AND (CT.CTT_CTT_EXP_DT > GETDATE() OR CT.CTT_CTT_EXP_DT IS NULL) AND CT.CCM_CONTRACT_ID IS NOT NULL
    GROUP BY REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', ''), RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM), SU.SEC_USR_ID
) AgentDetail ON Detail.CSRCompletedAccountCreationCSR = AgentDetail.SEC_USR_ID AND ISNULL(Detail.Supervisor, '') = ''
WHERE rn = 1
GROUP BY CSRCompletedAccountCreation, CostCenter, Employee, CSRCompletedAccountCreationCSR, Supervisor, ProducerName, AgencyName, SEC_USR_ID;


DROP TABLE IF EXISTS #awm_inforce_emp;
SELECT
    CASE WHEN ISNULL(ued.account_creation_completed_csr, '') <> '' THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other') ELSE 'Customer Self Service' END AS CostCenter
    , CASE WHEN ISNULL(ued.account_creation_completed_csr, '') <> '' THEN COALESCE(NULLIF(ued.account_csr_full_name, ''), UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))) ELSE 'Customer Self Service' END AS Employee
    , CASE WHEN ISNULL(ued.account_creation_completed_csr, '') <> '' THEN COALESCE(NULLIF(ued.account_csr_supervisor_name, ''), 'OTHER') ELSE 'Customer Self Service' END AS Supervisor
    , COUNT(DISTINCT pual.party_anchor_id) AS AWM_Total
INTO #awm_inforce_emp
FROM (SELECT party_user_account_link_id, user_name, ROW_NUMBER() OVER (PARTITION BY party_user_account_link_id ORDER BY valid_from_date DESC, valid_to_date DESC) AS rn FROM AWM.dbo.asp_user_account_detail WHERE is_up_and_running_indicator = 255) uad
INNER JOIN AWM.dbo.party_user_account_link pual ON pual.party_user_account_link_id = uad.party_user_account_link_id AND uad.rn = 1
INNER JOIN AWM.dbo.party_id_same_as_link pil ON pil.party_anchor_id_duplicate = pual.party_anchor_id
INNER JOIN DWM.EDW.vw_policyholder vph ON vph.party_key = pil.party_anchor_id_master
INNER JOIN DWM.EDW.vw_policy vp ON vp.policy_term_key = vph.policy_term_key AND vp.policy_inforce_indicator = 1 AND vp.effective_from_date <= CAST(GETDATE() AS DATE) AND vp.effective_to_date > CAST(GETDATE() AS DATE)
LEFT JOIN (SELECT DATA_1, account_creation_completed_csr, account_csr_department, account_csr_full_name, account_csr_supervisor_name, ROW_NUMBER() OVER (PARTITION BY DATA_1 ORDER BY EVENT_DATE ASC) AS rn FROM AWM.DBO.USER_EVENT_DETAIL WHERE EVENT_TYPE = 'Creation') ued ON ued.DATA_1 = uad.user_name AND ued.rn = 1
GROUP BY
    CASE WHEN ISNULL(ued.account_creation_completed_csr, '') <> '' THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other') ELSE 'Customer Self Service' END
    , CASE WHEN ISNULL(ued.account_creation_completed_csr, '') <> '' THEN COALESCE(NULLIF(ued.account_csr_full_name, ''), UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))) ELSE 'Customer Self Service' END
    , CASE WHEN ISNULL(ued.account_creation_completed_csr, '') <> '' THEN COALESCE(NULLIF(ued.account_csr_supervisor_name, ''), 'OTHER') ELSE 'Customer Self Service' END;


-- Delta comparison — Inforce Employee/Supervisor
SELECT
    COALESCE(b.CostCenter,  a.CostCenter)           AS CostCenter
    , COALESCE(b.Employee,  a.Employee)             AS Employee
    , COALESCE(b.Supervisor, a.Supervisor)          AS Supervisor
    , ISNULL(b.BIM_Total, 0)                        AS BIM_Total
    , ISNULL(a.AWM_Total, 0)                        AS AWM_Total
    , ISNULL(a.AWM_Total, 0) - ISNULL(b.BIM_Total, 0)  AS Delta
    , CASE
        WHEN ISNULL(b.BIM_Total, 0) = 0 THEN NULL
        ELSE CAST(100.0 * (ISNULL(a.AWM_Total, 0) - ISNULL(b.BIM_Total, 0)) / b.BIM_Total AS DECIMAL(6,2))
      END                                           AS Delta_Pct
FROM #bim_inforce_emp b
FULL OUTER JOIN #awm_inforce_emp a
    ON  a.CostCenter  = b.CostCenter
    AND a.Employee    = b.Employee
    AND a.Supervisor  = b.Supervisor
ORDER BY ABS(ISNULL(a.AWM_Total, 0) - ISNULL(b.BIM_Total, 0)) DESC;
*/


-- ============================================================
-- SECTION 4A: BIM — DriverOnly grouped by CostCenter + Employee + Supervisor
-- ============================================================

SELECT
    CASE
        WHEN CSRCompletedAccountCreation = 'true'
            THEN COALESCE(CostCenter, 'Community Agents & Other')
        ELSE 'Customer Self Service'
    END                                             AS CostCenter
    , CASE
        WHEN CSRCompletedAccountCreation = 'true' AND ProducerName IS NULL
            THEN COALESCE(Employee, CSRCompletedAccountCreationCSR)
        WHEN CSRCompletedAccountCreation = 'true' AND ProducerName IS NOT NULL
            THEN COALESCE(Employee, ProducerName)
        ELSE 'Customer Self Service'
    END                                             AS Employee
    , CASE
        WHEN CSRCompletedAccountCreation = 'true' AND AgencyName IS NULL
            THEN COALESCE(Supervisor, 'OTHER')
        WHEN CSRCompletedAccountCreation = 'true' AND AgencyName IS NOT NULL
            THEN COALESCE(Supervisor, AgencyName)
        ELSE 'Customer Self Service'
    END                                             AS Supervisor
    , COUNT(*)                                      AS BIM_Total
FROM (
    SELECT DISTINCT
        u.CifId
        , u.UserName
        , u.CSRCompletedAccountCreation
        , u.CSRCompletedAccountCreationCSR
        , CASE
            WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountFullName)[1]', 'varchar(50)'), '') <> ''
                THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountFullName)[1]', 'varchar(50)')
            ELSE e.pfsEmp_First_Last_Nm
          END                                       AS Employee
        , CASE
            WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountSupervisorName)[1]', 'varchar(50)'), '') <> ''
                THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountSupervisorName)[1]', 'varchar(50)')
            ELSE e.pfsEmp_Supervisor_First_Nm + ' ' + e.pfsEmp_Supervisor_Last_Nm
          END                                       AS Supervisor
        , CASE
            WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountDepartment)[1]', 'varchar(50)'), '') <> ''
                THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountDepartment)[1]', 'varchar(50)')
            ELSE e.pfsEmp_pfsCostCtr_Nm
          END                                       AS CostCenter
        , ROW_NUMBER() OVER (
            PARTITION BY u.CifId
            ORDER BY CASE
                WHEN u.CSRCompletedAccountCreation = 'true'
                    THEN DATEADD(day, DATEDIFF(day, 0, u.AgreeTCDate), 0)
                ELSE LEFT(u.KBAIdentificationDate, 21)
            END DESC
          )                                         AS rn
    FROM ASPMembership_PRX.dbo.UserAccountDetails u (NOLOCK)
    LEFT JOIN [BIM_Reporting_Daily].OneSource.pfs_Employee_new e (NOLOCK)
        ON u.CSRCompletedAccountCreationCSR = e.pfsEmp_Logon_Id
    LEFT JOIN [BIM_Reporting_Daily].MEM.Inforce_Pol ip (NOLOCK)
        ON ip.CifId = u.CifId
    WHERE ISNULL(ip.CifId, '') <> ''
      AND u.IsUpAndRunning = 1
      AND ((u.CSRCompletedAccountCreation = 'true' AND u.AgreeTC = 1)
           OR (u.CSRCompletedAccountCreation = 'false'
               AND u.KBAIdentificationStatus IN ('UserCompleted', 'NotAttemptedIgnore')))
) Detail
LEFT JOIN (
    SELECT
        REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', '')         AS AgencyName
        , RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM)     AS ProducerName
        , SU.SEC_USR_ID
    FROM Exceed_Reporting.XCD.SEC_USRS SU
    LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C1 (NOLOCK) ON C1.CLIENT_ID = SU.SEC_USR_CLT_ID
    LEFT JOIN Exceed_Reporting.XCD.CCM_PRODUCER CP (NOLOCK) ON CP.CPR_PDC_CLIENT_ID = C1.CLIENT_ID
    LEFT JOIN Exceed_Reporting.XCD.CCM_AGC_PRODUCER CAP (NOLOCK) ON CAP.CCM_PRODUCER_ID = CP.CCM_PRODUCER_ID
    LEFT JOIN Exceed_Reporting.XCD.CCM_CONTRACT CT (NOLOCK)
        ON CAP.CCM_AGENCY_ID = CT.CCM_AGENCY_ID
       AND CAP.CCM_PRODUCER_NBR = CT.CTT_CONTRACT_NBR
       AND CAP.HISTORY_VLD_NBR = 0
    LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C (NOLOCK) ON C.CLIENT_ID = CT.CTT_CTT_CLT_ID
    WHERE (C1.CICL_EXP_DT = '9999-12-31' OR C1.CICL_EXP_DT IS NULL)
      AND (C.CICL_EXP_DT  = '9999-12-31' OR C.CICL_EXP_DT IS NULL)
      AND (CT.CTT_CTT_EXP_DT > GETDATE() OR CT.CTT_CTT_EXP_DT IS NULL)
      AND CT.CCM_CONTRACT_ID IS NOT NULL
    GROUP BY
        REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', '')
        , RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM)
        , SU.SEC_USR_ID
) AgentDetail
    ON Detail.CSRCompletedAccountCreationCSR = AgentDetail.SEC_USR_ID
   AND ISNULL(Detail.Supervisor, '') = ''
-- DriverOnly filter — BIM
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
    WHERE NI_ANI_COUNT = 0 AND DR_COUNT > 0
) dr ON dr.CifId = Detail.CifId
WHERE rn = 1
GROUP BY
    CSRCompletedAccountCreation
    , CostCenter
    , Employee
    , CSRCompletedAccountCreationCSR
    , Supervisor
    , ProducerName
    , AgencyName
    , SEC_USR_ID
ORDER BY COUNT(*) DESC;


-- ============================================================
-- SECTION 4B: AWM — DriverOnly grouped by CostCenter + Employee + Supervisor
-- ============================================================

SELECT
    CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
            THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
        ELSE 'Customer Self Service'
    END                                             AS CostCenter
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
            THEN COALESCE(
                     NULLIF(ued.account_csr_full_name, '')
                     , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                 )
        ELSE 'Customer Self Service'
    END                                             AS Employee
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
            THEN COALESCE(
                     NULLIF(ued.account_csr_supervisor_name, '')
                     , 'OTHER'
                 )
        ELSE 'Customer Self Service'
    END                                             AS Supervisor
    , COUNT(DISTINCT pual.party_anchor_id)          AS AWM_Total
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
        , account_csr_department
        , account_csr_full_name
        , account_csr_supervisor_name
        , ROW_NUMBER() OVER (PARTITION BY DATA_1 ORDER BY EVENT_DATE ASC) AS rn
    FROM AWM.DBO.USER_EVENT_DETAIL
    WHERE EVENT_TYPE = 'Creation'
) ued ON ued.DATA_1 = uad.user_name
      AND ued.rn = 1
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
            THEN COALESCE(NULLIF(ued.account_csr_department, ''), 'Community Agents & Other')
        ELSE 'Customer Self Service'
    END
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
            THEN COALESCE(
                     NULLIF(ued.account_csr_full_name, '')
                     , UPPER(LTRIM(RTRIM(ued.account_creation_completed_csr)))
                 )
        ELSE 'Customer Self Service'
      END
    , CASE
        WHEN ISNULL(ued.account_creation_completed_csr, '') <> ''
            THEN COALESCE(
                     NULLIF(ued.account_csr_supervisor_name, '')
                     , 'OTHER'
                 )
        ELSE 'Customer Self Service'
      END
ORDER BY COUNT(DISTINCT pual.party_anchor_id) DESC;


-- ============================================================
-- SECTION 4C: Delta — BIM vs AWM DriverOnly by Employee + Supervisor
-- Uncomment the full block, run as one batch.
-- NOTE: Known ~43% total count gap (vw_policy_driver coverage).
--       Focus on proportion within CSR vs CSS split, not absolute counts.
-- ============================================================

/*
DROP TABLE IF EXISTS #bim_driver_emp;
-- paste 4A query above with INTO #bim_driver_emp (remove ORDER BY)

DROP TABLE IF EXISTS #awm_driver_emp;
-- paste 4B query above with INTO #awm_driver_emp (remove ORDER BY)

SELECT
    COALESCE(b.CostCenter,   a.CostCenter)          AS CostCenter
    , COALESCE(b.Employee,   a.Employee)            AS Employee
    , COALESCE(b.Supervisor, a.Supervisor)          AS Supervisor
    , ISNULL(b.BIM_Total, 0)                        AS BIM_Total
    , ISNULL(a.AWM_Total, 0)                        AS AWM_Total
    , ISNULL(a.AWM_Total, 0) - ISNULL(b.BIM_Total, 0)  AS Delta
    , CASE
        WHEN ISNULL(b.BIM_Total, 0) = 0 THEN NULL
        ELSE CAST(100.0 * (ISNULL(a.AWM_Total, 0) - ISNULL(b.BIM_Total, 0)) / b.BIM_Total AS DECIMAL(6,2))
      END                                           AS Delta_Pct
FROM #bim_driver_emp b
FULL OUTER JOIN #awm_driver_emp a
    ON  a.CostCenter  = b.CostCenter
    AND a.Employee    = b.Employee
    AND a.Supervisor  = b.Supervisor
ORDER BY ABS(ISNULL(a.AWM_Total, 0) - ISNULL(b.BIM_Total, 0)) DESC;
*/
