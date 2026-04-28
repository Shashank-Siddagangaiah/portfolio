# Online Accounts Report — Reference Material

Read this file when:
- Applying or debugging deduplication logic
- Running a SQL review checklist
- Investigating a known data issue class

---

## Deduplication Checklist (apply before every ROW_NUMBER usage)

**1. PARTITION BY — Grain & NULLs**
- Partition key must exactly match the output grain (policy_number, household_id, party_anchor_id — never mix levels)
- If partition key can be NULL: NULL rows cluster into one partition and dedup against each other; use `ISNULL(key, -1)` or filter NULLs out first if they should not compete
- Adding extra columns to PARTITION BY splits the dedup grain — one row per (key + extra) is NOT the same as one row per key

**2. ORDER BY — Tiebreakers & NULLs**
- Primary sort must be the column that defines "latest" for this dataset (update_date > effective_date if records can share effective_date)
- Always add a secondary tiebreaker (e.g., `primary_key DESC`) — without it, ties produce non-deterministic results across executions
- SQL Server sorts NULLs LAST in DESC order — a NULL timestamp ranks worst and gets eliminated; add `ISNULL(sort_col, '1900-01-01')` if NULLs should sort as "newest"

**3. Input Pool — Pre-filter Before Ranking**
- Dedup operates on whatever rows enter the CTE — orphaned, inactive, or invalid rows in the pool compete for rn=1
- Apply all validity filters (inforce indicator, valid_to_date, join conditions) INSIDE the deduped CTE, not after it
- Test: the number of distinct partition keys in the deduplicated output must equal the row count — if not, invalid rows are winning

**4. Apply Dedup EARLY — Not After Joins**
- Dedup the right-hand side of every JOIN before joining, not the result after
- A 1:N join before dedup produces fan-out; deduping the output does not recover the correct row — it just hides the fan-out
- Rule: if a table has duplicate keys, dedup it in its own CTE first, then join the deduplicated CTE

**5. Post-Dedup Validation (run these checks)**
```sql
-- Did dedup actually reduce rows?
SELECT COUNT(*) AS before_dedup FROM source_table;
SELECT COUNT(*) AS after_dedup  FROM deduped_cte;   -- should equal COUNT(DISTINCT key)

-- Verify no duplicates survived
SELECT partition_key, COUNT(*)
FROM deduped_cte
GROUP BY partition_key
HAVING COUNT(*) > 1;    -- must return 0 rows

-- Spot-check one key with multiple source rows
SELECT * FROM source_table WHERE partition_key = '<known_duplicate_key>';
SELECT * FROM deduped_cte  WHERE partition_key = '<known_duplicate_key>';
```

**6. ROW_NUMBER vs RANK vs DENSE_RANK**
- Always use `ROW_NUMBER()` for deduplication — it guarantees one unique integer per row even on ties
- `RANK()` and `DENSE_RANK()` can assign rank=1 to multiple rows when there is a tie — do NOT use them for dedup
- Only use `RANK`/`DENSE_RANK` when you intentionally want ties treated equally (e.g., ranking agents by revenue where shared rank is meaningful)

---

## SQL Review Checklist (apply to every query)

### Correctness
- [ ] Every JOIN produces expected grain — no fan-out, no silent row loss
- [ ] WHERE/ON conditions logically complete
- [ ] NULLs handled: LEFT JOINs, aggregations, CASE logic
- [ ] Commented-out code flagged

### Joins & Keys
- [ ] Every JOIN has a documented reason
- [ ] No `SELECT *`
- [ ] Right side of JOIN is unique or deduped first
- [ ] Join keys at correct grain

### Performance
- [ ] Dedup applied early
- [ ] No functions in JOIN ON clause (e.g., SUBSTRING in ON)
- [ ] No implicit type conversions
- [ ] Date boundaries applied on large tables

### Data Integrity
- [ ] Row count preserved or reduced at each step — never silently increases
- [ ] COUNT validation comments at critical checkpoints
- [ ] Dedup key + ORDER is deterministic (no ties)

### Readability
- [ ] Descriptive aliases
- [ ] WHY comments on non-obvious logic
- [ ] Consistent formatting and casing
- [ ] Section headers per pipeline step

---

## Continuous Learning

*Root causes and fix patterns discovered during development.*

| Date | Issue | Root Cause | Fix Pattern |
|---|---|---|---|
| 2026-04-17 | `is_up_and_running_indicator = 1` returned 0 rows | Column is tinyint, not boolean. Empirically confirmed: active = 255, inactive = 0, unknown = NULL. | Filter `= 255` for active accounts. Never `= 1` or `ISNULL(...,0) = 1`. |
| 2026-04-17 | AWM→EDW policy join lost 99% of rows (265K→2K) | `policy_party_link → awm.dbo.policy` is a partial satellite (~2K rows). `policy_party_link.party_anchor_id` does not share ID space with `party_user_account_link.party_anchor_id` | Use `party_id_same_as_link` to map AWM `party_anchor_id` (duplicate) → EDW `party_key` (master), then join via `vw_policyholder.party_key → vw_policy.policy_term_key`. |
| 2026-04-20 | DriverOnly AWM count ~43% lower than BIM | `vw_policy_driver` has ~13% coverage gap vs BIM's `CIFDM.fact_person_coverage → dim_policy_role`. 3,971 BIM DR parties have no row in `vw_policy_driver`. No EDW view is a full equivalent of `dim_policy_role`. | **Gap under active investigation.** Interim: INNER JOIN on `vw_policy_driver` (require positive DR signal). NOT EXISTS inflates count 17x. |
| 2026-04-20 | `vw_policyholder.policyholder_type_code` has no DR rows | DR code does not exist in `vw_policyholder` — only NIN/ANI. EDW separates driver roles into `vw_policy_driver`. | Use `vw_policy_driver` for DriverOnly filter, not `vw_policyholder`. |
| 2026-04-24 | AWM shows username/OTHER for ~61% of parties instead of employee name/supervisor | `USER_EVENT_DETAIL` CSR fields only populated for ~39% of Creation events. | Accept gap. Show `UPPER(LTRIM(RTRIM(username)))` as Employee and 'OTHER' as Supervisor. Do not use `community_agent.agent_name` as fallback — agency-level, not the enrolling person. |
| 2026-04-24 | `vw_policyholder.policyholder_inforce_indicator = 1` returns 7.2M rows vs 272K from `vw_policy` join | `policyholder_inforce_indicator` marks the person-policy relationship row as valid, not the policy as effective today. | Always join `vw_policy` with `policy_inforce_indicator = 1` AND date boundaries. Never substitute `policyholder_inforce_indicator` alone. |
| 2026-04-24 | BIM shows agent names in Employee/Supervisor for Community Agents & Other rows | BIM's `AccountStatusXml` CSR fields are populated for agent-assisted enrollments with agent name and agency name. | Expected behavior — not a bug. CostCenter correctly lands as 'Community Agents & Other'. |
| 2026-04-27 | BIM DriverOnly query (`validation_Self.sql`) used `prld_code IN ('NIN', 'ANI')` — returned only 8 CSR rows, CSS row absent | `CIFDM.dim_policy_role.prld_code` uses `'NI'` for Named Insured (not `'NIN'`). `'NIN'` is `vw_policy_driver.policyholder_type_code` — the EDW code. Never cross-use. BIM codes: `NI`, `ANI`, `DR`. EDW codes: `NIN`, `ANI`, `DR`. | Fixed BIM query to `IN ('NI', 'ANI')`. After fix: BIM CSR=476, CSS=264. The 43% DriverOnly gap is real — not a baseline error. |
| 2026-04-27 | 39,002 parties with NULL `policyholder_type_code` in `vw_policy_driver` classified as DriverOnly | `HAVING SUM(CASE WHEN policyholder_type_code IN ('NIN','ANI') THEN 1 ELSE 0 END) = 0` treats NULL as "not NIN/ANI". Role is unknown, not confirmed DR. | Documented as known data quality gap. Not removing from count. Monitor if population improves. |
| 2026-04-27 | `ECOMM1` and `ECOMM1:XXXXXXXX` in `account_creation_completed_csr` landing as 'Community Agents & Other' | Web self-enrollment channel/session identifiers, not human CSR usernames. 262 users with plain `ECOMM1`; others with hex suffix. | Add `AND account_creation_completed_csr NOT LIKE 'ECOMM1%'` to CSR detection WHEN condition in all sections. These route to 'Customer Self Service'. |
| 2026-04-27 | AWM shows 0 accounts under reassigned employee's new supervisor (e.g., Shelly Eckel) | `USER_EVENT_DETAIL` captures supervisor at account creation time. BIM reads current supervisor from employee table. Employees transferred after account creation keep old supervisor in AWM. | Structural difference, not a bug. Pending stakeholder decision: reflect creation-time supervisor (current AWM behavior) or current supervisor (requires employee table join). |
