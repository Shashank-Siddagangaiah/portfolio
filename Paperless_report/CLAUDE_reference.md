# Paperless Report — Reference Material

Deduplication checklist and SQL review checklist are in root `CLAUDE_reference.md`.

---

## Critical SQL Patterns

**1. Active account indicator**
```sql
WHERE is_up_and_running_indicator = 255   -- tinyint; NOT 1
```

**2. vw_policyholder — policy_term_key ONLY**
```sql
LEFT JOIN DWM.EDW.vw_policyholder vph ON vph.policy_term_key = it.policy_term_key
-- NEVER add term_effective_date or term_expiration_date — drops 35,820 policies
```

**3. Bad anchor IDs**
```sql
WHERE pual.party_anchor_id NOT IN ('7771543', '13322119')
```

**4. CIF filter — both date columns**
```sql
WHERE cppd.effective_to_date = '9999-12-31'
  AND cppd.valid_to_date     = '9999-12-31'
```

**5. CIF dedup — update_date not effective_from_date**
```sql
ROW_NUMBER() OVER (PARTITION BY cppd.cif_id ORDER BY cppd.update_date DESC)
```

**6. Email-aware grain dedup**
```sql
ROW_NUMBER() OVER (
    PARTITION BY policy_term_key
    ORDER BY
        CASE WHEN user_name IS NOT NULL        THEN 0 ELSE 1 END,
        CASE WHEN policyholder_type_code='NIN' THEN 0 ELSE 1 END,
        party_key DESC
)
-- 47,658 policies get email from ANI — blind NIN preference drops them all
```

**7. NULL paper_notify_indicator**
```sql
CASE
    WHEN MIN(paper_notify_indicator) = 0    THEN 'Y'
    WHEN MIN(paper_notify_indicator) IS NULL THEN NULL
    ELSE 'N'
END
```

**8. asp_user_account_detail dedup**
```sql
ROW_NUMBER() OVER (PARTITION BY party_user_account_link_id ...)
-- WRONG: PARTITION BY (link_id, user_name) → multiple rn=1 → email count > total
```

**9. BIM fallback join**
```sql
ON bim.policy_number = src.policy_number   -- no format stripping needed
```

---

## Continuous Learning

---

## Continuous Learning

### CIF Data Issues

| Date | Issue | Root Cause | Fix Pattern |
|---|---|---|---|
| 2026-04-09 | CIF superseded records included | Only filtered `effective_to_date = '9999-12-31'`. Stale superseded rows have future `effective_to_date` but past `valid_to_date`. | Add `AND valid_to_date = '9999-12-31'` alongside `effective_to_date`. |
| 2026-04-09 | CIF dedup non-deterministic | `ROW_NUMBER()` ordered by `effective_from_date DESC` — correction records share same date as original. | Order by `update_date DESC` — the actual audit column. |
| 2026-04-09 | NULL `paper_notify_indicator` shown as `'N'` | Two-branch CASE `ELSE 'N'` coerces absent data to explicit non-paperless. | Three-branch: `= 0 → 'Y'`, `IS NULL → NULL`, `ELSE → 'N'`. |
| 2026-04-09 | `#bim_deduped_ind` all NULL | Downstream query referenced `POL_KEY` but SELECT INTO aliased it as `PolNumber`. Silent GROUP BY failure. | Always check the alias used in SELECT INTO before referencing downstream. |
| 2026-04-09 | Mismatch direction CASE returning `'agree'` for mismatches | No branch for `BIM='N', CIF=NULL` or `BIM=' '` (single space). Blank not normalized. | Wrap all BIM comparisons with `NULLIF(LTRIM(...), '')`. Add branches for all combinations. |
| 2026-04-09 | CIF vs BIM 500+ day divergence flagged as bug | CIF (AWM) and BIM (Eloqua) are separately maintained with no live sync. Bidirectional. | Structural gap. Not a pipeline error. Document and accept. |

---

### Email Chain / Account Link

| Date | Issue | Root Cause | Fix Pattern |
|---|---|---|---|
| 2026-04-09 | Email count > total policies | `asp_user_account_detail` deduped by `(link_id, user_name)` — a link with 3 user_names produced 3 rows all `rn=1`. | Partition by `party_user_account_link_id` only. |
| 2026-04-09 | Email counts inflated | Anchor IDs `7771543` and `13322119` produce bad party mappings. | `WHERE party_anchor_id NOT IN ('7771543', '13322119')` in all email chain queries. |
| 2026-04-09 | Diagnostic counts ~20K lower than production | Orphaned link (newest, no account detail) picked as `rn=1`, hiding valid older link with email. | INNER JOIN to `asp_user_account_detail` inside the link ranking subquery — only links with valid records compete for `rn=1`. |
| 2026-04-09 | 26,476 emails lost — NIN preferred over ANI with email | Grain dedup ordered by `policyholder_type_code = 'NIN'` first, regardless of email presence. | Email-aware ORDER BY: Priority 1 = `user_name IS NOT NULL`, Priority 2 = NIN, Priority 3 = `party_key DESC`. |
| 2026-04-09 | Diagnostic grain dedup not email-aware | `row_number()` ordered by CIF dates — NIN with CIF dates wins over ANI with email. | Mirror production's email-aware ORDER BY in all diagnostic queries. |
| 2026-04-09 | Diagnostic counts summed above total | No policy-level dedup — one policy appeared in both `EMAIL_RESOLVED` and `NO_ACCOUNT_LINK`. | Outer dedup: collapse to one row per `policy_term_key` before GROUP BY, prioritising EMAIL_RESOLVED. |

---

### BIM Fallback

| Date | Issue | Root Cause | Fix Pattern |
|---|---|---|---|
| 2026-04-09 | BIM fallback = 0 | `POL_KEY` already matches EDW `policy_number` format. Substring strip broke the join. | Direct join: `ON bim.policy_number = src.policy_number`. No stripping. |
| 2026-04-09 | BIM HOH filter excluded valid fallback emails | `HOH_IND = 'Y'` filter removed non-HOH contacts who held the only available email. | Remove HOH filter — `MAX(EMAIL_ADDRESS)` already ensures one email per policy. |

---

### Cross-System / Architecture

| Date | Issue | Root Cause | Fix Pattern |
|---|---|---|---|
| 2026-04-09 | `vw_policyholder` join dropped 35,820 policies | Mid-term endorsements shift policyholder date fields away from policy dates. Strict 3-column join fails silently. | Join on `policy_term_key` ONLY — never add `term_effective_date` or `term_expiration_date`. |
