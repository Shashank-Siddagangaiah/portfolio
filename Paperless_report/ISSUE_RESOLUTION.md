# Paperless Report — Issue Resolution Document

**Project:** EDW/AWM Paperless Report (replacement for legacy BIM/Eloqua `old_paper.sql`)  
**Date:** 2026-04-09  
**Files:** `new_paper_final.sql`, `cif_join_validation.sql`, `email_val.sql`  
**Author:** _______________

---

## Executive Summary

During the build and validation of the new EDW/AWM paperless report, **15 issues** were identified
and resolved — 11 in the production pipeline (`new_paper_final.sql`) and 4 in the diagnostic/validation
query (`cif_join_validation.sql`). The pipeline was reduced from 16 to 10 temp tables.

### Issue Impact Summary

| # | File | Issue | Policies Impacted |
|---|------|-------|-------------------|
| 1 | `new_paper_final.sql` | Strict policyholder date join dropping policies | 35,820 |
| 2 | `new_paper_final.sql` | CIF superseded records not filtered | Data quality risk |
| 3 | `new_paper_final.sql` | CIF dedup using wrong sort key | Data quality risk |
| 4 | `new_paper_final.sql` | NULL paper_notify coerced to `'N'` (false negative) | All NULL CIF rows |
| 5 | `new_paper_final.sql` | Email fan-out from partition bug | Counts exceed total |
| 6 | `new_paper_final.sql` | Known bad party anchor IDs in email chain | Inflated link counts |
| 7 | `new_paper_final.sql` | BIM fallback join format mismatch | 27,756 (fallback = 0) |
| 8 | `new_paper_final.sql` | NIN dedup preference discarding ANI email | 26,476 |
| 9 | `new_paper_final.sql` | BIM HOH filter too restrictive for fallback | ~25,000+ |
| 10 | `new_paper_final.sql` | `#bim_deduped_ind` built on wrong column name | All BIM indicator/date columns NULL |
| 11 | `new_paper_final.sql` | Mismatch direction CASE not handling `'N'`/blank BIM values | Incorrect `'agree'` label |
| D1 | `cif_join_validation.sql` | `policyholder_type_code` missing from `#view_ph` | Email-aware dedup blocked |
| D2 | `cif_join_validation.sql` | Orphaned link picked as `rn=1`, hiding valid older link | ~20,034 emails missed |
| D3 | `cif_join_validation.sql` | Grain dedup not email-aware — NIN always picked over ANI | 47,658 ANI emails missed |
| D4 | `cif_join_validation.sql` | No policy-level dedup — breakpoint counts summed above total | 423K rows vs 294K policies |

### Final Email Coverage

| Metric | Before Fixes | After All Fixes |
|--------|-------------|-----------------|
| Total policies | 297,413 | 296,399 |
| AWM email | 225,188 (75.8%) | 251,664 (84.9%) |
| BIM fallback | 0 | 464 (0.2%) |
| **Has email total** | **225,188 (75.8%)** | **252,128 (85.1%)** |
| No email (structural) | 72,225 | 44,271 (14.9%) |

---

## PART 1 — Production Pipeline Issues (`new_paper_final.sql`)

---

## Issue 1 — Strict Policyholder Date Join Dropping ~35,820 Policies

### Problem
`#view_ph` joined `DWM.EDW.vw_policyholder` on three conditions: `policy_term_key`,
`term_effective_date`, and `term_expiration_date`. Mid-term endorsements shift the policyholder's
date fields away from the policy's effective dates, causing the join to fail silently.
When the join fails, `party_key = NULL`, and the entire downstream chain (same-as-link, CIF,
email) produces no output for that policy.

```sql
-- BEFORE
left join DWM.EDW.vw_policyholder vplh
    on vplh.policy_term_key      = it.policy_term_key
   and vplh.term_effective_date  = it.effective_from_date
   and vplh.term_expiration_date = it.effective_to_date

-- AFTER
left join DWM.EDW.vw_policyholder vplh
    on vplh.policy_term_key = it.policy_term_key
```

### Result
```
NULL party_key            : 35,820 → 0
Has party anchor (chain proceeds) : 261,592 → 297,412
```

---

## Issue 2 — CIF Superseded Records Not Filtered (`valid_to_date`)

### Problem
`cif_policy_party_detail` uses two date columns:
- `effective_to_date` — when the paperless preference ends
- `valid_to_date` — when the record was superseded by a newer data load

The original query only filtered on `effective_to_date`. Stale superseded records with old
paperless indicators were included, potentially overriding the current preference.

```sql
-- BEFORE
where cppd.effective_to_date = '9999-12-31'

-- AFTER
where cppd.effective_to_date = '9999-12-31'
  and cppd.valid_to_date     = '9999-12-31'
```

### Result
Only current, non-superseded CIF records feed the paperless indicators.

---

## Issue 3 — CIF Dedup Using Wrong Sort Key

### Problem
`ROW_NUMBER()` to pick the latest CIF record ordered by `effective_from_date DESC`. If a
correction record is loaded on the same effective date as the original, both share the same
`effective_from_date` — the dedup is non-deterministic and may pick the wrong record.
`update_date` is the correct audit column in AWM indicating when a record was last modified.

```sql
-- BEFORE
order by cppd.effective_from_date desc

-- AFTER
order by cppd.update_date desc
```

### Result
Correction records loaded on the same effective date now correctly supersede the original.

---

## Issue 4 — NULL `paper_notify_indicator` Coerced to `'N'` (False Negative)

### Problem
When no CIF record exists for a policy, `MIN(paper_notify_indicator)` returns `NULL`.
A two-branch CASE evaluated `NULL` in the `ELSE 'N'` branch — the policy appeared
explicitly non-paperless when the data was simply absent. This made unmapped policies
indistinguishable from confirmed non-paperless ones.

```sql
-- BEFORE
case when c.BIL_paper_notify = 0 then 'Y' else 'N' end as Paperless_Bil_Ind

-- AFTER
case
    when min(...BIL...) = 0    then 'Y'
    when min(...BIL...) is null then null   -- absent ≠ non-paperless
    else 'N'
end as Paperless_Bil_Ind
```

### Result
Policies with no CIF record show `NULL` (unknown) rather than `'N'` (explicitly non-paperless).

---

## Issue 5 — Email Fan-Out from `asp_user_account_detail` Partition Bug

### Problem
Dedup of `asp_user_account_detail` partitioned by `(party_user_account_link_id, user_name)`.
A single link with 3 distinct `user_name` values produced 3 rows all with `rn = 1`.
Joining downstream fanned out email counts above the total policy count — mathematically
impossible, confirming the bug.

```
UMB : email_resolved = 29,243  >  total = 27,389  ← impossible
```

```sql
-- BEFORE
partition by auad.party_user_account_link_id, auad.user_name

-- AFTER
partition by auad.party_user_account_link_id   -- one email row per link only
```

### Result
`has_email + missing_email = total` exactly for every policy symbol.

---

## Issue 6 — Known Bad Party Anchor IDs Inflating Email Links

### Problem
Anchor IDs `7771543` and `13322119` appear in `party_user_account_link` and produce incorrect
party-to-account mappings, inflating email link counts. Originally identified and excluded in
`paperless.sql` but not carried forward into `new_paper_final.sql`.

### Fix
Applied to all email chain queries:
```sql
where pual.party_anchor_id not in ('7771543', '13322119')
```

---

## Issue 7 — BIM Fallback Email Join Format Mismatch

### Problem
Initial assumption: `POL_KEY` in BIM is numeric-only (`0130957`), requiring a prefix strip
before joining to EDW `policy_number` (`CA 0130957`). The strip broke the join entirely —
`bim_fallback_used = 0` for all 27,756 target policies.

```sql
-- BROKEN (incorrect strip — POL_KEY already matches EDW format)
on bim.policy_number = substring(src.policy_number,
    case when ... then 5 else 4 end, len(...))

-- FIXED (direct join)
on bim.policy_number = src.policy_number
```

### Result
BIM fallback joined correctly. After Issue 8 resolved the bulk via AWM, 464 policies remain
that genuinely have no AWM account and are served by the BIM fallback.

---

## Issue 8 — Grain Dedup Discarding ANI Email When NIN Has None

### Problem
The final grain dedup ordered by NIN (`policyholder_type_code = 'NIN'`) preference first,
regardless of whether the NIN had an email. For policies where the NIN had no email but an
Additional Named Insured (ANI) did, the NIN row always won — the ANI's email was silently
dropped.

```sql
-- BEFORE (email-blind — NIN always wins)
order by
    case when b.policyholder_type_code = 'NIN' then 0 else 1 end,
    b.party_key desc

-- AFTER (email-aware — email presence is Priority 1)
order by
    case when ea.user_name is not null         then 0 else 1 end,  -- Priority 1: has email
    case when b.policyholder_type_code = 'NIN' then 0 else 1 end,  -- Priority 2: NIN over ANI
    b.party_key desc                                                 -- Priority 3: tiebreak
```

**Note:** When an ANI row wins, the output carries ANI demographics (`HOH_IND = 'N'`).
The `EmailSource = 'AWM'` column confirms the email still comes from the AWM system.

### Result
```
AWM email : 225,188 → 251,664   (+26,476 recovered from ANI parties)
no_email  :  71,211 →  44,735   (-26,476)
```

---

## Issue 9 — BIM HOH Filter Too Restrictive for Fallback

### Problem
`#bim_email` filtered `HOH_IND = 'Y'` (head of household only) to avoid duplicate contacts
per policy. Many of the 27,756 target policies had email only on non-HOH BIM contacts — the
HOH either had no email or was the policyholder with the incomplete AWM account. The filter
excluded all valid fallback emails for these policies.

```sql
-- BEFORE
where C.HOH_IND = 'Y'   -- excluded valid non-HOH BIM emails

-- AFTER (filter removed — MAX already ensures one email per policy)
select MAX(C.EMAIL_ADDRESS) as EmailAddress, P.POL_KEY as policy_number
from [BIM_Reporting_Weekly].[Eloqua].[CONTACT] C
...
group by P.POL_KEY
```

### Result
After Issue 8 resolved the bulk via AWM, the remaining 464 BIM matches are the correct
residual — policies with truly absent AWM accounts where BIM holds the only email on record.

---

## Issue 10 — `#bim_deduped_ind` Built on Wrong Column Name

### Problem
`#old_bim` is built with `P.POL_KEY as PolNumber` — the column is aliased `PolNumber` in the
temp table. The downstream `#bim_deduped_ind` creation referenced `POL_KEY` directly, which
does not exist in `#old_bim`. The table was created with all NULL indicator and date columns
because the `GROUP BY POL_KEY` silently failed to match any rows.

```sql
-- BEFORE (wrong column name — POL_KEY doesn't exist in #old_bim)
select
    POL_KEY               as policy_number,
    max(PaperlessBillInd) as PaperlessBillInd, ...
from #old_bim
group by POL_KEY

-- AFTER (correct alias from #old_bim SELECT INTO)
select
    PolNumber             as policy_number,
    max(PaperlessBillInd) as PaperlessBillInd, ...
from #old_bim
group by PolNumber
```

### Result
`PaperlessBillInd`, `PaperlessBillDate`, `PaperlessPolInd`, `PaperlessPolDate` all populate
correctly in `#bim_deduped_ind`.

---

## Issue 11 — Mismatch Direction CASE Not Handling `'N'`/Blank BIM Values

### Problem
The `BIL_mismatch_direction` / `POL_mismatch_direction` columns only fired on `'Y'`
disagreements. Two patterns fell through to `else 'agree'` incorrectly:

1. **BIM = `'N'`, CIF = NULL** — the WHERE clause correctly flagged these as mismatches, but
   the CASE had no branch for this combination, returning `'agree'` instead.
2. **BIM = `' '` (single space), CIF = `'N'`** — blank space was not normalized to NULL, so
   the `bim IS NULL` check did not fire even after adding a NULL branch.

### Fix
Added two new branches and wrapped all BIM comparisons with `NULLIF(LTRIM(...), '')`:

```sql
case
    when nullif(ltrim(bim.PaperlessBillInd),'') = 'Y'
      and isnull(cif.Paperless_Bil_Ind,'N') <> 'Y'        then 'BIM_only'
    when isnull(nullif(ltrim(bim.PaperlessBillInd),''),'N') <> 'Y'
      and cif.Paperless_Bil_Ind = 'Y'                      then 'CIF_only'
    when nullif(ltrim(bim.PaperlessBillInd),'') = 'N'
      and cif.Paperless_Bil_Ind is null                    then 'BIM_N_CIF_missing'
    when nullif(ltrim(bim.PaperlessBillInd),'') is null
      and cif.Paperless_Bil_Ind = 'N'                      then 'CIF_N_BIM_missing'
    else 'agree'
end as BIL_mismatch_direction
```

Applied identically to both BIL and POL.

### Result
Five mismatch direction values now correctly classify all combinations:
`BIM_only`, `CIF_only`, `BIM_N_CIF_missing`, `CIF_N_BIM_missing`, `agree`.

---

## PART 2 — Diagnostic Query Issues (`cif_join_validation.sql`)

These issues caused the validation query to report incorrect email counts, making it appear
the production pipeline had fewer emails than it actually did.

---

## Issue D1 — `policyholder_type_code` Missing from `#view_ph`

### Problem
`#view_ph` only selected `party_key` from `vw_policyholder`. Without `policyholder_type_code`,
the diagnostic grain dedup had no way to distinguish NIN from ANI, so it could not apply
email-aware ordering. The NIN/ANI priority in the `ORDER BY` was inoperative.

```sql
-- BEFORE
select it.*, vplh.party_key
into #view_ph ...

-- AFTER
select it.*, vplh.party_key, vplh.policyholder_type_code
into #view_ph ...
```

### Result
`policyholder_type_code` flows through to `#base_data` and is available in all downstream
diagnostic queries for email-aware dedup ordering.

---

## Issue D2 — Orphaned Link Picked as `rn=1`, Hiding Valid Older Link

### Problem
`party_user_account_link` is ranked `rn=1` by `load_date DESC` before joining to
`asp_user_account_detail`. When a party has multiple links, a newer one may be orphaned
(no `asp_user_account_detail` row), while an older one has a valid email. The diagnostic
picked the newer orphaned link as `rn=1`, classified the policy as `HAS_LINK_NO_DETAIL`,
and never reached the valid older link.

```
party_anchor_id = 500
  Link A  load_date = 2024-06-01  rn=1 picked  → no auad row → HAS_LINK_NO_DETAIL  ✗
  Link B  load_date = 2022-03-01  rn=2 ignored → has auad, email = john@email.com  ✓
```

```sql
-- BEFORE: ranked all links, orphaned ones could win
select party_anchor_id, party_user_account_link_id,
       row_number() over (partition by party_anchor_id order by load_date desc) as rn
from AWM.dbo.party_user_account_link
where party_anchor_id not in ('7771543', '13322119')

-- AFTER: INNER JOIN on auad inside the subquery — only links with valid account records
-- are ranked, so rn=1 is always the latest link that actually has an email
select pual.party_anchor_id, pual.party_user_account_link_id,
       row_number() over (partition by pual.party_anchor_id order by pual.load_date desc) as rn
from AWM.dbo.party_user_account_link pual
inner join AWM.dbo.asp_user_account_detail
    on asp_user_account_detail.party_user_account_link_id = pual.party_user_account_link_id
where pual.party_anchor_id not in ('7771543', '13322119')
```

### Result
~20,034 policies that had valid emails on older links are now correctly classified as
`EMAIL_RESOLVED`. Diagnostic count moves from 229,851 → ~250,280.

---

## Issue D3 — Grain Dedup Not Email-Aware — NIN Always Picked Over ANI

### Problem
The diagnostic's grain dedup (one row per `policy_term_key`) used a static breakpoint
priority ordering. While `EMAIL_RESOLVED = rank 1` was present, the underlying
`row_number()` in `#new_edw` used a date-based tiebreak
(`order by PaperlessBillDate desc, PaperlessPolDate desc`) rather than email presence.
This caused the NIN row to be selected even when it had no email and the ANI did,
because the NIN's CIF dates were non-NULL and ranked first.

```sql
-- BEFORE (date-based tiebreak — NIN with CIF dates wins over ANI with email)
row_number() over (
    partition by b.policy_term_key, b.cif_id
    order by cif.PaperlessBillDate desc, cif.PaperlessPolDate desc
)

-- AFTER (email-aware — mirrors new_paper_final.sql FIX 8)
row_number() over (
    partition by b.policy_term_key
    order by
        case when auad.user_name is not null        then 0 else 1 end,  -- Priority 1: has email
        case when b.policyholder_type_code = 'NIN'  then 0 else 1 end,  -- Priority 2: NIN
        b.party_key desc                                                  -- Priority 3: tiebreak
)
```

### Result
ANI email is selected when NIN has none. Confirmed: 47,658 policies have their email
supplied by an ANI party (`NIN: 202,622` + `ANI: 47,658` = `250,280 EMAIL_RESOLVED`).

---

## Issue D4 — No Policy-Level Dedup — Breakpoint Counts Summed Above Total

### Problem
`vw_policyholder` returns multiple rows per `policy_term_key` (one per policyholder: NIN,
ANI, etc.). Without a policy-level dedup, the breakpoint summary counted each party row
independently. One policy could appear in both `EMAIL_RESOLVED` (ANI row) and
`NO_ACCOUNT_LINK` (NIN row), inflating totals above the actual policy count.

```
EMAIL_RESOLVED  + NO_ACCOUNT_LINK + HAS_LINK_NO_DETAIL + NO_SAME_AS_LINK
= 229,851 + 152,359 + 41,137 + 1 = 423,348   ← impossible (base = 294,275)
```

```sql
-- AFTER: outer dedup collapses to one row per policy_term_key before group by
select chain_breakpoint, count(*) as policy_count
from (
    select policy_term_key, chain_breakpoint,
           row_number() over (
               partition by policy_term_key
               order by case chain_breakpoint when 'EMAIL_RESOLVED' then 1 ... end
           ) as rn
    from (...classified subquery...)
) deduped
where rn = 1
group by chain_breakpoint
```

### Result
Breakpoint counts now sum exactly to 294,275. Each policy appears in exactly one bucket.

---

## Email Chain — Full Diagnostic Results (After All Fixes)

### How the email chain works

To resolve an email for a policy, data must flow through 4 tables in sequence:

```
#base_data (policy + party_key)
   → party_id_same_as_link         maps party_key → duplicate_party_anchor_id
      → party_user_account_link    did this party register online?
         → asp_user_account_detail what is their email (user_name)?
```

Each step is a potential drop-off point. The diagnostic classifies every policy by where
it falls out of the chain.

### Breakpoint summary (294,275 total policies, after all fixes)

| Breakpoint | Policies | % | Meaning |
|---|---|---|---|
| `EMAIL_RESOLVED` | 250,280 | 85.0% | Full chain resolved, email available |
| `NO_ACCOUNT_LINK` | ~36,376 | 12.4% | Never registered online — no `party_user_account_link` |
| `HAS_LINK_NO_DETAIL` | ~8,013 | 2.7% | Registered (link exists) but AWM never wrote account detail |
| `NO_SAME_AS_LINK` | 1 | ~0% | Missing entry in `party_id_same_as_link` |

### ANI email contribution

| Party Type | Policies with EMAIL_RESOLVED |
|---|---|
| NIN (named insured / head of household) | 202,622 |
| ANI (additional named insured) | 47,658 |
| **Total** | **250,280** |

47,658 policies have their email coming from an ANI party. Without Issue 8 / D3 fixes,
all 47,658 would have been dropped as `NO_ACCOUNT_LINK` or `HAS_LINK_NO_DETAIL`.

### Remaining no-email breakdown (~44,271 policies)

| Category | Policies | Resolution Path |
|---|---|---|
| Never registered online | ~36,376 | Outreach: drive online registration |
| Orphaned link — no AWM account detail written | ~8,013 | AWM data quality — flag upstream |
| No same-as-link entry | 1 | Investigate `party_id_same_as_link` manually |
| BIM fallback applied (incomplete AWM account) | 464 | Resolved — BIM email used |

---

## CIF vs BIM Analysis Findings

From `email_val.sql` Section 6 (CIF validation queries):

### Timing Lag (Section 6e)
| Type | Policies | Avg Days Divergence | >30 Days |
|------|----------|--------------------:|----------|
| BIL mismatches | 14,701 | 508 days | >99% |
| POL mismatches | 16,251 | 771 days | >99% |

Negative `min_days` confirms this is **bidirectional** — not a processing lag. CIF (AWM)
and BIM (Eloqua) are separately maintained systems with no live sync. The divergence is
a chronic structural gap, not a batch timing issue.

### Missing CIF Join Path (Section 6f)
| Metric | Value |
|--------|-------|
| `truly_absent_in_awm` | 0 (across all symbols) |
| `has_cif_on_other_link` | ~2× the missing count |

Every "missing" CIF record exists in AWM — it is attached to a different
`policy_party_link_id` than the one the pipeline resolves. Root cause: the pipeline joins
via `party_anchor_id → party_id_same_as_link → duplicate_party_anchor_id`, which may
resolve to the wrong link when a party appears under multiple household configurations.

### CIF-Only Opt-In Dates (Section 6g)
Top opt-in dates are concentrated in **January 2015** (initial Eloqua rollout), with
scattered 2016–2018 entries. These customers enrolled via the agent portal — not the Eloqua
online channel — so they never created an AWM account. This is a chronic historical gap,
not a pipeline error.

---

## Pipeline Structure

### Temp Tables (10 total, reduced from 16 in `paperless.sql`)

| Step | Table | Purpose | Issues Fixed |
|------|-------|---------|---|
| 1 | `#policy_latest` | EDW inforce policies as of yesterday | — |
| 2 | `#house_latest` | Latest household per policy term | — |
| 3 | `#inforce_terms` | Policy + household joined | — |
| 4 | `#cif_detail` | CIF BIL/POL indicators | Issues 2, 3, 4 |
| 5 | `#view_ph` | Policyholder → party_key | Issues 1, D1 |
| 6 | `#base_data` | same-as-link → duplicate_party_anchor_id | — |
| 7 | `#email_account` | AWM email chain | Issues 5, 6 |
| 8 | `#policy_agent` | Agent/channel info | — |
| 9 | `#policy_add_info` | EDW paperless indicators | — |
| 10 | `#bim_email` | BIM/Eloqua fallback email | Issues 7, 9 |

Final grain dedup (Issue 8, D2, D3) and BIM join handled in the output SELECT.

### Merged/Removed Tables (vs `paperless.sql`)

| Removed | Merged Into |
|---------|-------------|
| `#base_data_link` | Inlined in `#base_data` |
| `#CIF_POLICY_Detail1` + `#CIF_POLICY_Detail2` | `#cif_detail` |
| `#ct_asp_user_account` | `#email_account` |
| `#ct_party_user_account_link` | `#email_account` |
| `#ct_party_user_account` | `#email_account` |
| `#ct_asp_membership` | `#email_account` |

---

## Final Output Validation

Expected values when running `new_paper_final.sql` (as of 2026-04-09):

| Metric | Value |
|---|---|
| total_rows | ~296,399 |
| has_email | ~252,128 (85.1%) |
| bim_fallback_used | ~464 |
| awm_email | ~251,664 |
| no_email | ~44,271 (14.9%) |
| paperless_bill_y | ~113,834 |
| paperless_pol_y | ~146,296 |
| inforce_count | ~284,879 |

Expected values when running `cif_join_validation.sql` diagnostics (as of 2026-04-09):

| Metric | Value |
|---|---|
| Total policies in base_data | ~294,275 |
| EMAIL_RESOLVED | ~250,280 (85.0%) |
| — of which NIN supplied email | ~202,622 |
| — of which ANI supplied email | ~47,658 |
| NO_ACCOUNT_LINK | ~36,376 (12.4%) |
| HAS_LINK_NO_DETAIL (orphaned) | ~8,013 (2.7%) |
| NO_SAME_AS_LINK | 1 |
