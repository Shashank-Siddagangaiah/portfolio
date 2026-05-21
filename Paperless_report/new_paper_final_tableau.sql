--==========================================================================================================
-- TABLEAU USAGE
--   Initial SQL  : everything below up to and including the ##New_Paper_Report step
--   Custom SQL   : SELECT * FROM ##New_Paper_Report
--==========================================================================================================

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Set variables
----------------------------------------------------------------------------------------------------------

declare @as_of_date as date;
set @as_of_date = cast(dateadd(day, -1, getdate()) as date);

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Inforce EDW policies as of yesterday
----------------------------------------------------------------------------------------------------------

drop table if exists #policy_latest;

select
    p.policy_term_key
    , p.policy_number
    , p.exceed_policy_id
    , p.policy_symbol
    , p.policy_inforce_indicator
    , p.policy_transaction_type_code
    , p.policy_form
    , p.line_of_business
    , p.risk_state_code
    , p.term_type_code
    , p.effective_from_date
    , p.effective_to_date
    , p.policy_origin_type
    , p.insurance_score
    , p.pemco_tenure_date
into #policy_latest
from DWM.EDW.vw_policy p
where p.effective_from_date <= @as_of_date
  and p.effective_to_date   >  @as_of_date
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Latest household per policy term
----------------------------------------------------------------------------------------------------------

drop table if exists #house_latest;

select
    phm.policy_term_anchor_id
    , phm.household_id
    , row_number() over (
        partition by phm.policy_term_anchor_id
        order by phm.effective_date desc
    ) as rn
into #house_latest
from AWM.dbo.policy_household_mapping phm
where phm.effective_date <= @as_of_date
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Policy + household combined
----------------------------------------------------------------------------------------------------------

drop table if exists #inforce_terms;

select
    pl.*
    , h.household_id
into #inforce_terms
from #policy_latest pl
left join #house_latest h
    on h.policy_term_anchor_id = pl.policy_term_key
   and h.rn = 1
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Raw BIL/POL rows from cif_policy_party_detail — latest per link + doc type
----------------------------------------------------------------------------------------------------------

drop table if exists #CIF_POLICY_Detail1;

select
    cppd.policy_party_link_id
    , cppd.output_document_type_code
    , cppd.paper_notify_indicator
    , cppd.effective_from_date
    , row_number() over (
        partition by cppd.policy_party_link_id, cppd.output_document_type_code
        order by cppd.update_date desc
    ) as rn
into #CIF_POLICY_Detail1
from AWM.dbo.cif_policy_party_detail cppd
where cppd.output_document_type_code in ('BIL', 'POL')
  and cppd.effective_to_date = '9999-12-31'
  and cppd.valid_to_date     = '9999-12-31'
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Pivot BIL/POL + join to policy_anchor for full policy_number_raw
----------------------------------------------------------------------------------------------------------

drop table if exists #CIF_POLICY_Detail2;

select
    d1.policy_party_link_id
    , ltrim(rtrim(pa.policy_number))                                                              as policy_number_raw
    , ppl.party_anchor_id
    , max(case when d1.output_document_type_code = 'BIL' then d1.paper_notify_indicator end)     as BIL_paper_notify
    , max(case when d1.output_document_type_code = 'BIL' then d1.effective_from_date    end)     as paperless_bill_date
    , max(case when d1.output_document_type_code = 'POL' then d1.paper_notify_indicator end)     as POL_paper_notify
    , max(case when d1.output_document_type_code = 'POL' then d1.effective_from_date    end)     as paperless_pol_date
into #CIF_POLICY_Detail2
from #CIF_POLICY_Detail1 d1
inner join AWM.dbo.policy_party_link ppl
    on ppl.policy_party_link_id = d1.policy_party_link_id
inner join AWM.dbo.policy_anchor pa
    on pa.policy_anchor_id = ppl.policy_anchor_id
where d1.rn = 1
group by
    d1.policy_party_link_id
    , ltrim(rtrim(pa.policy_number))
    , ppl.party_anchor_id
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Convert paper_notify_indicator to Y/N flags
----------------------------------------------------------------------------------------------------------

drop table if exists #CIF_POLICY_Detail;

select
    c.policy_party_link_id
    , c.policy_number_raw
    , c.party_anchor_id
    , case when c.BIL_paper_notify = 0 then 'Y' when c.BIL_paper_notify is null then null else 'N' end  as paperless_bil_ind
    , c.paperless_bill_date
    , case when c.POL_paper_notify = 0 then 'Y' when c.POL_paper_notify is null then null else 'N' end  as paperless_pol_ind
    , c.paperless_pol_date
into #CIF_POLICY_Detail
from #CIF_POLICY_Detail2 c
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Policyholder demographics per policy term
----------------------------------------------------------------------------------------------------------

drop table if exists #view_ph;

select
    it.policy_term_key
    , it.policy_number
    , it.exceed_policy_id
    , it.policy_symbol
    , it.policy_inforce_indicator
    , it.policy_transaction_type_code
    , it.policy_form
    , it.line_of_business
    , it.risk_state_code
    , it.term_type_code
    , it.effective_from_date
    , it.effective_to_date
    , it.policy_origin_type
    , it.insurance_score
    , it.pemco_tenure_date
    , it.household_id
    , vplh.party_key
    , vplh.full_name                      as FullName
    , vplh.term_effective_date            as Start_date
    , vplh.term_expiration_date           as End_Date
    , vplh.policyholder_type_code
    , vplh.affinity_group_code
    , vplh.gender
    , vplh.gender_code
    , vplh.marital_status
    , vplh.marital_status_code
    , datediff(year, vplh.birth_date, @as_of_date)
        - case
              when dateadd(year, datediff(year, vplh.birth_date, @as_of_date), vplh.birth_date) > @as_of_date
              then 1 else 0
          end                             as Age
    , case when vplh.policyholder_type_code = 'NIN' then 'Y' else 'N' end  as HOH_IND
    , vplh.mailing_address_city
    , vplh.mailing_address_state_code
    , vplh.mailing_address_zip_code
    , vplh.original_effective_date
into #view_ph
from #inforce_terms it
left join DWM.EDW.vw_policyholder vplh
    on vplh.policy_term_key = it.policy_term_key
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Map EDW party_key to AWM duplicate_party_anchor_id via party_id_same_as_link
----------------------------------------------------------------------------------------------------------

drop table if exists #base_data;

select
    ph.*
    , pil.party_anchor_id_duplicate
    , pta.party_anchor_id     as duplicate_party_anchor_id
    , pil.cif_id
    , pta.exceed_client_id
into #base_data
from #view_ph ph
left join (
    select
        party_anchor_id_master
        , party_anchor_id_duplicate
        , party_id_duplicate  as cif_id
        , row_number() over (
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
-- Initial SQL: Latest account detail row per party_user_account_link_id
----------------------------------------------------------------------------------------------------------

drop table if exists #ct_asp_user_account;

select
    auad.party_user_account_link_id
    , auad.user_name
    , auad.is_anonymous_indicator
    , auad.is_up_and_running_indicator
    , auad.valid_from_date
    , auad.valid_to_date
    , row_number() over (
        partition by auad.party_user_account_link_id
        order by auad.valid_from_date desc, auad.valid_to_date desc
    ) as rn_user_account
into #ct_asp_user_account
from AWM.dbo.asp_user_account_detail auad
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Latest link row per party_anchor_id (bad anchor IDs excluded)
----------------------------------------------------------------------------------------------------------

drop table if exists #ct_party_user_account_link;

select
    pual.*
    , row_number() over (
        partition by pual.party_anchor_id
        order by pual.load_date desc
    ) as rn_link
into #ct_party_user_account_link
from AWM.dbo.party_user_account_link pual
where pual.party_anchor_id not in ('7771543', '13322119')
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Joined email account per party (one row per party)
----------------------------------------------------------------------------------------------------------

drop table if exists #ct_party_user_account;

select
    a.party_user_account_link_id
    , a.user_name
    , a.is_anonymous_indicator
    , a.is_up_and_running_indicator
    , a.valid_from_date
    , a.valid_to_date
    , l.user_account_anchor_id
    , l.party_anchor_id
    , l.load_date
into #ct_party_user_account
from #ct_asp_user_account a
inner join #ct_party_user_account_link l
    on a.party_user_account_link_id = l.party_user_account_link_id
where a.rn_user_account = 1
  and l.rn_link         = 1
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: SSA membership details per party
----------------------------------------------------------------------------------------------------------

drop table if exists #ct_asp_membership;

select
    cua.party_anchor_id
    , cua.user_name
    , cua.is_anonymous_indicator
    , cua.is_up_and_running_indicator
    , cua.user_account_anchor_id
    , am.create_date                                                               as SSACreateDate
    , am.is_approved_indicator
    , am.is_locked_out_indicator
    , am.last_login_date
    , am.tc_agree_date
    , am.tc_agree_indicator
    , case when cua.user_name is not null then 'SSA' else null end                 as EmailType
    , case when am.last_login_date > '2013-01-01' then 'Y' else 'N' end           as VerifiedEmailInd
    , row_number() over (
        partition by am.user_account_anchor_id
        order by am.valid_from_date desc
    ) as rn_membership
into #ct_asp_membership
from #ct_party_user_account cua
inner join AWM.dbo.asp_membership_detail am
    on am.user_account_anchor_id = cua.user_account_anchor_id
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: One agent row per policy term
----------------------------------------------------------------------------------------------------------

drop table if exists #policy_agent;

select
    ag.policy_term_key
    , ag.policy_agent_type_code
    , ag.policy_agent_inforce_indicator
    , ag.agent_number
    , ag.agent_name
    , ag.sales_channel_code
    , ag.sales_channel
    , ag.sales_subchannel_code
    , ag.sales_subchannel
    , ag.financial_sales_subchannel_code
    , ag.financial_sales_subchannel
    , substring(ag.agent_number, 4, 3)    as agency
into #policy_agent
from (
    select
        policy_term_key
        , policy_agent_type_code
        , policy_agent_inforce_indicator
        , agent_number
        , agent_name
        , sales_channel_code
        , sales_channel
        , sales_subchannel_code
        , sales_subchannel
        , financial_sales_subchannel_code
        , financial_sales_subchannel
        , row_number() over (
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
-- Initial SQL: Final output — one row per policy_term_key (email-aware grain dedup)
----------------------------------------------------------------------------------------------------------

drop table if exists ##New_Paper_Report;

select
    src.policy_term_key
    , src.policy_number
    , src.exceed_policy_id
    , src.policy_symbol
    , src.policy_transaction_type_code
    , src.policy_form
    , src.line_of_business
    , src.risk_state_code
    , src.term_type_code
    , src.effective_from_date
    , src.effective_to_date
    , src.policy_origin_type
    , src.insurance_score
    , src.pemco_tenure_date
    , src.household_id
    , case when src.policy_inforce_indicator = 1 then 'INFORCE' else '' end   as PolicyStatus
    , src.policy_inforce_indicator
    , src.party_key
    , src.duplicate_party_anchor_id   as party_anchor_id
    , src.cif_id                      as CIFID
    , src.exceed_client_id
    , src.FullName
    , src.Age
    , src.HOH_IND
    , src.policyholder_type_code
    , src.gender                       as Gender
    , src.gender_code
    , src.marital_status
    , src.marital_status_code
    , src.affinity_group_code
    , src.Start_date
    , src.End_Date
    , src.mailing_address_city
    , src.mailing_address_state_code
    , src.mailing_address_zip_code
    , src.original_effective_date
    , src.paperless_bil_ind            as paperless_billing_indicator
    , src.paperless_bill_date
    , src.paperless_pol_ind            as paperless_policy_indicator
    , src.paperless_pol_date
    , src.policy_agent_type_code
    , src.policy_agent_inforce_indicator
    , src.agent_number
    , src.agent_name
    , src.sales_channel_code
    , src.sales_channel
    , src.sales_subchannel_code
    , src.sales_subchannel
    , src.financial_sales_subchannel_code
    , src.financial_sales_subchannel
    , src.agency
    , src.user_name
    , case when src.user_name is not null then 'AWM' else null end             as EmailSource
    , src.EmailType
    , src.VerifiedEmailInd            as EmailVerification
    , case when src.EmailType = 'SSA' then 'Y' else 'N' end                   as SelfServiceInd
    , src.SSACreateDate               as SelfServiceDate
    , src.is_anonymous_indicator
    , src.is_up_and_running_indicator
    , src.is_approved_indicator
    , src.is_locked_out_indicator
    , src.last_login_date
    , src.tc_agree_date
    , src.tc_agree_indicator
into ##New_Paper_Report
from (
    select
        b.*
        , cif.paperless_bil_ind
        , cif.paperless_bill_date
        , cif.paperless_pol_ind
        , cif.paperless_pol_date
        , ag.policy_agent_type_code
        , ag.policy_agent_inforce_indicator
        , ag.agent_number
        , ag.agent_name
        , ag.sales_channel_code
        , ag.sales_channel
        , ag.sales_subchannel_code
        , ag.sales_subchannel
        , ag.financial_sales_subchannel_code
        , ag.financial_sales_subchannel
        , ag.agency
        , m.user_name
        , m.is_anonymous_indicator
        , m.is_up_and_running_indicator
        , m.SSACreateDate
        , m.is_approved_indicator
        , m.is_locked_out_indicator
        , m.last_login_date
        , m.tc_agree_date
        , m.tc_agree_indicator
        , m.EmailType
        , m.VerifiedEmailInd
        , row_number() over (
            partition by b.policy_term_key
            order by
                case when m.user_name is not null           then 0 else 1 end,
                case when b.policyholder_type_code = 'NIN'  then 0 else 1 end,
                b.party_key desc
        ) as rn_grain
    from #base_data b
    left join #CIF_POLICY_Detail cif
        on  cif.party_anchor_id   = b.duplicate_party_anchor_id
        and cif.policy_number_raw = ltrim(rtrim(b.policy_number))
    left join #ct_asp_membership m
        on  m.party_anchor_id = b.duplicate_party_anchor_id
        and m.rn_membership   = 1
    left join #policy_agent ag
        on ag.policy_term_key = b.policy_term_key
) src
where src.rn_grain = 1
;

--==========================================================================================================
-- Custom SQL (paste into Tableau Custom SQL dialog):
--   SELECT * FROM ##New_Paper_Report
--==========================================================================================================
