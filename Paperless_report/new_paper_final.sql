--==========================================================================================================
-- new_paper_final.sql
-- Purpose : EDW/AWM paperless report — replaces legacy BIM/Eloqua (old_paper.sql)
-- Output  : #New_Paper_Report (change to permanent table once DDL permissions confirmed)
-- Grain   : One row per policy_term_key
--           Priority 1: party with AWM email (captures ANI email when NIN has none)
--           Priority 2: NIN (named insured / head of household) over ANI
--           Priority 3: party_key DESC for deterministic tiebreak
--
-- FINAL COVERAGE (as of 2026-04-07)
-- ────────────────────────────────────────────────────────────────────────────────────────
--   Total policies              : 296,399
--   Has AWM email               : 251,664  (84.9%)
--   No email (structural)       :  44,271  (14.9%)
--   Paperless BIL = Y           : 113,834
--   Paperless POL = Y           : 146,296
--   Inforce                     : 284,879
--
-- NO-EMAIL BREAKDOWN
-- ────────────────────────────────────────────────────────────────────────────────────────
--   Never registered online          :  ~50,453   Outreach: drive online registration
--   Incomplete account, no email     :  ~14,310   Outreach: prompt account activation
--   No same-as-link                  :        1   Data fix: party_id_same_as_link gap
--
-- FIXES APPLIED vs old_paper.sql / paperless.sql
-- ────────────────────────────────────────────────────────────────────────────────────────
-- FIX 1  Policyholder join relaxed to policy_term_key only
--        Strict date match dropped ~35,820 policies with mid-term endorsement date offsets
-- FIX 2  CIF: valid_to_date = '9999-12-31' — excludes superseded CIF records
-- FIX 3  CIF: ORDER BY update_date DESC — was using effective_from_date (wrong latest-record key)
-- FIX 4  CIF: NULL paper_notify_indicator stays NULL — was coerced to 'N' (false negative)
-- FIX 5  Email dedup: partition by party_user_account_link_id ONLY
--        user_name in partition produced fan-out (rn=1 for every distinct user_name per link)
-- FIX 6  Exclude bad party anchor IDs 7771543 and 13322119 from email chain
-- FIX 7  (removed) BIM fallback dropped — BIM is comparison-only, not an attribute source
-- FIX 8  Grain dedup email-aware: email presence is Priority 1
--        Previous logic always picked NIN regardless of email, losing +26,476 ANI emails
-- FIX 9  (removed) #bim_email and #policy_add_info steps dropped — BIM/EDW-vw-add-info not attribute sources
--
-- PIPELINE (13 temp tables)
-- ────────────────────────────────────────────────────────────────────────────────────────
--   Step  1: #policy_latest            — inforce EDW policies as of @as_of_date
--   Step  2: #house_latest             — latest household mapping per policy term
--   Step  3: #inforce_terms            — policy + household combined
--   Step  4: #CIF_POLICY_Detail1       — raw BIL/POL rows from cif_policy_party_detail
--   Step  5: #CIF_POLICY_Detail2       — pivot BIL/POL, join to policy_anchor for policy_number_raw
--   Step  6: #CIF_POLICY_Detail        — convert paper_notify_indicator to Y/N flags
--   Step  7: #view_ph                  — policyholder demographics per policy
--   Step  8: #base_data                — EDW party_key mapped to AWM duplicate_party_anchor_id
--   Step  9: #ct_asp_user_account      — deduped asp_user_account_detail (FIX 5)
--   Step 10: #ct_party_user_account_link — deduped party_user_account_link (FIX 6)
--   Step 11: #ct_party_user_account    — joined email account per party
--   Step 12: #ct_asp_membership        — SSA membership details per party
--   Step 13: #policy_agent             — one agent row per policy term
--   Final  : #New_Paper_Report         — grain dedup + all columns joined
--==========================================================================================================

declare @as_of_date as date;
set @as_of_date = cast(dateadd(day, -1, getdate()) as date);

--==========================================================================================================
-- Step 1: policy_latest — inforce EDW policies as of @as_of_date
--==========================================================================================================

drop table if exists #policy_latest;

select
    p.policy_term_key,
    p.policy_number,
    p.exceed_policy_id,
    p.policy_symbol,
    p.policy_inforce_indicator,
    p.policy_form,
    p.line_of_business,
    p.risk_state_code,
    p.term_type_code,
    p.effective_from_date,
    p.effective_to_date,
    p.policy_origin_type,
    p.insurance_score,
    p.pemco_tenure_date
into #policy_latest
from DWM.EDW.vw_policy p
where p.effective_from_date <= @as_of_date
  and p.effective_to_date   >  @as_of_date
;

--==========================================================================================================
-- Step 2: house_latest — latest household per policy term (future-dated rows excluded)
--==========================================================================================================

drop table if exists #house_latest;

select
    phm.policy_term_anchor_id,
    phm.household_id,
    row_number() over (
        partition by phm.policy_term_anchor_id
        order by phm.effective_date desc
    ) as rn
into #house_latest
from AWM.dbo.policy_household_mapping phm
where phm.effective_date <= @as_of_date
;

--==========================================================================================================
-- Step 3: inforce_terms — policy + household
-- INNER JOIN: policies with no household mapping are excluded (intentional)
--==========================================================================================================

drop table if exists #inforce_terms;

select
    pl.*,
    h.household_id
into #inforce_terms
from #policy_latest pl
inner join #house_latest h
    on h.policy_term_anchor_id = pl.policy_term_key
   and h.rn = 1
;

--==========================================================================================================
-- Step 4: CIF_POLICY_Detail1 — raw BIL/POL rows, latest record per link + doc type
-- FIX 2: valid_to_date = '9999-12-31' — excludes superseded CIF records
-- FIX 3: ORDER BY update_date DESC — correct latest-record key (not effective_from_date)
--==========================================================================================================

drop table if exists #CIF_POLICY_Detail1;

select
    cppd.policy_party_link_id,
    cppd.output_document_type_code,
    cppd.paper_notify_indicator,
    cppd.effective_from_date,
    row_number() over (
        partition by cppd.policy_party_link_id, cppd.output_document_type_code
        order by cppd.update_date desc          -- FIX 3: update_date, not effective_from_date
    ) as rn
into #CIF_POLICY_Detail1
from AWM.dbo.cif_policy_party_detail cppd
where cppd.output_document_type_code in ('BIL', 'POL')
  and cppd.effective_to_date = '9999-12-31'
  and cppd.valid_to_date     = '9999-12-31'    -- FIX 2: exclude superseded records
;

--==========================================================================================================
-- Step 5: CIF_POLICY_Detail2 — pivot BIL/POL, join to policy_anchor to get policy_number_raw
-- FIX: store full pa.policy_number (with LOB prefix) instead of stripping to bare number.
-- Stripping caused cross-LOB collisions: 'CA 1774271' and 'HO 1774271' both became '1774271'.
-- Keeping the full string ensures 'CA 1774271' only matches 'CA 1774271' on the b side.
--==========================================================================================================

drop table if exists #CIF_POLICY_Detail2;

select
    d1.policy_party_link_id,
    ltrim(rtrim(pa.policy_number))                                                              as policy_number_raw,
    ppl.party_anchor_id,
    max(case when d1.output_document_type_code = 'BIL' then d1.paper_notify_indicator end)     as BIL_paper_notify,
    max(case when d1.output_document_type_code = 'BIL' then d1.effective_from_date    end)     as PaperlessBillDate,
    max(case when d1.output_document_type_code = 'POL' then d1.paper_notify_indicator end)     as POL_paper_notify,
    max(case when d1.output_document_type_code = 'POL' then d1.effective_from_date    end)     as PaperlessPolDate
into #CIF_POLICY_Detail2
from #CIF_POLICY_Detail1 d1
inner join AWM.dbo.policy_party_link ppl
    on ppl.policy_party_link_id = d1.policy_party_link_id
inner join AWM.dbo.policy_anchor pa
    on pa.policy_anchor_id = ppl.policy_anchor_id
where d1.rn = 1
group by
    d1.policy_party_link_id,
    ltrim(rtrim(pa.policy_number)),   -- FIX: group by full string to keep CA/HO/bare rows distinct
    ppl.party_anchor_id
;

--==========================================================================================================
-- Step 6: CIF_POLICY_Detail — convert paper_notify_indicator (0/1) to Y/N flags
-- FIX 4: NULL paper_notify_indicator stays NULL — no BIL/POL record = unknown, not 'N'
--==========================================================================================================

drop table if exists #CIF_POLICY_Detail;

select
    c.policy_party_link_id,
    c.policy_number_raw,
    c.party_anchor_id,
    -- FIX 4: NULL stays NULL (0 = paperless = Y; NULL = no record = unknown)
    case when c.BIL_paper_notify = 0 then 'Y' when c.BIL_paper_notify is null then null else 'N' end  as Paperless_Bil_Ind,
    c.PaperlessBillDate,
    case when c.POL_paper_notify = 0 then 'Y' when c.POL_paper_notify is null then null else 'N' end  as Paperless_Pol_Ind,
    c.PaperlessPolDate
into #CIF_POLICY_Detail
from #CIF_POLICY_Detail2 c
;

--==========================================================================================================
-- Step 7: view_ph — policyholder demographics per policy term
-- FIX 1: join on policy_term_key only (was: + term_effective_date + term_expiration_date)
--         Strict date match dropped ~35,820 policies with mid-term endorsement date offsets
--==========================================================================================================

drop table if exists #view_ph;

select
    it.policy_term_key,
    it.policy_number,
    it.exceed_policy_id,
    it.policy_symbol,
    it.policy_inforce_indicator,
    it.policy_form,
    it.line_of_business,
    it.risk_state_code,
    it.term_type_code,
    it.effective_from_date,
    it.effective_to_date,
    it.policy_origin_type,
    it.insurance_score,
    it.pemco_tenure_date,
    it.household_id,
    vplh.party_key,
    vplh.full_name                      as FullName,
    vplh.term_effective_date            as Start_date,
    vplh.term_expiration_date           as End_Date,
    vplh.policyholder_type_code,
    vplh.affinity_group_code,
    vplh.gender,
    vplh.gender_code,
    vplh.marital_status,
    vplh.marital_status_code,
    -- Age as of @as_of_date for consistent daily snapshot (not GETDATE())
    datediff(year, vplh.birth_date, @as_of_date)
      - case
            when dateadd(year, datediff(year, vplh.birth_date, @as_of_date), vplh.birth_date) > @as_of_date
            then 1 else 0
        end                             as Age,
    case
        when vplh.policyholder_type_code = 'NIN' then 'Y'
        else 'N'
    end                                 as HOH_IND,
    vplh.mailing_address_city,
    vplh.mailing_address_state_code,
    vplh.mailing_address_zip_code,
    vplh.original_effective_date
into #view_ph
from #inforce_terms it
-- FIX 1: key-only join — no date conditions
left join DWM.EDW.vw_policyholder vplh
    on vplh.policy_term_key = it.policy_term_key
;

--==========================================================================================================
-- Step 8: base_data — maps EDW party_key to AWM duplicate_party_anchor_id via party_id_same_as_link
-- Inlines #base_data_link subquery (was a separate temp table in paperless.sql)
--==========================================================================================================

drop table if exists #base_data;

select
    ph.*,
    pil.party_anchor_id_duplicate,
    pta.party_anchor_id     as duplicate_party_anchor_id,
    pil.cif_id,
    pta.exceed_client_id
into #base_data
from #view_ph ph
left join (
    select
        party_anchor_id_master,
        party_anchor_id_duplicate,
        party_id_duplicate  as cif_id,
        row_number() over (
            partition by party_anchor_id_master
            order by party_anchor_id_duplicate desc
        ) as rn
    from AWM.dbo.party_id_same_as_link
) pil
    on pil.party_anchor_id_master = ph.party_key
   and pil.rn = 1
left join AWM.dbo.party_anchor pta
    on pta.party_anchor_id = pil.party_anchor_id_duplicate
;

--==========================================================================================================
-- Step 9: ct_asp_user_account — latest account detail row per party_user_account_link_id
-- FIX 5: partition by party_user_account_link_id ONLY (not by user_name — caused fan-out)
--==========================================================================================================

drop table if exists #ct_asp_user_account;

select
    auad.party_user_account_link_id,
    auad.user_name,
    auad.is_anonymous_indicator,
    auad.is_up_and_running_indicator,
    auad.valid_from_date,
    auad.valid_to_date,
    row_number() over (
        partition by auad.party_user_account_link_id
        order by auad.valid_from_date desc, auad.valid_to_date desc
    ) as rn_user_account
into #ct_asp_user_account
from AWM.dbo.asp_user_account_detail auad
;

--==========================================================================================================
-- Step 10: ct_party_user_account_link — latest link row per party_anchor_id
-- FIX 6: exclude known bad party anchor IDs 7771543 and 13322119
--==========================================================================================================

drop table if exists #ct_party_user_account_link;

select
    pual.*,
    row_number() over (
        partition by pual.party_anchor_id
        order by pual.load_date desc
    ) as rn_link
into #ct_party_user_account_link
from AWM.dbo.party_user_account_link pual
where pual.party_anchor_id not in ('7771543', '13322119')
;

--==========================================================================================================
-- Step 11: ct_party_user_account — joined email account per party (one row per party)
--==========================================================================================================

drop table if exists #ct_party_user_account;

select
    a.party_user_account_link_id,
    a.user_name,
    a.is_anonymous_indicator,
    a.is_up_and_running_indicator,
    a.valid_from_date,
    a.valid_to_date,
    l.user_account_anchor_id,
    l.party_anchor_id,
    l.load_date
into #ct_party_user_account
from #ct_asp_user_account a
inner join #ct_party_user_account_link l
    on a.party_user_account_link_id = l.party_user_account_link_id
where a.rn_user_account = 1
  and l.rn_link         = 1
;

--==========================================================================================================
-- Step 12: ct_asp_membership — SSA membership details per party
--==========================================================================================================

drop table if exists #ct_asp_membership;

select
    cua.party_anchor_id,
    cua.user_name,
    cua.is_anonymous_indicator,
    cua.is_up_and_running_indicator,
    cua.user_account_anchor_id,
    am.create_date                                                                   as SSACreateDate,
    am.is_approved_indicator,
    am.is_locked_out_indicator,
    am.last_login_date,
    am.tc_agree_date,
    am.tc_agree_indicator,
    case when cua.user_name is not null then 'SSA' else null end                     as EmailType,
    case when am.last_login_date > '2013-01-01' then 'Y' else 'N' end               as VerifiedEmailInd,
    row_number() over (
        partition by am.user_account_anchor_id
        order by am.valid_from_date desc
    ) as rn_membership
into #ct_asp_membership
from #ct_party_user_account cua
inner join AWM.dbo.asp_membership_detail am
    on am.user_account_anchor_id = cua.user_account_anchor_id
;

--==========================================================================================================
-- Step 13: policy_agent — one agent row per policy term
--==========================================================================================================

drop table if exists #policy_agent;

select
    ag.policy_term_key,
    ag.agent_number,
    ag.agent_name,
    ag.sales_channel_code,
    ag.sales_channel,
    ag.sales_subchannel_code,
    ag.sales_subchannel,
    ag.financial_sales_subchannel_code,
    ag.financial_sales_subchannel,
    substring(ag.agent_number, 4, 3)    as agency
into #policy_agent
from (
    select
        policy_term_key,
        agent_number,
        agent_name,
        sales_channel_code,
        sales_channel,
        sales_subchannel_code,
        sales_subchannel,
        financial_sales_subchannel_code,
        financial_sales_subchannel,
        row_number() over (
            partition by policy_term_key
            order by term_effective_date desc
        ) as rn
    from DWM.EDW.vw_policy_agent
    where policy_agent_type_code         = 'AGT'
      and policy_agent_inforce_indicator = 1
) ag
where ag.rn = 1
;

--==========================================================================================================
-- FINAL OUTPUT
-- Grain: one row per policy_term_key
--
-- Dedup priority (FIX 8 — email-aware):
--   1. Party with AWM email (captures ANI email when NIN has none — +26,476 recovered)
--   2. NIN over ANI
--   3. party_key DESC for deterministic tiebreak
--
-- Email source: AWM only (user_name from #email_account)
-- CIF paperless indicators: AWM only (#cif_detail) — primary source of truth
--==========================================================================================================

drop table if exists #New_Paper_Report;

select
    -- Policy identifiers
    src.policy_term_key,
    src.policy_number,
    src.exceed_policy_id,
    src.policy_symbol,
    src.policy_form,
    src.line_of_business,
    src.risk_state_code,
    src.term_type_code,
    src.effective_from_date,
    src.effective_to_date,
    src.policy_origin_type,
    src.insurance_score,
    src.pemco_tenure_date,
    src.household_id,
    case when src.policy_inforce_indicator = 1 then 'INFORCE' else '' end   as PolicyStatus,
    -- Policyholder demographics
    src.party_key,
    src.duplicate_party_anchor_id   as party_anchor_id,
    src.cif_id                      as CIFID,
    src.exceed_client_id,
    src.FullName,
    src.Age,
    src.HOH_IND,
    src.policyholder_type_code,
    src.gender,
    src.gender_code,
    src.marital_status,
    src.marital_status_code,
    src.affinity_group_code,
    src.mailing_address_city        as City,
    src.mailing_address_state_code  as State,
    src.mailing_address_zip_code    as Zip,
    src.original_effective_date,
    -- CIF paperless indicators — primary source of truth (AWM)
    src.Paperless_Bil_Ind,
    src.PaperlessBillDate,
    src.Paperless_Pol_Ind,
    src.PaperlessPolDate,
    -- Agent / sales channel
    src.agent_number                as AgentNumber,
    src.agent_name,
    src.sales_channel_code,
    src.sales_channel,
    src.sales_subchannel_code,
    src.sales_subchannel,
    src.financial_sales_subchannel_code,
    src.financial_sales_subchannel,
    src.agency,
    -- Email: AWM only
    src.user_name                                                            as EmailAddress,
    case when src.user_name is not null then 'AWM' else null end             as EmailSource,
    src.EmailType,
    src.VerifiedEmailInd            as EmailVerification,
    case when src.EmailType = 'SSA' then 'Y' else 'N' end                   as SelfServiceInd,
    src.SSACreateDate               as SelfServiceDate,
    src.is_anonymous_indicator,
    src.is_up_and_running_indicator,
    src.is_approved_indicator,
    src.is_locked_out_indicator,
    src.last_login_date,
    src.tc_agree_date,
    src.tc_agree_indicator
into #New_Paper_Report
from (
    select
        b.*,
        cif.Paperless_Bil_Ind,
        cif.PaperlessBillDate,
        cif.Paperless_Pol_Ind,
        cif.PaperlessPolDate,
        ag.agent_number,
        ag.agent_name,
        ag.sales_channel_code,
        ag.sales_channel,
        ag.sales_subchannel_code,
        ag.sales_subchannel,
        ag.financial_sales_subchannel_code,
        ag.financial_sales_subchannel,
        ag.agency,
        m.user_name,
        m.is_anonymous_indicator,
        m.is_up_and_running_indicator,
        m.SSACreateDate,
        m.is_approved_indicator,
        m.is_locked_out_indicator,
        m.last_login_date,
        m.tc_agree_date,
        m.tc_agree_indicator,
        m.EmailType,
        m.VerifiedEmailInd,
        -- FIX 8: email-aware grain dedup
        row_number() over (
            partition by b.policy_term_key
            order by
                case when m.user_name is not null           then 0 else 1 end,  -- Priority 1: has AWM email
                case when b.policyholder_type_code = 'NIN'  then 0 else 1 end,  -- Priority 2: NIN over ANI
                b.party_key desc                                                 -- Priority 3: tiebreak
        ) as rn_grain
    from #base_data b
    left join #CIF_POLICY_Detail cif
        on  cif.party_anchor_id   = b.duplicate_party_anchor_id
        -- FIX: join on full policy_number_raw to avoid cross-LOB collisions.
        -- 'CA 1774271' (CIF) matches only 'CA 1774271' (b) — not 'HO 1774271'.
        -- Bare CIF rows (no prefix, e.g. '1774271') fall through to the second condition
        -- and match any b.policy_number whose numeric part equals the bare anchor number.
        and (
            cif.policy_number_raw = ltrim(rtrim(b.policy_number))
            or (
                cif.policy_number_raw not like '% %'
                and cif.policy_number_raw = case
                        when b.policy_number like '% %'
                            then substring(b.policy_number, charindex(' ', b.policy_number) + 1, len(b.policy_number))
                        else b.policy_number
                    end
            )
        )
    left join #ct_asp_membership m
        on  m.party_anchor_id = b.duplicate_party_anchor_id
        and m.rn_membership   = 1
    left join #policy_agent ag
        on ag.policy_term_key = b.policy_term_key
) src
where src.rn_grain = 1
;

--==========================================================================================================
-- VALIDATION: Row count and email coverage check
-- Expected values (as of 2026-04-07):
--   total_rows       : ~296,399
--   has_email        : ~251,664  (84.9%)
--   no_email         :  ~44,735  (15.1%)
--   paperless_bill_y : ~113,834
--   paperless_pol_y  : ~146,296
--   inforce_count    : ~284,879
--==========================================================================================================

--==========================================================================================================
-- Step 9: Policy-number grain validation
-- Verifies that policy_term_key and policy_number are 1:1 for inforce data.
-- Expected for a clean pull: difference = 0 and Step 11c returns 0 rows.
--==========================================================================================================

-- Step 11a: dedup #New_Paper_Report to one row per policy_number
-- For inforce data policy_number should be 1:1 with policy_term_key.
-- If duplicates exist here, investigate #policy_latest for multi-term inforce anomalies.
drop table if exists #final_by_policy_number;

select *
into   #final_by_policy_number
from (
    select *,
           row_number() over (
               partition by policy_number
               order by policy_term_key desc   -- keep latest term if ever >1
           ) as rn_pn
    from #New_Paper_Report
) x
where rn_pn = 1
;

-- Step 11b: grain consistency check
-- term_key_rows = policy_number_rows  →  data is clean (expected for inforce)
-- term_key_rows > policy_number_rows  →  same policy_number on multiple active terms (investigate)
select
    (select count(*) from #New_Paper_Report)         as term_key_rows,
    (select count(*) from #final_by_policy_number)   as policy_number_rows,
    (select count(*) from #New_Paper_Report)
     - (select count(*) from #final_by_policy_number) as difference
;

-- Step 11c: list any policy_numbers with multiple policy_term_keys
-- Expected: 0 rows for a clean inforce pull
select
    policy_number,
    count(distinct policy_term_key) as term_count,
    min(policy_term_key)            as term_key_min,
    max(policy_term_key)            as term_key_max
from #New_Paper_Report
group by policy_number
having count(distinct policy_term_key) > 1
order by term_count desc
;

--==========================================================================================================
-- VALIDATION: Row count and email coverage check
-- Expected values (as of 2026-04-07):
--   total_rows       : ~296,399
--   has_email        : ~251,664  (84.9%)
--   no_email         :  ~44,735  (15.1%)
--   paperless_bill_y : ~113,834
--   paperless_pol_y  : ~146,296
--   inforce_count    : ~284,879
--==========================================================================================================

select
    count(*)                                                            as total_rows,
    sum(case when EmailAddress is not null  then 1 else 0 end)         as has_email,
    sum(case when EmailAddress is null      then 1 else 0 end)         as no_email,
    sum(case when Paperless_Bil_Ind = 'Y'  then 1 else 0 end)         as paperless_bill_y,
    sum(case when Paperless_Pol_Ind = 'Y'  then 1 else 0 end)         as paperless_pol_y,
    sum(case when PolicyStatus = 'INFORCE' then 1 else 0 end)         as inforce_count
from #New_Paper_Report
;
