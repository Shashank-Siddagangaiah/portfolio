# Online Accounts Report — Reference Material

Deduplication checklist and SQL review checklist have moved to root `CLAUDE_reference.md`.

Read this file for project-specific Continuous Learning (root causes and fix patterns).

---

## Continuous Learning

| Date | Issue | Root Cause | Fix Pattern |
|---|---|---|---|
| 2026-04-17 | `is_up_and_running_indicator = 1` returned 0 rows | Column is tinyint, not boolean. Active = 255, inactive = 0, unknown = NULL. | Filter `= 255`. Never `= 1` or `ISNULL(...,0) = 1`. |
| 2026-04-17 | AWM→EDW policy join lost 99% of rows (265K→2K) | `policy_party_link → awm.dbo.policy` is a partial satellite (~2K rows). Its `party_anchor_id` does not share ID space with `party_user_account_link.party_anchor_id`. | Use `party_id_same_as_link`: AWM `party_anchor_id` (duplicate) → EDW `party_key` (master) → `vw_policyholder.party_key` → `vw_policy.policy_term_key`. |
| 2026-04-20 | DriverOnly AWM count ~43% lower than BIM | `vw_policy_driver` has ~13% coverage gap vs BIM's `CIFDM.fact_person_coverage → dim_policy_role`. 3,971 BIM DR parties have no row in `vw_policy_driver`. No EDW view fully equivalent to `dim_policy_role`. | **Gap under active investigation.** Interim: INNER JOIN on `vw_policy_driver` (require positive DR signal). NOT EXISTS inflates count 17×. |
| 2026-04-20 | `vw_policyholder.policyholder_type_code` has no DR rows | DR code does not exist in `vw_policyholder` — only NIN/ANI. EDW separates driver roles into `vw_policy_driver`. | Use `vw_policy_driver` for DriverOnly filter, not `vw_policyholder`. |
| 2026-04-24 | AWM shows username/OTHER for ~61% of parties | `USER_EVENT_DETAIL` CSR fields only populated for ~39% of Creation events. | Accept gap. Show `UPPER(LTRIM(RTRIM(username)))` as Employee and `'OTHER'` as Supervisor. Do not use `community_agent.agent_name` as fallback — agency-level, not the enrolling person. |
| 2026-04-24 | `policyholder_inforce_indicator = 1` returns 7.2M rows | Marks the person-policy relationship row as valid, not the policy as effective today. | Always join `vw_policy` with `policy_inforce_indicator = 1` AND date boundaries. Never substitute `policyholder_inforce_indicator` alone. |
| 2026-04-24 | BIM shows agent names in Employee/Supervisor for Community Agents & Other | BIM's `AccountStatusXml` CSR fields are populated for agent-assisted enrollments with agent name and agency name. | Expected — not a bug. CostCenter correctly lands as `'Community Agents & Other'`. |
| 2026-04-27 | BIM DriverOnly query used `prld_code IN ('NIN', 'ANI')` — returned only 8 CSR rows | `CIFDM.dim_policy_role.prld_code` uses `'NI'` for Named Insured. `'NIN'` is `vw_policy_driver.policyholder_type_code` (EDW). BIM codes: `NI`, `ANI`, `DR`. EDW codes: `NIN`, `ANI`, `DR`. Never cross-use. | Fixed BIM query to `IN ('NI', 'ANI')`. After fix: BIM CSR=476, CSS=264. The 43% gap is real — not a baseline error. |
| 2026-04-27 | 39,002 NULL `policyholder_type_code` parties classified as DriverOnly | `HAVING SUM(CASE WHEN ... IN ('NIN','ANI') THEN 1 ELSE 0 END) = 0` treats NULL as "not NIN/ANI". Role is unknown, not confirmed DR. | Known data quality gap. Not removing from count. Monitor if population improves. |
| 2026-04-27 | `ECOMM1` / `ECOMM1:XXXXXXXX` landing as 'Community Agents & Other' | Web self-enrollment channel/session identifiers, not human CSR usernames. | Add `AND account_creation_completed_csr NOT LIKE 'ECOMM1%'` to CSR detection. Routes to `'Customer Self Service'`. |
| 2026-04-27 | AWM shows 0 accounts under reassigned employee's new supervisor | `USER_EVENT_DETAIL` captures supervisor at creation time. BIM reads current supervisor from employee table. | Structural difference. Pending stakeholder decision: creation-time (current AWM behavior) vs current supervisor (requires employee table join). |
