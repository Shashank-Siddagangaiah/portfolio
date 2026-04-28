---
tags: [concept]
topic: work-data
sources: 2
updated: 2026-04-20
---

# Online Account Indicator

A flag indicating whether a policyholder has enrolled in an online account
(self-service portal) with the insurer.

---

## Source

- Primary: **AWM** (`asp_user_account_detail.is_up_and_running_indicator`)
- Cross-validate against Eloqua enrollment data
- If flag only populated for one product/symbol → suspect data issue, flag it

---

## Active Account Filter

```sql
-- is_up_and_running_indicator is a SQL Server tinyint, NOT a boolean
-- Active = 255 (all bits set), Inactive = 0, Unknown = NULL
WHERE is_up_and_running_indicator = 255   -- NEVER use = 1 or ISNULL(...,0) = 1
```

Discovered 2026-04-17: filtering `= 1` returns 0 rows. Active value is `255`.

---

## AWM → EDW Join Pattern (Validated)

To connect active online account holders to inforce policies, the correct path is:

```
asp_user_account_detail
  → party_user_account_link          (party_user_account_link_id)
  → party_id_same_as_link            (party_anchor_id_duplicate → party_anchor_id_master)
  → vw_policyholder                  (party_key = party_anchor_id_master)
  → vw_policy                        (policy_term_key)
```

**Why not `policy_party_link → awm.dbo.policy`?**
- `awm.dbo.policy` is a partial satellite (~2K rows) — loses 99% of records
- `policy_party_link → policy_anchor` is also partial
- `policy_party_link.party_anchor_id` does not share ID space with `party_user_account_link.party_anchor_id`
- The `party_id_same_as_link` bridge is the correct AWM↔EDW connector (same pattern as Paperless report)

**Validation result (2026-04-17):**
- Active parties: 295,675
- Parties with EDW key: 295,674
- Parties with inforce policy: 127,471
- WA Auto EDW: 103,490 vs BIM: 102,910 (~0.5% variance — expected AWM/BIM delta)

---

## DriverOnly Metric — EDW Pattern

Parties inforce on a policy but with no NIN/ANI role = driver-only. Use `vw_policy_driver`:

```sql
INNER JOIN (
    SELECT party_key
    FROM DWM.EDW.vw_policy_driver
    WHERE driver_inforce_indicator = 1
      AND effective_from_date <= CAST(GETDATE() AS DATE)
      AND effective_to_date > CAST(GETDATE() AS DATE)
    GROUP BY party_key
    HAVING SUM(CASE WHEN policyholder_type_code IN ('NIN', 'ANI') THEN 1 ELSE 0 END) = 0
) DriverOnly ON DriverOnly.party_key = pil.party_anchor_id_master
```

**Known gap vs BIM:** ~43% lower. `vw_policy_driver` covers ~87% of inforce parties (110,462 of 127,422). The 3,971-party shortfall vs BIM's `CIFDM.dim_policy_role` is a coverage difference — no EDW view is a full equivalent. Accept this delta.

**DO NOT use NOT EXISTS:** Tested 2026-04-20 — inflates count 17x because parties absent from `vw_policy_driver` are not necessarily DR-only.

**`vw_policyholder` has no DR code** — `policyholder_type_code` there is only NIN/ANI. Use `vw_policy_driver` for driver role filtering.

---

## Known Issues

- Eloqua join key must be validated — mismatches cause missing flags
- Flag may only appear for 'CA' (Auto) policies → indicator of incomplete data population
- MH (Mobile Home) returns 0 in OR/WA — verify `policy_symbol/product` values in `vw_policy`

---

## Employee / Supervisor Dimensions — AWM Mapping

BIM outputs three dimensions per row: CostCenter, Employee, Supervisor. AWM equivalents:

### AWM Source: `awm.dbo.community_agent`

| BIM column | BIM source | AWM equivalent |
|---|---|---|
| `AgencyName` | `Exceed_Reporting.XCD` tables | `community_agent.agent_name` |
| `Supervisor` (territory) | `Exceed_Reporting.XCD` tables | `community_agent.territory_manager` |
| `Employee` (CSR full name) | `UserEventDetails.CSRCompletedAccountFullName` | **TBD** — needs USER_EVENT_DETAIL column check |
| `Supervisor` (CSR supervisor) | `UserEventDetails.CSRCompletedAccountSupervisorName` | **TBD** — needs USER_EVENT_DETAIL column check |

### Join Path (Sections 3 & 4 — Inforce / DriverOnly)

```sql
-- vw_policy already in scope via policy_term_key
JOIN AWM.dbo.policy_agent_commission pac
    ON pac.policy_term_anchor_id = vp.policy_term_key
   AND pac.valid_to_date = '9999-12-31'
JOIN AWM.dbo.agent agt
    ON agt.agent_number = pac.agent_number
   AND agt.agency_party_role_anchor_id IS NOT NULL
   AND agt.valid_to_date = '9999-12-31'
JOIN AWM.dbo.community_agent ca
    ON ca.agent_number = SUBSTRING(agt.agent_number, 4, 3)
   AND ca.valid_to_date = '9999-12-31'
   AND ca.account_status = 'Active'
```

`ca.agent_name` → AgencyName (the community agency name, NOT individual producer name)
`ca.territory_manager` → Supervisor / territory manager name

### Sections 1 & 2 (Activation / Initiation) — Open Gap

No `policy_term_key` in scope for these sections (pure USER_EVENT_DETAIL). Whether an agent number exists in USER_EVENT_DETAIL to enable a `community_agent` join is **TBD** — need full USER_EVENT_DETAIL column list.

### BIM CASE Logic (Inforce / DriverOnly) mapped to AWM

```sql
-- Employee
CASE WHEN ISNULL(account_creation_completed_csr, '') <> '' THEN
         CASE WHEN ca.agent_name IS NULL THEN COALESCE(csr_full_name, account_creation_completed_csr)
              ELSE COALESCE(csr_full_name, ca.agent_name)
         END
     ELSE 'Customer Self Service'
END AS Employee

-- Supervisor
CASE WHEN ISNULL(account_creation_completed_csr, '') <> '' THEN
         CASE WHEN ca.agent_name IS NULL THEN COALESCE(csr_supervisor_name, 'OTHER')
              ELSE COALESCE(csr_supervisor_name, ca.territory_manager)
         END
     ELSE 'Customer Self Service'
END AS Supervisor
```

`csr_full_name` and `csr_supervisor_name` = **pending** USER_EVENT_DETAIL column names.

---

## Related

- [[household-grain-reporting]] — household-level enrollment rate uses this flag
- [[data-sources-edw-awm-bim]] — source hierarchy
- [[policy-deduplication-pattern]] — dedup applied to `asp_user_account_detail`
- [[online-accounts-report-schema]] — project that owns this metric
