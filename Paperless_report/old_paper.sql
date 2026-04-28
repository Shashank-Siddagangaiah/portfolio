SELECT DISTINCT    
      P.AGT_NBR as AgentNumber   
      ,C.[HH_ID] as HouseholdID   
      ,C.[CIF_ID] as CIFID   
      ,C.[HOH_IND] as HeadOfHousehold   
      ,C.[CITY] as City   
      ,C.[ST_CD] as State   
      ,C.[ZIPCODE] as Zip   
      ,C.[EMP_IND] as EmplInd   
      ,C.[EMAIL_TYPE] as EmailType   
      ,C.[EMAIL_ADDRESS] as EmailAddress   
      ,C.[EMAIL_VERIFY_IND] as EmailVerification   
      ,C.[CSS_IND] as SelfServiceInd   
      ,C.[CSS_DT] as SelfServiceDate   
      ,C.[START_DT] as StartDate   
		,C.GNDR_CD
      ,P.POL_KEY as PolNumber   
      ,P.PPRLESS_BIL_DT as PaperlessBillDate   
      ,P.PPRLESS_BIL_IND as PaperlessBillInd   
      ,P.PPRLESS_POL_DT as PaperlessPolDate   
      ,P.PPRLESS_POL_IND as PaperlessPolInd   
      ,P.POL_OGN_IPT_DT as OriginalPolIncDate   
      ,P.FORM_CD as FormCode   
      ,P.Pol_STS_CD as PolicyStatus 
	  ,P.START_DT as Policy_Start_Date
	  ,P.END_DT as Policy_End_Date
INTO dbo.Old_Paper_Report	
  FROM [BIM_Reporting_Weekly].[Eloqua].[CONTACT] AS C    
 
  LEFT OUTER JOIN [BIM_Reporting_Weekly].[Eloqua].[POLICY] AS P   
  ON C.HH_ID = P.HH_ID   
 
  WHERE C.END_DT = '9999-12-31'    
  AND P.END_DT = '9999-12-31'   
  And P.POL_STS_CD = 'INFORCE'   
--AND C.CSS_IND = 'N'
  --AND P.PPRLESS_POL_IND <> 'Y' 
  --AND P.PPRLESS_BIL_IND <> 'Y' 
  --AND C.HH_ID IN  (10001257)
  --AND C.HOH_IND  = 'N'
  ORDER BY C.HH_ID


  --DROP TABLE dbo.Old_Paper_Report	
  --Select Start_DT,END_DT,POL_STS_CD,* From Eloqua.POLICY where HH_ID=10000077 and END_DT > GETDATE()
  --SELECT * FROM Eloqua.CONTACT WHERE HH_ID=10000077


/*
  SELECT COUNT(P.POL_KEY) AS Paperless_CA
FROM Eloqua.POLICY (NOLOCK) AS P
WHERE HH_ID IN (SELECT HH_ID FROM Eloqua.CONTACT (NOLOCK) WHERE EMAIL_VERIFY_IND = 'Y' /* AND CSS_IND = 'Y' */ AND END_DT = '9999-12-31' GROUP BY HH_ID) 
AND P.END_DT = '9999-12-31' 
AND (P.PPRLESS_POL_IND IN ('Y') OR P.PPRLESS_BIL_IND IN ('Y'))
AND P.POL_STS_CD = 'Inforce'
*/