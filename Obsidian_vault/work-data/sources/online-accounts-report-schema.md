---
tags: [source]
topic: work-data
sources: 1
updated: 2026-04-17
---

# Source: Online Accounts Report — Project Schema

**File:** `../../../Online_accounts_report/CLAUDE.md`
**Type:** Project schema / CLAUDE.md
**Ingested:** 2026-04-17

---

## Core Claim

Reporting project focused on online account enrollment and adoption across policy,
household, and agent dimensions. Feeds Tableau dashboards. Sub-domain of the
broader [[paperless-report-schema]] project.

---

## Data Sources

- **EDW** (`[DWM].[EDW].[vw_policy]`) — source of truth for policy data
- **AWM** (`[AWM].[dbo].[policy_household_mapping]`) — household mapping
- **Eloqua** (`[BIM_Reporting_Weekly].[Eloqua].[CONTACT/POLICY]`) — online account flags
- **BIM** — legacy, comparison only

See [[data-sources-edw-awm-bim]] for cross-project source rules.

---

## Key Concepts

- [[online-account-indicator]] — Eloqua-sourced flag, cross-validated with AWM
- [[household-grain-reporting]] — dedup to one row per household_id via AWM mapping
- [[policy-deduplication-pattern]] — ROW_NUMBER() over effective_date DESC

---

## Key Metrics

| Metric | Grain |
|---|---|
| Policies with online accounts | Policy |
| Households with online accounts | Household |
| % households enrolled | Household |
| Agent-level rollup | Agent |

---

## Flags

- ℹ Closely related to `../Paperless_report/` — shares all SQL patterns and data sources
- ℹ Online accounts was previously a sub-report inside paperless; now a dedicated project
