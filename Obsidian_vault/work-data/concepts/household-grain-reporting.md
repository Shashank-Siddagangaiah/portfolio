---
tags: [concept]
topic: work-data
sources: 1
updated: 2026-04-17
---

# Household Grain Reporting

Reporting at the household level (one row per household) rather than policy level.
Critical for online account enrollment metrics where the same household may have
multiple policies.

---

## How It Works

1. Join policies to `[AWM].[dbo].[policy_household_mapping]` on policy key
2. Deduplicate to one row per `household_id`
3. Apply household-level aggregations

```sql
ROW_NUMBER() OVER (PARTITION BY household_id ORDER BY effective_date DESC) AS rn
-- WHERE rn = 1
```

---

## Known Issues

- NULL `household_id` = reporting gap — always validate mapping completeness
- NULL households cause variance between household-grain and policy-grain counts
- AWM mapping must be validated before household rollups are trusted

---

## Related

- [[online-account-indicator]] — the flag being reported at household grain
- [[policy-deduplication-pattern]] — dedup pattern used within household logic
- [[data-sources-edw-awm-bim]] — AWM is the source for household mapping
