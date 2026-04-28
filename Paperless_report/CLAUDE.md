# Paperless Report

**Goal:** EDW/AWM rewrite of the legacy BIM/Eloqua paperless report (`old_paper.sql`). Produces per-policy paperless indicators (bill/policy), email resolution, and CIF vs BIM comparison — feeding Tableau dashboards.

**Related project:** `../Online_accounts_report/` — shares the AWM→EDW party bridge pattern and `is_up_and_running_indicator = 255`.

---

## File Map

| File | Type | Status |
|---|---|---|
| `new_paper_final.sql` | **Production** — EDW/AWM paperless report (10 temp tables) | Validated 2026-04-09 |
| `cif_join_validation.sql` | **Diagnostic** — email chain breakpoint analysis | All D-issues fixed |
| `email_val.sql` | **Validation** — CIF vs BIM indicator comparison, Section 6 queries | Complete |
| `missing_mail.sql` | Investigation — no-email population analysis | Reference |
| `paperless.sql` | Legacy AWM version — superseded by `new_paper_final.sql` | Reference only |
| `old_paper.sql` | Legacy BIM/Eloqua version | Reference only |
| `new_paper.sql` | Intermediate draft — superseded by `new_paper_final.sql` | Reference only |
| `example_paper.sql` | Example/template | Reference |
| `ISSUE_RESOLUTION.md` | Full root cause + fix documentation for all 15 issues | Read for deep dives |

---

## Data Sources

| System | Role | Trust |
|---|---|---|
| EDW (`DWM.EDW.*`) | Primary source of truth | Highest |
| AWM (`AWM.dbo.*`) | Operational — CIF indicators, email, account links | High |
| BIM / Eloqua | Legacy — fallback email only (464 policies) | Low |

---

## Pipeline Architecture

10 temp tables in sequence. Every downstream step depends on the one above.

```
vw_policy            → #policy_latest    (inforce as of yesterday)
#policy_latest       → #house_latest     (latest household per policy term)
#inforce_terms       = #policy_latest + #house_latest joined

#inforce_terms       → #view_ph          (vw_policyholder — party_key)
#view_ph             → #base_data        (party_id_same_as_link: AWM duplicate → EDW master)
#base_data           → #email_account    (party_user_account_link → asp_user_account_detail)
                     → #cif_detail       (cif_policy_party_detail — BIL/POL indicators)
                     → #policy_agent     (agent/channel info)
                     → #policy_add_info  (EDW paperless indicators)
#base_data           → #bim_email        (BIM/Eloqua fallback for 464 policies)
```

Final output SELECT: grain dedup (email-aware) + BIM fallback join.

---

## Critical Patterns — Each One Has Caused a Major Bug

**1. Active account indicator**
```sql
WHERE is_up_and_running_indicator = 255   -- tinyint; NOT 1
```

**2. vw_policyholder join — policy_term_key ONLY**
```sql
-- CORRECT — join on policy_term_key alone
LEFT JOIN DWM.EDW.vw_policyholder vph ON vph.policy_term_key = it.policy_term_key

-- WRONG — adding date conditions drops 35,820 policies (mid-term endorsements shift dates)
-- ON vph.policy_term_key = it.policy_term_key
-- AND vph.term_effective_date = it.effective_from_date   ← NEVER ADD THIS
```

**3. Bad anchor IDs — exclude in every email chain query**
```sql
WHERE pual.party_anchor_id NOT IN ('7771543', '13322119')
```

**4. CIF filter — both date columns required**
```sql
WHERE cppd.effective_to_date = '9999-12-31'
  AND cppd.valid_to_date     = '9999-12-31'   -- superseded records excluded
```

**5. CIF dedup — order by update_date, not effective_from_date**
```sql
ROW_NUMBER() OVER (PARTITION BY cppd.cif_id ORDER BY cppd.update_date DESC)
-- effective_from_date is non-deterministic when correction records share the same date
```

**6. Email-aware grain dedup — ANI email must not be lost**
```sql
ROW_NUMBER() OVER (
    PARTITION BY policy_term_key
    ORDER BY
        CASE WHEN user_name IS NOT NULL        THEN 0 ELSE 1 END,  -- Priority 1: has email
        CASE WHEN policyholder_type_code='NIN' THEN 0 ELSE 1 END,  -- Priority 2: NIN > ANI
        party_key DESC                                               -- Priority 3: tiebreak
)
-- 47,658 policies get email from ANI party — blind NIN preference drops them all
```

**7. NULL paper_notify_indicator = absent, not 'N'**
```sql
CASE
    WHEN MIN(paper_notify_indicator) = 0    THEN 'Y'
    WHEN MIN(paper_notify_indicator) IS NULL THEN NULL  -- absent ≠ non-paperless
    ELSE 'N'
END
```

**8. asp_user_account_detail dedup — partition by link_id ONLY**
```sql
ROW_NUMBER() OVER (PARTITION BY party_user_account_link_id ...)
-- WRONG: PARTITION BY (link_id, user_name) produces multiple rn=1 rows → email count > total
```

**9. BIM fallback join — no format stripping needed**
```sql
ON bim.policy_number = src.policy_number   -- POL_KEY already matches EDW format
-- WRONG: SUBSTRING strip breaks the join entirely (bim_fallback_used = 0)
```

---

## Pipeline Status (Validated 2026-04-09)

| Metric | Value |
|---|---|
| Total rows | ~296,399 |
| Has email (`AWM + BIM`) | ~252,128 (85.1%) |
| — AWM email | ~251,664 |
| — BIM fallback | ~464 |
| No email | ~44,271 (14.9%) |
| Paperless Bill Y | ~113,834 |
| Paperless Policy Y | ~146,296 |
| Inforce count | ~284,879 |

**Breakpoints (cif_join_validation.sql, 294,275 base policies):**

| Stage | Count | % |
|---|---|---|
| EMAIL_RESOLVED (NIN) | ~202,622 | 68.9% |
| EMAIL_RESOLVED (ANI) | ~47,658 | 16.2% |
| NO_ACCOUNT_LINK | ~36,376 | 12.4% |
| HAS_LINK_NO_DETAIL | ~8,013 | 2.7% |
| NO_SAME_AS_LINK | 1 | ~0% |

---

## SQL Standards

- Default: **temp tables** for this pipeline — each step is independently executable and debuggable.
- Dedup **early** — before joins, not after. See CLAUDE_reference.md checklist.
- No `SELECT *` in production. No correlated subqueries.
- Always `ROW_NUMBER()` for dedup (never RANK/DENSE_RANK).
- CIF vs BIM 500+ day divergence is **structural** — bidirectional, not a timing issue.

---

## Workflow

1. Confirm grain (policy / household)
2. Identify source and trust level
3. Plan join chain on paper — check each step for fan-out before writing
4. Write with section headers and row-count checkpoint comments
5. Validate: `has_email + no_email = total` exactly; COUNT vs COUNT DISTINCT
6. Optimize only after correctness confirmed

---

## Clarification Protocol

**Always ask:**
- Join key ambiguous (policy_term_key vs policy_number vs party_anchor_id)
- "Active" definition — inforce? not cancelled? as-of-date?
- Output grain unclear (policy / household / party)
- Column exists in multiple sources — which takes precedence

**Never ask:**
- Syntax errors, typos, broken SQL — fix and explain
- Patterns defined in this file — just apply them

---

## Debugging Playbook

| Symptom | First check |
|---|---|
| Email count > total policies | Fan-out — check `asp_user_account_detail` PARTITION BY (must be link_id only) |
| `party_key = NULL` for many policies | `vw_policyholder` join has extra date conditions — remove them |
| AWM email count low | ANI email — verify grain dedup is email-aware (Priority 1 = has email) |
| BIM fallback = 0 | Format strip on join — remove it, POL_KEY already matches EDW format |
| CIF indicators all NULL | Column name mismatch in `#bim_deduped_ind` — check alias from SELECT INTO |
| Counts too high | Missing bad anchor ID exclusion — add `NOT IN ('7771543', '13322119')` |
| CIF vs BIM mismatch large | Structural — 500+ day divergence, bidirectional. Not a bug. |
| Counts too low | `is_up_and_running_indicator` — must be 255, not 1 |

---

## Tooling

- **SQL Server** — primary query environment
- **Tableau** — visualization
- **Databricks** — future pipeline work
