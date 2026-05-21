# Online Accounts Report

**Goal:** Accurate reporting on online account enrollment and adoption (Activation, Initiation, Inforce, DriverOnly) feeding Tableau dashboards. AWM/EDW is the rewrite target; BIM is the legacy baseline used for validation only.

**Related project:** `../Paperless_report/` — shares data sources, SQL patterns, and the AWM→EDW join chain.

---

## File Map

| File | Type | Status |
|---|---|---|
| `online_accounts_edw_Self.sql` | **Production** — Self Service report (4 DateTypes) | Validated vs BIM |
| `online_accounts_edw_active.sql` | **Production** — Active accounts by state/product | Validated vs BIM ✓ |
| `online_accounts_edw_active_tableau.sql` | **Tableau Custom SQL** — nested subquery version of `_active.sql` | Mirrors production |
| `online_accounts_validation_Self.sql` | Validation — CSR/CSS bucket counts (BIM vs AWM) | All 4 sections complete |
| `online_accounts_validation_EmpSup.sql` | Validation — Employee/Supervisor grain (BIM vs AWM) | All sections complete |
| `online_accounts_bim_Self_Service_Account.sql` | BIM legacy — reference/comparison only | Do not modify |
| `online_account_bim_Active_Accounts.sql` | BIM legacy — reference/comparison only | Do not modify |
| `agent.sql` | Reference scratch — community_agent join pattern | Not a report |
| `driver_ony_compare.sql` | Diagnostic — individual-level DriverOnly gap analysis | Complete — see Rewrite Status |

---

## CSR vs CSS Classification

- `account_creation_completed_csr` IS NOT NULL and NOT LIKE `'ECOMM1%'` → **CSR** (agent/rep enrolled)
- NULL or `ECOMM1%` → **Customer Self Service** (web self-enrollment)
- `ECOMM1%` values are web session identifiers, not human CSR usernames
- Supervisor captured at account creation time from `USER_EVENT_DETAIL` — NOT current supervisor

---

## Rewrite Status & Known Gaps

| DateType / Report | Delta vs BIM | Status |
|---|---|---|
| Activation | < 1% | Validated ✓ |
| Initiation | < 2% (2021+ only) | Validated ✓ — pre-2021 AWM history incomplete |
| Inforce CSR | −1.21% | Validated ✓ |
| Inforce CSS | +1.46% | Validated ✓ |
| DriverOnly CSR | −46.6% | Accepted — known structural gap |
| DriverOnly CSS | −38.3% | Accepted — known structural gap |
| Active — Auto | OR +0.05% / WA +0.28% | Validated ✓ |
| Active — Home | OR +2.77% / WA +0.99% | Validated ✓ |
| Active — Condo | OR +3.54% / WA +1.09% | Validated ✓ |
| Active — Renter | OR −0.68% / WA −6.44% | Accepted — see note below |
| Active — DP | OR +4.81% / WA +1.81% | Validated ✓ |
| Active — Boat | OR +7.14% / WA +3.01% | Validated ✓ — small absolute numbers |
| Active — Umbrella | OR +1.24% / WA +0.01% | Validated ✓ |

**DriverOnly ~43% gap (accepted):** `vw_policy_driver` has ~13% coverage gap vs `CIFDM.dim_policy_role`. 3,971 BIM DR parties have no row in `vw_policy_driver`. No EDW view is a full equivalent of `dim_policy_role`. Individual-level diagnostic complete — see `driver_ony_compare.sql`.

**Active Renter WA −6.44% (accepted):** BIM identifies Renters via `DWELLING_TAB.FORM_CD = '4'`; EDW uses `vw_policy.product = 'Renter'`. Some HO-4 policies in WA are classified differently in EDW's product field. Classification method difference, not a join error.

**Supervisor staleness:** AWM captures supervisor at account creation time. BIM reads current supervisor. Employees reassigned to a new supervisor show AWM=0 under the new supervisor — structural difference, not a bug.

**prld_code system difference:**
- `CIFDM.dim_policy_role.prld_code` (BIM): `'NI'`, `'ANI'`, `'DR'`
- `vw_policy_driver.policyholder_type_code` (EDW): `'NIN'`, `'ANI'`, `'DR'`
- Never cross-use these codes between systems.

---

## Tableau Custom SQL

CTEs are invalid inside Tableau Custom SQL (Tableau wraps queries in `SELECT * FROM (...)`). Write CTE version as source of truth in `.sql`; maintain a separate `_tableau.sql` with nested subqueries.

---

## Debugging Playbook

| Symptom | First check |
|---|---|
| DriverOnly count low | Expected ~43% below BIM — structural gap, see Rewrite Status above |
| AWM→EDW join loses rows | `party_id_same_as_link` — confirm `party_anchor_id_duplicate` side used |
| Inforce count inflated | Using `policyholder_inforce_indicator` alone — add `vw_policy` date boundaries |
| Employee shows username/OTHER | Normal — CSR fields only populated for ~39% of Creation events |
| Supervisor shows 0 under CSR | Supervisor staleness — accounts created before the supervisor change |
