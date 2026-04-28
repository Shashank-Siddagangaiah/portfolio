--==========================================================================================================
-- email_val.sql
-- Purpose : Validate missing email coverage in the new EDW/AWM paperless pipeline
--
-- PREREQUISITE: Run cif_join_validation.sql first in the same session.
--   Reuses temp tables: #base_data, #old_bim, #CIF_POLICY_Detail
--
-- Sections:
--   1. Email chain funnel       — how many policies survive each step of the chain
--   2. Missing rate + break point by symbol
--   3. Backfill candidate list  — policies recoverable from BIM email
--   4. Gap summary              — all no-email categories, mutually exclusive
--   5. CIF fix validation       — quantify impact of Issues 2 & 3 (valid_to_date + update_date)
--   6. CIF vs BIM comparison    — direct indicator comparison, mismatch direction, root cause
--==========================================================================================================

--==========================================================================================================
-- SETUP: Email chain temp tables
--==========================================================================================================

-- #email_link: one row per party_anchor_id (latest load_date)
-- Excludes known bad anchors 7771543 and 13322119 (inflate link counts)
drop table if exists #email_link;

select
    pual.party_anchor_id,
    pual.party_user_account_link_id,
    pual.load_date,
    row_number() over (
        partition by pual.party_anchor_id
        order by pual.load_date desc
    ) as rn_link
into #email_link
from AWM.dbo.party_user_account_link pual
where pual.party_anchor_id not in ('7771543', '13322119')
;

-- #email_detail: one row per party_user_account_link_id (latest valid_from_date)
-- Partitioned by link_id ONLY — adding user_name caused fan-out (rn=1 for every username per link)
drop table if exists #email_detail;

select
    auad.party_user_account_link_id,
    auad.user_name,
    auad.valid_from_date,
    auad.valid_to_date,
    auad.is_anonymous_indicator,
    auad.is_up_and_running_indicator,
    row_number() over (
        partition by auad.party_user_account_link_id
        order by auad.valid_from_date desc, auad.valid_to_date desc
    ) as rn_detail
into #email_detail
from AWM.dbo.asp_user_account_detail auad
;

-- #email_chain_by_policy: best email outcome per policy_term_key across all parties
-- Logic: if ANY party on the policy resolved email, the policy has email.
-- Break-point = furthest step reached by the best party for that policy.
drop table if exists #email_chain_by_policy;

select
    b.policy_term_key,
    b.policy_symbol,
    max(case when b.party_key                is not null then 1 else 0 end) as has_party_key,
    max(case when b.duplicate_party_anchor_id is not null then 1 else 0 end) as has_same_as_link,
    max(case when el.party_anchor_id          is not null then 1 else 0 end) as has_account_link,
    max(case when ed.user_name                is not null then 1 else 0 end) as has_email
into #email_chain_by_policy
from #base_data b
left join #email_link el
    on el.party_anchor_id = b.duplicate_party_anchor_id
   and el.rn_link = 1
left join #email_detail ed
    on ed.party_user_account_link_id = el.party_user_account_link_id
   and ed.rn_detail = 1
group by b.policy_term_key, b.policy_symbol
;

-- #bim_deduped_ind: one row per policy_number from #old_bim
-- FIX: #old_bim has multiple contact rows per policy (one per household member).
-- MAX() picks 'Y' so any paperless opt-in on any contact survives the dedup.
drop table if exists #bim_deduped_ind;

select
    PolNumber                   as policy_number,
    max(PaperlessBillInd)       as PaperlessBillInd,
    max(PaperlessBillDate)      as PaperlessBillDate,
    max(PaperlessPolInd)        as PaperlessPolInd,
    max(PaperlessPolDate)       as PaperlessPolDate
into #bim_deduped_ind
from #old_bim
group by PolNumber
;

--==========================================================================================================
-- SECTION 1: EMAIL CHAIN FUNNEL
-- Counts how many distinct policies survive each step of the email resolution chain.
-- Chain: base_data → party_key → same_as_link → account_link → user_name (email)
-- Expected after all fixes: ~252,128 resolved (85.1%), ~44,271 no email (14.9%)
--==========================================================================================================

select 'Total policies in base_data'                           as step, count(distinct b.policy_term_key) as policy_count from #base_data b
union all
select 'Has NULL party_key (no policyholder match)',            count(distinct b.policy_term_key) from #base_data b where b.party_key is null
union all
select 'Has NULL duplicate_party_anchor_id (no same-as-link)', count(distinct b.policy_term_key) from #base_data b where b.party_key is not null and b.duplicate_party_anchor_id is null
union all
select 'Has duplicate_party_anchor_id (chain can proceed)',    count(distinct b.policy_term_key) from #base_data b where b.duplicate_party_anchor_id is not null
union all
select 'Matched party_user_account_link',
    count(distinct b.policy_term_key)
from #base_data b
inner join #email_link el on el.party_anchor_id = b.duplicate_party_anchor_id and el.rn_link = 1
union all
select 'No party_user_account_link (never registered online)',
    count(distinct b.policy_term_key)
from #base_data b
left join #email_link el on el.party_anchor_id = b.duplicate_party_anchor_id and el.rn_link = 1
where b.duplicate_party_anchor_id is not null
  and el.party_anchor_id is null
union all
select 'Has asp_user_account_detail record',
    count(distinct b.policy_term_key)
from #base_data b
inner join #email_link   el on el.party_anchor_id            = b.duplicate_party_anchor_id and el.rn_link   = 1
inner join #email_detail ed on ed.party_user_account_link_id = el.party_user_account_link_id and ed.rn_detail = 1
union all
select 'Email resolved (non-NULL user_name)',
    count(distinct b.policy_term_key)
from #base_data b
inner join #email_link   el on el.party_anchor_id            = b.duplicate_party_anchor_id and el.rn_link   = 1
inner join #email_detail ed on ed.party_user_account_link_id = el.party_user_account_link_id and ed.rn_detail = 1
where ed.user_name is not null
;

--==========================================================================================================
-- SECTION 2: MISSING RATE + BREAK POINT BY SYMBOL
-- 2a: % with email per product line
-- 2b: where the chain breaks — each policy falls in exactly one bucket
--==========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 2a: Email coverage rate by policy symbol
----------------------------------------------------------------------------------------------------------

select
    policy_symbol,
    count(*)                                                as total_policies,
    sum(has_email)                                          as has_email,
    sum(1 - has_email)                                      as missing_email,
    cast(100.0 * sum(has_email) / nullif(count(*), 0)
         as decimal(5,1))                                   as pct_with_email
from #email_chain_by_policy
group by policy_symbol
order by missing_email desc
;

----------------------------------------------------------------------------------------------------------
-- 2b: Break point breakdown by policy symbol
-- Buckets are mutually exclusive — each policy is classified at the earliest break.
--   no_party_key     : policyholder join returned no match
--   no_same_as_link  : party found but no AWM party_id_same_as_link
--   no_account_link  : party mapped but never registered online
--   no_user_name     : account exists but email not populated
--   email_resolved   : at least one party resolved an email
----------------------------------------------------------------------------------------------------------

select
    policy_symbol,
    count(*)                                                                                    as total,
    sum(case when has_party_key    = 0                                          then 1 else 0 end) as no_party_key,
    sum(case when has_party_key    = 1 and has_same_as_link = 0                 then 1 else 0 end) as no_same_as_link,
    sum(case when has_same_as_link = 1 and has_account_link = 0                 then 1 else 0 end) as no_account_link,
    sum(case when has_account_link = 1 and has_email        = 0                 then 1 else 0 end) as no_user_name,
    sum(has_email)                                                                                 as email_resolved
from #email_chain_by_policy
group by policy_symbol
order by total desc
;

--==========================================================================================================
-- SECTION 3: BACKFILL CANDIDATE LIST
-- Policies with no AWM email but BIM/Eloqua holds a valid email address.
-- These are the highest-value recovery candidates — BIM email can be used as fallback.
--
-- 3a: Policy-level list (one row per policy)
-- 3b: Summary by symbol
--==========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 3a: Full backfill candidate list
----------------------------------------------------------------------------------------------------------

select
    b.policy_number,
    b.policy_symbol,
    b.household_id                          as new_HouseholdID,
    ob.HouseholdID                          as bim_HouseholdID,
    b.cif_id                                as new_CIFID,
    ob.CIFID                                as bim_CIFID,
    ob.EmailAddress                         as bim_email,
    el.party_user_account_link_id,
    b.duplicate_party_anchor_id             as party_anchor_id,
    b.policy_term_key,
    b.effective_from_date,
    b.effective_to_date,
    ed.is_anonymous_indicator,
    ed.is_up_and_running_indicator
from #base_data b
inner join #email_link el
    on el.party_anchor_id = b.duplicate_party_anchor_id
   and el.rn_link = 1
left join #email_detail ed
    on ed.party_user_account_link_id = el.party_user_account_link_id
   and ed.rn_detail = 1
inner join #old_bim ob
    on ob.PolNumber = b.policy_number
where ed.user_name is null
  and ob.EmailAddress is not null
  and ob.EmailAddress <> ''
order by b.policy_symbol, b.policy_number
;

----------------------------------------------------------------------------------------------------------
-- 3b: Backfill candidate summary by symbol
----------------------------------------------------------------------------------------------------------

select
    b.policy_symbol,
    count(distinct b.policy_number)         as recoverable_policies,
    count(distinct ob.EmailAddress)         as distinct_email_addresses
from #base_data b
inner join #email_link el
    on el.party_anchor_id = b.duplicate_party_anchor_id
   and el.rn_link = 1
left join #email_detail ed
    on ed.party_user_account_link_id = el.party_user_account_link_id
   and ed.rn_detail = 1
inner join #old_bim ob
    on ob.PolNumber = b.policy_number
where ed.user_name is null
  and ob.EmailAddress is not null
  and ob.EmailAddress <> ''
group by b.policy_symbol
order by recoverable_policies desc
;

--==========================================================================================================
-- SECTION 4: GAP SUMMARY — all no-email categories, mutually exclusive
-- Each policy without an email falls into exactly one category.
-- Categories and their resolution action:
--   1. No same-as-link          → Data fix: investigate party_id_same_as_link gaps
--   2. Never registered online  → Outreach: drive online registration
--   3. Incomplete account       → Outreach: prompt account activation
--   4. BIM email available      → Data fix: backfill from BIM (see Section 3)
--==========================================================================================================

select
    gap_category,
    policies,
    resolution
from (

    select
        'No same-as-link (AWM party not mapped)'             as gap_category,
        count(distinct b.policy_term_key)                    as policies,
        'Data fix: investigate party_id_same_as_link gaps'   as resolution,
        1                                                    as sort_order
    from #base_data b
    where b.party_key is not null
      and b.duplicate_party_anchor_id is null

    union all

    select
        'Never registered online (no account on any party)',
        count(distinct b.policy_term_key),
        'Outreach: paper/phone campaign to drive online registration',
        2
    from #base_data b
    left join #email_link el
        on el.party_anchor_id = b.duplicate_party_anchor_id
       and el.rn_link = 1
    where b.duplicate_party_anchor_id is not null
      and el.party_anchor_id is null
      and not exists (
        select 1
        from #base_data b2
        inner join #email_link   el2 on el2.party_anchor_id            = b2.duplicate_party_anchor_id and el2.rn_link   = 1
        inner join #email_detail ed2 on ed2.party_user_account_link_id = el2.party_user_account_link_id and ed2.rn_detail = 1
        where b2.policy_term_key = b.policy_term_key
          and ed2.user_name is not null
      )

    union all

    select
        'Incomplete account setup — no email in either system',
        count(distinct b.policy_term_key),
        'Outreach: prompt customer to complete account activation',
        3
    from #base_data b
    inner join #email_link el
        on el.party_anchor_id = b.duplicate_party_anchor_id
       and el.rn_link = 1
    left join #email_detail ed
        on ed.party_user_account_link_id = el.party_user_account_link_id
       and ed.rn_detail = 1
    left join #old_bim ob
        on ob.PolNumber = b.policy_number
    where ed.user_name is null
      and (ob.EmailAddress is null or ob.EmailAddress = '')

    union all

    select
        'Incomplete account setup — BIM email available (recoverable)',
        count(distinct b.policy_term_key),
        'Data fix: backfill email from BIM into AWM (see Section 3)',
        4
    from #base_data b
    inner join #email_link el
        on el.party_anchor_id = b.duplicate_party_anchor_id
       and el.rn_link = 1
    left join #email_detail ed
        on ed.party_user_account_link_id = el.party_user_account_link_id
       and ed.rn_detail = 1
    inner join #old_bim ob
        on ob.PolNumber = b.policy_number
    where ed.user_name is null
      and ob.EmailAddress is not null
      and ob.EmailAddress <> ''

) gaps
order by sort_order
;

--==========================================================================================================
-- SECTION 5: CIF FIX VALIDATION
-- Quantify the actual data impact of Issues 2 and 3 from the fix log.
--
-- Issue 2 (valid_to_date): were superseded CIF records carrying a DIFFERENT indicator?
--   If indicator_mismatch > 0 → fix changed real paperless outcomes (stale data was surfacing)
--   If indicator_mismatch = 0 → fix was defensive; superseded rows happened to agree with current
--
-- Issue 3 (update_date sort): are there records tied on effective_from_date with conflicting indicators?
--   If groups_with_tied_date > 0 → effective_from_date sort was non-deterministic for those records
--   If groups_with_tied_date = 0 → fix was defensive; tied dates always agreed on the indicator
--
-- Runs directly against AWM — no temp table prereqs required.
--==========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 5a: Issue 2 — Superseded records that disagree with the current record (overall)
----------------------------------------------------------------------------------------------------------

select
    count(*)                                                                        as total_superseded_rows,
    sum(case when s.paper_notify_indicator
             != c.paper_notify_indicator then 1 else 0 end)                        as indicator_mismatch,
    sum(case when s.paper_notify_indicator = 0
              and c.paper_notify_indicator != 0 then 1 else 0 end)                 as superseded_says_paperless_current_says_no,
    sum(case when s.paper_notify_indicator != 0
              and c.paper_notify_indicator  = 0 then 1 else 0 end)                 as superseded_says_not_current_says_paperless
from AWM.dbo.cif_policy_party_detail s                          -- superseded rows
join AWM.dbo.cif_policy_party_detail c                          -- current rows
    on  c.policy_party_link_id      = s.policy_party_link_id
    and c.output_document_type_code = s.output_document_type_code
    and c.effective_to_date         = '9999-12-31'
    and c.valid_to_date             = '9999-12-31'
where s.effective_to_date           = '9999-12-31'
  and s.valid_to_date              != '9999-12-31'              -- superseded rows only
  and s.output_document_type_code  in ('BIL', 'POL')
;

----------------------------------------------------------------------------------------------------------
-- 5b: Issue 2 — Breakdown by document type (BIL vs POL)
----------------------------------------------------------------------------------------------------------

select
    s.output_document_type_code,
    count(*)                                                                        as superseded_rows,
    sum(case when s.paper_notify_indicator
             != c.paper_notify_indicator then 1 else 0 end)                        as indicator_mismatch
from AWM.dbo.cif_policy_party_detail s
join AWM.dbo.cif_policy_party_detail c
    on  c.policy_party_link_id      = s.policy_party_link_id
    and c.output_document_type_code = s.output_document_type_code
    and c.effective_to_date         = '9999-12-31'
    and c.valid_to_date             = '9999-12-31'
where s.effective_to_date           = '9999-12-31'
  and s.valid_to_date              != '9999-12-31'
  and s.output_document_type_code  in ('BIL', 'POL')
group by s.output_document_type_code
;

----------------------------------------------------------------------------------------------------------
-- 5c: Issue 3 — Records tied on effective_from_date with different paper_notify_indicator
-- These are cases where effective_from_date sort was non-deterministic — update_date fix matters here.
----------------------------------------------------------------------------------------------------------

select
    count(*)                                                                        as groups_with_tied_date_and_different_indicator
from (
    select
        policy_party_link_id,
        output_document_type_code,
        effective_from_date,
        min(paper_notify_indicator)                                                 as min_indicator,
        max(paper_notify_indicator)                                                 as max_indicator
    from AWM.dbo.cif_policy_party_detail
    where output_document_type_code   in ('BIL', 'POL')
      and effective_to_date            = '9999-12-31'
      and valid_to_date                = '9999-12-31'
    group by
        policy_party_link_id,
        output_document_type_code,
        effective_from_date
    having count(*) > 1
       and min(paper_notify_indicator) != max(paper_notify_indicator)               -- tied date, different indicator
) ties
;

----------------------------------------------------------------------------------------------------------
-- 5d: Issue 3 — Detail rows for tied groups (top 50 sample)
-- Shows which record wins under each sort strategy side by side.
----------------------------------------------------------------------------------------------------------

select top 50
    d.policy_party_link_id,
    d.output_document_type_code,
    d.effective_from_date,
    d.update_date,
    d.paper_notify_indicator,
    row_number() over (
        partition by d.policy_party_link_id, d.output_document_type_code, d.effective_from_date
        order by d.effective_from_date desc, d.update_date desc     -- AFTER fix: update_date wins ties
    )                                                               as rn_after_fix,
    row_number() over (
        partition by d.policy_party_link_id, d.output_document_type_code, d.effective_from_date
        order by d.effective_from_date desc                         -- BEFORE fix: non-deterministic
    )                                                               as rn_before_fix
from AWM.dbo.cif_policy_party_detail d
where output_document_type_code  in ('BIL', 'POL')
  and effective_to_date           = '9999-12-31'
  and valid_to_date               = '9999-12-31'
  and exists (
    select 1
    from AWM.dbo.cif_policy_party_detail d2
    where d2.policy_party_link_id      = d.policy_party_link_id
      and d2.output_document_type_code = d.output_document_type_code
      and d2.effective_from_date       = d.effective_from_date
      and d2.effective_to_date         = '9999-12-31'
      and d2.valid_to_date             = '9999-12-31'
      and d2.paper_notify_indicator   != d.paper_notify_indicator
  )
order by d.policy_party_link_id, d.output_document_type_code, d.effective_from_date desc, d.update_date desc
;

--==========================================================================================================
-- SECTION 6: CIF (AWM) vs BIM/ELOQUA — DIRECT PAPERLESS INDICATOR COMPARISON
--
-- Sources:
--   CIF  : AWM.dbo.cif_policy_party_detail — paper_notify_indicator (0 = paperless)
--   BIM  : BIM_Reporting_Weekly.Eloqua.POLICY — PPRLESS_BIL_IND / PPRLESS_POL_IND ('Y' = paperless)
--
-- Key structural difference:
--   BIM stores BIL and POL as two columns on ONE row per policy → BIL count always = POL count
--   CIF stores BIL and POL as SEPARATE rows per party link     → counts can differ independently
--
-- Mismatch direction values:
--   BIM_only         : BIM says paperless, CIF does not
--   CIF_only         : CIF says paperless, BIM does not
--   BIM_N_CIF_missing: BIM explicitly 'N', CIF has no record
--   CIF_N_BIM_missing: CIF explicitly 'N', BIM value is NULL/blank
--   agree            : both agree (both 'Y', both 'N', or both NULL)
--
-- BIM blank/space (' ') is normalized to NULL in all comparisons via NULLIF(LTRIM(...), '').
--==========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 6a: Overall agreement summary — how often do CIF and BIM agree on BIL and POL?
--     Matched on policy_number. Covers policies present in BOTH sources.
----------------------------------------------------------------------------------------------------------

select
    sum(case when bim.PaperlessBillInd = 'Y' and cif.Paperless_Bil_Ind = 'Y' then 1 else 0 end)                              as BIL_both_paperless,
    sum(case when bim.PaperlessBillInd = 'Y' and isnull(cif.Paperless_Bil_Ind,'N') <> 'Y' then 1 else 0 end)                 as BIL_bim_yes_cif_no,
    sum(case when isnull(bim.PaperlessBillInd,'N') <> 'Y' and cif.Paperless_Bil_Ind = 'Y' then 1 else 0 end)                 as BIL_cif_yes_bim_no,
    sum(case when isnull(bim.PaperlessBillInd,'N') <> 'Y' and isnull(cif.Paperless_Bil_Ind,'N') <> 'Y' then 1 else 0 end)   as BIL_both_not_paperless,

    sum(case when bim.PaperlessPolInd  = 'Y' and cif.Paperless_Pol_Ind = 'Y' then 1 else 0 end)                              as POL_both_paperless,
    sum(case when bim.PaperlessPolInd  = 'Y' and isnull(cif.Paperless_Pol_Ind,'N') <> 'Y' then 1 else 0 end)                 as POL_bim_yes_cif_no,
    sum(case when isnull(bim.PaperlessPolInd,'N') <> 'Y' and cif.Paperless_Pol_Ind = 'Y' then 1 else 0 end)                  as POL_cif_yes_bim_no,
    sum(case when isnull(bim.PaperlessPolInd,'N') <> 'Y' and isnull(cif.Paperless_Pol_Ind,'N') <> 'Y' then 1 else 0 end)    as POL_both_not_paperless,

    count(*)                                                                                                                   as total_matched_policies
from #old_bim bim
inner join #CIF_POLICY_Detail cif
    on try_cast(
           case when bim.PolNumber like '% %'
               then substring(bim.PolNumber, charindex(' ', bim.PolNumber) + 1, len(bim.PolNumber))
               else bim.PolNumber
           end as bigint
       ) = cif.policy_number_int
;

----------------------------------------------------------------------------------------------------------
-- 6b: Agreement by policy symbol (uses #bim_deduped_ind — one row per policy)
----------------------------------------------------------------------------------------------------------

select
    b.policy_symbol,
    count(distinct b.policy_term_key)                                                               as total_policies,

    sum(case when bim.PaperlessBillInd = 'Y' and cif.Paperless_Bil_Ind = 'Y' then 1 else 0 end)   as BIL_agree_Y,
    sum(case when bim.PaperlessBillInd = 'Y' and isnull(cif.Paperless_Bil_Ind,'N') <> 'Y' then 1 else 0 end) as BIL_bim_yes_cif_no,
    sum(case when isnull(bim.PaperlessBillInd,'N') <> 'Y' and cif.Paperless_Bil_Ind = 'Y' then 1 else 0 end) as BIL_cif_yes_bim_no,

    sum(case when bim.PaperlessPolInd  = 'Y' and cif.Paperless_Pol_Ind = 'Y' then 1 else 0 end)   as POL_agree_Y,
    sum(case when bim.PaperlessPolInd  = 'Y' and isnull(cif.Paperless_Pol_Ind,'N') <> 'Y' then 1 else 0 end) as POL_bim_yes_cif_no,
    sum(case when isnull(bim.PaperlessPolInd,'N') <> 'Y' and cif.Paperless_Pol_Ind = 'Y' then 1 else 0 end)  as POL_cif_yes_bim_no
from #base_data b
inner join #bim_deduped_ind bim
    on bim.policy_number = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
group by b.policy_symbol
order by b.policy_symbol
;

----------------------------------------------------------------------------------------------------------
-- 6c: Mismatch detail — policies where BIM and CIF disagree on BIL or POL
--     BIM blank/space normalized to NULL for accurate direction classification.
----------------------------------------------------------------------------------------------------------

select
    b.policy_number,
    b.policy_symbol,
    b.policy_inforce_indicator,

    bim.PaperlessBillInd                                                            as bim_BIL_ind,
    bim.PaperlessBillDate                                                           as bim_BIL_date,
    bim.PaperlessPolInd                                                             as bim_POL_ind,
    bim.PaperlessPolDate                                                            as bim_POL_date,

    cif.Paperless_Bil_Ind                                                           as cif_BIL_ind,
    cif.PaperlessBillDate                                                           as cif_BIL_date,
    cif.Paperless_Pol_Ind                                                           as cif_POL_ind,
    cif.PaperlessPolDate                                                            as cif_POL_date,

    case
        when nullif(ltrim(bim.PaperlessBillInd),'') = 'Y' and isnull(cif.Paperless_Bil_Ind,'N') <> 'Y'    then 'BIM_only'
        when isnull(nullif(ltrim(bim.PaperlessBillInd),''),'N') <> 'Y' and cif.Paperless_Bil_Ind = 'Y'    then 'CIF_only'
        when nullif(ltrim(bim.PaperlessBillInd),'') = 'N' and cif.Paperless_Bil_Ind is null               then 'BIM_N_CIF_missing'
        when nullif(ltrim(bim.PaperlessBillInd),'') is null and cif.Paperless_Bil_Ind = 'N'               then 'CIF_N_BIM_missing'
        else 'agree'
    end                                                                             as BIL_mismatch_direction,

    case
        when nullif(ltrim(bim.PaperlessPolInd),'')  = 'Y' and isnull(cif.Paperless_Pol_Ind,'N') <> 'Y'    then 'BIM_only'
        when isnull(nullif(ltrim(bim.PaperlessPolInd),''),'N') <> 'Y' and cif.Paperless_Pol_Ind = 'Y'     then 'CIF_only'
        when nullif(ltrim(bim.PaperlessPolInd),'')  = 'N' and cif.Paperless_Pol_Ind is null               then 'BIM_N_CIF_missing'
        when nullif(ltrim(bim.PaperlessPolInd),'')  is null and cif.Paperless_Pol_Ind = 'N'               then 'CIF_N_BIM_missing'
        else 'agree'
    end                                                                             as POL_mismatch_direction,

    case when cif.Paperless_Bil_Ind is null then 'Y' else 'N' end                  as cif_BIL_record_missing,
    case when cif.Paperless_Pol_Ind is null then 'Y' else 'N' end                  as cif_POL_record_missing

from #base_data b
inner join #old_bim bim
    on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where
    isnull(bim.PaperlessBillInd,'') <> isnull(cif.Paperless_Bil_Ind,'')
    or isnull(bim.PaperlessPolInd,'')  <> isnull(cif.Paperless_Pol_Ind,'')
order by b.policy_symbol, BIL_mismatch_direction, POL_mismatch_direction
;

----------------------------------------------------------------------------------------------------------
-- 6d: Root cause breakdown — for BIM_only mismatches, is the CIF record missing or does it disagree?
--     Two causes: (a) CIF has no record, (b) CIF has a record but says 'N'
----------------------------------------------------------------------------------------------------------

select
    'BIL — CIF record missing (NULL)'                                               as root_cause,
    count(distinct b.policy_term_key)                                               as policy_count
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessBillInd = 'Y' and cif.Paperless_Bil_Ind is null

union all

select 'BIL — CIF record exists but disagrees', count(distinct b.policy_term_key)
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessBillInd = 'Y' and cif.Paperless_Bil_Ind = 'N'

union all

select 'POL — CIF record missing (NULL)', count(distinct b.policy_term_key)
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessPolInd = 'Y' and cif.Paperless_Pol_Ind is null

union all

select 'POL — CIF record exists but disagrees', count(distinct b.policy_term_key)
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessPolInd = 'Y' and cif.Paperless_Pol_Ind = 'N'
;

----------------------------------------------------------------------------------------------------------
-- 6e: Timing lag — how far ahead is BIM vs CIF for genuine disagreements?
--     avg_days >> 30 → not a batch lag; this is a long-term synchronization gap
--     min_days negative → CIF is ahead of BIM for a subset (bidirectional disagreement)
----------------------------------------------------------------------------------------------------------

select
    'BIL timing lag (BIM ahead of CIF)'                                             as indicator,
    count(distinct b.policy_term_key)                                               as mismatch_policies,
    avg(datediff(day, cif.PaperlessBillDate, bim.PaperlessBillDate))               as avg_days_bim_ahead,
    max(datediff(day, cif.PaperlessBillDate, bim.PaperlessBillDate))               as max_days_bim_ahead,
    min(datediff(day, cif.PaperlessBillDate, bim.PaperlessBillDate))               as min_days,
    sum(case when datediff(day, cif.PaperlessBillDate, bim.PaperlessBillDate) <= 7
             then 1 else 0 end)                                                     as within_7_days,
    sum(case when datediff(day, cif.PaperlessBillDate, bim.PaperlessBillDate) between 8 and 30
             then 1 else 0 end)                                                     as days_8_to_30,
    sum(case when datediff(day, cif.PaperlessBillDate, bim.PaperlessBillDate) > 30
             then 1 else 0 end)                                                     as over_30_days
from #base_data b
inner join #bim_deduped_ind bim on bim.policy_number = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessBillInd = 'Y'
  and cif.Paperless_Bil_Ind = 'N'
  and bim.PaperlessBillDate is not null
  and cif.PaperlessBillDate is not null

union all

select
    'POL timing lag (BIM ahead of CIF)',
    count(distinct b.policy_term_key),
    avg(datediff(day, cif.PaperlessPolDate, bim.PaperlessPolDate)),
    max(datediff(day, cif.PaperlessPolDate, bim.PaperlessPolDate)),
    min(datediff(day, cif.PaperlessPolDate, bim.PaperlessPolDate)),
    sum(case when datediff(day, cif.PaperlessPolDate, bim.PaperlessPolDate) <= 7  then 1 else 0 end),
    sum(case when datediff(day, cif.PaperlessPolDate, bim.PaperlessPolDate) between 8 and 30 then 1 else 0 end),
    sum(case when datediff(day, cif.PaperlessPolDate, bim.PaperlessPolDate) > 30  then 1 else 0 end)
from #base_data b
inner join #bim_deduped_ind bim on bim.policy_number = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessPolInd = 'Y'
  and cif.Paperless_Pol_Ind = 'N'
  and bim.PaperlessPolDate is not null
  and cif.PaperlessPolDate is not null
;

----------------------------------------------------------------------------------------------------------
-- 6f: Missing CIF records — broken join path vs truly absent in AWM
--     Checks whether a CIF record exists on a DIFFERENT party link for the same policy number.
--     has_cif_on_other_link > 0  → fix the join path, not the data
--     truly_absent_in_awm > 0   → record genuinely missing; escalate to data team
----------------------------------------------------------------------------------------------------------

select
    b.policy_symbol,
    count(distinct b.policy_term_key)                                               as policies_missing_cif_bil,
    sum(case when alt.policy_number is not null then 1 else 0 end)                 as has_cif_on_other_link,
    sum(case when alt.policy_number is null     then 1 else 0 end)                 as truly_absent_in_awm
from #base_data b
inner join #bim_deduped_ind bim on bim.policy_number = b.policy_number
left join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
left join (
    -- All policy numbers that have a BIL CIF record on ANY party link (not just the current join path)
    select distinct
        try_cast(
            case when pa.policy_number like '% %'
                then substring(pa.policy_number, charindex(' ', pa.policy_number) + 1, len(pa.policy_number))
                else pa.policy_number
            end as bigint
        )                                                                           as policy_number_int,
        pa.policy_number
    from AWM.dbo.cif_policy_party_detail cppd
    inner join AWM.dbo.policy_party_link ppl on ppl.policy_party_link_id = cppd.policy_party_link_id
    inner join AWM.dbo.policy_anchor pa      on pa.policy_anchor_id      = ppl.policy_anchor_id
    where cppd.output_document_type_code = 'BIL'
      and cppd.effective_to_date          = '9999-12-31'
      and cppd.valid_to_date              = '9999-12-31'
      and cppd.paper_notify_indicator     = 0
) alt
    on alt.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessBillInd = 'Y'
  and cif.Paperless_Bil_Ind is null
group by b.policy_symbol
order by b.policy_symbol
;

----------------------------------------------------------------------------------------------------------
-- 6g: CIF-only opt-ins — top 30 dates by volume (spike detection)
--     Spread across many dates → ongoing channel gap (agent portal not syncing to Eloqua)
--     Spike on a specific date → one-time integration failure; backfill may be possible
----------------------------------------------------------------------------------------------------------

select top 30
    cast(cif.PaperlessBillDate as date)                                             as cif_opt_in_date,
    count(distinct b.policy_term_key)                                               as cif_only_policies,
    count(distinct case when b.policy_symbol = 'HO'  then b.policy_term_key end)   as HO,
    count(distinct case when b.policy_symbol = 'CA'  then b.policy_term_key end)   as CA,
    count(distinct case when b.policy_symbol = 'UMB' then b.policy_term_key end)   as UMB,
    count(distinct case when b.policy_symbol = 'DP'  then b.policy_term_key end)   as DP,
    count(distinct case when b.policy_symbol = 'MA'  then b.policy_term_key end)   as MA
from #base_data b
inner join #bim_deduped_ind bim on bim.policy_number = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where cif.Paperless_Bil_Ind = 'Y'
  and isnull(bim.PaperlessBillInd,'N') <> 'Y'
  and cif.PaperlessBillDate is not null
group by cast(cif.PaperlessBillDate as date)
order by cif_only_policies desc
;

----------------------------------------------------------------------------------------------------------
-- 6h: CIF-only opt-ins by symbol + age band (scope for Eloqua integration team)
--     Recent gaps (< 30 days) may resolve naturally; older gaps (> 90 days) are structural.
----------------------------------------------------------------------------------------------------------

select
    b.policy_symbol,
    case
        when cif.PaperlessBillDate >= dateadd(day, -30,  getdate()) then 'Last 30 days'
        when cif.PaperlessBillDate >= dateadd(day, -90,  getdate()) then '31-90 days ago'
        when cif.PaperlessBillDate >= dateadd(day, -180, getdate()) then '91-180 days ago'
        when cif.PaperlessBillDate >= dateadd(day, -365, getdate()) then '181-365 days ago'
        else 'Over 1 year ago'
    end                                                                             as opt_in_age_band,
    count(distinct b.policy_term_key)                                               as BIL_cif_only_policies,
    count(distinct case when cif.Paperless_Pol_Ind = 'Y'
                         and isnull(bim.PaperlessPolInd,'N') <> 'Y'
                        then b.policy_term_key end)                                 as POL_cif_only_policies
from #base_data b
inner join #bim_deduped_ind bim on bim.policy_number = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where cif.Paperless_Bil_Ind = 'Y'
  and isnull(bim.PaperlessBillInd,'N') <> 'Y'
group by
    b.policy_symbol,
    case
        when cif.PaperlessBillDate >= dateadd(day, -30,  getdate()) then 'Last 30 days'
        when cif.PaperlessBillDate >= dateadd(day, -90,  getdate()) then '31-90 days ago'
        when cif.PaperlessBillDate >= dateadd(day, -180, getdate()) then '91-180 days ago'
        when cif.PaperlessBillDate >= dateadd(day, -365, getdate()) then '181-365 days ago'
        else 'Over 1 year ago'
    end
order by b.policy_symbol, opt_in_age_band
;
