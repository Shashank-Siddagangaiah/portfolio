---
name: AI Tools in Daily Data Engineering Workflow
description: How Claude Code CLI and ChatGPT are integrated into daily SQL development, debugging, planning, and reporting workflows
type: user
tags: [claude-code, chatgpt, workflow, sql, data-engineering, skills]
topic: ai
sources: direct practice, ai-adoption-research-2025
updated: 2026-04-23
---

# AI Tools in Daily Data Engineering Workflow

Documents how AI tools are actively used in insurance analytics data engineering work.

## Primary Tool: Claude Code CLI

**Role:** Drives all structured, multi-step engineering tasks directly inside VS Code and the terminal.

### Daily Use Cases

| Task | How AI Helps |
|------|-------------|
| SQL query building | Translates business requirements into correct, optimized queries against EDW/AWM |
| Deduplication logic | Debugs ROW_NUMBER() patterns across complex multi-table joins |
| Tableau-compatible SQL | Writes CTEs in `.sql` files (best practice); converts to nested subqueries only when pasting into Tableau Custom SQL (platform limitation, not a SQL standard) |
| Schema exploration | Navigates unfamiliar EDW/AWM/BIM tables and join paths without trial-and-error |
| Pipeline planning | Breaks multi-section report builds into ordered, independently testable steps |

### Structured Workflows (Skills)

Six structured AI workflows replace ad-hoc prompting:

1. **Brainstorming** — Explore requirements and design before touching code
2. **Test-Driven Development** — RED-GREEN-REFACTOR cycle for SQL and scripts
3. **Systematic Debugging** — Root cause first, not trial-and-error
4. **Implementation Planning** — Bite-sized, reviewable steps before execution
5. **Verification** — Explicit checklist before marking any task complete
6. **Code Review** — Structured review of AI-generated SQL before production execution

## Secondary Tool: ChatGPT

**Role:** Ad-hoc research, writing assistance, quick exploratory questions outside the coding environment.

- Industry and technical research
- Writing assistance (documentation, emails, reports)
- Cross-referencing SQL behavior and edge cases

## Governance Rules

- All AI-generated SQL is manually reviewed before execution on production data
- No sensitive customer data is shared with external AI tools — schema references only
- Cross-source validation queries reconcile EDW vs. AWM vs. BIM counts at every milestone
- All decisions, architectural gaps, and resolutions documented in Obsidian vault

## Real Work Applications

### Online Accounts EDW Rewrite
- Four-section UNION ALL rewrite replacing BIM dependency with AWM + EDW
- AI assisted: join path analysis, dedup review, Employee/Supervisor dimension mapping
- Results: <2% variance on 3 of 4 sections; DriverOnly ~43% gap identified and documented
- See: [[work-data/sources/online-accounts-edw-rewrite-session]]

### Paperless Report Pipeline
- Multi-source pipeline (EDW/AWM/BIM) for paperless indicator and adoption tracking
- AI assisted: CIF join path analysis, missing mail/email validation, Tableau SQL structuring
- See: [[work-data/sources/online-accounts-report-schema]]

## See Also

- [[ai/sources/ai-adoption-research-2025]] — Industry context and adoption statistics
- [[work-data/concepts/policy-deduplication-pattern]] — Key SQL pattern used in all AI-assisted queries
- [[work-data/concepts/data-sources-edw-awm-bim]] — The source hierarchy AI helps navigate

## Portfolio Presentation

This note is the source of record for the public-facing slide deck:
**`git_portfolio/ai-at-work-presentation.html`** — "AI in My Daily Workflow" (Shashank Siddagangaiah)

The presentation covers the same use cases, governance rules, and structured skill workflows documented here. If this note is updated, review the presentation for consistency. The presentation is the outward-facing version; this note is the internal living document.
