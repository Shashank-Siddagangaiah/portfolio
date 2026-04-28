--check that...
--I think employee == Agent Name (but you will get agency name here) 
--Supervisor == territory manager name 
 
--check if this has the actual agents name - awm.dbo.community_agent 
 
SELECT pac.policy_term_anchor_id AS policy_term_key,
       pac.effective_date AS effective_date,
       EOMONTH(pac.effective_date) AS as_of_date_com,
       SUM(pac.commission_amount) AS commission_amount,
       SUM(pac.policy_transaction_amount) AS sum_WP,
       pac.agent_number AS subproducer_number,
       pa.policy_number AS policy_number,
       p.risk_state_code AS risk_state_code,
       pta.policy_symbol_code AS policy_symbol,
       pta.term_effective_date AS term_effective_date,
       pta.term_expiration_date AS term_expiration_date,
       ptt.policy_transaction_type_name AS policy_transaction_type,
       pf.product_name AS product_name,
       vph.full_name AS insured_name,
       ca.agent_name AS agency_name,
       ca.agent_number AS producer_number,
       ca.territory_manager AS territory_manager,
       hh.household_id AS household_id
FROM [AWM].dbo.policy_agent_commission pac
JOIN [AWM].dbo.policy_anchor pa WITH (NOLOCK) ON pac.policy_anchor_id = pa.policy_anchor_id
AND pac.valid_to_date = '9999-12-31'
JOIN [AWM].dbo.policy_term_anchor pta WITH (NOLOCK) ON pac.policy_term_anchor_id = pta.policy_term_anchor_id
JOIN [AWM].dbo.policy_form pf ON pac.policy_form_id = pf.policy_form_id
JOIN [AWM].dbo.policy p ON pac.policy_term_anchor_id = p.policy_term_anchor_id
LEFT JOIN [AWM].dbo.policy_transaction_type ptt WITH (NOLOCK) ON pac.policy_transaction_type_id = ptt.policy_transaction_type_id
JOIN [AWM].dbo.agent agt ON pac.agent_number = agt.agent_number
AND agt.agency_party_role_anchor_id IS NOT NULL
AND agt.valid_to_date = '9999-12-31'
JOIN cte_vph vph ON vph.policy_term_key = pac.policy_term_anchor_id
AND vph.rn = 1
JOIN awm.dbo.community_agent AS ca ON ca.agent_number = SUBSTRING(agt.agent_number, 4, 3)
AND ca.valid_to_date = '9999-12-31'
AND ca.account_status = 'Active'
JOIN cte_household hh ON hh.policy_term_anchor_id = pac.policy_term_anchor_id
AND hh.rownum = 1
WHERE EOMONTH(pac.effective_date) = @Last_Day_Last_Month
GROUP BY pac.policy_term_anchor_id,
         pac.effective_date,
         EOMONTH(pac.effective_date),
         pac.agent_number,
         pa.policy_number,
         pta.policy_symbol_code,
         pta.term_effective_date,
         pta.term_expiration_date,
         ptt.policy_transaction_type_name,
         pf.product_name,
         vph.full_name,
         ca.agent_name,
         ca.agent_number,
         ca.territory_manager,
         hh.household_id,
         p.risk_state_code;