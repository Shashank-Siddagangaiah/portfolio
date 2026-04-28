---
tags: [concept]
topic: work-data
sources: 2
updated: 2026-04-17
---

# Data Sources — EDW / AWM / BIM / Eloqua

The four data systems used across insurance analytics reporting projects.
Applies to both [[online-accounts-report-schema]] and the Paperless Report.

---

## Source Hierarchy

| System | Role | Trust |
|---|---|---|
| EDW | Primary source of truth | Highest |
| AWM | Operational system | High |
| BIM | Legacy — validation only | Low |
| Eloqua | Marketing / contact data | Supplemental |

**Rule:** Always prefer EDW over BIM. Use BIM only for legacy comparison.

---

## Key Tables

```sql
[DWM].[EDW].[vw_policy]                          -- policy (EDW)
[AWM].[dbo].[policy_household_mapping]            -- household mapping (AWM)
[BIM_Reporting_Weekly].[Eloqua].[CONTACT]         -- contact / online flags
[BIM_Reporting_Weekly].[Eloqua].[POLICY]          -- policy-level Eloqua data
```

---

## Count Differences

AWM counts will differ from BIM — **this is expected**, not a bug.
EDW/AWM logic is more accurate. BIM is legacy.
Always document which source was used in any validation or report.

---

## Related

- [[policy-deduplication-pattern]] — applied when reading from EDW/AWM
- [[online-account-indicator]] — sourced from Eloqua
- [[household-grain-reporting]] — sourced from AWM
