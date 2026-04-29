# Workspace — Shared Reference

Shared across all data projects. Read when applying deduplication, running a SQL review, or debugging query correctness.

Project-specific Continuous Learning logs live in each folder's own `CLAUDE_reference.md`.

---

## Deduplication Checklist

**1. PARTITION BY — grain and NULLs**
- Key must exactly match output grain. Never mix levels (policy_number vs policy_term_key vs party_anchor_id).
- NULL keys cluster into one partition and dedup against each other — use `ISNULL(key, -1)` or pre-filter NULLs.
- Extra columns in PARTITION BY split the grain — one row per (key + extra) ≠ one row per key.

**2. ORDER BY — tiebreakers**
- Primary sort = column defining "latest" for this dataset (`update_date` > `effective_date` when corrections share the same effective date).
- Always add a secondary tiebreaker (e.g., `primary_key DESC`) — without it, ties produce non-deterministic results.
- SQL Server sorts NULLs LAST in DESC — a NULL timestamp ranks worst. Use `ISNULL(sort_col, '1900-01-01')` if NULLs should rank as newest.

**3. Input pool — pre-filter before ranking**
- Dedup operates on whatever rows enter the CTE/subquery. Apply all validity filters (inforce indicator, `valid_to_date`, join conditions) BEFORE the `ROW_NUMBER()`, not after.
- Test: distinct partition keys in the deduplicated output must equal the row count.

**4. Apply dedup EARLY — before joins**
- Dedup the right side of every JOIN before joining. A 1:N join before dedup produces fan-out that cannot be recovered by deduping the output — it hides the fan-out.
- Rule: if a table has duplicate keys, dedup it in its own CTE first, then join the deduplicated result.

**5. Post-dedup validation**
```sql
-- Did dedup actually reduce rows?
SELECT COUNT(*) AS before_dedup FROM source_table;
SELECT COUNT(*) AS after_dedup  FROM deduped_cte;   -- should equal COUNT(DISTINCT key)

-- Verify no duplicates survived
SELECT partition_key, COUNT(*) FROM deduped_cte
GROUP BY partition_key HAVING COUNT(*) > 1;         -- must return 0 rows
```

**6. ROW_NUMBER vs RANK vs DENSE_RANK**
- Always `ROW_NUMBER()` for dedup — guarantees one unique integer per row even on ties.
- `RANK`/`DENSE_RANK` assign rank=1 to multiple rows on ties — never use for dedup.

---

## SQL Review Checklist

### Correctness
- [ ] Every JOIN produces expected grain — no fan-out, no silent row loss
- [ ] WHERE/ON conditions logically complete and correct
- [ ] NULLs handled: LEFT JOINs that silently drop rows, NULLs in aggregations, NULLs in CASE logic
- [ ] Commented-out code flagged — intentional or leftover?

### Joins & Keys
- [ ] No `SELECT *` in production
- [ ] Right side of every JOIN is unique or deduped first
- [ ] Join keys at correct grain (policy_term_key vs policy_number vs party_anchor_id)
- [ ] `vw_policyholder` joined on `policy_term_key` ONLY — no date conditions

### Performance
- [ ] Dedup applied early — before joins, not after
- [ ] No functions in JOIN ON clause (e.g., SUBSTRING in ON)
- [ ] No implicit type conversions
- [ ] Date boundaries applied on large tables

### Data Integrity
- [ ] Row count preserved or reduced at each step — never silently increases
- [ ] `COUNT` validation comments at critical checkpoints
- [ ] Dedup key + ORDER is deterministic (no unresolved ties)

### Readability
- [ ] Descriptive aliases (not a, b, c)
- [ ] WHY comments on non-obvious logic — not WHAT
- [ ] Consistent formatting and casing
- [ ] Section headers per pipeline step
