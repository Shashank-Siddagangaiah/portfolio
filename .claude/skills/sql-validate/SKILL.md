---
name: sql-validate
description: Run the full SQL validation checklist against the current query or file
---

# SQL Validate

Run every check below against the query in context (open file or selection). For each item, state PASS / FAIL / N/A and a one-line reason. Fail items get a concrete fix suggestion.

---

## 1. Grain

- What is the expected output grain? (policy / party / household / state)
- Does every JOIN preserve that grain — no fan-out, no silent row loss?
- If a JOIN multiplies rows, is that intentional and handled (DISTINCT or GROUP BY)?

## 2. Deduplication

- Is `ROW_NUMBER()` used for all dedup? (never RANK/DENSE_RANK)
- Is dedup applied **before** joins, not after?
- Is PARTITION BY keyed to exactly the right grain — no extra columns splitting it?
- Is ORDER BY deterministic — primary sort + a tiebreaker?
- Does the dedup input pool pre-filter invalid/stale rows before ranking?

## 3. NULL Handling

- LEFT JOINs: are unmatched rows handled explicitly, or do they silently become NULLs in GROUP BY / CASE?
- CASE statements: does every branch cover NULL, or does ELSE catch NULLs incorrectly (e.g., NULL → `'N'` instead of NULL)?
- Aggregations: does `MIN()` / `MAX()` on nullable columns produce misleading results?

## 4. Date Boundaries

- Are all large table joins filtered with both `effective_from_date <= @date` AND `effective_to_date > @date`?
- Is `vw_policyholder` joined on `policy_term_key` ONLY (no date conditions)?
- Is `is_up_and_running_indicator = 255` (not 1) for active account filters?

## 5. Row Count Integrity

- Does row count stay flat or decrease at every pipeline step — never increases without explanation?
- Is there a `COUNT` validation comment or checkpoint after the most complex joins?
- For email resolution: does `has_email + no_email = total` exactly?

## 6. Join Keys

- Are join keys at the correct grain? (`policy_term_key` vs `policy_number` vs `party_anchor_id`)
- Is the right side of every JOIN unique or deduped first?
- For AWM→EDW joins: is `party_id_same_as_link` used (not `policy_party_link`)?

## 7. Production Hygiene

- No `SELECT *`
- No correlated subqueries on large tables
- No functions in JOIN ON clause (e.g., `SUBSTRING` in ON)
- No implicit type conversions on join keys
- No commented-out code left unexplained

---

## Output Format

```
GRAIN        : PASS — one row per policy_term_key confirmed
DEDUP        : FAIL — ROW_NUMBER partitioned by (link_id, user_name); must be link_id only
NULLS        : PASS
DATE BOUNDS  : PASS
ROW COUNT    : FAIL — Step 4→5 increases rows; fan-out suspected
JOIN KEYS    : PASS
HYGIENE      : PASS

Fixes needed:
1. DEDUP: Change PARTITION BY to party_user_account_link_id only
2. ROW COUNT: Add COUNT(*) checkpoint between Step 4 and Step 5; check vw_policyholder join grain
```
