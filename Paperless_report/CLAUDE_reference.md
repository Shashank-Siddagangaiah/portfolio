# Paperless Report — Reference Material

Read this file when:
- Applying or debugging deduplication logic
- Running a SQL review
- Investigating a known issue pattern

---

## Deduplication Checklist

**1. PARTITION BY — grain and NULLs**
- Key must exactly match output grain. NULL keys cluster into one partition and dedup against each other — use `ISNULL(key, -1)` or pre-filter.
- Extra columns in PARTITION BY split the grain — one row per (key + extra) ≠ one row per key.

**2. ORDER BY — tiebreakers**
- Primary sort = column defining "latest" for this dataset.
- Always add a secondary tiebreaker (e.g., `primary_key DESC`) — without it, ties are non-deterministic.
- SQL Server sorts NULLs LAST in DESC — a NULL timestamp ranks worst. Use `ISNULL(sort_col, '1900-01-01')` if NULLs should rank as newest.

**3. Input pool — pre-filter before ranking**
- Dedup operates on whatever rows enter the CTE/subquery. Apply validity filters (inforce, valid_to_date, join conditions) BEFORE ranking.
- Test: distinct keys in deduplicated output must equal row count.

**4. Apply dedup EARLY — before joins**
- Dedup the right side of every JOIN before joining. Fan-out from a 1:N join cannot be recovered by deduping the output.

**5. Paperless-specific: email-aware dedup**
- When deduplicating to one row per `policy_term_key`, Priority 1 = has email, Priority 2 = NIN over ANI. Blind NIN preference drops 47,658 ANI email policies.

**6. ROW_NUMBER vs RANK vs DENSE_RANK**
- Always `ROW_NUMBER()` for dedup — guarantees one unique integer per row even on ties.
- `RANK`/`DENSE_RANK` can assign rank=1 to multiple rows on ties — never use for dedup.

---

## SQL Review Checklist

### Correctness
- [ ] Every JOIN produces expected grain — no fan-out, no silent row loss
- [ ] WHERE/ON conditions logically complete
- [ ] NULLs handled: LEFT JOINs, aggregations, CASE logic
- [ ] Commented-out code flagged

### Joins & Keys
- [ ] No `SELECT *`
- [ ] Right side of JOIN is unique or deduped first
- [ ] Join keys at correct grain
- [ ] `vw_policyholder` joined on `policy_term_key` only — no date conditions

### Performance
- [ ] Dedup applied early
- [ ] No functions in JOIN ON clause (e.g., SUBSTRING in ON)
- [ ] No implicit type conversions
- [ ] Date boundaries applied on large tables

### Data Integrity
- [ ] Row count preserved or reduced at each step — never silently increases
- [ ] `has_email + no_email = total` exactly
- [ ] COUNT validation comments at critical checkpoints

### Readability
- [ ] Descriptive aliases
- [ ] WHY comments on non-obvious logic
- [ ] Section headers per pipeline step

---

## Continuous Learning

| Date | Issue | Root Cause | Fix Pattern |
|---|---|---|---|
| 2026-04-09 | `vw_policyholder` join dropped 35,820 policies | Mid-term endorsements shift policyholder date fields away from policy dates. Strict 3-column join fails silently. | Join on `policy_term_key` ONLY — never add `term_effective_date` or `term_expiration_date`. |
| 2026-04-09 | CIF dedup non-deterministic | `ROW_NUMBER()` ordered by `effective_from_date DESC` — correction records share same date as original, producing random winner. | Order by `update_date DESC` — it's the actual audit column. |
| 2026-04-09 | CIF superseded records included | Query only filtered `effective_to_date = '9999-12-31'`. Stale superseded rows have future `effective_to_date` but past `valid_to_date`. | Add `AND valid_to_date = '9999-12-31'` alongside `effective_to_date` filter. |
| 2026-04-09 | NULL `paper_notify_indicator` shown as `'N'` | Two-branch CASE with `ELSE 'N'` coerces NULL (absent data) to explicit non-paperless. | Three-branch CASE: `= 0 → 'Y'`, `IS NULL → NULL`, `ELSE → 'N'`. |
| 2026-04-09 | Email count > total policies | `asp_user_account_detail` deduped by `(link_id, user_name)` — a link with 3 user_names produced 3 rows all with rn=1. | Partition by `party_user_account_link_id` only. |
| 2026-04-09 | Email counts inflated by bad anchor IDs | `7771543` and `13322119` in `party_user_account_link` produce bad party mappings. | `WHERE party_anchor_id NOT IN ('7771543', '13322119')` in all email chain queries. |
| 2026-04-09 | BIM fallback = 0 | `POL_KEY` in BIM already matches EDW `policy_number` format. Substring strip broke the join entirely. | Direct join: `ON bim.policy_number = src.policy_number`. No stripping needed. |
| 2026-04-09 | 26,476 emails lost — NIN preferred over ANI with email | Grain dedup ordered by `policyholder_type_code = 'NIN'` first, regardless of email. NIN with no email wins over ANI with email. | Email-aware ORDER BY: Priority 1 = `user_name IS NOT NULL`, Priority 2 = NIN, Priority 3 = `party_key DESC`. |
| 2026-04-09 | `#bim_deduped_ind` all NULL | Downstream query referenced `POL_KEY` but temp table column was aliased `PolNumber` in SELECT INTO. Silent GROUP BY failure. | Always check the alias used in SELECT INTO before referencing downstream. |
| 2026-04-09 | Mismatch direction CASE returning `'agree'` for mismatches | CASE had no branch for `BIM='N', CIF=NULL` or `BIM=' '` (single space). Blank not normalized. | Wrap all BIM comparisons with `NULLIF(LTRIM(...), '')`. Add explicit branches for all combinations. |
| 2026-04-09 | CIF vs BIM 500+ day divergence flagged as bug | CIF (AWM) and BIM (Eloqua) are separately maintained with no live sync. Divergence is bidirectional. | Structural gap, not a pipeline error. Document and accept. |
| 2026-04-09 | Diagnostic email counts ~20K lower than production | Orphaned link (newest, no account detail) picked as rn=1, hiding valid older link with email. | INNER JOIN to `asp_user_account_detail` inside the link ranking subquery — only links with valid records are ranked. |
