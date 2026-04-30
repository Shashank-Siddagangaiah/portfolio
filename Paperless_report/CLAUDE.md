# Paperless Report

**Goal:** EDW/AWM rewrite of the legacy BIM/Eloqua paperless report (`old_paper.sql`). Produces per-policy paperless indicators (bill/policy), email resolution, and CIF vs BIM comparison — feeding Tableau dashboards.

**Related project:** `../Online_accounts_report/` — shares AWM→EDW party bridge and `is_up_and_running_indicator = 255`.

---

## File Map

| File | Type | Status |
|---|---|---|
| `new_paper_final.sql` | **Production** — EDW/AWM paperless report (10 temp tables) | Validated 2026-04-09 |
| `cif_join_validation.sql` | **Diagnostic** — email chain breakpoint analysis | All issues fixed |
| `email_val.sql` | **Validation** — CIF vs BIM indicator comparison | Complete |
| `missing_mail.sql` | Investigation — no-email population analysis | Reference |
| `paperless.sql` | Legacy AWM version — superseded | Reference only |
| `old_paper.sql` | Legacy BIM/Eloqua version | Reference only |
| `ISSUE_RESOLUTION.md` | Full root cause + fix for all 15 issues | Deep dives |

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

## Critical Patterns — SQL in CLAUDE_reference.md

Each pattern below has caused a major bug. Full SQL in `CLAUDE_reference.md`.

1. `is_up_and_running_indicator = 255` — tinyint, NOT 1
2. `vw_policyholder` join on `policy_term_key` ONLY — no date conditions (drops 35,820 policies)
3. Bad anchor IDs: exclude `'7771543', '13322119'` in every email chain query
4. CIF filter: both `effective_to_date = '9999-12-31'` AND `valid_to_date = '9999-12-31'`
5. CIF dedup: `ORDER BY update_date DESC` — not `effective_from_date` (correction records share same date)
6. Email-aware grain dedup: Priority 1 = has email, Priority 2 = NIN, Priority 3 = `party_key DESC`
7. `paper_notify_indicator` NULL = absent (not 'N') — use 3-branch CASE
8. `asp_user_account_detail` dedup: PARTITION BY `party_user_account_link_id` only (not link+username)
9. BIM fallback join: no format stripping — `POL_KEY` already matches EDW format

---

## Pipeline Status (Validated 2026-04-09)

| Metric | Value |
|---|---|
| Total rows | ~296,399 |
| Has email (AWM + BIM) | ~252,128 (85.1%) |
| — AWM email | ~251,664 |
| — BIM fallback | ~464 |
| No email | ~44,271 (14.9%) |
| Paperless Bill Y | ~113,834 |
| Paperless Policy Y | ~146,296 |

**Email breakpoints (294,275 base):** EMAIL_RESOLVED NIN ~202,622 (68.9%) | ANI ~47,658 (16.2%) | NO_ACCOUNT_LINK ~36,376 (12.4%) | HAS_LINK_NO_DETAIL ~8,013 (2.7%)

---

## SQL Standards

Generic rules in root `CLAUDE.md` and `CLAUDE_reference.md`.

**Pipeline-specific:** Default to **temp tables** — each step must be independently debuggable. CIF vs BIM 500+ day divergence is **structural** — bidirectional, not a bug.

---

## Clarification Protocol

**Always ask:** join key ambiguous (policy_term_key vs policy_number vs party_anchor_id) | "active" definition | output grain unclear | column exists in multiple sources.

**Never ask:** syntax errors, typos, broken SQL — fix and explain | patterns defined here — just apply.

---

## Debugging Playbook

| Symptom | First check |
|---|---|
| Email count > total policies | Fan-out — `asp_user_account_detail` PARTITION BY must be link_id only |
| `party_key = NULL` for many policies | `vw_policyholder` join has extra date conditions — remove them |
| AWM email count low | ANI email — grain dedup must be email-aware (Priority 1 = has email) |
| BIM fallback = 0 | Format strip on join — remove it, POL_KEY already matches EDW format |
| CIF indicators all NULL | Column name mismatch in `#bim_deduped_ind` — check alias from SELECT INTO |
| Counts too high | Missing bad anchor ID exclusion — `NOT IN ('7771543', '13322119')` |
| CIF vs BIM mismatch large | Structural — 500+ day divergence, bidirectional. Not a bug. |
| Counts too low | `is_up_and_running_indicator` must be 255, not 1 |
