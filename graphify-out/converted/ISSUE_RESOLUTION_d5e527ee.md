<!-- converted from ISSUE_RESOLUTION.docx -->


Paperless Report
Issue Resolution Document

Project:  EDW/AWM Paperless Report (replacement for legacy BIM/Eloqua)
Files:    new_paper.sql  |  cif_join_validation.sql  |  missing_mail.sql
Date:     2026-04-07
Author:   _______________

# Executive Summary
During the build and validation of new_paper.sql — the new EDW/AWM-based paperless report replacing the legacy old_paper.sql (BIM/Eloqua source) — 9 data quality issues were identified and resolved. The pipeline was also optimized from 16 to 10 temp tables.
## Issue Impact Summary

## Final Email Coverage


# Issue 1 — Strict Policyholder Date Join Dropping ~35,820 Policies
### Problem
In cif_join_validation.sql, #view_ph joined DWM.EDW.vw_policyholder using three conditions: policy_term_key + term_effective_date + term_expiration_date. Mid-term endorsements (coverage changes, address updates, etc.) cause the policyholder's term dates to be slightly offset from the policy's effective dates. When these don't match exactly, the join returns no row → party_key = NULL → the entire downstream chain (same-as-link, CIF, email) is broken.
-- BEFORE (broken)
left join DWM.EDW.vw_policyholder vplh
    on vplh.policy_term_key      = it.policy_term_key
   and vplh.term_effective_date  = it.effective_from_date   -- strict date match
   and vplh.term_expiration_date = it.effective_to_date     -- strict date match
   and vplh.term_expiration_date > @as_of_date
### Discovery
missing_mail.sql Section 1 (Email Chain Funnel) showed:
    Has NULL party_key (no policyholder match) : 35,820
### Fix
Relaxed the join to policy_term_key only — matching the pattern already used in paperless.sql:
-- AFTER (fixed)
left join DWM.EDW.vw_policyholder vplh
    on vplh.policy_term_key = it.policy_term_key
### Result
Has NULL party_key : 35,820 → 0
Has duplicate_party_anchor_id (chain can proceed) : 261,592 → 297,412

# Issue 2 — CIF Superseded Records Not Filtered (valid_to_date)
### Problem
AWM.dbo.cif_policy_party_detail uses two separate date columns: effective_to_date (when the paperless preference ends) and valid_to_date (when the record itself was superseded by a newer load). The original query only filtered effective_to_date = '9999-12-31', leaving superseded records in scope. A policy could return a stale paperless indicator from a previous load that has since been updated.
-- BEFORE (incomplete filter)
where cppd.output_document_type_code in ('BIL', 'POL')
  and cppd.effective_to_date = '9999-12-31'
### Discovery
Code review of cif_policy_party_detail table structure. valid_to_date is the AWM standard audit column for record supersession — omitting it is a known pattern risk in AWM queries.
### Fix
Added valid_to_date filter alongside the existing effective_to_date filter:
-- AFTER (fixed)
where cppd.output_document_type_code in ('BIL', 'POL')
  and cppd.effective_to_date = '9999-12-31'
  and cppd.valid_to_date     = '9999-12-31'   -- excludes superseded records
### Result
Ensures only current, non-superseded paperless indicator records are used. Reduces risk of stale 'Y'/'N' indicators from old CIF loads appearing in the report.
# Issue 3 — CIF Dedup Using Wrong Sort Key
### Problem
To get the latest CIF record per (policy_party_link_id, output_document_type_code), the query used ROW_NUMBER() ordered by effective_from_date DESC. However, two records can share the same effective_from_date if a correction was loaded — in that case, effective_from_date does not distinguish which is truly the latest. update_date is the correct audit trail column in AWM for 'most recently written' row.
-- BEFORE (wrong sort key)
row_number() over (
    partition by cppd.policy_party_link_id, cppd.output_document_type_code
    order by cppd.effective_from_date desc
) as rn
### Discovery
Code review of AWM table conventions. update_date is the standard 'last modified' timestamp on AWM operational tables.
### Fix
Changed sort key to update_date DESC:
-- AFTER (correct sort key)
row_number() over (
    partition by cppd.policy_party_link_id, cppd.output_document_type_code
    order by cppd.update_date desc
) as rn
### Result
Guarantees the most recently updated CIF record wins the dedup, preventing stale indicators from surviving when a correction record was loaded on the same effective date.

# Issue 4 — NULL paper_notify_indicator Coerced to 'N' (False Negative)
### Problem
The paperless indicator logic used a two-branch CASE. When no BIL record exists for a policy, MIN(paper_notify_indicator) returns NULL. The CASE evaluates NULL in the ELSE branch → outputs 'N'. This makes the policy appear explicitly non-paperless when in fact there is simply no data. Downstream, this created mismatches in the BIM vs EDW comparison.
-- BEFORE (false negative)
case when c.BIL_paper_notify = 0 then 'Y' else 'N' end as Paperless_Bil_Ind
### Discovery
BIM vs EDW mismatch analysis in cif_join_validation.sql — policies with BillInd = 'Y' in BIM but 'N' in EDW, where the root cause was a missing CIF record rather than a true preference change.
### Fix
Added explicit NULL branch — unknown is not the same as non-paperless:
-- AFTER (correct NULL handling)
case
    when min(case when d.output_document_type_code = 'BIL'
             then d.paper_notify_indicator end) = 0    then 'Y'
    when min(case when d.output_document_type_code = 'BIL'
             then d.paper_notify_indicator end) is null then null
    else 'N'
end as Paperless_Bil_Ind
### Result
Policies with no CIF record now show NULL instead of 'N' for paperless indicators. In Tableau, NULL can be filtered or displayed separately from explicit 'N'.
# Issue 5 — Email Fan-Out from asp_user_account_detail Partition Bug
### Problem
The deduplication of asp_user_account_detail to get one email per account link partitioned by (party_user_account_link_id, user_name). A single link_id with 3 distinct user_name values produced 3 rows all with rn=1 — one per username. When joined downstream, this fanned out every policy with multiple email addresses, producing counts larger than the total policy count.
-- BEFORE (fan-out bug)
row_number() over (
    partition by auad.party_user_account_link_id, auad.user_name
    order by auad.valid_from_date desc
) as rn_detail

-- Observed impossible results:
-- UMB : email_resolved = 29,243  >  total = 27,389  <- impossible
-- DP  : email_resolved = 11,812  >  total = 11,419  <- impossible
### Discovery
missing_mail.sql Sections 4/5 — email counts exceeded total policies, which is mathematically impossible and confirmed a fan-out bug in the partition logic.
### Fix
Removed user_name from the partition — one row per link only:
-- AFTER (fixed)
row_number() over (
    partition by auad.party_user_account_link_id     -- link only, not per user_name
    order by auad.valid_from_date desc, auad.valid_to_date desc
) as rn_detail
### Result
Email counts now exactly satisfy has_email + missing_email = total for every symbol:
  HO  : 101,232 + 29,185 = 130,417
  CA  :  94,405 + 27,697 = 122,102
  UMB :  22,599 +  4,790 =  27,389
  DP  :   9,156 +  2,263 =  11,419
  MA  :   4,867 +  1,219 =   6,086

# Issue 6 — Known Bad Party Anchor IDs Inflating Email Links
### Problem
Two party anchor IDs (7771543 and 13322119) appear in AWM.dbo.party_user_account_link and produce incorrect or inflated link matches. These are known data anomalies.
### Discovery
Identified in the original paperless.sql codebase (line 284) which already excluded them with a comment. Any new query building the email chain that doesn't carry this exclusion will pick up incorrect party-to-account mappings.
### Fix
Added exclusion to all email chain queries in both new_paper.sql and missing_mail.sql:
where pual.party_anchor_id not in ('7771543', '13322119')
### Result
Prevents two known bad anchors from being matched to unrelated parties during the party_user_account_link join, ensuring email resolves to the correct customer.
# Issue 7 — BIM Fallback Email Join Format Mismatch
### Problem
#bim_email stores P.POL_KEY from Eloqua.POLICY. The initial assumption was that POL_KEY is numeric-only (e.g. 0130957), requiring the EDW policy_number (e.g. CA 0130957) to be stripped before joining. This stripping broke the join entirely — bim_fallback_used = 0.
-- BROKEN attempt (incorrect strip)
left join #bim_email bim
    on bim.policy_number = substring(
        src.policy_number,
        case when src.policy_number like 'UMB%' then 5 else 4 end,
        len(src.policy_number)
    )
### Discovery
Validation query showed bim_fallback_used = 0 after the strip was applied — zero BIM emails were matching, confirming the format assumption was wrong.
### Fix
Confirmed POL_KEY format matches EDW policy_number (both use 'CA 0130957' format). Reverted to direct join:
-- FIXED (direct join)
left join #bim_email bim
    on bim.policy_number = src.policy_number
### Result
BIM fallback join started matching correctly. After the ANI fix (Issue 8) resolved the bulk of the gap via AWM, the BIM fallback covered the remaining 464 truly AWM-absent policies.

# Issue 8 — Grain Dedup Losing Email by Preferring NIN Regardless of Email
### Problem
The final output dedup to one row per policy_term_key sorted first by NIN preference. This always selected the NIN (named insured / head of household) row regardless of whether that party had an email. For policies where NIN had no AWM email but the ANI did, the email was discarded — the NIN row won and EmailAddress = NULL.
-- BEFORE (email-blind dedup)
row_number() over (
    partition by b.policy_term_key
    order by
        case when b.policyholder_type_code = 'NIN' then 0 else 1 end,
        b.party_key desc
) as rn_grain
### Discovery
After the policyholder date join fix (Issue 1), awm_email count was 225,188 — still lower than the 232,259 expected from the Section 1 funnel. The gap of ~7,071 was traced to policies where only the ANI party resolved an email address.
### Fix
Added email presence as the first dedup priority, before NIN preference:
-- AFTER (email-aware dedup)
row_number() over (
    partition by b.policy_term_key
    order by
        case when ea.user_name is not null then 0 else 1 end,  -- Priority 1: has email
        case when b.policyholder_type_code = 'NIN' then 0 else 1 end,  -- Priority 2: NIN
        b.party_key desc                                        -- Priority 3: tiebreak
) as rn_grain
### Result
AWM email : 225,188 → 251,664   (+26,476 recovered from ANI parties)
no_email  :  71,211 →  44,735   (-26,476)

Note: When an ANI row wins due to email, the output row carries ANI demographics (HOH_IND = 'N', policyholder_type_code = 'ANI'). The EmailSource column identifies the row as AWM-sourced.
# Issue 9 — BIM HOH Filter Too Restrictive for Fallback
### Problem
#bim_email was built with WHERE C.HOH_IND = 'Y' to pick only the head of household's email from BIM. Many of the 27,756 target policies (incomplete AWM account setup) had email only on non-HOH BIM contacts. The HOH contact either had no email or was the one with the incomplete AWM account. Filtering to HOH only excluded the majority of valid BIM emails.
-- BEFORE (over-filtered)
where C.END_DT      = '9999-12-31'
  and P.END_DT      = '9999-12-31'
  and P.POL_STS_CD  = 'INFORCE'
  and C.HOH_IND     = 'Y'                -- too restrictive
  and C.EMAIL_ADDRESS is not null
### Discovery
After the join format was corrected (Issue 7), bim_fallback_used showed only 2,375 instead of the expected ~27,756 from the Section 7c analysis.
### Fix
Removed HOH_IND = 'Y' filter. MAX(EMAIL_ADDRESS) already ensures one email per POL_KEY across all contacts:
-- AFTER (all contacts, one email per policy)
where C.END_DT      = '9999-12-31'
  and P.END_DT      = '9999-12-31'
  and P.POL_STS_CD  = 'INFORCE'
  and C.EMAIL_ADDRESS is not null
  and C.EMAIL_ADDRESS <> ''
group by P.POL_KEY   -- MAX(EMAIL_ADDRESS) picks one per policy
### Result
After Issue 8 (ANI fix) resolved the bulk of the gap via AWM, the BIM fallback was left with the remaining 464 truly AWM-absent policies — the correct expected residual.

# Email Gap Analysis Summary
After all fixes, the remaining 44,271 policies with no email break down as follows (from missing_mail.sql Section 9a):

Note: The 50,453 + 13,846 + 27,756 total is from the pre-ANI-fix analysis. After the ANI fix (Issue 8) resolved 26,476 via AWM, the structural no-email count reduced to ~44,271. Relative proportions across categories remain consistent.
## No-Account Policies — Product Line Breakdown

All symbols are consistently 50–62% without an account link. This is a structural customer adoption gap, not a data pipeline issue.

# Final Output Validation
Run this query after new_paper.sql completes to confirm expected values:
select
    count(*)                                                         as total_rows,
    sum(case when EmailAddress is not null then 1 else 0 end)        as has_email,
    sum(case when EmailSource = 'BIM'      then 1 else 0 end)        as bim_fallback_used,
    sum(case when EmailSource = 'AWM'      then 1 else 0 end)        as awm_email,
    sum(case when EmailAddress is null     then 1 else 0 end)        as no_email,
    sum(case when Paperless_Bil_Ind = 'Y' then 1 else 0 end)        as paperless_bill_y,
    sum(case when Paperless_Pol_Ind = 'Y' then 1 else 0 end)        as paperless_pol_y,
    sum(case when PolicyStatus = 'INFORCE' then 1 else 0 end)        as inforce_count
from #New_Paper_Report;
## Expected Results (as of 2026-04-07)

# Pipeline Optimization Summary
new_paper.sql reduced the temp table count from 16 (in paperless.sql) to 10:
## Tables Removed

## Tables Added

Grain dedup (one row per policy_term_key) is handled in the final SELECT without an additional temp table, using a priority-aware ROW_NUMBER() that selects email-present rows first, NIN second, and uses party_key as a deterministic tiebreak.
| # | Issue | Policies Impacted |
| --- | --- | --- |
| 1 | Strict policyholder date join dropping policies | 35,820 |
| 2 | CIF superseded records not filtered | Unknown (data quality risk) |
| 3 | CIF dedup using wrong sort key | Unknown (data quality risk) |
| 4 | NULL paper_notify coerced to 'N' (false negative) | Affected all NULL CIF rows |
| 5 | Email fan-out from partition bug | All symbols (counts > total) |
| 6 | Known bad party anchor IDs in email chain | Inflated link counts |
| 7 | BIM fallback join format mismatch | 27,756 (fallback = 0) |
| 8 | NIN dedup preference losing ANI email | 26,476 |
| 9 | BIM HOH filter too restrictive | ~25,000+ (fallback = 2,375 vs expected 27,756) |
| Metric | Before Fixes | After All Fixes |
| --- | --- | --- |
| Total policies | 297,413 | 296,399 (grain dedup) |
| AWM email | 225,188 (75.8%) | 251,664 (84.9%) |
| BIM fallback | 0 | 464 (0.2%) |
| Has email total | 225,188 (75.8%) | 252,128 (85.1%) |
| No email (structural) | 72,225 | 44,271 (14.9%) |
| Gap Category | Policies | Resolution |
| --- | --- | --- |
| No same-as-link (AWM party not mapped) | 1 | Data fix: investigate party_id_same_as_link |
| Never registered online (no account on any party) | 50,453 | Outreach: campaign to drive online registration |
| Incomplete account setup — no email in either system | 13,846 | Outreach: prompt customers to complete account activation |
| Incomplete account setup — BIM email available | 27,756 | Data fix: backfill from BIM (see missing_mail.sql Section 8) |
| Symbol | Unregistered Policies | % of Symbol Total |
| --- | --- | --- |
| HO | 67,670 | 51.9% |
| CA | 61,921 | 50.7% |
| UMB | 14,634 | 53.4% |
| DP | 6,027 | 52.8% |
| MA | 3,748 | 61.6% |
| Metric | Expected Value |
| --- | --- |
| total_rows | ~296,399 |
| has_email | ~252,128  (85.1%) |
| bim_fallback_used | ~464 |
| awm_email | ~251,664 |
| no_email | ~44,271   (14.9%) |
| paperless_bill_y | ~113,834 |
| paperless_pol_y | ~146,296 |
| inforce_count | ~284,879 |
| Removed Table | Merged Into |
| --- | --- |
| #base_data_link | Inlined as subquery in #base_data |
| #CIF_POLICY_Detail1 | Merged into #cif_detail |
| #CIF_POLICY_Detail2 | Merged into #cif_detail |
| #ct_asp_user_account | Merged into #email_account |
| #ct_party_user_account_link | Merged into #email_account |
| #ct_party_user_account | Merged into #email_account |
| #ct_asp_membership | Merged into #email_account |
| Added Table | Purpose |
| --- | --- |
| #bim_email | BIM/Eloqua email fallback (Issue 7 — join format fixed, HOH filter removed) |