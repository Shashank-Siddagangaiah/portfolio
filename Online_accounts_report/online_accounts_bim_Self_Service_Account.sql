SELECT ActivationDate AS Date
	, 'Activation' AS DateType
	, CASE WHEN ISNULL(CSRCompletedAccountCreationCSR, '') <> '' 
			THEN CASE WHEN ISNULL(CostCenter, '') = '' THEN 'Community Agents & Other' ELSE CostCenter END
			ELSE 'Customer Self Service'
			END AS CostCenter
	, CASE WHEN ISNULL(CSRCompletedAccountCreationCSR, '') <> '' THEN 
			CASE 
				WHEN ISNULL(Employee	, '') <> '' AND ISNULL(ProducerName, '') = '' THEN COALESCE(Employee, CSRCompletedAccountCreationCSR) 
				WHEN ISNULL(Employee	, '') = '' AND ISNULL(ProducerName, '') <> '' THEN  COALESCE(ProducerName, CSRCompletedAccountCreationCSR) 
				WHEN ISNULL(EMployee, '') = '' AND ISNULL(ProducerName, '') = '' THEN CSRCompletedAccountCreationCSR
			END 
		ELSE 'Customer Self Service'
		END AS Employee
	, CASE WHEN ISNULL(CSRCompletedAccountCreationCSR, '') <> '' THEN
			CASE 
				WHEN ISNULL(Supervisor, '') <> '' AND ISNULL(AgencyName, '') = '' THEN COALESCE(Supervisor, CSRCompletedAccountCreationCSR) 
				WHEN ISNULL(Supervisor, '') = '' AND ISNULL(AgencyName, '') <> '' THEN  COALESCE(AgencyName, CSRCompletedAccountCreationCSR) 
				WHEN ISNULL(Supervisor, '') = '' AND ISNULL(AgencyName, '') = '' THEN 'Other'
			END
			ELSE 'Customer Self Service' 
			END AS Supervisor	
	, COUNT(*) AS Total
FROM
(
	SELECT DISTINCT 
		e.CifId
		, e.Data1 As UserName
		, ISNULL(d.[CSRCompletedAccountCreationCSR],'') AS 'CSRCompletedAccountCreationCSR'
		, CAST(ActivateDates.ActivateDate AS DATE) AS ActivationDate
		, COALESCE(d.[CSRCompletedAccountFullName], o.pfsEmp_First_Last_Nm) AS Employee
		, COALESCE(d.[CSRCompletedAccountSupervisorName], o.pfsEmp_Supervisor_First_Nm + ' ' + o.pfsEmp_Supervisor_Last_Nm) AS Supervisor
		, COALESCE(d.[CSRCompletedAccountDepartment], o.pfsEmp_pfsCostCtr_Nm) AS CostCenter		
		, ROW_NUMBER() OVER (PARTITION BY CifId ORDER BY e.TimeStamp DESC) AS rn 
	FROM ASPMembership_PRX..UserEvents e (NOLOCK)
	LEFT JOIN ASPMembership_PRX..UserEventDetails d (NOLOCK)  ON e.Id = d.UserEventId	
	LEFT JOIN [BIM_Reporting_Daily].OneSource.pfs_Employee_new o (NOLOCK) ON d.[CSRCompletedAccountCreationCSR] = o.pfsEmp_Logon_Id
	LEFT JOIN (
		SELECT ue1.Data1 AS Data1, MIN(ue1.TimeStamp) AS ActivateDate
		FROM ASPMembership_PRX..UserEvents ue1
		WHERE EventType = 'Activation'
		GROUP BY ue1.Data1   
	) AS ActivateDates ON ActivateDates.Data1 = e.Data1
	WHERE e.EventType = 'Activation'
	AND ActivateDate > '2018-01-01'
) AS DETAIL
LEFT JOIN (
		SELECT REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', '') AS AgencyName
			, RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM) AS ProducerName
			, SU.SEC_USR_ID
		FROM Exceed_Reporting.XCD.SEC_USRS SU
		LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C1 (NOLOCK) ON C1.CLIENT_ID = SU.SEC_USR_CLT_ID
		LEFT JOIN Exceed_Reporting.XCD.CCM_PRODUCER CP (NOLOCK) ON CP.CPR_PDC_CLIENT_ID = C1.CLIENT_ID
		LEFT JOIN Exceed_Reporting.XCD.CCM_AGC_PRODUCER CAP (NOLOCK) ON CAP.CCM_PRODUCER_ID = CP.CCM_PRODUCER_ID
		LEFT JOIN Exceed_Reporting.XCD.CCM_CONTRACT CT (NOLOCK) ON CAP.CCM_AGENCY_ID = CT.CCM_AGENCY_ID AND CAP.CCM_PRODUCER_NBR = CT.CTT_CONTRACT_NBR AND CAP.HISTORY_VLD_NBR = 0
		LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C (NOLOCK) ON C.CLIENT_ID = CT.CTT_CTT_CLT_ID
		WHERE  (C1.CICL_EXP_DT = '9999-12-31' OR C.CICL_EXP_DT = NULL)
			AND (C.CICL_EXP_DT = '9999-12-31' OR C.CICL_EXP_DT = NULL)
			AND (CT.CTT_CTT_EXP_DT > GETDATE() OR CT.CTT_CTT_EXP_DT = NULL)
			AND CT.CCM_CONTRACT_ID IS NOT NULL
		GROUP BY REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', ''), RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM), SU.SEC_USR_ID
) AS AgentDetail
ON Detail.CSRCompletedAccountCreationCSR = AgentDetail.SEC_USR_ID AND ISNULL(Supervisor, '') = ''
WHERE RN = 1
GROUP BY ActivationDate
		, CostCenter
		, Employee
		, CSRCompletedAccountCreationCSR
		, Supervisor
		, ProducerName
		, AgencyName
		, SEC_USR_ID		

UNION ALL

SELECT CreatedDate As Date
	, 'Initiation' AS DateType
	, CASE WHEN ISNULL(CSRCompletedAccountCreationCSR, '') <> '' 
			THEN CASE WHEN ISNULL(CostCenter, '') = '' THEN 'Community Agents & Other' ELSE CostCenter END
			ELSE 'Customer Self Service'
			END AS CostCenter
	, CASE WHEN ISNULL(CSRCompletedAccountCreationCSR, '') <> '' THEN 
			CASE 
				WHEN ISNULL(Employee	, '') <> '' AND ISNULL(ProducerName, '') = '' THEN COALESCE(Employee, CSRCompletedAccountCreationCSR) 
				WHEN ISNULL(Employee	, '') = '' AND ISNULL(ProducerName, '') <> '' THEN  COALESCE(ProducerName, CSRCompletedAccountCreationCSR) 
				WHEN ISNULL(EMployee, '') = '' AND ISNULL(ProducerName, '') = '' THEN CSRCompletedAccountCreationCSR
			END 
		ELSE 'Customer Self Service'
		END AS Employee
	, CASE WHEN ISNULL(CSRCompletedAccountCreationCSR, '') <> '' THEN
			CASE 
				WHEN ISNULL(Supervisor, '') <> '' AND ISNULL(AgencyName, '') = '' THEN COALESCE(Supervisor, CSRCompletedAccountCreationCSR) 
				WHEN ISNULL(Supervisor, '') = '' AND ISNULL(AgencyName, '') <> '' THEN  COALESCE(AgencyName, CSRCompletedAccountCreationCSR) 
				WHEN ISNULL(Supervisor, '') = '' AND ISNULL(AgencyName, '') = '' THEN 'Other'
			END
			ELSE 'Customer Self Service' 
			END AS Supervisor
	, COUNT(*) AS Total
FROM
(
	SELECT DISTINCT 
		e.CifId
		, e.Data1 As UserName
		, d.[CSRCompletedAccountCreationCSR] AS 'CSRCompletedAccountCreationCSR'
		, CAST(e.TimeStamp AS Date) AS CreatedDate
		, COALESCE(d.[CSRCompletedAccountFullName], o.pfsEmp_First_Last_Nm) AS Employee
		, COALESCE(d.[CSRCompletedAccountSupervisorName], o.pfsEmp_Supervisor_First_Nm + ' ' + o.pfsEmp_Supervisor_Last_Nm) AS Supervisor
		, COALESCE(d.[CSRCompletedAccountDepartment], o.pfsEmp_pfsCostCtr_Nm) AS CostCenter	
		, ROW_NUMBER() OVER (PARTITION BY e.Data1 ORDER BY TimeStamp) AS rn 	
	FROM ASPMembership_PRX..UserEvents e
	LEFT JOIN ASPMembership_PRX..UserEventDetails d ON e.Id = d.UserEventId
	LEFT JOIN [BIM_Reporting_Daily].OneSource.pfs_Employee_new o (NOLOCK) ON d.[CSRCompletedAccountCreationCSR] = o.pfsEmp_Logon_Id
	WHERE e.EventType = 'Creation'
	AND e.TimeStamp > '1/1/2018'
) AS DETAIL
LEFT JOIN (
		SELECT REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', '') AS AgencyName
			, RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM) AS ProducerName
			, SU.SEC_USR_ID
		FROM Exceed_Reporting.XCD.SEC_USRS SU
		LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C1 (NOLOCK) ON C1.CLIENT_ID = SU.SEC_USR_CLT_ID
		LEFT JOIN Exceed_Reporting.XCD.CCM_PRODUCER CP (NOLOCK) ON CP.CPR_PDC_CLIENT_ID = C1.CLIENT_ID
		LEFT JOIN Exceed_Reporting.XCD.CCM_AGC_PRODUCER CAP (NOLOCK) ON CAP.CCM_PRODUCER_ID = CP.CCM_PRODUCER_ID
		LEFT JOIN Exceed_Reporting.XCD.CCM_CONTRACT CT (NOLOCK) ON CAP.CCM_AGENCY_ID = CT.CCM_AGENCY_ID AND CAP.CCM_PRODUCER_NBR = CT.CTT_CONTRACT_NBR AND CAP.HISTORY_VLD_NBR = 0
		LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C (NOLOCK) ON C.CLIENT_ID = CT.CTT_CTT_CLT_ID
		WHERE  (C1.CICL_EXP_DT = '9999-12-31' OR C.CICL_EXP_DT = NULL)
			AND (C.CICL_EXP_DT = '9999-12-31' OR C.CICL_EXP_DT = NULL)
			AND (CT.CTT_CTT_EXP_DT > GETDATE() OR CT.CTT_CTT_EXP_DT = NULL)
			AND CT.CCM_CONTRACT_ID IS NOT NULL
		GROUP BY REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', ''), RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM), SU.SEC_USR_ID
) AS AgentDetail
ON Detail.CSRCompletedAccountCreationCSR = AgentDetail.SEC_USR_ID AND ISNULL(Supervisor, '') = ''
WHERE RN = 1
GROUP BY CreatedDate
		, CostCenter
		, Employee
		, CSRCompletedAccountCreationCSR
		, Supervisor	
		, ProducerName
		, AgencyName

UNION ALL 

SELECT CAST(getdate() AS Date) as Date
      , 'Inforce' as DateType
      , CASE      WHEN CSRCompletedAccountCreation ='true' 
                  THEN COALESCE(CostCenter, 'Community Agents & Other') 
                  ELSE 'Customer Self Service' 
                  END as CostCenter
      , CASE      WHEN CSRCompletedAccountCreation ='true' AND ProducerName IS NULL THEN COALESCE(Employee, CSRCompletedAccountCreationCSR) 
                  WHEN CSRCompletedAccountCreation ='true' AND ProducerName IS NOT NULL THEN COALESCE(Employee, ProducerName) 
                  ELSE 'Customer Self Service' 
                  END as Employee
      , CASE      WHEN CSRCompletedAccountCreation ='true' AND AgencyName IS NULL THEN COALESCE(Supervisor, ' OTHER') 
                  WHEN CSRCompletedAccountCreation ='true' AND AgencyName IS NOT NULL THEN COALESCE(Supervisor, AgencyName) 
                  ELSE 'Customer Self Service' 
                  END as Supervisor
      , COUNT(*) as Total
FROM (
      SELECT distinct u.CifId, u.UserName
            , u.CSRCompletedAccountCreation
            , u.CSRCompletedAccountCreationCSR
            , u.KBAIdentificationDate AS 'KBAIdentificationStatusDate' 
			, CASE WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountFullName)[1]', 'varchar(50)'), '') <> '' THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountFullName)[1]', 'varchar(50)') ELSE e.pfsEmp_First_Last_Nm END AS Employee
			, CASE WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountSupervisorName)[1]', 'varchar(50)'), '') <> '' THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountSupervisorName)[1]', 'varchar(50)') ELSE e.pfsEmp_Supervisor_First_Nm + ' ' + pfsEmp_Supervisor_Last_Nm END AS Supervisor
			, CASE WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountDepartment)[1]', 'varchar(50)'), '') <> '' THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountDepartment)[1]', 'varchar(50)') ELSE e.pfsEmp_pfsCostCtr_Nm END AS CostCenter
            , ROW_NUMBER() OVER (PARTITION BY u.CifId ORDER BY CASE WHEN u.CSRCompletedAccountCreation = 'true' THEN DATEADD(day, DATEDIFF(day, 0, u.AgreeTCDate), 0) ELSE LEFT(u.KBAIdentificationDate, 21) End DESC) AS rn 
      FROM ASPMembership_PRX.dbo.UserAccountDetails u (NOLOCK)
      LEFT JOIN [BIM_Reporting_Daily].OneSource.pfs_Employee_new e (NOLOCK) ON u.CSRCompletedAccountCreationCSR = e.pfsEmp_Logon_Id
      LEFT JOIN [BIM_Reporting_Daily].MEM.Inforce_Pol ip (NOLOCK) ON ip.CifId = u.CifId
      WHERE 1=1 
      AND ISNULL(ip.CifId, '') <> ''
      AND u.IsUpAndRunning = 1
      AND ((u.CSRCompletedAccountCreation = 'true' AND u.AgreeTC = 1)
           OR (u.CSRCompletedAccountCreation = 'false' AND u.KBAIdentificationStatus IN ('UserCompleted','NotAttemptedIgnore')))           
      ) AS Detail
LEFT JOIN (
      SELECT REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', '') AS AgencyName
            , RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM) AS ProducerName
            , SU.SEC_USR_ID
      FROM Exceed_Reporting.XCD.SEC_USRS SU
      LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C1 (NOLOCK) ON C1.CLIENT_ID = SU.SEC_USR_CLT_ID
      LEFT JOIN Exceed_Reporting.XCD.CCM_PRODUCER CP (NOLOCK) ON CP.CPR_PDC_CLIENT_ID = C1.CLIENT_ID
      LEFT JOIN Exceed_Reporting.XCD.CCM_AGC_PRODUCER CAP (NOLOCK) ON CAP.CCM_PRODUCER_ID = CP.CCM_PRODUCER_ID
      LEFT JOIN Exceed_Reporting.XCD.CCM_CONTRACT CT (NOLOCK) ON CAP.CCM_AGENCY_ID = CT.CCM_AGENCY_ID AND CAP.CCM_PRODUCER_NBR = CT.CTT_CONTRACT_NBR AND CAP.HISTORY_VLD_NBR = 0
      LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C (NOLOCK) ON C.CLIENT_ID = CT.CTT_CTT_CLT_ID
      WHERE  (C1.CICL_EXP_DT = '9999-12-31' OR C.CICL_EXP_DT = NULL)
            AND (C.CICL_EXP_DT = '9999-12-31' OR C.CICL_EXP_DT = NULL)
            AND (CT.CTT_CTT_EXP_DT > GETDATE() OR CT.CTT_CTT_EXP_DT = NULL)
            AND CT.CCM_CONTRACT_ID IS NOT NULL
      GROUP BY REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', ''), RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM), SU.SEC_USR_ID
) AS AgentDetail
ON Detail.CSRCompletedAccountCreationCSR = AgentDetail.SEC_USR_ID AND ISNULL(Supervisor, '') = ''
WHERE RN = 1
GROUP BY CSRCompletedAccountCreation, CostCenter, Employee, CSRCompletedAccountCreationCSR, Supervisor, ProducerName, AgencyName, SEC_USR_ID

UNION ALL 

SELECT CAST(getdate() AS Date) as Date
      , 'DriverOnly' as DateType
      , CASE      WHEN CSRCompletedAccountCreation ='true' 
                  THEN COALESCE(CostCenter, 'Community Agents & Other') 
                  ELSE 'Customer Self Service' 
                  END as CostCenter
      , CASE      WHEN CSRCompletedAccountCreation ='true' AND ProducerName IS NULL THEN COALESCE(Employee, CSRCompletedAccountCreationCSR) 
                  WHEN CSRCompletedAccountCreation ='true' AND ProducerName IS NOT NULL THEN COALESCE(Employee, ProducerName) 
                  ELSE 'Customer Self Service' 
                  END as Employee
      , CASE      WHEN CSRCompletedAccountCreation ='true' AND AgencyName IS NULL THEN COALESCE(Supervisor, ' OTHER') 
                  WHEN CSRCompletedAccountCreation ='true' AND AgencyName IS NOT NULL THEN COALESCE(Supervisor, AgencyName) 
                  ELSE 'Customer Self Service' 
                  END as Supervisor
      , COUNT(*) as Total
FROM (
      SELECT distinct u.CifId, u.UserName
            , u.CSRCompletedAccountCreation
            , u.CSRCompletedAccountCreationCSR
            , u.KBAIdentificationDate AS 'KBAIdentificationStatusDate' 
			, CASE WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountFullName)[1]', 'varchar(50)'), '') <> '' THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountFullName)[1]', 'varchar(50)') ELSE e.pfsEmp_First_Last_Nm END AS Employee
			, CASE WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountSupervisorName)[1]', 'varchar(50)'), '') <> '' THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountSupervisorName)[1]', 'varchar(50)') ELSE e.pfsEmp_Supervisor_First_Nm + ' ' + pfsEmp_Supervisor_Last_Nm END AS Supervisor
			, CASE WHEN ISNULL(u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountDepartment)[1]', 'varchar(50)'), '') <> '' THEN u.AccountStatusXml.value('(/AccountStatus/CSRCompletedAccountDepartment)[1]', 'varchar(50)') ELSE e.pfsEmp_pfsCostCtr_Nm END AS CostCenter
            , ROW_NUMBER() OVER (PARTITION BY u.CifId ORDER BY CASE WHEN u.CSRCompletedAccountCreation = 'true' THEN DATEADD(day, DATEDIFF(day, 0, u.AgreeTCDate), 0) ELSE LEFT(u.KBAIdentificationDate, 21) End DESC) AS rn 
      FROM ASPMembership_PRX.dbo.UserAccountDetails u (NOLOCK)
      LEFT JOIN [BIM_Reporting_Daily].OneSource.pfs_Employee_new e (NOLOCK) ON u.CSRCompletedAccountCreationCSR = e.pfsEmp_Logon_Id
      LEFT JOIN [BIM_Reporting_Daily].MEM.Inforce_Pol ip (NOLOCK) ON ip.CifId = u.CifId
      WHERE 1=1 
      AND ISNULL(ip.CifId, '') <> ''
      AND u.IsUpAndRunning = 1
      AND ((u.CSRCompletedAccountCreation = 'true' AND u.AgreeTC = 1)
           OR (u.CSRCompletedAccountCreation = 'false' AND u.KBAIdentificationStatus IN ('UserCompleted','NotAttemptedIgnore')))           
      ) AS Detail
LEFT JOIN (
      SELECT REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', '') AS AgencyName
            , RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM) AS ProducerName
            , SU.SEC_USR_ID
      FROM Exceed_Reporting.XCD.SEC_USRS SU
      LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C1 (NOLOCK) ON C1.CLIENT_ID = SU.SEC_USR_CLT_ID
      LEFT JOIN Exceed_Reporting.XCD.CCM_PRODUCER CP (NOLOCK) ON CP.CPR_PDC_CLIENT_ID = C1.CLIENT_ID
      LEFT JOIN Exceed_Reporting.XCD.CCM_AGC_PRODUCER CAP (NOLOCK) ON CAP.CCM_PRODUCER_ID = CP.CCM_PRODUCER_ID
      LEFT JOIN Exceed_Reporting.XCD.CCM_CONTRACT CT (NOLOCK) ON CAP.CCM_AGENCY_ID = CT.CCM_AGENCY_ID AND CAP.CCM_PRODUCER_NBR = CT.CTT_CONTRACT_NBR AND CAP.HISTORY_VLD_NBR = 0
      LEFT JOIN Exceed_Reporting.XCD.CLIENT_TAB C (NOLOCK) ON C.CLIENT_ID = CT.CTT_CTT_CLT_ID
      WHERE  (C1.CICL_EXP_DT = '9999-12-31' OR C.CICL_EXP_DT = NULL)
            AND (C.CICL_EXP_DT = '9999-12-31' OR C.CICL_EXP_DT = NULL)
            AND (CT.CTT_CTT_EXP_DT > GETDATE() OR CT.CTT_CTT_EXP_DT = NULL)
            AND CT.CCM_CONTRACT_ID IS NOT NULL
      GROUP BY REPLACE(REPLACE(C.CICL_LNG_NM, '+ ', ''), '+', ''), RTRIM(C1.CICL_FST_NM) + ' ' + LTRIM(C1.CICL_LST_NM), SU.SEC_USR_ID
) AS AgentDetail
ON Detail.CSRCompletedAccountCreationCSR = AgentDetail.SEC_USR_ID AND ISNULL(Supervisor, '') = ''
LEFT JOIN (
	select u.CifId,
		sum(case when pr.prld_code in ('NIN', 'ANI') then 1 else 0 end) as NI_ANI_COUNT,
		sum(case when pr.prld_code in ('DR') then 1 else 0 end) as DR_COUNT
	from ASPMembership_PRX..users u (nolock)
	join BIM_Reporting_Weekly.CIFDM.dim_person p (nolock) on u.CifId = p.psnd_clt_id_cif
	join BIM_Reporting_Weekly.CIFDM.fact_person_coverage pc (nolock) on p.psnd_id = pc.pcvf_psnd_id
	join [BIM_Reporting_Weekly].[CIFDM].[dim_policy_role] pr (nolock) on pc.pcvf_prld_id = prld_id
	where 1=1
	AND [pcvf_run_effective_date_td_id] = (select max(td_id) from [BIM_Reporting_Weekly].[CIFDM].[dim_time])
	group by u.CifId
) AS InsuredType
ON Detail.CifId = InsuredType.CifId
WHERE RN = 1
AND (NI_ANI_COUNT = 0 AND DR_COUNT > 0)
GROUP BY CSRCompletedAccountCreation, CostCenter, Employee, CSRCompletedAccountCreationCSR, Supervisor, ProducerName, AgencyName, SEC_USR_ID