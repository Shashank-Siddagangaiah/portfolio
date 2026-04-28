----------------------------------------------------------------------------------------------------------
-- OLD BIM vs NEW EDW Validation
-- Purpose: Compare old Eloqua/BIM paperless report against new AWM/EDW approach
-- Join key: PolNumber only
-- Compares: PaperlessBillInd, PaperlessBillDate, PaperlessPolInd, PaperlessPolDate, EmailAddress
--
-- DIAGNOSTIC FIXES APPLIED
-- FIX D1: policyholder_type_code added to #view_ph — required for email-aware grain dedup
-- FIX D2: pual subquery uses INNER JOIN on asp_user_account_detail before rn=1 assignment
--         Orphaned links (pual exists, no auad) are excluded from ranking so a valid older
--         link is not hidden behind a newer orphaned one. Recovers ~20,034 missed emails.
-- FIX D3: Grain dedup uses email-aware ordering (mirrors new_paper_final.sql FIX 8)
--         ANI email is preferred over NIN when NIN has no email. Recovers +47,658 ANI emails.
-- FIX D4: Summary dedup collapses multi-party rows to one per policy_term_key before counting
--         Without this, NIN + ANI rows per policy caused breakpoints to sum above total (423K > 294K)
----------------------------------------------------------------------------------------------------------

declare @as_of_date as date;
set @as_of_date = cast(dateadd(day, -1, getdate()) as date);

----------------------------------------------------------------------------------------------------------
-- Step 1: policy_latest (EDW policies as of yesterday)
----------------------------------------------------------------------------------------------------------

drop table if exists #policy_latest;

select
    p.policy_term_key,
    p.policy_number,
    p.exceed_policy_id,
    p.policy_symbol,
    p.policy_inforce_indicator,
    p.effective_from_date,
    p.effective_to_date
into #policy_latest
from DWM.EDW.vw_policy p
where p.effective_from_date <= @as_of_date
  and p.effective_to_date  >  @as_of_date
;

----------------------------------------------------------------------------------------------------------
-- Step 2: house_latest (latest household per policy term)
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
-- Step 3: inforce_terms (policy + household)
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
-- Step 4: policyholder (to get party_key for same-as-link join)
-- FIX D1: Added policyholder_type_code — needed for email-aware grain dedup (mirrors FIX 8)
--         Without this, NIN was always preferred regardless of email availability
----------------------------------------------------------------------------------------------------------

drop table if exists #view_ph;

select
    it.*,
    vplh.party_key,
    vplh.policyholder_type_code
into #view_ph
from #inforce_terms it
-- FIX: relaxed to policy_term_key only (matches new_paper_final.sql FIX 1)
-- Strict date match dropped ~35,820 policies with mid-term endorsement date offsets
left join DWM.EDW.vw_policyholder vplh
    on vplh.policy_term_key = it.policy_term_key
;

----------------------------------------------------------------------------------------------------------
-- Step 5a: #base_data_link — deduplicated party_id_same_as_link
-- Extracts one duplicate party anchor per master party_key.
-- Mirrors paperless.sql #base_data_link pattern so inline subquery fan-out is eliminated early.
----------------------------------------------------------------------------------------------------------

drop table if exists #base_data_link;

select
    pil.party_anchor_id_master,
    pil.party_anchor_id_duplicate,
    pil.party_id_duplicate as cif_id,
    row_number() over (
        partition by pil.party_anchor_id_master
        order by pil.party_anchor_id_duplicate desc
    ) as rn_link
into #base_data_link
from AWM.dbo.party_id_same_as_link pil
;

----------------------------------------------------------------------------------------------------------
-- Step 5b: #base_data — party + household + same-as-link + party anchor
-- Maps party_key -> duplicate_party_anchor_id for email chain and CIF matching
----------------------------------------------------------------------------------------------------------

drop table if exists #base_data;

select
    ph.*,
    bdl.party_anchor_id_duplicate,
    pta.party_anchor_id as duplicate_party_anchor_id,
    bdl.cif_id,
    pta.exceed_client_id
into #base_data
from #view_ph ph
left join #base_data_link bdl
    on ph.party_key = bdl.party_anchor_id_master
   and bdl.rn_link = 1        -- one duplicate party per master
left join AWM.dbo.party_anchor pta
    on bdl.party_anchor_id_duplicate = pta.party_anchor_id
;

----------------------------------------------------------------------------------------------------------
-- Step 6a: #CIF_POLICY_Detail1 — raw filtered rows from cif_policy_party_detail
-- Mirrors paperless.sql #CIF_POLICY_Detail1 pattern.
-- Deduplicates per (policy_party_link_id, doc_type) using update_date desc so the latest
-- notification preference wins when a party has multiple history rows.
----------------------------------------------------------------------------------------------------------

drop table if exists #CIF_POLICY_Detail1;

select
    cppd.policy_party_link_id,
    cppd.output_document_type_code,
    cppd.paper_notify_indicator,
    cppd.effective_from_date,
    cppd.effective_to_date,
    row_number() over (
        partition by cppd.policy_party_link_id, cppd.output_document_type_code
        order by cppd.update_date desc
    ) as row_num
into #CIF_POLICY_Detail1
from AWM.dbo.cif_policy_party_detail cppd
where cppd.output_document_type_code in ('BIL', 'POL')
  and cppd.effective_to_date = '9999-12-31'
  and cppd.valid_to_date     = '9999-12-31'
;

----------------------------------------------------------------------------------------------------------
-- Step 6b: #CIF_POLICY_Detail2 — pivot BIL/POL rows into columns, join to policy_anchor + party_anchor
-- FIX: stores full pa.policy_number as policy_number_raw (no stripping).
-- Stripping to bare number caused cross-LOB collisions: 'CA 1774271' and 'HO 1774271' both → '1774271',
-- causing b.policy_number = 'CA 1774271' to incorrectly match CIF rows linked to the HO anchor.
-- Keeping the full string + using exact match in the JOIN prevents this fan-out.
-- Bare anchor rows (no prefix) are matched via a separate fallback condition in the JOIN.
----------------------------------------------------------------------------------------------------------

drop table if exists #CIF_POLICY_Detail2;

select
    d1.policy_party_link_id,
    ppl.party_anchor_id,
    pta.exceed_client_id,
    ltrim(rtrim(pa.policy_number))                                                              as policy_number_raw,
    min(case when d1.output_document_type_code = 'BIL' then d1.paper_notify_indicator end)     as BIL_paper_notify,
    max(case when d1.output_document_type_code = 'BIL' then d1.effective_from_date end)        as PaperlessBillDate,
    min(case when d1.output_document_type_code = 'POL' then d1.paper_notify_indicator end)     as POL_paper_notify,
    max(case when d1.output_document_type_code = 'POL' then d1.effective_from_date end)        as PaperlessPolDate
into #CIF_POLICY_Detail2
from #CIF_POLICY_Detail1 d1
inner join AWM.dbo.policy_party_link ppl
    on d1.policy_party_link_id = ppl.policy_party_link_id
inner join AWM.dbo.policy_anchor pa
    on pa.policy_anchor_id = ppl.policy_anchor_id
left join AWM.dbo.party_anchor pta
    on pta.party_anchor_id = ppl.party_anchor_id
where d1.row_num = 1
group by
    d1.policy_party_link_id,
    ppl.party_anchor_id,
    pta.exceed_client_id,
    ltrim(rtrim(pa.policy_number))   -- FIX: full string — keeps CA/HO/bare rows distinct
;

----------------------------------------------------------------------------------------------------------
-- Step 6c: #CIF_POLICY_Detail — convert paper_notify_indicator (0/1) to Y/N flags
-- paper_notify_indicator = 0 means paperless (no paper) → 'Y'
-- NULL notify → NULL indicator (policy exists in CIF but no preference set)
----------------------------------------------------------------------------------------------------------

drop table if exists #CIF_POLICY_Detail;

select
    c.policy_party_link_id,
    c.party_anchor_id,
    c.exceed_client_id,
    c.policy_number_raw,
    case when c.BIL_paper_notify = 0 then 'Y' when c.BIL_paper_notify is null then null else 'N' end as Paperless_Bil_Ind,
    c.PaperlessBillDate,
    case when c.POL_paper_notify = 0 then 'Y' when c.POL_paper_notify is null then null else 'N' end as Paperless_Pol_Ind,
    c.PaperlessPolDate
into #CIF_POLICY_Detail
from #CIF_POLICY_Detail2 c
;

--=========================================================================================================
-- VALIDATION: OLD BIM vs NEW (pol+party) COMPARISON
-- Compares Eloqua (BIM) data against new AWM/EDW approach on 4 key attributes:
--   PolNumber, PaperlessBillInd, PaperlessBillDate, PaperlessPolInd, PaperlessPolDate, EmailAddress
--=========================================================================================================

----------------------------------------------------------------------------------------------------------
-- Step 1: Pull old BIM data (same logic as old_paper.sql)
----------------------------------------------------------------------------------------------------------

drop table if exists #old_bim;

select distinct
    C.HH_ID           as HouseholdID,
    C.CIF_ID          as CIFID,
    C.EMAIL_ADDRESS   as EmailAddress,
    P.POL_KEY         as PolNumber,
    P.PPRLESS_BIL_IND as PaperlessBillInd,
    P.PPRLESS_BIL_DT  as PaperlessBillDate,
    P.PPRLESS_POL_IND as PaperlessPolInd,
    P.PPRLESS_POL_DT  as PaperlessPolDate
into #old_bim
from [BIM_Reporting_Weekly].[Eloqua].[CONTACT] as C
left outer join [BIM_Reporting_Weekly].[Eloqua].[POLICY] as P
    on C.HH_ID = P.HH_ID
where C.END_DT = '9999-12-31'
  and P.END_DT = '9999-12-31'
  and P.POL_STS_CD = 'INFORCE'
;

--==========================================================================================================
-- INTERMEDIATE INSPECTION TABLE A: #cif_join_raw
-- Purpose: Shows every b row joined to its CIF row BEFORE any grain dedup.
--          Use this to verify:
--            - Each party gets its own CIF row (not another party's)
--            - policy_number_raw on CIF side matches correctly (prefixed vs bare)
--            - Paperless indicators are correct per party
--          Run: SELECT * FROM #cif_join_raw WHERE policy_number = 'CA 0054176'
--==========================================================================================================

drop table if exists #cif_join_raw;

select
    b.policy_term_key,
    b.policy_number,
    b.party_key,
    b.policyholder_type_code,
    b.duplicate_party_anchor_id,
    b.cif_id,
    -- CIF columns — NULL if no CIF row matched for this party
    cif.party_anchor_id          as cif_matched_party_anchor_id,
    cif.policy_number_raw        as cif_policy_number_raw,
    cif.Paperless_Bil_Ind,
    cif.PaperlessBillDate,
    cif.Paperless_Pol_Ind,
    cif.PaperlessPolDate,
    -- Match type: shows which branch of the join condition fired
    case
        when cif.policy_number_raw is null then 'NO_CIF_MATCH'
        when cif.policy_number_raw = ltrim(rtrim(b.policy_number)) then 'EXACT_MATCH'
        else 'BARE_FALLBACK'
    end as cif_match_type,
    -- FIX: dedup rank per (policy_term_key, party_key) — a party can match both EXACT and BARE rows
    -- when the CIF stores both a prefixed ('CA 0073063') and bare ('0073063') policy_number_raw.
    -- Prefer: EXACT_MATCH > BARE_FALLBACK > NO_CIF_MATCH, then most recent dates, then arbitrary tiebreak.
    row_number() over (
        partition by b.policy_term_key, b.party_key
        order by
            case
                when cif.policy_number_raw = ltrim(rtrim(b.policy_number)) then 0  -- EXACT_MATCH first
                when cif.policy_number_raw is not null                      then 1  -- BARE_FALLBACK second
                else 2                                                              -- NO_CIF_MATCH last
            end,
            cif.PaperlessPolDate  desc,
            cif.PaperlessBillDate desc
    ) as rn_cif_match
into #cif_join_raw
from #base_data b
left join #CIF_POLICY_Detail cif
    on  cif.party_anchor_id = b.duplicate_party_anchor_id
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

--==========================================================================================================
-- INTERMEDIATE INSPECTION TABLE B: #email_join_raw
-- Purpose: Shows every b row with its resolved email BEFORE grain dedup.
--          Use this to verify:
--            - Which party has email (NIN vs ANI)
--            - Whether pual link exists, and whether auad row exists
--            - load_date of the winning pual link
--          Run: SELECT * FROM #email_join_raw WHERE policy_number = 'CA 0054176'
--==========================================================================================================

drop table if exists #email_join_raw;

select
    b.policy_term_key,
    b.policy_number,
    b.party_key,
    b.policyholder_type_code,
    b.duplicate_party_anchor_id,
    pual.party_user_account_link_id  as pual_link_id,
    pual.load_date                   as pual_load_date,
    auad.user_name                   as email_address,
    auad.valid_from_date             as auad_valid_from,
    auad.valid_to_date               as auad_valid_to,
    -- Link status: shows exactly where the email chain breaks for this party
    case
        when b.duplicate_party_anchor_id          is null then 'NO_PARTY_ANCHOR'
        when pual.party_user_account_link_id       is null then 'NO_PUAL_LINK'
        when auad.party_user_account_link_id       is null then 'PUAL_NO_AUAD'
        when auad.user_name                        is null then 'AUAD_NULL_EMAIL'
        else 'EMAIL_RESOLVED'
    end as email_chain_status
into #email_join_raw
from #base_data b
-- FIX D2: INNER JOIN on auad inside pual — orphaned links excluded from ranking
left join (
    select
        pual.party_anchor_id,
        pual.party_user_account_link_id,
        pual.load_date,
        row_number() over (partition by pual.party_anchor_id order by pual.load_date desc) as rn_pual
    from AWM.dbo.party_user_account_link pual
    inner join AWM.dbo.asp_user_account_detail
        on asp_user_account_detail.party_user_account_link_id = pual.party_user_account_link_id
    where pual.party_anchor_id not in ('7771543', '13322119')
) pual
    on pual.party_anchor_id = b.duplicate_party_anchor_id
   and pual.rn_pual = 1
left join (
    select
        auad2.party_user_account_link_id,
        auad2.user_name,
        auad2.valid_from_date,
        auad2.valid_to_date,
        row_number() over (
            partition by auad2.party_user_account_link_id
            order by auad2.valid_from_date desc, auad2.valid_to_date desc
        ) as rn
    from AWM.dbo.asp_user_account_detail auad2
) auad
    on auad.party_user_account_link_id = pual.party_user_account_link_id
   and auad.rn = 1
;

--==========================================================================================================
-- Step 2: #new_edw_pre_dedup — all parties per policy with CIF + email resolved, ranked but not filtered
-- Purpose: Shows which party wins rn=1 (will become the final row) and why.
--          Use this to trace: if Paperless is wrong, check which party won and what CIF they matched.
--          Run: SELECT * FROM #new_edw_pre_dedup WHERE PolNumber = 'CA 0054176' ORDER BY rn
--==========================================================================================================

drop table if exists #new_edw_pre_dedup;

select
    b.policy_term_key,
    b.policy_number                  as PolNumber,
    b.exceed_policy_id,
    b.household_id                   as HouseholdID,
    b.cif_id                         as CIFID,
    b.party_key,
    b.policyholder_type_code,
    b.duplicate_party_anchor_id,
    -- CIF columns from #cif_join_raw (already validated party match)
    cjr.cif_matched_party_anchor_id,
    cjr.cif_policy_number_raw,
    cjr.cif_match_type,
    cjr.Paperless_Bil_Ind            as PaperlessBillInd,
    cjr.PaperlessBillDate,
    cjr.Paperless_Pol_Ind            as PaperlessPolInd,
    cjr.PaperlessPolDate,
    -- Email columns from #email_join_raw (already validated link chain)
    ejr.email_address                as EmailAddress,
    ejr.email_chain_status,
    ejr.pual_link_id,
    ejr.pual_load_date,
    -- EMAIL rank: picks the best party to supply the email address
    -- Priority 1: party that has an email (ANI email preferred over NIN with no email)
    -- Priority 2: NIN over ANI when both have or both lack email
    -- Priority 3: party_key DESC tiebreak
    row_number() over (
        partition by b.policy_term_key
        order by
            case when ejr.email_address is not null    then 0 else 1 end,
            case when b.policyholder_type_code = 'NIN' then 0 else 1 end,
            b.party_key desc
    ) as rn_email,
    -- CIF rank: picks the NIN party's CIF row for paperless indicators
    -- NIN is the primary policyholder — their paperless preference is authoritative
    -- ANI's CIF is only used as fallback if NIN has no matched CIF row at all
    -- Priority 1: NIN over ANI (policyholder_type_code)
    -- Priority 2: party that has a CIF match at all (cif_matched_party_anchor_id not null)
    --             Using join key presence — NOT the indicator value — to avoid NIN with NULL BIL
    --             being incorrectly ranked below ANI who has a BIL record
    -- Priority 3: party_key DESC tiebreak
    row_number() over (
        partition by b.policy_term_key
        order by
            case when b.policyholder_type_code = 'NIN'              then 0 else 1 end,
            case when cjr.cif_matched_party_anchor_id is not null    then 0 else 1 end,
            b.party_key desc
    ) as rn_cif
into #new_edw_pre_dedup
from #base_data b
left join #cif_join_raw cjr
    on  cjr.policy_term_key = b.policy_term_key
   and  cjr.party_key       = b.party_key
   and  cjr.rn_cif_match    = 1  -- FIX: one CIF row per party — EXACT_MATCH preferred over BARE_FALLBACK
left join #email_join_raw ejr
    on  ejr.policy_term_key = b.policy_term_key
   and  ejr.party_key       = b.party_key
;

--==========================================================================================================
-- Step 3: #new_edw — final output, one row per policy_term_key
-- Email and CIF are resolved independently via two separate ranks from #new_edw_pre_dedup:
--   email_row (rn_email=1): party with best email — ANI email preferred over NIN with no email
--   cif_row   (rn_cif=1) : NIN party's CIF — NIN is authoritative for paperless preference
-- This prevents ANI's Paperless=Y from overriding NIN's Paperless=N just because ANI has email.
-- Tracing: inspect #new_edw_pre_dedup for a specific policy to see both rn_email and rn_cif winners.
--==========================================================================================================

drop table if exists #new_edw;

select
    email_row.policy_term_key,
    email_row.PolNumber,
    email_row.exceed_policy_id,
    email_row.HouseholdID,
    email_row.CIFID,
    -- Email columns: from the email-winner party (rn_email=1)
    email_row.party_key                       as email_party_key,
    email_row.policyholder_type_code          as email_party_type,
    email_row.EmailAddress,
    email_row.email_chain_status,
    email_row.pual_link_id,
    email_row.pual_load_date,
    -- CIF columns: from the NIN-winner party (rn_cif=1) — authoritative paperless preference
    cif_row.party_key                         as cif_party_key,
    cif_row.policyholder_type_code            as cif_party_type,
    cif_row.duplicate_party_anchor_id         as cif_duplicate_party_anchor_id,
    cif_row.cif_matched_party_anchor_id,
    cif_row.cif_policy_number_raw,
    cif_row.cif_match_type,
    cif_row.PaperlessBillInd,
    cif_row.PaperlessBillDate,
    cif_row.PaperlessPolInd,
    cif_row.PaperlessPolDate
into #new_edw
from #new_edw_pre_dedup email_row
-- Self-join to get NIN's CIF row independently of the email row
inner join #new_edw_pre_dedup cif_row
    on  cif_row.policy_term_key = email_row.policy_term_key
   and  cif_row.rn_cif          = 1
where email_row.rn_email = 1
;

--==========================================================================================================
-- Step 4: #pipeline_funnel — row count at every stage of the pipeline
-- Purpose: Quickly identify where policies are being lost or gained between steps.
--          Compare counts down each stage; any unexpected drop points to a join or filter issue.
--==========================================================================================================

drop table if exists #pipeline_funnel;

select stage, row_count
into #pipeline_funnel
from (
    select 1 as sort_order, 'Step 1: #policy_latest'        as stage, count(*)                     as row_count from #policy_latest
    union all
    select 2,               'Step 2: #house_latest (rn=1)'  , count(*)                             from #house_latest       where rn = 1
    union all
    select 3,               'Step 3: #inforce_terms'         , count(*)                             from #inforce_terms
    union all
    select 4,               'Step 4: #view_ph'               , count(*)                             from #view_ph
    union all
    select 5,               'Step 5a: #base_data_link (rn=1)', count(*)                             from #base_data_link     where rn_link = 1
    union all
    select 6,               'Step 5b: #base_data'            , count(*)                             from #base_data
    union all
    select 7,               'Step 6a: #CIF_POLICY_Detail1'   , count(*)                             from #CIF_POLICY_Detail1
    union all
    select 8,               'Step 6b: #CIF_POLICY_Detail2'   , count(*)                             from #CIF_POLICY_Detail2
    union all
    select 9,               'Step 6c: #CIF_POLICY_Detail'    , count(*)                             from #CIF_POLICY_Detail
    union all
    select 10,              '#cif_join_raw (all)'             , count(*)                             from #cif_join_raw
    union all
    select 11,              '#cif_join_raw EXACT_MATCH'       , count(*)                             from #cif_join_raw       where cif_match_type = 'EXACT_MATCH'
    union all
    select 12,              '#cif_join_raw BARE_FALLBACK'     , count(*)                             from #cif_join_raw       where cif_match_type = 'BARE_FALLBACK'
    union all
    select 13,              '#cif_join_raw NO_CIF_MATCH'      , count(*)                             from #cif_join_raw       where cif_match_type = 'NO_CIF_MATCH'
    union all
    select 14,              '#email_join_raw (all)'           , count(*)                             from #email_join_raw
    union all
    select 15,              '#email_join_raw EMAIL_RESOLVED'  , count(*)                             from #email_join_raw     where email_chain_status = 'EMAIL_RESOLVED'
    union all
    select 16,              '#new_edw_pre_dedup (all)'        , count(*)                             from #new_edw_pre_dedup
    union all
    select 17,              '#new_edw_pre_dedup (rn_email=1)' , count(*)                             from #new_edw_pre_dedup  where rn_email = 1
    union all
    select 18,              '#new_edw (final — 1 per policy)' , count(*)                             from #new_edw
    union all
    select 19,              '#old_bim (BIM baseline)'         , count(*)                             from #old_bim
) f
order by sort_order
;

select * from #pipeline_funnel order by sort_order;

----------------------------------------------------------------------------------------------------------
-- Result 1: Summary — match counts between old BIM and new EDW
----------------------------------------------------------------------------------------------------------

select
    'Total OLD BIM policies'        as metric, count(distinct PolNumber) as cnt from #old_bim
union all
select
    'Total NEW EDW policies',                  count(distinct PolNumber) from #new_edw
union all
select
    'Matched on PolNumber',                    count(distinct o.PolNumber)
from #old_bim o
inner join #new_edw n on o.PolNumber = n.PolNumber
union all
select
    'In OLD only (not in NEW)',                count(distinct o.PolNumber)
from #old_bim o
left join #new_edw n on o.PolNumber = n.PolNumber
where n.PolNumber is null
union all
select
    'In NEW only (not in OLD)',                count(distinct n.PolNumber)
from #new_edw n
left join #old_bim o on o.PolNumber = n.PolNumber
where o.PolNumber is null
;

----------------------------------------------------------------------------------------------------------
-- Result 2: Mismatch detail on 4 attributes (BillInd, PolInd, EmailAddress)
-- Only shows rows where at least one attribute differs
----------------------------------------------------------------------------------------------------------

select
    o.PolNumber,
    o.HouseholdID       as old_HouseholdID,
    n.HouseholdID       as new_HouseholdID,
    o.CIFID             as old_CIFID,
    n.CIFID             as new_CIFID,
    n.cif_match_type,                    -- added: shows whether CIF joined via EXACT_MATCH, BARE_FALLBACK, or NO_CIF_MATCH
    o.PaperlessBillInd  as old_BillInd,
    n.PaperlessBillInd  as new_BillInd,
    case when isnull(o.PaperlessBillInd, '') <> isnull(n.PaperlessBillInd, '') then 'MISMATCH' else 'OK' end as bil_ind_flag,
    o.PaperlessBillDate as old_BillDate,
    n.PaperlessBillDate as new_BillDate,
    o.PaperlessPolInd   as old_PolInd,
    n.PaperlessPolInd   as new_PolInd,
    case when isnull(o.PaperlessPolInd, '') <> isnull(n.PaperlessPolInd, '') then 'MISMATCH' else 'OK' end as pol_ind_flag,
    o.PaperlessPolDate  as old_PolDate,
    n.PaperlessPolDate  as new_PolDate,
    o.EmailAddress      as old_Email,
    n.EmailAddress      as new_Email,
    case when isnull(o.EmailAddress, '') <> isnull(n.EmailAddress, '') then 'MISMATCH' else 'OK' end as email_flag
from #old_bim o
inner join #new_edw n
    on o.PolNumber = n.PolNumber
where isnull(o.PaperlessBillInd, '') <> isnull(n.PaperlessBillInd, '')
   or isnull(o.PaperlessPolInd, '')  <> isnull(n.PaperlessPolInd, '')
   or isnull(o.EmailAddress, '')     <> isnull(n.EmailAddress, '')
order by o.PolNumber
;

----------------------------------------------------------------------------------------------------------
-- Result 2b: Policies in OLD BIM only (not matched in NEW EDW)
----------------------------------------------------------------------------------------------------------

select
    o.PolNumber,
    o.HouseholdID,
    o.CIFID,
    o.PaperlessBillInd,
    o.PaperlessBillDate,
    o.PaperlessPolInd,
    o.PaperlessPolDate,
    o.EmailAddress,
    -- cif_match_type is NULL here since no matching new_edw row exists — included for schema consistency
    cast(null as varchar(20)) as cif_match_type
from #old_bim o
left join #new_edw n
    on o.PolNumber = n.PolNumber
where n.PolNumber is null
order by o.PolNumber
;

----------------------------------------------------------------------------------------------------------
-- Result 3: Mismatch summary by attribute
----------------------------------------------------------------------------------------------------------

select
    'BillInd MISMATCH'       as mismatch_type,
    count(distinct o.PolNumber) as distinct_policies
from #old_bim o
inner join #new_edw n on o.PolNumber = n.PolNumber
where isnull(o.PaperlessBillInd, '') <> isnull(n.PaperlessBillInd, '')

union all

select
    'PolInd MISMATCH',
    count(distinct o.PolNumber)
from #old_bim o
inner join #new_edw n on o.PolNumber = n.PolNumber
where isnull(o.PaperlessPolInd, '') <> isnull(n.PaperlessPolInd, '')

union all

select
    'Email MISMATCH',
    count(distinct o.PolNumber)
from #old_bim o
inner join #new_edw n on o.PolNumber = n.PolNumber
where isnull(o.EmailAddress, '') <> isnull(n.EmailAddress, '')

union all

select
    'ALL 3 MATCH (no mismatch)',
    count(distinct o.PolNumber)
from #old_bim o
inner join #new_edw n on o.PolNumber = n.PolNumber
where isnull(o.PaperlessBillInd, '') = isnull(n.PaperlessBillInd, '')
  and isnull(o.PaperlessPolInd, '')  = isnull(n.PaperlessPolInd, '')
  and isnull(o.EmailAddress, '')     = isnull(n.EmailAddress, '')
;

--=========================================================================================================
-- SECTION 1: EMAIL CHAIN FUNNEL — DIAGNOSTIC
-- Chain: base_data → party_key → same_as_link → party_user_account_link → asp_user_account_detail → email
-- One row per policy_term_key. Best breakpoint wins when multiple parties exist per policy.
-- Expected after all fixes: ~250,280 EMAIL_RESOLVED (85.0%)
--
-- FIX D2 applied: pual ranked only among links with valid auad (INNER JOIN inside subquery)
-- FIX D3 applied: email-aware ordering — EMAIL_RESOLVED = rank 1 regardless of party type
-- FIX D4 applied: outer dedup collapses to one row per policy_term_key before group by
--=========================================================================================================

----------------------------------------------------------------------------------------------------------
-- DIAGNOSTIC 1: Deduplicated summary — policy count by breakpoint
----------------------------------------------------------------------------------------------------------

select
    chain_breakpoint,
    count(*) as policy_count
from (
    select
        policy_term_key,
        chain_breakpoint,
        row_number() over (
            partition by policy_term_key
            order by
                case chain_breakpoint
                    when 'EMAIL_RESOLVED'         then 1
                    when 'HAS_DETAIL_NULL_EMAIL'  then 2
                    when 'HAS_LINK_NO_DETAIL'     then 3
                    when 'NO_ACCOUNT_LINK'        then 4
                    when 'SAME_AS_LINK_NO_ANCHOR' then 5
                    when 'NO_SAME_AS_LINK'        then 6
                    when 'NO_PARTY_KEY'           then 7
                end
        ) as rn
    from (
        select
            b.policy_term_key,
            case
                when b.party_key                  is null then 'NO_PARTY_KEY'
                when b.duplicate_party_anchor_id  is null
                 and b.party_anchor_id_duplicate  is null then 'NO_SAME_AS_LINK'
                when b.duplicate_party_anchor_id  is null
                 and b.party_anchor_id_duplicate  is not null then 'SAME_AS_LINK_NO_ANCHOR'
                when pual.party_user_account_link_id is null then 'NO_ACCOUNT_LINK'
                when auad.party_user_account_link_id is null then 'HAS_LINK_NO_DETAIL'
                when auad.user_name               is null then 'HAS_DETAIL_NULL_EMAIL'
                else 'EMAIL_RESOLVED'
            end as chain_breakpoint
        from #base_data b
        -- FIX D2: INNER JOIN on auad inside pual — ranks only links with valid account records
        left join (
            select
                pual.party_anchor_id,
                pual.party_user_account_link_id,
                row_number() over (partition by pual.party_anchor_id order by pual.load_date desc) as rn
            from AWM.dbo.party_user_account_link pual
            inner join AWM.dbo.asp_user_account_detail
                on asp_user_account_detail.party_user_account_link_id = pual.party_user_account_link_id
            where pual.party_anchor_id not in ('7771543', '13322119')
        ) pual
            on pual.party_anchor_id = b.duplicate_party_anchor_id
           and pual.rn = 1
        left join (
            select
                party_user_account_link_id,
                user_name,
                row_number() over (
                    partition by party_user_account_link_id
                    order by valid_from_date desc, valid_to_date desc
                ) as rn
            from AWM.dbo.asp_user_account_detail
        ) auad
            on auad.party_user_account_link_id = pual.party_user_account_link_id
           and auad.rn = 1
    ) classified
) deduped
where rn = 1
group by chain_breakpoint
order by policy_count desc
;

----------------------------------------------------------------------------------------------------------
-- DIAGNOSTIC 2: Raw deduplicated records — one row per policy_term_key
-- Use this to inspect specific policy numbers at each breakpoint
----------------------------------------------------------------------------------------------------------

select
    policy_term_key,
    policy_number,
    exceed_policy_id,
    household_id,
    party_key,
    policyholder_type_code,
    cif_id,
    exceed_client_id,
    party_anchor_id_duplicate,
    duplicate_party_anchor_id,
    pual_link_id,
    pual_load_date,
    email_raw,
    auad_valid_from,
    auad_valid_to,
    chain_breakpoint
from (
    select
        b.policy_term_key,
        b.policy_number,
        b.exceed_policy_id,
        b.household_id,
        b.party_key,
        b.policyholder_type_code,
        b.cif_id,
        b.exceed_client_id,
        b.party_anchor_id_duplicate,
        b.duplicate_party_anchor_id,
        pual.party_user_account_link_id  as pual_link_id,
        pual.load_date                   as pual_load_date,
        auad.user_name                   as email_raw,
        auad.valid_from_date             as auad_valid_from,
        auad.valid_to_date               as auad_valid_to,
        case
            when b.party_key                  is null then 'NO_PARTY_KEY'
            when b.duplicate_party_anchor_id  is null
             and b.party_anchor_id_duplicate  is null then 'NO_SAME_AS_LINK'
            when b.duplicate_party_anchor_id  is null
             and b.party_anchor_id_duplicate  is not null then 'SAME_AS_LINK_NO_ANCHOR'
            when pual.party_user_account_link_id is null then 'NO_ACCOUNT_LINK'
            when auad.party_user_account_link_id is null then 'HAS_LINK_NO_DETAIL'
            when auad.user_name               is null then 'HAS_DETAIL_NULL_EMAIL'
            else 'EMAIL_RESOLVED'
        end as chain_breakpoint,
        -- FIX D3 + D4: email-aware priority, one row per policy_term_key
        row_number() over (
            partition by b.policy_term_key
            order by
                case when auad.user_name is not null        then 0 else 1 end,
                case when b.policyholder_type_code = 'NIN'  then 0 else 1 end,
                b.party_key desc
        ) as rn
    from #base_data b
    -- FIX D2: INNER JOIN on auad inside pual — orphaned links excluded from ranking
    left join (
        select
            pual.party_anchor_id,
            pual.party_user_account_link_id,
            pual.load_date,
            row_number() over (partition by pual.party_anchor_id order by pual.load_date desc) as rn
        from AWM.dbo.party_user_account_link pual
        inner join AWM.dbo.asp_user_account_detail
            on asp_user_account_detail.party_user_account_link_id = pual.party_user_account_link_id
        where pual.party_anchor_id not in ('7771543', '13322119')
    ) pual
        on pual.party_anchor_id = b.duplicate_party_anchor_id
       and pual.rn = 1
    left join (
        select
            party_user_account_link_id,
            user_name,
            valid_from_date,
            valid_to_date,
            row_number() over (
                partition by party_user_account_link_id
                order by valid_from_date desc, valid_to_date desc
            ) as rn
        from AWM.dbo.asp_user_account_detail
    ) auad
        on auad.party_user_account_link_id = pual.party_user_account_link_id
       and auad.rn = 1
) ranked
where rn = 1
order by chain_breakpoint, policy_number
;

----------------------------------------------------------------------------------------------------------
-- DIAGNOSTIC 3: ANI recovery validation — shows which party type is supplying the email
-- Expected: ANI ~47,658 (emails recovered from additional named insured when NIN has none)
----------------------------------------------------------------------------------------------------------

select
    b.policyholder_type_code,
    count(distinct b.policy_term_key) as policy_count
from #base_data b
inner join (
    select
        policy_term_key,
        party_key,
        chain_breakpoint,
        row_number() over (
            partition by policy_term_key
            order by
                case chain_breakpoint
                    when 'EMAIL_RESOLVED'         then 1
                    when 'HAS_DETAIL_NULL_EMAIL'  then 2
                    when 'HAS_LINK_NO_DETAIL'     then 3
                    when 'NO_ACCOUNT_LINK'        then 4
                    when 'SAME_AS_LINK_NO_ANCHOR' then 5
                    when 'NO_SAME_AS_LINK'        then 6
                    when 'NO_PARTY_KEY'           then 7
                end
        ) as rn
    from (
        select
            b2.policy_term_key,
            b2.party_key,
            case
                when b2.party_key                  is null then 'NO_PARTY_KEY'
                when b2.duplicate_party_anchor_id  is null
                 and b2.party_anchor_id_duplicate  is null then 'NO_SAME_AS_LINK'
                when b2.duplicate_party_anchor_id  is null
                 and b2.party_anchor_id_duplicate  is not null then 'SAME_AS_LINK_NO_ANCHOR'
                when pual.party_user_account_link_id is null then 'NO_ACCOUNT_LINK'
                when auad.party_user_account_link_id is null then 'HAS_LINK_NO_DETAIL'
                when auad.user_name               is null then 'HAS_DETAIL_NULL_EMAIL'
                else 'EMAIL_RESOLVED'
            end as chain_breakpoint
        from #base_data b2
        left join (
            select
                pual.party_anchor_id,
                pual.party_user_account_link_id,
                row_number() over (partition by pual.party_anchor_id order by pual.load_date desc) as rn
            from AWM.dbo.party_user_account_link pual
            inner join AWM.dbo.asp_user_account_detail
                on asp_user_account_detail.party_user_account_link_id = pual.party_user_account_link_id
            where pual.party_anchor_id not in ('7771543', '13322119')
        ) pual
            on pual.party_anchor_id = b2.duplicate_party_anchor_id
           and pual.rn = 1
        left join (
            select
                party_user_account_link_id,
                user_name,
                row_number() over (
                    partition by party_user_account_link_id
                    order by valid_from_date desc, valid_to_date desc
                ) as rn
            from AWM.dbo.asp_user_account_detail
        ) auad
            on auad.party_user_account_link_id = pual.party_user_account_link_id
           and auad.rn = 1
    ) classified
) winners
    on  winners.policy_term_key = b.policy_term_key
   and  winners.party_key       = b.party_key
   and  winners.rn              = 1
where winners.chain_breakpoint = 'EMAIL_RESOLVED'
group by b.policyholder_type_code
order by policy_count desc
;
