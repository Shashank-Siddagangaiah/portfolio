# Wiki Log

Append-only chronological record of all wiki activity.
Format: `## [YYYY-MM-DD] <action> | <title>`
Parse last 5 entries: `grep "^## \[" log.md | tail -5`

---

## [2026-04-23] ingest | AI Tools & Adoption — Manager Presentation Research

- Pages created: 2
  - `ai/sources/ai-adoption-research-2025.md` — enterprise adoption stats, data engineering trends, presentation best practices
  - `ai/concepts/ai-tools-daily-workflow.md` — Claude Code CLI + ChatGPT workflows, six structured skills, governance rules, real project applications
- Overview updated: `ai/_overview.md` — first substantive content, key themes documented
- Index updated: ai pages 1 → 4, total pages 9 → 12, sources 2 → 4
- Key findings: 78% enterprise AI adoption (McKinsey 2025), 3.7× ROI; structured skills outperform ad-hoc prompting; validation-first governance documented
- Output: `git_portfolio/ai-at-work-presentation.html` — 13-slide formal HTML presentation with industry context, case studies, before/after comparison, governance slide, and roadmap

---

## [2026-04-21] update | Online Accounts EDW Rewrite — Employee/Supervisor dimensions added to all 4 sections

- File updated: `Online_accounts_report/online_accounts_edw_Self.sql`
- All 4 sections (Activation, Initiation, Inforce, DriverOnly) now output Employee and Supervisor columns
- Sections 1 & 2: CSR path only — `account_csr_full_name`, `account_csr_supervisor_name` from USER_EVENT_DETAIL
- Sections 3 & 4: CSR path + agent fallback via `community_agent.agent_name` / `territory_manager`
  - AgentInfo subquery deduped per `policy_term_key` (ROW_NUMBER) to prevent fan-out
  - Join: `policy_agent_commission → agent → community_agent` via `SUBSTRING(agt.agent_number, 4, 3)`
- CASE priority: CSR full name → AgentInfo name → CSR login fallback (Employee); CSR supervisor → territory_manager → 'OTHER' (Supervisor)
- GROUP BY updated in all sections to include Employee/Supervisor CASE expressions
- Pending: validation of Employee/Supervisor dimension against BIM output

---

## [2026-04-20] update | Online Accounts EDW Rewrite — Employee/Supervisor dimension mapping (agent.sql)

- Source analyzed: `Online_accounts_report/agent.sql`
- Concept updated: `work-data/concepts/online-account-indicator.md` — added Employee/Supervisor dimension section
- Key findings:
  - `awm.dbo.community_agent`: `agent_name` = AgencyName, `territory_manager` = Supervisor
  - Join path for Sections 3 & 4: `vw_policy → policy_agent_commission → agent → community_agent` via `SUBSTRING(agt.agent_number, 4, 3)`
  - Sections 1 & 2 (Activation/Initiation): no policy key in scope — agent join requires USER_EVENT_DETAIL column check (open gap)
  - CSR Employee full name + CSR Supervisor name: column names in USER_EVENT_DETAIL unknown — TBD
- Source page updated: `work-data/sources/online-accounts-edw-rewrite-session.md`

---

## [2026-04-20] update | Online Accounts EDW Rewrite — DriverOnly gap analysis + validation complete

- Source page created: `work-data/sources/online-accounts-edw-rewrite-session.md`
- Concept updated: `work-data/concepts/online-account-indicator.md` — added DriverOnly pattern, vw_policy_driver findings
- CLAUDE.md updated: 2 new rows in Continuous Learning (vw_policy_driver coverage gap, vw_policyholder has no DR code)
- Validation results:
  - Activation: ✅ <1% delta
  - Initiation: ✅ <2% delta (2021+ only)
  - Inforce: ✅ CSR -0.88%, Self Service +1.45%
  - DriverOnly: ⚠ ~43% lower than BIM — accepted, documented
- Key finding: `vw_policy_driver` has ~13% coverage gap vs BIM's `CIFDM.fact_person_coverage`. NOT EXISTS approach inflates 17x. INNER JOIN (positive DR signal) is correct approach.

---

## [2026-04-17] update | Online Account Indicator — AWM join pattern validated

- Page updated: `work-data/concepts/online-account-indicator.md`
- Key findings added:
  - `is_up_and_running_indicator = 255` (not 1) for active accounts
  - Correct AWM→EDW join path: `party_id_same_as_link` → `vw_policyholder` → `vw_policy`
  - `policy_party_link → awm.dbo.policy` confirmed partial/broken (2K rows only)
  - WA Auto: 103,490 EDW vs 102,910 BIM (~0.5% delta — within expected variance)
- CLAUDE.md continuous learning table updated with both root causes

---

## [2026-04-17] ingest | Online Accounts Report — Project Schema

- Source: `Online_accounts_report/CLAUDE.md`
- Pages created: 5
  - `work-data/sources/online-accounts-report-schema.md`
  - `work-data/concepts/online-account-indicator.md`
  - `work-data/concepts/household-grain-reporting.md`
  - `work-data/concepts/policy-deduplication-pattern.md`
  - `work-data/concepts/data-sources-edw-awm-bim.md`
- Pages updated: 1 (`index.md`)
- Flags: Online accounts was previously a sub-report inside Paperless; now dedicated project

---

## [2026-04-16] init | Wiki created

- Schema written to `CLAUDE.md`
- `index.md` initialized (0 sources)
- `log.md` initialized
- Topic areas created: `work-data`, `ai`
- Folder structure: concepts/, entities/, sources/, raw/ per topic
