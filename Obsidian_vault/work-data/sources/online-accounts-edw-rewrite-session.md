---
tags: [source]
topic: work-data
sources: 2
updated: 2026-04-20
---

# Source: Online Accounts EDW Rewrite — Self Service Account Report

**Session:** 2026-04-17 to 2026-04-20
**Files:** `Online_accounts_report/online_accounts_edw_Self.sql`, `online_accounts_validation_Self.sql`
**Goal:** Full EDW/AWM rewrite of BIM Self Service Account report — retire all BIM table dependencies

---

## What Was Built

Four-section UNION ALL query replacing BIM with AWM + EDW views:

| Section | DateType | Source | Validation Status | Dimensions |
|---|---|---|---|---|
| 1 | Activation | `USER_EVENT_DETAIL` EVENT_TYPE='Activation' | ✅ <1% delta vs BIM | CostCenter, Employee, Supervisor ✅ |
| 2 | Initiation | `USER_EVENT_DETAIL` EVENT_TYPE='Creation' | ✅ <2% delta (2021+ only) | CostCenter, Employee, Supervisor ✅ |
| 3 | Inforce | Active accounts + EDW inforce policy join | ✅ CSR -0.88%, Self Service +1.45% | CostCenter, Employee, Supervisor ✅ |
| 4 | DriverOnly | Inforce + `vw_policy_driver` DR filter | ⚠ ~43% lower than BIM — accepted gap | CostCenter, Employee, Supervisor ✅ |

**Pending:** Employee/Supervisor validation against BIM output.

**Rule enforced:** BIM tables are only allowed in the validation file as comparison baseline. Never in the EDW rewrite query.

---

## Key Join Path (AWM → EDW)

```
asp_user_account_detail          (is_up_and_running_indicator = 255)
  → party_user_account_link      (party_user_account_link_id)
  → party_id_same_as_link        (party_anchor_id_duplicate → party_anchor_id_master)
  → vw_policyholder              (party_key = party_anchor_id_master)
  → vw_policy                    (policy_term_key, policy_inforce_indicator = 1)
```

CSR info sourced from earliest `USER_EVENT_DETAIL` EVENT_TYPE='Creation' per user, joined via `DATA_1 = user_name`.

---

## DriverOnly — Root Cause Analysis

**BIM logic:** `CIFDM.dim_person → fact_person_coverage → dim_policy_role` filtered to DR-only parties (NI_ANI_COUNT = 0, DR_COUNT > 0).

**EDW logic:** `vw_policy_driver` with `driver_inforce_indicator = 1`, HAVING no NIN/ANI rows.

**Gap breakdown (BIM DR-only parties mapped to EDW):**

| Finding | Count |
|---|---|
| No row in `vw_policy_driver` at all | 3,971 |
| Show as ANI in EDW | 51 |
| Show as NIN in EDW | 128 |

**Why NOT EXISTS failed:** Tested as alternative to INNER JOIN. Resulted in 17x inflation (CSR: 8,531 vs BIM 470) because parties absent from `vw_policy_driver` are NOT necessarily DR-only — they may be NIN/ANI parties simply not covered by the view.

**Decision:** Use INNER JOIN (positive signal required). Accept ~43% delta as known architecture difference. No EDW view is a full equivalent of `CIFDM.dim_policy_role`.

---

## `vw_policy_driver` — What It Contains

- Columns: `party_key`, `policy_term_key`, `driver_inforce_indicator`, `policyholder_type_code`, `effective_from_date`, `effective_to_date`
- `policyholder_type_code` values: `NIN`, `ANI`, `NULL`
- Does NOT contain a `DR` code — DR parties appear by absence of NIN/ANI, not a positive code
- Coverage: ~110,462 of 127,422 inforce parties (~13% gap vs `vw_policyholder` population)

---

## Pre-2021 Initiation Gap

AWM `USER_EVENT_DETAIL` history is incomplete pre-2021. Delta vs BIM: ~5-11% lower. Use 2021-01 onward as the reliable window.

---

## Employee / Supervisor Dimensions — Findings from agent.sql

**Source:** `Online_accounts_report/agent.sql`
**AWM table:** `awm.dbo.community_agent`

| Column | Maps to BIM |
|---|---|
| `ca.agent_name` | `AgencyName` (community agency name, NOT individual producer name) |
| `ca.territory_manager` | `Supervisor` (territory manager) |
| `ca.agent_number` | `ProducerNumber` |

**Join path (Sections 3 & 4 — has policy_term_key):**
```sql
JOIN AWM.dbo.policy_agent_commission pac ON pac.policy_term_anchor_id = vp.policy_term_key
  AND pac.valid_to_date = '9999-12-31'
JOIN AWM.dbo.agent agt ON agt.agent_number = pac.agent_number
  AND agt.agency_party_role_anchor_id IS NOT NULL
  AND agt.valid_to_date = '9999-12-31'
JOIN AWM.dbo.community_agent ca ON ca.agent_number = SUBSTRING(agt.agent_number, 4, 3)
  AND ca.valid_to_date = '9999-12-31'
  AND ca.account_status = 'Active'
```

**Open gaps (as of 2026-04-20):**
- CSR full name (`Employee`) and CSR supervisor name columns in `USER_EVENT_DETAIL` — unknown, need column list
- Sections 1 & 2 (Activation/Initiation): no `policy_term_key` in scope — `community_agent` join path TBD

---

## Related

- [[online-account-indicator]] — active account filter, AWM→EDW join pattern
- [[data-sources-edw-awm-bim]] — source trust hierarchy
- [[online-accounts-report-schema]] — project schema
- [[policy-deduplication-pattern]] — ROW_NUMBER dedup applied throughout
