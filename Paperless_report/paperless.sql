----------------------------------------------------------------------------------------------------------
-- Initial SQL: Set variables
----------------------------------------------------------------------------------------------------------

declare @years as tinyint;
declare @calendar_start as date;
declare @calendar_end as date;
declare @now as datetime;
declare @as_of_date as date;

set @years = 5;
set @now = getdate();

-- As-of date (yesterday)
set @as_of_date = cast(dateadd(day, -1, @now) as date);

-- Calendar end date (same as as-of date)
set @calendar_end = @as_of_date;

-- Calendar start date: year start @years prior to calendar_end
set @calendar_start =
    dateadd(
        year,
        @years * -1,
        dateadd(year, datediff(year, 0, @calendar_end), 0)
    )
;


----------------------------------------------------------------------------------------------------------
-- SQL: policy_latest
----------------------------------------------------------------------------------------------------------

drop table if exists #policy_latest
;

select
    p.policy_term_key,
    p.policy_number,
    p.policy_inforce_indicator,
    p.policy_transaction_type_code,
    p.exceed_policy_id,
    p.policy_symbol,
    p.line_of_business,
    p.policy_form,
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
  and p.effective_to_date  >  @as_of_date
;

----------------------------------------------------------------------------------------------------------
-- SQL: house_latest
----------------------------------------------------------------------------------------------------------

drop table if exists #house_latest
;

select
    phm.policy_term_anchor_id,
    phm.household_id,
    row_number() over (
        partition by phm.policy_term_anchor_id
        order by phm.effective_date desc
    ) as rn
into #house_latest
from AWM.dbo.policy_household_mapping phm
where phm.effective_date <= @as_of_date  -- FIX: added date filter to prevent future-dated household mappings
;

----------------------------------------------------------------------------------------------------------
-- SQL: inforce_terms
-- UPDATED: moved rn=1 filter into JOIN condition for cleaner logic
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
;  -- and pl.policy_inforce_indicator = 1

----------------------------------------------------------------------------------------------------------
-- NEW: CIF policy detail step 1
-- Pulls paperless notification settings from AWM cif_policy_party_detail
-- Filters to BIL/POL document types with open-ended effective_to_date
----------------------------------------------------------------------------------------------------------

drop table if exists #CIF_POLICY_Detail1;

select
    cppd.policy_party_link_id,
    cppd.output_document_type_code,
    cppd.paper_notify_indicator,
    cppd.effective_from_date,
    cppd.effective_to_date,
    row_number() over
    (
        partition by cppd.policy_party_link_id, cppd.output_document_type_code
        order by cppd.effective_from_date desc
    ) as row_num
into #CIF_POLICY_Detail1
from AWM.dbo.cif_policy_party_detail cppd
where cppd.output_document_type_code in ('BIL', 'POL')
  and cppd.effective_to_date = '9999-12-31'
;

----------------------------------------------------------------------------------------------------------
-- NEW: CIF policy detail step 2
-- Pivots BIL/POL rows into columns per policy_party_link_id
-- Joins to policy_party_link and policy_anchor to get policy_number and party_anchor_id
----------------------------------------------------------------------------------------------------------

drop table if exists #CIF_POLICY_Detail2;

-- FIX: store full pa.policy_number (with LOB prefix) instead of stripping to bare number.
-- Stripping caused cross-LOB collisions: 'CA 1774271' and 'HO 1774271' both became '1774271'
-- and b.policy_number = 'CA 1774271' incorrectly matched CIF rows for HO 1774271.
-- Keeping the full string ensures exact LOB match. Bare anchor rows (no prefix) are handled
-- in the join via a separate fallback condition.
select
    d1.policy_party_link_id,
    ltrim(rtrim(pa.policy_number)) as policy_number_raw,
    ppl.party_anchor_id,
    max(case when d1.output_document_type_code = 'BIL' then d1.paper_notify_indicator end) as BIL_paper_notify,
    max(case when d1.output_document_type_code = 'BIL' then d1.effective_from_date end) as PaperlessBillDate,
    max(case when d1.output_document_type_code = 'POL' then d1.paper_notify_indicator end) as POL_paper_notify,
    max(case when d1.output_document_type_code = 'POL' then d1.effective_from_date end) as PaperlessPolDate
into #CIF_POLICY_Detail2
from #CIF_POLICY_Detail1 d1
inner join AWM.dbo.policy_party_link ppl
    on d1.policy_party_link_id = ppl.policy_party_link_id
inner join AWM.dbo.policy_anchor pa
    on pa.policy_anchor_id = ppl.policy_anchor_id
where d1.row_num = 1
group by
    d1.policy_party_link_id,
    ltrim(rtrim(pa.policy_number)),   -- FIX: group by full string to keep CA/HO/bare rows distinct
    ppl.party_anchor_id
;

----------------------------------------------------------------------------------------------------------
-- NEW: Final CIF policy detail
-- Converts paper_notify_indicator (0/1) to Paperless Y/N flags
-- paper_notify_indicator = 0 means paperless (no paper), hence 'Y'
----------------------------------------------------------------------------------------------------------

drop table if exists #CIF_POLICY_Detail;

select
    c.policy_party_link_id,
    c.policy_number_raw,   -- FIX: full policy number with LOB prefix (e.g. 'CA 1774271') — no stripping
    c.party_anchor_id,
    case when c.BIL_paper_notify = 0 then 'Y' else 'N' end as Paperless_Bil_Ind,
    c.PaperlessBillDate,
    case when c.POL_paper_notify = 0 then 'Y' else 'N' end as Paperless_Pol_Ind,
    c.PaperlessPolDate
into #CIF_POLICY_Detail
from #CIF_POLICY_Detail2 c
;

----------------------------------------------------------------------------------------------------------
-- SQL: view_ph
----------------------------------------------------------------------------------------------------------

drop table if exists #view_ph;

select
    it.*,
    vplh.party_key,
    vplh.full_name as FullName,
    vplh.term_effective_date as Start_date,
    vplh.term_expiration_date as End_Date,
    vplh.policyholder_type_code,
    vplh.affinity_group_code,
    vplh.gender as Gender,
    vplh.gender_code,
    vplh.marital_status,
    vplh.marital_status_code,
    datediff(year, vplh.birth_date, @as_of_date)
      - case
            when dateadd(year, datediff(year, vplh.birth_date, @as_of_date), vplh.birth_date) > @as_of_date
            then 1 else 0
        end as Age,
    case
        when vplh.policyholder_type_code = 'NIN' then 'Y'
        when vplh.policyholder_type_code = 'ANI' then 'N'
        else 'N'
    end as HOH_IND,
    vplh.mailing_address_city,
    vplh.mailing_address_state_code,
    vplh.mailing_address_zip_code,
    vplh.original_effective_date
into #view_ph
from #inforce_terms it
left join DWM.EDW.vw_policyholder vplh
    on vplh.policy_term_key      = it.policy_term_key
   and vplh.term_effective_date  = it.effective_from_date
   and vplh.term_expiration_date = it.effective_to_date
   and vplh.term_expiration_date > @as_of_date
;

----------------------------------------------------------------------------------------------------------
-- SQL: base_data
-- FIX: deduplicated party_id_same_as_link to prevent row fan-out from multiple duplicate party matches
----------------------------------------------------------------------------------------------------------

drop table if exists #base_data_link;

-- Dedup: take one duplicate party per master party_key
select
    pil.party_anchor_id_master,
    pil.party_anchor_id_duplicate,
    pil.party_id_duplicate as cif_id,  -- NEW: CIF ID from party_id_same_as_link (different from exceed_client_id)
    row_number() over (
        partition by pil.party_anchor_id_master
        order by pil.party_anchor_id_duplicate desc
    ) as rn_link
into #base_data_link
from AWM.dbo.party_id_same_as_link pil
;

drop table if exists #base_data;

select
    ph.*,
    bdl.party_anchor_id_duplicate,
    pta.party_anchor_id as duplicate_party_anchor_id,
    bdl.cif_id,           -- NEW: CIF ID (party_id_duplicate from party_id_same_as_link)
    pta.exceed_client_id
into #base_data
from #view_ph ph
left join #base_data_link bdl
    on ph.party_key = bdl.party_anchor_id_master
   and bdl.rn_link = 1  -- FIX: take only one duplicate per party_key
left join AWM.dbo.party_anchor pta
    on bdl.party_anchor_id_duplicate = pta.party_anchor_id
;

----------------------------------------------------------------------------------------------------------
-- SQL: ct_asp_user_account
----------------------------------------------------------------------------------------------------------

drop table if exists #ct_asp_user_account
;

select
    auad.party_user_account_link_id,
    auad.user_name,
    auad.is_anonymous_indicator,
    auad.is_up_and_running_indicator,
    auad.valid_from_date,
    auad.valid_to_date,
    row_number() over (
        partition by auad.party_user_account_link_id, auad.user_name
        order by auad.valid_from_date desc, auad.valid_to_date desc
    ) as rn_user_account
into #ct_asp_user_account
from AWM.dbo.asp_user_account_detail auad
;

----------------------------------------------------------------------------------------------------------
-- SQL: ct_party_user_account_link
----------------------------------------------------------------------------------------------------------

drop table if exists #ct_party_user_account_link
;

select
    pual.*,
    row_number() over (
        partition by pual.party_anchor_id
        order by pual.load_date desc
    ) as rn_link
into #ct_party_user_account_link
from AWM.dbo.party_user_account_link pual
where party_anchor_id not in ('7771543','13322119')
;

----------------------------------------------------------------------------------------------------------
-- SQL: ct_party_user_account
----------------------------------------------------------------------------------------------------------

drop table if exists #ct_party_user_account
;

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
  and l.rn_link = 1           -- FIX: added missing dedup filter to take only latest link per party
;

----------------------------------------------------------------------------------------------------------
-- SQL: ct_policy_add_info
----------------------------------------------------------------------------------------------------------

drop table if exists #ct_policy_add_info
;

select *
into #ct_policy_add_info
from (
    select *,
        row_number() over (
            partition by policy_term_key, policy_number
            order by effective_to_date desc
        ) as row_order
    from DWM.EDW.vw_policy_additional_information  -- FIX: removed stray 'SELECT * F' syntax error
) a
where row_order = 1
;

----------------------------------------------------------------------------------------------------------
-- SQL: ct_policy_agent
----------------------------------------------------------------------------------------------------------

drop table if exists #ct_policy_agent
;

select *
into #ct_policy_agent
from (
    select
        policy_term_key,
        party_key,
        effective_to_date,
        policy_number,
        policy_agent_type_code,
        policy_agent_inforce_indicator,
        agent_number,
        agent_name,
        sales_channel_code,
        sales_channel,
        sales_subchannel_code,
        sales_subchannel,
        financial_sales_subchannel_code,
        financial_sales_subchannel,
        substring(agent_number, 4, 3) as agency,
        row_number() over (
            partition by party_key, policy_number
            order by term_effective_date desc
        ) as row_num
    from DWM.EDW.vw_policy_agent
    where policy_agent_type_code = 'AGT'
      and policy_agent_inforce_indicator = 1
) a
where row_num = 1
;

----------------------------------------------------------------------------------------------------------
-- SQL: Create #policy
----------------------------------------------------------------------------------------------------------

drop table if exists #policy
;

select
    b.*,
    pai.policy_symbol_code,    -- FIX: added 'pai.' alias to resolve column ambiguity
    pai.paperless_policy_indicator,
    pai.paperless_billing_indicator,
    ag.policy_agent_type_code,
    ag.policy_agent_inforce_indicator,
    ag.agent_number,
    ag.agent_name,
    ag.sales_channel_code,
    ag.sales_channel,
    ag.sales_subchannel_code,
    ag.sales_subchannel,
    ag.financial_sales_subchannel_code,
    ag.financial_sales_subchannel,
    ag.agency,
    cua.user_name,
    cua.is_anonymous_indicator,
    cua.is_up_and_running_indicator,
    cua.valid_from_date as user_valid_from_date,
    cua.valid_to_date   as user_valid_to_date,
    cua.user_account_anchor_id,
    cua.party_user_account_link_id,
    cua.load_date       as user_link_load_date,
    -- CIF JOIN: strict PARTY+POL match only (for comparison with old_paper.sql)
    cif.Paperless_Bil_Ind,
    cif.PaperlessBillDate,
    cif.Paperless_Pol_Ind,
    cif.PaperlessPolDate
into #policy
from #base_data b
left join #ct_party_user_account cua
    on cua.party_anchor_id = b.duplicate_party_anchor_id
left join #ct_policy_add_info pai
    on b.policy_term_key = pai.policy_term_key
left join #ct_policy_agent ag
    on ag.policy_term_key = b.policy_term_key
-- CIF JOIN: match on party_anchor_id + full policy_number_raw to avoid cross-LOB collisions.
-- 'CA 1774271' (CIF) matches only b.policy_number = 'CA 1774271', not 'HO 1774271'.
-- Bare CIF rows (no prefix) fall through to the second condition as a numeric fallback.
left join #CIF_POLICY_Detail cif
    on cif.party_anchor_id = b.duplicate_party_anchor_id
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
;

----------------------------------------------------------------------------------------------------------
-- SQL: ct_asp_membership
-- NEW: SSA/Email details from asp_membership_detail (separate temp table for easy removal if not needed)
-- Ref: example_paper.sql ct_asp_user_account CTE step 3
----------------------------------------------------------------------------------------------------------

drop table if exists #ct_asp_membership;

select
    cua.party_anchor_id,
    cua.user_name,
    cua.user_account_anchor_id,
    am.create_date       as SSACreateDate,
    am.asp_membership_detail_id,
    am.is_approved_indicator,
    am.is_locked_out_indicator,
    am.last_login_date,
    am.tc_agree_date,
    am.tc_agree_indicator,
    am.telematics_eula_agree_date,
    am.telematics_eula_version,
    case when cua.user_name is not null then 'SSA' else null end as EmailType,
    case when am.last_login_date > '2013-01-01' then 'Y' else 'N' end as VerifiedEmailInd,
    row_number() over (
        partition by am.user_account_anchor_id
        order by am.valid_from_date desc
    ) as rn_membership
into #ct_asp_membership
from #ct_party_user_account cua
inner join AWM.dbo.asp_membership_detail am
    on cua.user_account_anchor_id = am.user_account_anchor_id
;

----------------------------------------------------------------------------------------------------------
-- SQL: Output
-- Joins #policy with SSA/membership details
-- Adds PolicyStatus and SSA-derived columns to match example_paper.sql output
----------------------------------------------------------------------------------------------------------

select
    p.*,
    case when p.policy_inforce_indicator = 1 then 'INFORCE' else '' end as PolicyStatus,  -- NEW: matches old BIM POL_STS_CD
    m.EmailType,
    m.user_name        as EmailAddress,
    m.VerifiedEmailInd as EmailVerification,
    case when m.EmailType = 'SSA' then 'Y' else 'N' end as SelfServiceInd,
    m.SSACreateDate    as SelfServiceDate,
    m.is_approved_indicator,
    m.is_locked_out_indicator,
    m.last_login_date,
    m.tc_agree_date,
    m.tc_agree_indicator
from #policy p
left join #ct_asp_membership m
    on m.party_anchor_id = p.duplicate_party_anchor_id
   and m.rn_membership = 1  -- latest membership record per user_account
;
 