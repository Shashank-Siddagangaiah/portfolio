---
tags: [concept]
topic: work-data
sources: 1
updated: 2026-04-17
---

# Policy Deduplication Pattern

Standard SQL pattern used across all EDW/AWM reporting to get the latest
effective record per key, avoiding duplicate rows from SCD (slowly changing
dimension) history tables.

---

## Pattern

```sql
WITH deduped AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY policy_number  -- or policy_term_key depending on grain
            ORDER BY effective_date DESC
        ) AS rn
    FROM [DWM].[EDW].[vw_policy]
    WHERE effective_from_date <= @as_of_date
      AND effective_to_date   >  @as_of_date
)
SELECT *
FROM deduped
WHERE rn = 1
```

---

## Rules

- Apply **early** — before downstream joins — to minimize row fan-out
- Partition key depends on grain: `policy_number`, `policy_term_key`, or `household_id`
- ORDER BY must be deterministic — avoid ties (add secondary sort if needed)
- Always validate: `COUNT(*) vs COUNT(DISTINCT partition_key)` should match after dedup

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Dedup after a fan-out join | Move dedup before the join |
| Non-deterministic ORDER BY | Add secondary sort column |
| Wrong partition key | Confirm grain with business requirement |

---

## Related

- [[household-grain-reporting]] — uses this pattern at household level
- [[data-sources-edw-awm-bim]] — applies to EDW and AWM tables
- [[online-accounts-report-schema]] — uses this pattern throughout
