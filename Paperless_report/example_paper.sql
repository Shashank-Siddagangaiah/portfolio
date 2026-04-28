WITH Paper_HouseHold AS (
    SELECT 
        policy_term_anchor_id
		,HouseholdID
		,effective_date
        
    FROM (
	SELECT 
        phm.household_id as HouseholdID
		,phm.policy_term_anchor_id
		,phm.effective_date
        ,ROW_NUMBER() OVER (
            PARTITION BY phm.policy_term_anchor_id, phm.household_id
            ORDER BY phm.effective_date DESC
        ) AS row_num
    FROM AWM.dbo.policy_household_mapping AS phm
	--where phm.household_id in (10004110) 
	) as Pol where row_num=1

),

Paper_Head_Of_Household AS (
	SELECT
		DISTINCT HH.HouseholdID
		,vplh.party_key as party_anchor_id
		,HPD.household_role_type_code
	FROM Paper_HouseHold HH 
	INNER JOIN [DWM].[EDW].[vw_policyholder] vplh on vplh.policy_term_key=HH.policy_term_anchor_id 
	INNER JOIN AWM.dbo.household_policy_party_link HPL on HPL.party_anchor_id=vplh.party_key and HPL.policy_term_anchor_id=vplh.policy_term_key
	INNER JOIN AWM.dbo.household_party_detail HPD on HPD.household_policy_party_link_id = HPL.household_policy_party_link_id
	Where HPD.household_role_type_code = 'A'
),
CIF_POLICY_Detail1 AS
(
	SELECT 
		policy_party_link_id
		,output_document_type_code
		,paper_notify_indicator
		,effective_from_date
		,effective_to_date
		,ROW_NUMBER() OVER (
            PARTITION BY policy_party_link_id,output_document_type_code
            ORDER BY effective_from_date DESC
        ) AS row_num
	FROM AWM.[dbo].[cif_policy_party_detail]
	Where output_document_type_code in ('BIL','POL') and  effective_to_date='9999-12-31'--and Policy_party_link_id in (7765195)
),
CIF_POLICY_Detail2 as (
SELECT
    CPPD.policy_party_link_id,
	PA.Policy_number,
	PPL.Party_anchor_id,
    MAX(CASE WHEN output_document_type_code = 'BIL' THEN paper_notify_indicator END) AS BIL_paper_notify,
	MAX(CASE WHEN output_document_type_code = 'BIL' THEN effective_from_date   END) AS PaperlessBillDate,
    MAX(CASE WHEN output_document_type_code = 'POL' THEN paper_notify_indicator END) AS POL_paper_notify,
	MAX(CASE WHEN output_document_type_code = 'POL' THEN effective_from_date   END) AS PaperlessPolDate
FROM
    CIF_POLICY_Detail1 CPPD
	INNER JOIN [AWM].[dbo].[policy_party_link] PPL ON CPPD.policy_party_link_id = PPL.policy_party_link_id
	INNER JOIN [AWM].[dbo].[policy_anchor] PA ON PA.policy_anchor_id = PPL.policy_anchor_id 
WHERE CPPD.row_num = 1
GROUP BY
    CPPD.policy_party_link_id,PA.Policy_number,PPL.Party_anchor_id
),
CIF_POLICY_Detail AS (
Select 
	C.policy_party_link_id
	,C.policy_number
	,C.Party_anchor_id
	,CASE WHEN C.BIL_paper_notify = 0 THEN 'Y' ELSE 'N' END as Paperless_Bil_Ind
	,C.PaperlessBillDate
	,CASE WHEN C.POL_paper_notify = 0 THEN 'Y' ELSE 'N' END as Paperless_Pol_Ind
	,C.PaperlessPolDate
FROM CIF_POLICY_Detail2 C
),


Paper_Policy_Detail AS(
	SELECT
		DISTINCT HH.HouseholdID
		,vp.policy_term_key
		,vplh.policy_number as PolNumber
		,SUBSTRING(vplh.policy_number, 4, LEN(vplh.policy_number)) as POL_KEY
		,C.policy_number
		,vpa.agent_number	as AgentNumber
		,PTA.exceed_client_id as CIFID
		--,vpai.paperless_billing_indicator as PaperlessBillInd
		--,vpai.paperless_policy_indicator as PaperlessPolInd
		,C.Paperless_Bil_Ind as PaperlessBillInd
		,C.PaperlessBillDate
		,C.Paperless_Pol_Ind as PaperlessPolInd
		,C.PaperlessPolDate
		,vp.policy_form as FormCode
		,PIL.party_anchor_id_duplicate as party_anchor_id
		--,PIL.Pol
		,vplh.party_key as VW_party_anchor_id
		,vplh.policy_term_key as policy_term_anchor_id
		,vplh.full_name as FullName
		,vplh.term_effective_date as Start_date
		,vplh.term_expiration_date as End_Date
		,Vp.effective_to_date as policy_effective_to_date
		,vplh.policy_symbol as Policy_Symbol
		,vplh.policyholder_type_code
		,vp.risk_state_code as risk_state
		,CASE WHEN VP.policy_inforce_indicator = 1 Then 'INFORCE' ELSE '' END as PolicyStatus
		,vp.insurance_score as Ins_Score
		,vplh.affinity_group_code as Affinity_Group
		,vplh.gender as Gender
		,vplh.gender_code as Gender_Code
		,vplh.marital_status as Maritial_Status
		,vplh.marital_status_code AS Maritial_Status_Code
		,DATEDIFF(YEAR, vplh.birth_date, GETDATE()) - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, vplh.birth_date, GETDATE()), vplh.birth_date) > GETDATE() THEN 1 ELSE 0 END AS Age
		,vplh.mailing_address_city as City
		,vplh.mailing_address_state_code as State
		,vplh.mailing_address_zip_code as Zip
		,vplh.original_effective_date as Orignal_Policy_Effective_Date
		,CASE 
			WHEN PHH.household_role_type_code = 'A' THEN 'Y' 
			WHEN PHH.household_role_type_code='M' THEN 'N' 
			ELSE 'N' END as HOH_IND 
	FROM Paper_HouseHold HH 
	INNER JOIN [DWM].[EDW].vw_policy vp on vp.policy_term_key = HH.policy_term_anchor_id 
	INNER JOIN [DWM].[EDW].[vw_policyholder] vplh on vplh.policy_term_key=vp.policy_term_key --and vplh.term_effective_date=vp.effective_From_date and vplh.term_expiration_date=vp.effective_to_date
	INNER JOIN [DWM].[EDW].[vw_policy_agent] vpa on vp.policy_term_key = vpa.policy_term_key
	INNER JOIN AWM.DBO.party_id_same_as_link PIL on vplh.party_key = PIL.party_anchor_id_master
	INNER JOIN AWM.DBO.party_anchor PTA on  PIL.party_anchor_id_duplicate = PTA.party_anchor_id
	LEFT JOIN Paper_Head_Of_Household PHH on PHH.HouseholdID=HH.HouseholdID and PHH.party_anchor_id=vplh.party_key
	LEFT JOIN CIF_POLICY_Detail C ON  PIL.party_anchor_id_duplicate = C.Party_anchor_id and  C.policy_number = SUBSTRING(vplh.policy_number, CASE WHEN vplh.policy_number LIKE 'UMB%' THEN 5 ELSE 4 END, LEN(vplh.policy_number)) --
	
),

---Contact email details
ct_asp_user_account1 AS(
Select 
	auad.party_user_account_link_id,
	auad.user_name,
	auad.is_anonymous_indicator,
	auad.is_up_and_running_indicator,
	auad.valid_from_date,
	auad.valid_to_date,
	ROW_NUMBER() OVER (
            PARTITION BY auad.party_user_account_link_id
            ORDER BY auad.valid_from_date DESC
        ) AS row_num
From AWM.dbo.asp_user_account_detail auad

),

ct_asp_user_account2 AS(
SELECT 
	tu.party_user_account_link_id
	,tu.user_name
	,tu.is_anonymous_indicator
	,tu.is_up_and_running_indicator
	,tu.valid_from_date
	,tu.valid_to_date
	,PL.user_account_anchor_id
	,PL.party_anchor_id
	,Pl.Load_date
	,ROW_NUMBER() OVER (
            PARTITION BY PL.party_anchor_id
            ORDER BY PL.Load_date DESC
        ) AS row_order
FROM ct_asp_user_account1 TU 
INNER JOIN AWM.dbo.party_user_account_link PL ON TU.party_user_account_link_id = PL.party_user_account_link_id
WHERE row_num=1
),
ct_asp_user_account AS (
SELECT 
	TU.*
	,am.create_date as 'SSACreateDate'
	,am.asp_membership_detail_id
	,am.is_approved_indicator
	,am.is_locked_out_indicator
	,am.last_login_date
	,am.tc_agree_date
	,am.tc_agree_indicator
	,am.telematics_eula_agree_date
	,am.telematics_eula_version
	,case when TU.user_name IS NOT NULL THEN 'SSA' ELSE NULL END AS EmailType
	,case when am.last_login_date > '2013-01-01' THEN 'Y' ELSE 'N' END AS VerifiedEmailInd  
	,ROW_NUMBER() OVER (
            PARTITION BY am.user_account_anchor_id
            ORDER BY am.valid_from_date DESC
        ) AS row_num
FROM ct_asp_user_account2 TU
INNER JOIN AWM.dbo.asp_membership_detail am on TU.user_account_anchor_id = am.user_account_anchor_id and TU.row_order=1
)


--Select * From Paper_HouseHold order by effective_date desc
--Select * From CT_asp_user_account2 where party_anchor_ID=7606991 and row_order=1
--Select * From Paper_Policy_Detail  WHERE PolNumber='CA 0104972' order by policy_effective_to_date desc--(policy_effective_to_date>GETDATE() or End_Date>GETDATE()) and PolicyStatus='INFORCE'

Select 
	PPD.HouseholdID
	,PPD.PolNumber
	,PPD.AgentNumber
	,PPD.party_anchor_id
	,PPD.VW_party_anchor_id
	,PPD.policy_term_anchor_id
	,PPD.HOH_IND
	,PPD.policyholder_type_code
	,PPD.CIFID
	,PPD.FullName
	,PPD.PaperlessBillInd
	,PPD.PaperlessBillDate
	,PPD.PaperlessPolInd
	,PPD.PaperlessPolDate
	,PPD.FormCode
	,PPD.Start_date
	,PPD.End_Date
	,PPD.Policy_Symbol
	,PPD.risk_state
	,PPD.PolicyStatus
	,PPD.Ins_Score 
	,PPD.Affinity_Group
	,PPD.Gender
	,PPD.Gender_Code
	,PPD.Maritial_Status
	,PPD.Maritial_Status_Code
	,PPD.Age
	,PPD.City
	,PPD.State
	,PPD.Zip
	,PPD.Orignal_Policy_Effective_Date
	,'' as EmplInd  
    ,UA.EmailType as EmailType  
    ,UA.user_name as EmailAddress  
    ,UA.VerifiedEmailInd as EmailVerification  
    ,case when UA.EmailType = 'SSA' then 'Y' ELSE 'N' END  as SelfServiceInd  
    ,UA.SSACreateDate as SelfServiceDate  	
--INTO dbo.New_Paper_Report
FROM 
	Paper_Policy_Detail PPD 
	LEFT JOIN ct_asp_user_account UA on UA.party_anchor_id = PPD.party_anchor_id and UA.row_num=1
WHERE (PPD.policy_effective_to_date>GETDATE() or PPD.End_Date>GETDATE()) and PPD.PolicyStatus='INFORCE' --and UA.user_name IS NOT NULL--and PPD.PaperlessPolInd <> 1 and PPD.PaperlessBillInd <> 1 
ORDER BY PPD.HouseholdID,PPD.PolNumber

--DROP TABLE dbo.New_Paper_Report
Select * From dbo.New_Paper_Report

--Select * From paper_hou
--