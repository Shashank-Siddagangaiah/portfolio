SELECT RiskStateCd As PrimaryState
    , SUM(CASE WHEN InforceAuto > 0 THEN 1 ELSE 0 END) AS Auto
       , SUM(CASE WHEN InforceHome > 0 THEN 1 ELSE 0 END) AS Home
       , SUM(CASE WHEN InforceCondo > 0 THEN 1 ELSE 0 END) AS Condo
       , SUM(CASE WHEN InforceRenter > 0 THEN 1 ELSE 0 END) AS Renter
       , SUM(CASE WHEN InforceDP > 0 THEN 1 ELSE 0 END) AS DP
       , SUM(CASE WHEN InforceMA > 0 THEN 1 ELSE 0 END) AS Boat
       , SUM(CASE WHEN InforceUMB > 0 THEN 1 ELSE 0 END) AS Umbrella
FROM
(
       SELECT i.cifid
           , E.[POL_PRI_RSK_ST_CD] As RiskStateCd
              , SUM(CASE WHEN i.cdv_short = 'CA' THEN 1 ELSE 0 END) AS InforceAuto
              , SUM(CASE WHEN i.cdv_short = 'HO' THEN 1 ELSE 0 END) AS InforceHO
              , SUM(CASE WHEN i.cdv_short = 'HO' AND d.FORM_CD IN ('8','9') THEN 1 ELSE 0 END) AS InforceHome
              , SUM(CASE WHEN i.cdv_short = 'HO' AND d.FORM_CD IN ('1','2', '6', '7') THEN 1 ELSE 0 END) AS InforceCondo
              , SUM(CASE WHEN i.cdv_short = 'HO' AND d.FORM_CD = '4' THEN 1 ELSE 0 END) AS InforceRenter
              , SUM(CASE WHEN i.cdv_short = 'DP' THEN 1 ELSE 0 END) AS InforceDP
              , SUM(CASE WHEN i.cdv_short = 'MA' THEN 1 ELSE 0 END) AS InforceMA
              , SUM(CASE WHEN i.cdv_short = 'MH' THEN 1 ELSE 0 END) AS InforceMH
              , SUM(CASE WHEN i.cdv_short = 'UMB' THEN 1 ELSE 0 END) AS InforceUMB
              , SUM(1) AS InforceCount
       FROM [ASPMembership_PRX].[dbo].[UserAccountDetails] u 
       JOIN [BIM_Reporting_Daily].[mem].[Inforce_Pol_Detail] i ON u.CifId = i.CifId
       JOIN [Exceed_Reporting].[XCD].[POLICY_TAB] e (NOLOCK) ON i.pol_id = e.POLICY_ID
       LEFT JOIN [Exceed_Reporting].[XCD].[DWELLING_TAB] D (NOLOCK) 
       ON e.POLICY_ID = d.POLICY_ID 
       AND e.OGN_EFF_DT = d.OGN_EFF_DT 
       AND e.LOB_CD = d.INSURANCE_LINE_CD 
       AND e.QUOTE_SEQUENCE_NBR = D.QUOTE_SEQUENCE_NBR --? 
       WHERE 1=1
       AND ISNULL(u.IsUpAndRunning, 0) = 1
       AND ISNULL(u.AgreeTC, 0) = 1      
       GROUP BY i.cifid, e.[POL_PRI_RSK_ST_CD]
) AS Detail
GROUP By RiskStateCd

--
policy_tab - get the policy_symbol_details 

form_code 
awm.dbo.dwelling - policy_form_id 
awm.dbo.dwelling_policy_detail ?