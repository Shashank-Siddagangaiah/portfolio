# Claude_git — Workspace

**Projects:** Insurance analytics (SQL/Tableau), portfolio website, knowledge vault.
All data work targets AWM/EDW as the rewrite of legacy BIM.

---

## Folder Structure

| Folder | Type | Description |
|---|---|---|
| `Online_accounts_report/` | Data project | Self-service account enrollment reporting — 4 DateTypes, Tableau |
| `Paperless_report/` | Data project | Paperless indicators, email resolution, CIF vs BIM comparison |
| `Obsidian_vault/` | Knowledge base | LLM-maintained wiki — work-data and ai topics |
| `git_portfolio/` | Frontend | Static portfolio website — GitHub Pages, pure HTML/CSS/JS |
| `graphify-out/` | Generated output | Knowledge graph from `/graphify` — do not manually edit |

Each folder has its own `CLAUDE.md` with file maps, project status, and known issues.
Shared SQL checklists and deduplication rules live in root `CLAUDE_reference.md`.

---

## Shared AWM/EDW Architecture

These facts apply to every query touching AWM or EDW. Each one has caused a major debugging session.

**Active account indicator**
```sql
WHERE is_up_and_running_indicator = 255   -- tinyint all-bits-set; NEVER use = 1
```

**AWM → EDW party bridge**
```sql
-- party_user_account_link.party_anchor_id  = AWM DUPLICATE anchor (not the EDW key)
-- party_id_same_as_link maps it to the EDW MASTER party_key
INNER JOIN AWM.dbo.party_id_same_as_link pil
    ON pil.party_anchor_id_duplicate = pual.party_anchor_id
-- then reach EDW via: pil.party_anchor_id_master = vph.party_key
```

**Inforce policy filter — always both conditions**
```sql
AND vp.policy_inforce_indicator = 1
AND vp.effective_from_date <= @as_of_date
AND vp.effective_to_date   >  @as_of_date
-- WARNING: policyholder_inforce_indicator alone returns 7.2M rows — wrong
```

**vw_policyholder join — policy_term_key ONLY**
```sql
-- CORRECT
LEFT JOIN DWM.EDW.vw_policyholder vph ON vph.policy_term_key = it.policy_term_key
-- WRONG — adding date conditions silently drops policies with mid-term endorsements
```

---

## Data Source Trust Hierarchy

| System | Role | Trust |
|---|---|---|
| EDW (`DWM.EDW.*`) | Primary source of truth | Highest |
| AWM (`AWM.dbo.*`) | Operational | High |
| BIM (`BIM_Reporting_Weekly.*`) | Legacy — validation only | Low |
| Eloqua | Marketing / contact | Supplemental |

- All rewrites and new queries use EDW/AWM. BIM is comparison baseline only.
- When counts differ vs BIM: investigate root cause — higher is not automatically correct.
- Never guess the source of truth — ask if ambiguous.

---

## SQL Standards

- **Dedup:** `ROW_NUMBER()` only — never `RANK`/`DENSE_RANK`. Apply **early**, before joins, not after.
- **No `SELECT *`** in production. Explicit column list always.
- **No correlated subqueries** on large tables — use JOINs.
- **Date boundaries** on every large table join.
- **CTEs vs temp tables:** default CTEs; use temp tables only when materializing a result used 3+ times or when step-by-step debuggability is needed.
- Full dedup checklist and SQL review checklist: see `CLAUDE_reference.md` (root).

---

## Tooling

- **SQL Server** — primary query environment
- **Tableau** — visualization; CTEs invalid in Custom SQL, use `_tableau.sql` variants
- **Databricks** — future pipeline work
- **Atlan** — data catalog
