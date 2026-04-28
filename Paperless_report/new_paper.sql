--==========================================================================================================
-- new_paper.sql
-- Purpose : Optimized EDW/AWM paperless report — replaces legacy BIM/Eloqua (old_paper.sql)
-- Output  : dbo.New_Paper_Report
-- Grain   : One row per policy_term_key (NIN/named insured preferred over ANI)
--
-- ANALYSIS SUMMARY
-- ────────────────
-- Total inforce policies processed : 297,413
-- Email resolved (AWM)             : 232,259  (78%)
-- Missing email                    :  65,154  (22%)  broken into 4 categories:
--
--   Category                                  Policies   Action
--   ─────────────────────────────────────────────────────────────────────────────────────
--   Recoverable — BIM has email, AWM missing    27,756   FIX 7: BIM email fallback (below)
--   Never registered online                     50,453   Outreach: drive online registration
--   Incomplete account setup, no email anywhere 13,846   Outreach: prompt account activation
--   No same-as-link                                  1   Data fix: party_id_same_as_link gap
--
-- Expected email coverage after BIM fallback  : ~260,015 (~87%)
--
-- FIXES APPLIED vs paperless.sql
-- ────────────────────────────────────────────────────────────────────────────────────────
-- FIX 1  Policyholder join relaxed to policy_term_key only
--        Strict date match (term_effective_date + term_expiration_date) dropped ~35,820
--        policies with mid-term endorsement date offsets. paperless.sql also uses key-only.
-- FIX 2  CIF: added valid_to_date = '9999-12-31' filter — removes superseded CIF records
-- FIX 3  CIF: order by update_date DESC — was using effective_from_date (wrong latest-record key)
-- FIX 4  CIF: NULL paper_notify_indicator now stays NULL
--        Was coercing to 'N' (false negative — policy appeared non-paperless with no data)
-- FIX 5  Email dedup partitions by party_user_account_link_id ONLY
--        Adding user_name to partition made rn=1 fire for every distinct user_name per link
--        (fan-out). One row per link is correct.
-- FIX 6  Exclude known bad party anchor IDs 7771543 and 13322119 from email chain
-- FIX 7  BIM/Eloqua email fallback: 27,756 policies have an AWM account link with
--        is_up_and_running = N (incomplete setup) but BIM holds a valid email — backfilled here
--
-- OPTIMIZATION vs paperless.sql (16 temp tables → 10)
-- ────────────────────────────────────────────────────────────────────────────────────────
-- Removed #base_data_link            → inlined as subquery in #base_data
-- Removed #CIF_POLICY_Detail1/2      → merged with #CIF_POLICY_Detail into #cif_detail
-- Removed #ct_asp_user_account       → merged into #email_account
-- Removed #ct_party_user_account_link → merged into #email_account
-- Removed #ct_party_user_account     → merged into #email_account
-- Removed #ct_asp_membership         → merged into #email_account
-- Added   #bim_email                 → new: BIM email fallback (FIX 7)
-- Grain dedup applied in final SELECT (no extra temp table needed)
--==========================================================================================================

declare @as_of_date as date;
set @as_of_date = cast(dateadd(day, -1, getdate()) as date);

----------------------------------------------------------------------------------------------------------
-- Step 1: policy_latest — inforce EDW policies as of yesterday
----------------------------------------------------------------------------------------------------------

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

----------------------------------------------------------------------------------------------------------
-- Step 2: house_latest — latest household per policy term (future-dated rows excluded)
----------------------------------------------------------------------------------------------------------

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

----------------------------------------------------------------------------------------------------------
-- Step 3: inforce_terms — policy + household
-- INNER JOIN is intentional: policies with no household mapping are excluded
----------------------------------------------------------------------------------------------------------

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

----------------------------------------------------------------------------------------------------------
-- Step 4: cif_detail — AWM paperless indicators (BIL + POL) per party + policy
-- COMBINED from 3 separate steps in paperless.sql (#CIF_POLICY_Detail1/2 + final)
-- FIX 2: valid_to_date filter added (removes superseded CIF records)
-- FIX 3: order by update_date DESC (not effective_from_date) for true latest record
-- FIX 4: NULL paper_notify stays NULL — not coerced to 'N'
----------------------------------------------------------------------------------------------------------

drop table if exists #cif_detail;

select
    ppl.party_anchor_id,
    -- Normalize policy number for join: 'CA 0130957' → '0130957'
    case
        when pa.policy_number like '% %'
            then substring(pa.policy_number, charindex(' ', pa.policy_number) + 1, len(pa.policy_number))
        else pa.policy_number
    end                                                                              as policy_number_stripped,
    -- FIX 4: NULL stays NULL (no BIL record = unknown, not non-paperless)
    case
        when min(case when d.output_document_type_code = 'BIL' then d.paper_notify_indicator end)  = 0    then 'Y'
        when min(case when d.output_document_type_code = 'BIL' then d.paper_notify_indicator end) is null then null
        else 'N'
    end                                                                              as Paperless_Bil_Ind,
    max(case when d.output_document_type_code = 'BIL' then d.effective_from_date end) as PaperlessBillDate,
    case
        when min(case when d.output_document_type_code = 'POL' then d.paper_notify_indicator end)  = 0    then 'Y'
        when min(case when d.output_document_type_code = 'POL' then d.paper_notify_indicator end) is null then null
        else 'N'
    end                                                                              as Paperless_Pol_Ind,
    max(case when d.output_document_type_code = 'POL' then d.effective_from_date end) as PaperlessPolDate
into #cif_detail
from (
    select
        cppd.policy_party_link_id,
        cppd.output_document_type_code,
        cppd.paper_notify_indicator,
        cppd.effective_from_date,
        row_number() over (
            partition by cppd.policy_party_link_id, cppd.output_document_type_code
            order by cppd.update_date desc          -- FIX 3: update_date is the correct latest-record key
        ) as rn
    from AWM.dbo.cif_policy_party_detail cppd
    where cppd.output_document_type_code in ('BIL', 'POL')
      and cppd.effective_to_date = '9999-12-31'
      and cppd.valid_to_date     = '9999-12-31'    -- FIX 2: exclude superseded records
) d
inner join AWM.dbo.policy_party_link ppl
    on ppl.policy_party_link_id = d.policy_party_link_id
inner join AWM.dbo.policy_anchor pa
    on pa.policy_anchor_id = ppl.policy_anchor_id
where d.rn = 1
group by
    ppl.party_anchor_id,
    case
        when pa.policy_number like '% %'
            then substring(pa.policy_number, charindex(' ', pa.policy_number) + 1, len(pa.policy_number))
        else pa.policy_number
    end
;

----------------------------------------------------------------------------------------------------------
-- Step 5: view_ph — policyholder demographics per policy
-- FIX 1: join on policy_term_key only — strict date match dropped ~35,820 policies
--         with mid-term endorsement date offsets. Matches paperless.sql pattern.
----------------------------------------------------------------------------------------------------------

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
    -- Age calculated as of as_of_date (not GETDATE()) for daily snapshot consistency
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
-- FIX 1: policy_term_key only — no date conditions
left join DWM.EDW.vw_policyholder vplh
    on vplh.policy_term_key = it.policy_term_key
;

----------------------------------------------------------------------------------------------------------
-- Step 6: base_data — maps EDW party_key to AWM duplicate_party_anchor_id via party_id_same_as_link
-- COMBINED: inlines #base_data_link subquery (was a separate temp table in paperless.sql)
----------------------------------------------------------------------------------------------------------

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

----------------------------------------------------------------------------------------------------------
-- Step 7: email_account — resolves email + SSA details per party anchor
-- COMBINED: replaces 4 separate steps in paperless.sql:
--   #ct_asp_user_account + #ct_party_user_account_link +
--   #ct_party_user_account + #ct_asp_membership → one temp table
-- FIX 5: asp_user_account_detail partitioned by party_user_account_link_id ONLY
-- FIX 6: exclude known bad party anchor IDs 7771543 and 13322119
----------------------------------------------------------------------------------------------------------

drop table if exists #email_account;

select
    ea.party_anchor_id,
    ea.user_name,
    ea.is_anonymous_indicator,
    ea.is_up_and_running_indicator,
    ea.SSACreateDate,
    ea.is_approved_indicator,
    ea.is_locked_out_indicator,
    ea.last_login_date,
    ea.tc_agree_date,
    ea.tc_agree_indicator,
    ea.EmailType,
    ea.VerifiedEmailInd
into #email_account
from (
    select
        pual.party_anchor_id,
        auad.user_name,
        auad.is_anonymous_indicator,
        auad.is_up_and_running_indicator,
        am.create_date                                                               as SSACreateDate,
        am.is_approved_indicator,
        am.is_locked_out_indicator,
        am.last_login_date,
        am.tc_agree_date,
        am.tc_agree_indicator,
        case when auad.user_name is not null then 'SSA' else null end                as EmailType,
        case when am.last_login_date > '2013-01-01' then 'Y' else 'N' end           as VerifiedEmailInd,
        -- One row per party: latest account link by load_date
        row_number() over (
            partition by pual.party_anchor_id
            order by pual.load_date desc
        ) as rn
    from AWM.dbo.party_user_account_link pual
    inner join (
        -- FIX 5: partition by link_id ONLY — adding user_name caused fan-out
        select
            party_user_account_link_id,
            user_name,
            is_anonymous_indicator,
            is_up_and_running_indicator,
            row_number() over (
                partition by party_user_account_link_id
                order by valid_from_date desc, valid_to_date desc
            ) as rn_detail
        from AWM.dbo.asp_user_account_detail
    ) auad
        on  auad.party_user_account_link_id = pual.party_user_account_link_id
        and auad.rn_detail = 1
    inner join (
        -- One membership record per user_account_anchor_id
        select
            user_account_anchor_id,
            create_date,
            is_approved_indicator,
            is_locked_out_indicator,
            last_login_date,
            tc_agree_date,
            tc_agree_indicator,
            row_number() over (
                partition by user_account_anchor_id
                order by valid_from_date desc
            ) as rn_mem
        from AWM.dbo.asp_membership_detail
    ) am
        on  am.user_account_anchor_id = pual.user_account_anchor_id
        and am.rn_mem = 1
    where pual.party_anchor_id not in ('7771543', '13322119')  -- FIX 6: exclude known bad anchors
) ea
where ea.rn = 1
;

----------------------------------------------------------------------------------------------------------
-- Step 8: policy_agent — one agent row per policy term
----------------------------------------------------------------------------------------------------------

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

----------------------------------------------------------------------------------------------------------
-- Step 9: policy_add_info — EDW-side paperless indicators and policy metadata
-- Note: edw_paperless_pol_ind / edw_paperless_bil_ind are from vw_policy_additional_information
--       These are supplementary to the CIF/AWM indicators in #cif_detail (Step 4)
--       CIF indicators are the primary source; EDW indicators are for cross-reference in Tableau
----------------------------------------------------------------------------------------------------------

drop table if exists #policy_add_info;

select
    pai.policy_term_key,
    pai.policy_symbol_code,
    pai.paperless_policy_indicator  as edw_paperless_pol_ind,
    pai.paperless_billing_indicator as edw_paperless_bil_ind
into #policy_add_info
from (
    select
        policy_term_key,
        policy_symbol_code,
        paperless_policy_indicator,
        paperless_billing_indicator,
        row_number() over (
            partition by policy_term_key
            order by effective_to_date desc
        ) as rn
    from DWM.EDW.vw_policy_additional_information
) pai
where pai.rn = 1
;

----------------------------------------------------------------------------------------------------------
-- Step 10: bim_email — BIM/Eloqua email fallback
-- FIX 7: 27,756 policies have AWM account links where is_up_and_running = N (incomplete setup)
--        BIM holds a valid email for these. Joined as fallback in final output.
-- HOH_IND = 'Y' ensures we use the primary contact's email (avoids secondary named insured emails)
-- max(EMAIL_ADDRESS) used as tie-break when HOH has multiple BIM contact records
----------------------------------------------------------------------------------------------------------

drop table if exists #bim_email;

select
    P.POL_KEY               as policy_number,   -- POL_KEY format matches EDW policy_number
    max(C.EMAIL_ADDRESS)    as EmailAddress
into #bim_email
from [BIM_Reporting_Weekly].[Eloqua].[CONTACT] C
inner join [BIM_Reporting_Weekly].[Eloqua].[POLICY] P
    on C.HH_ID = P.HH_ID
where C.END_DT      = '9999-12-31'
  and P.END_DT      = '9999-12-31'
  and P.POL_STS_CD  = 'INFORCE'
  and C.EMAIL_ADDRESS is not null
  and C.EMAIL_ADDRESS <> ''
  -- HOH_IND filter removed: some policies only have email on non-HOH contacts
  -- max() across all contacts still gives one email per policy
group by P.POL_KEY
;

--==========================================================================================================
-- FINAL OUTPUT: dbo.New_Paper_Report
--
-- Grain dedup: one row per policy_term_key
--   - NIN (named insured / HOH) preferred over ANI (additional named insured)
--   - Secondary sort on party_key desc for deterministic tie-break when both are NIN or both ANI
--
-- EmailAddress: AWM primary → BIM fallback (COALESCE)
-- EmailSource : 'AWM' or 'BIM' — lets Tableau flag or filter fallback records
--==========================================================================================================

-- NOTE: Writing to temp table first — change to dbo.New_Paper_Report (or target schema)
-- once DDL permissions are confirmed on the destination database
drop table if exists #New_Paper_Report;

select
    -- Policy identifiers
    src.policy_term_key,
    src.policy_number,
    src.exceed_policy_id,
    src.policy_symbol,
    src.policy_symbol_code,
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
    -- CIF paperless indicators (AWM — primary source of truth)
    src.Paperless_Bil_Ind,
    src.PaperlessBillDate,
    src.Paperless_Pol_Ind,
    src.PaperlessPolDate,
    -- EDW paperless indicators (supplementary — from vw_policy_additional_information)
    src.edw_paperless_pol_ind,
    src.edw_paperless_bil_ind,
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
    -- Email (AWM primary, BIM fallback for 27,756 incomplete accounts — FIX 7)
    coalesce(src.user_name, bim.EmailAddress)                                as EmailAddress,
    case
        when src.user_name is not null      then 'AWM'
        when bim.EmailAddress is not null   then 'BIM'
        else null
    end                                                                      as EmailSource,
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
        -- CIF paperless indicators (Step 4)
        cif.Paperless_Bil_Ind,
        cif.PaperlessBillDate,
        cif.Paperless_Pol_Ind,
        cif.PaperlessPolDate,
        -- Policy metadata (Step 9)
        pai.policy_symbol_code,
        pai.edw_paperless_pol_ind,
        pai.edw_paperless_bil_ind,
        -- Agent (Step 8)
        ag.agent_number,
        ag.agent_name,
        ag.sales_channel_code,
        ag.sales_channel,
        ag.sales_subchannel_code,
        ag.sales_subchannel,
        ag.financial_sales_subchannel_code,
        ag.financial_sales_subchannel,
        ag.agency,
        -- Email / SSA (Step 7)
        ea.user_name,
        ea.is_anonymous_indicator,
        ea.is_up_and_running_indicator,
        ea.SSACreateDate,
        ea.is_approved_indicator,
        ea.is_locked_out_indicator,
        ea.last_login_date,
        ea.tc_agree_date,
        ea.tc_agree_indicator,
        ea.EmailType,
        ea.VerifiedEmailInd,
        -- Grain dedup: one row per policy_term_key
        -- Priority 1: any party with AWM email wins
        -- Priority 2: NIN (named insured) preferred over ANI
        -- Priority 3: party_key desc for deterministic tiebreak
        -- This ensures ANI email is used when NIN has no email (fills ~7k gap)
        row_number() over (
            partition by b.policy_term_key
            order by
                case when ea.user_name is not null then 0 else 1 end,
                case when b.policyholder_type_code = 'NIN' then 0 else 1 end,
                b.party_key desc
        ) as rn_grain
    from #base_data b
    left join #cif_detail cif
        on  cif.party_anchor_id       = b.duplicate_party_anchor_id
        and cif.policy_number_stripped = substring(
                b.policy_number,
                case when b.policy_number like 'UMB%' then 5 else 4 end,
                len(b.policy_number)
            )
    left join #email_account ea
        on ea.party_anchor_id = b.duplicate_party_anchor_id
    left join #policy_agent ag
        on ag.policy_term_key = b.policy_term_key
    left join #policy_add_info pai
        on pai.policy_term_key = b.policy_term_key
) src
-- BIM POL_KEY = EDW policy_number (both full format e.g. 'CA 0130957') — direct join
left join #bim_email bim
    on bim.policy_number = src.policy_number
where src.rn_grain = 1
;

----------------------------------------------------------------------------------------------------------
-- VALIDATION: Quick row count and email coverage check after load
-- Expected: ~297,413 rows (one per policy_term_key)
-- Expected email coverage: ~87% after BIM fallback
----------------------------------------------------------------------------------------------------------

select
    count(*)                                                            as total_rows,
    sum(case when EmailAddress is not null  then 1 else 0 end)         as has_email,
    sum(case when EmailSource = 'BIM'       then 1 else 0 end)         as bim_fallback_used,
    sum(case when EmailSource = 'AWM'       then 1 else 0 end)         as awm_email,
    sum(case when EmailAddress is null      then 1 else 0 end)         as no_email,
    sum(case when Paperless_Bil_Ind = 'Y'  then 1 else 0 end)         as paperless_bill_y,
    sum(case when Paperless_Pol_Ind = 'Y'  then 1 else 0 end)         as paperless_pol_y,
    sum(case when PolicyStatus = 'INFORCE' then 1 else 0 end)         as inforce_count
from #New_Paper_Report
;
