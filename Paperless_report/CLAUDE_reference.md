# Paperless Report — Reference Material

Deduplication checklist and SQL review checklist have moved to root `CLAUDE_reference.md`.

Read this file for project-specific Continuous Learning, organized by category for fast lookup.

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
