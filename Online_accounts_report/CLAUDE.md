# Online Accounts Report

**Goal:** Accurate reporting on online account enrollment and adoption (Activation, Initiation, Inforce, DriverOnly) feeding Tableau dashboards. AWM/EDW is the rewrite target; BIM is the legacy baseline used for validation only.

**Related project:** `../Paperless_report/` — shares data sources, SQL patterns, and the AWM→EDW join chain.

---

## File Map

| File | Type | Status |
|---|---|---|
| `online_accounts_edw_Self.sql` | **Production** — Self Service report (4 DateTypes) | Validated vs BIM |
| `online_accounts_edw_active.sql` | **Production** — Active accounts by state/product | Not yet validated vs BIM |
| `online_accounts_edw_active_tableau.sql` | **Tableau Custom SQL** — nested subquery version of `_active.sql` | Mirrors production |
| `online_accounts_validation_Self.sql` | Validation — CSR/CSS bucket counts (BIM vs AWM) | All 4 sections complete |
| `online_accounts_validation_EmpSup.sql` | Validation — Employee/Supervisor grain (BIM vs AWM) | All sections complete |
| `online_accounts_bim_Self_Service_Account.sql` | BIM legacy — reference/comparison only | Do not modify |
| `online_account_bim_Active_Accounts.sql` | BIM legacy — reference/comparison only | Do not modify |
| `agent.sql` | Reference scratch — community_agent join pattern | Not a report |

---

## CSR vs CSS Classification

Project-specific to the Self Service report. Shared AWM/EDW patterns (is_up_and_running, party bridge, inforce filter) are in root `CLAUDE.md`.

- `account_creation_completed_csr` IS NOT NULL and NOT LIKE `'ECOMM1%'` → **CSR** (agent/rep enrolled)
- NULL or `ECOMM1%` → **Customer Self Service** (web self-enrollment)
- `ECOMM1%` values are web session identifiers, not human CSR usernames
- Supervisor captured at account creation time from `USER_EVENT_DETAIL` — NOT current supervisor

---

## Rewrite Status & Known Gaps

| DateType | Delta vs BIM | Status |
|---|---|---|
| Activation | < 1% | Validated ✓ |
| Initiation | < 2% (2021+ only) | Validated ✓ — pre-2021 AWM history incomplete |
| Inforce CSR | −1.21% | Validated ✓ |
| Inforce CSS | +1.46% | Validated ✓ |
| DriverOnly CSR | −46.6% | Accepted — known structural gap |
| DriverOnly CSS | −38.3% | Accepted — known structural gap |

**DriverOnly ~43% gap (accepted, under investigation):**
`vw_policy_driver` has ~13% coverage gap vs `CIFDM.dim_policy_role`. 3,971 BIM DR parties have no row in `vw_policy_driver`. No EDW view is a full equivalent of `dim_policy_role`. See CLAUDE_reference.md Continuous Learning for full root cause.

**Supervisor staleness (pending stakeholder decision):**
AWM captures supervisor at account creation time. BIM reads current supervisor. Employees reassigned to a new supervisor show AWM=0 under the new supervisor — not a bug, structural difference. Decision pending on whether to reflect creation-time or current supervisor in Tableau.

**prld_code system difference:**
- `CIFDM.dim_policy_role.prld_code` (BIM): `'NI'`, `'ANI'`, `'DR'`
- `vw_policy_driver.policyholder_type_code` (EDW): `'NIN'`, `'ANI'`, `'DR'`
- Never cross-use these codes between systems.

---

## SQL Standards

Generic rules (dedup, no SELECT *, ROW_NUMBER, date boundaries) are in root `CLAUDE.md` and `CLAUDE_reference.md`.

**Tableau Custom SQL exception (project-specific):** Tableau wraps queries in `SELECT * FROM (...)` — CTEs are invalid inside it. Write CTE version as source of truth in `.sql`; maintain a separate `_tableau.sql` with nested subqueries.

---

## Workflow

1. Confirm grain (policy / party / household / state)
2. Identify source (EDW / AWM / BIM) and trust level
3. Plan joins on paper — check for fan-out before writing SQL
4. Write with section headers and checkpoint comments
5. Validate: COUNT vs COUNT DISTINCT, NULL handling, row counts vs expected
6. Optimize only after correctness confirmed

---

## Clarification Protocol

**Always ask before writing:**
- Join key is ambiguous (policy_number vs policy_term_key vs party_anchor_id)
- "Active" filter — inforce? not cancelled? as-of-date?
- Output grain is unclear
- Column exists in multiple sources — which takes precedence
- Commented-out code is present

**Never ask:**
- Syntax errors, typos, broken SQL — fix and explain
- Standard patterns from this file apply — just apply them

---

## Debugging Playbook

| Symptom | First check |
|---|---|
| Counts too high | Fan-out from JOIN — check grain, add dedup |
| Counts too low | Date boundaries, NULL mappings, `is_up_and_running_indicator` (must be 255) |
| AWM→EDW join loses rows | `party_id_same_as_link` — confirm `party_anchor_id_duplicate` side used |
| Inforce count inflated | Using `policyholder_inforce_indicator` alone — add `vw_policy` date boundaries |
| DriverOnly count low | Expected ~43% below BIM — see Rewrite Status above |
| Employee shows username/OTHER | Normal — CSR fields only populated for ~39% of Creation events |
| Supervisor shows 0 under CSR | Supervisor staleness — accounts created before the supervisor change |

