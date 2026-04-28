----------------------------------------------------------------------------------------------------------
-- missing_mail.sql
-- Purpose: Diagnose missing EmailAddress in the new EDW/AWM pipeline vs old BIM (Eloqua)
--
-- PREREQUISITE: Run cif_join_validation.sql first in the same session.
--   Reuses temp tables: #base_data, #old_bim, #new_edw
--
-- Sections:
--   1. Email chain funnel      — how many policies survive each step
--   2. Break point detail      — policy-level rows per break point
--   3. BIM vs EDW comparison   — gap and mismatch summary + detail
--   4. Missing rate by symbol  — which lines of business are most affected
--   5. Break point by symbol   — where the chain breaks per product type
--  10. CIF fix validation      — quantify actual impact of Issues 2 & 3 (valid_to_date + update_date fixes)
--  11. CIF vs BIM/Eloqua       — direct comparison of BIL/POL paperless indicators across both sources
----------------------------------------------------------------------------------------------------------

--=========================================================================================================
-- SETUP: Build email chain temp tables (mirrors paperless.sql dedup logic)
--=========================================================================================================

-- party_user_account_link: one row per party_anchor_id, latest load_date
-- Excludes known bad anchors that inflate link counts (from paperless.sql)
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

-- asp_user_account_detail: one row per (party_user_account_link_id, user_name), latest dates first
-- Partition includes user_name to avoid collapsing multiple accounts per link
drop table if exists #email_detail;

-- FIX: partition by party_user_account_link_id only (not by user_name).
-- Partitioning by (link_id, user_name) gave rn_detail=1 for EVERY distinct user_name per link,
-- causing a fan-out when joined — a link with 3 user_names produced 3 rn=1 rows.
-- One row per link (latest valid_from_date) is all we need to check email existence.
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

--=========================================================================================================
-- SECTION 1: EMAIL CHAIN FUNNEL
-- Counts how many distinct policies survive each step of the email resolution chain
-- Chain: base_data -> duplicate_party_anchor_id -> party_user_account_link
--        -> asp_user_account_detail -> non-NULL user_name
--=========================================================================================================

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
select 'No party_user_account_link (link missing)',
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

--=========================================================================================================
-- SECTION 2: BREAK POINT DETAIL
-- Policy-level rows for each break point — use to investigate patterns
--=========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 2a: NULL party_key — no policyholder match, entire email chain cannot start
----------------------------------------------------------------------------------------------------------

select
    'NULL party_key'            as break_point,
    b.policy_number,
    b.policy_symbol,
    b.policy_inforce_indicator,
    b.household_id,
    b.party_key,
    b.cif_id,
    b.duplicate_party_anchor_id
from #base_data b
where b.party_key is null
order by b.policy_symbol, b.policy_number
;

----------------------------------------------------------------------------------------------------------
-- 2b: party_key exists but no same-as-link — duplicate_party_anchor_id is NULL
--     CIF indicators AND email will both be NULL for these policies
----------------------------------------------------------------------------------------------------------

select
    'No same-as-link'           as break_point,
    b.policy_number,
    b.policy_symbol,
    b.policy_inforce_indicator,
    b.household_id,
    b.party_key,
    b.cif_id,
    b.duplicate_party_anchor_id
from #base_data b
where b.party_key is not null
  and b.duplicate_party_anchor_id is null
order by b.policy_symbol, b.policy_number
;

----------------------------------------------------------------------------------------------------------
-- 2c: duplicate_party_anchor_id exists but no party_user_account_link record
--     Party is in AWM but has never registered an online account
----------------------------------------------------------------------------------------------------------

select
    'No party_user_account_link' as break_point,
    b.policy_number,
    b.policy_symbol,
    b.household_id,
    b.party_key,
    b.duplicate_party_anchor_id,
    b.cif_id
from #base_data b
left join #email_link el
    on el.party_anchor_id = b.duplicate_party_anchor_id
   and el.rn_link = 1
where b.duplicate_party_anchor_id is not null
  and el.party_anchor_id is null
order by b.policy_symbol, b.policy_number
;

----------------------------------------------------------------------------------------------------------
-- 2d: Link exists but asp_user_account_detail has no record or user_name is NULL
--     Account link exists but email address was never populated
----------------------------------------------------------------------------------------------------------

select
    case
        when ed.party_user_account_link_id is null then 'No asp_user_account_detail'
        else 'NULL user_name in asp_user_account_detail'
    end                          as break_point,
    b.policy_number,
    b.policy_symbol,
    b.household_id,
    b.duplicate_party_anchor_id,
    el.party_user_account_link_id,
    el.load_date                 as link_load_date,
    ed.user_name,
    ed.valid_from_date,
    ed.valid_to_date
from #base_data b
inner join #email_link el
    on el.party_anchor_id = b.duplicate_party_anchor_id
   and el.rn_link = 1
left join #email_detail ed
    on ed.party_user_account_link_id = el.party_user_account_link_id
   and ed.rn_detail = 1
where ed.party_user_account_link_id is null
   or ed.user_name is null
order by b.policy_symbol, b.policy_number
;

--=========================================================================================================
-- SECTION 3: BIM vs EDW EMAIL COMPARISON
-- FIX: Pre-collapse both tables to one row per PolNumber before comparing.
--      #new_edw has multiple rows per PolNumber (one per policy_term_key + cif_id).
--      Without this, the inner join fans out and a policy appears in BOTH
--      "BOTH have email" and "BIM has email — NEW missing" simultaneously,
--      causing the totals to exceed the actual OLD BIM count.
-- Rule: if ANY row for a PolNumber has a non-NULL email, treat the policy as having email.
--=========================================================================================================

drop table if exists #bim_deduped;

select
    PolNumber,
    -- Take one representative row per policy for display in detail queries
    max(HouseholdID)    as HouseholdID,
    max(CIFID)          as CIFID,
    -- Prefer non-NULL email; coalesce across rows using max (email is a string, max picks non-null)
    max(nullif(EmailAddress, '')) as EmailAddress
into #bim_deduped
from #old_bim
group by PolNumber
;

drop table if exists #new_deduped;

select
    PolNumber,
    max(HouseholdID)              as HouseholdID,
    max(CIFID)                    as CIFID,
    max(nullif(EmailAddress, '')) as EmailAddress
into #new_deduped
from #new_edw
group by PolNumber
;

----------------------------------------------------------------------------------------------------------
-- 3a: Summary — email coverage comparison at PolNumber grain (clean, no fan-out)
----------------------------------------------------------------------------------------------------------

select 'OLD BIM: distinct PolNumbers'             as metric, count(*) as cnt from #bim_deduped
union all
select 'NEW EDW: distinct PolNumbers',             count(*) from #new_deduped
union all
select 'OLD BIM: policies with email',             count(*) from #bim_deduped where EmailAddress is not null
union all
select 'NEW EDW: policies with email',             count(*) from #new_deduped where EmailAddress is not null
union all
select 'Matched: BOTH have email',
    count(*)
from #bim_deduped o inner join #new_deduped n on o.PolNumber = n.PolNumber
where o.EmailAddress is not null and n.EmailAddress is not null
union all
select 'BIM has email — NEW is missing',
    count(*)
from #bim_deduped o inner join #new_deduped n on o.PolNumber = n.PolNumber
where o.EmailAddress is not null and n.EmailAddress is null
union all
select 'NEW has email — BIM is missing',
    count(*)
from #bim_deduped o inner join #new_deduped n on o.PolNumber = n.PolNumber
where o.EmailAddress is null and n.EmailAddress is not null
union all
select 'BOTH missing email',
    count(*)
from #bim_deduped o inner join #new_deduped n on o.PolNumber = n.PolNumber
where o.EmailAddress is null and n.EmailAddress is null
union all
select 'Both have email but values differ (mismatch)',
    count(*)
from #bim_deduped o inner join #new_deduped n on o.PolNumber = n.PolNumber
where o.EmailAddress is not null
  and n.EmailAddress is not null
  and o.EmailAddress <> n.EmailAddress
union all
select 'In OLD BIM only (not in NEW)',
    count(*)
from #bim_deduped o left join #new_deduped n on o.PolNumber = n.PolNumber
where n.PolNumber is null
union all
select 'In NEW EDW only (not in OLD)',
    count(*)
from #new_deduped n left join #bim_deduped o on o.PolNumber = n.PolNumber
where o.PolNumber is null
;

----------------------------------------------------------------------------------------------------------
-- 3b: Detail — BIM has email but NEW is missing (one row per PolNumber)
--     Highest priority gap: policies the old report emailed that the new pipeline will miss
----------------------------------------------------------------------------------------------------------

select
    o.PolNumber,
    o.HouseholdID           as old_HouseholdID,
    n.HouseholdID           as new_HouseholdID,
    o.CIFID                 as old_CIFID,
    n.CIFID                 as new_CIFID,
    o.EmailAddress          as bim_email,
    -- Show all email rows from #new_edw to help diagnose why they all resolved to NULL
    (
        select count(*)
        from #new_edw ne
        where ne.PolNumber = o.PolNumber
    )                       as new_edw_row_count,
    case
        when n.CIFID is null    then 'No same-as-link (CIF missing)'
        when n.HouseholdID is null then 'No household mapping'
        else                        'Link or account detail missing'
    end                     as likely_cause
from #bim_deduped o
inner join #new_deduped n on o.PolNumber = n.PolNumber
where o.EmailAddress is not null
  and n.EmailAddress is null
order by likely_cause, o.PolNumber
;

----------------------------------------------------------------------------------------------------------
-- 3c: Detail — email values differ between BIM and NEW (same policy, different address)
----------------------------------------------------------------------------------------------------------

select
    o.PolNumber,
    o.CIFID                 as old_CIFID,
    n.CIFID                 as new_CIFID,
    o.EmailAddress          as bim_email,
    n.EmailAddress          as new_email
from #bim_deduped o
inner join #new_deduped n on o.PolNumber = n.PolNumber
where o.EmailAddress is not null
  and n.EmailAddress is not null
  and o.EmailAddress <> n.EmailAddress
order by o.PolNumber
;

--=========================================================================================================
-- SECTION 4 + 5 PREP: Pre-aggregate email chain to policy level
-- FIX: relaxed policyholder join returns multiple party rows per policy_term_key (NIN + ANI).
--      Aggregating here first ensures:
--        - total = count(distinct policy_term_key) matches the sum of all categories
--        - columns are mutually exclusive (a policy belongs to exactly one break-point bucket)
--        - email_resolved can never exceed total
-- Logic: take the BEST outcome across all parties per policy —
--        if ANY party resolved email, the policy has email.
--        Break-point is the furthest step reached by the best party.
--=========================================================================================================

drop table if exists #email_chain_by_policy;

select
    b.policy_term_key,
    b.policy_symbol,
    -- Best outcome across all parties (max = 1 wins if any party reached that step)
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

--=========================================================================================================
-- SECTION 4: MISSING EMAIL RATE BY POLICY SYMBOL
-- Each policy counted once — email_resolved + missing_email = total (guaranteed)
--=========================================================================================================

select
    policy_symbol,
    count(*)                                            as total_policies,
    sum(has_email)                                      as has_email,
    sum(1 - has_email)                                  as missing_email,
    cast(100.0 * sum(has_email)
        / nullif(count(*), 0) as decimal(5,1))          as pct_with_email
from #email_chain_by_policy
group by policy_symbol
order by missing_email desc
;

--=========================================================================================================
-- SECTION 5: BREAK POINT BREAKDOWN BY POLICY SYMBOL
-- Mutually exclusive buckets — each policy falls into exactly one:
--   no_party_key → no_same_as_link → no_account_link → no_user_name → email_resolved
-- A policy is classified at the EARLIEST step where the chain broke.
--=========================================================================================================

select
    policy_symbol,
    count(*)                                                                                    as total,
    -- Bucket 1: no policyholder matched at all
    sum(case when has_party_key    = 0                                          then 1 else 0 end) as no_party_key,
    -- Bucket 2: policyholder found but no same-as-link to AWM party
    sum(case when has_party_key    = 1 and has_same_as_link = 0                 then 1 else 0 end) as no_same_as_link,
    -- Bucket 3: same-as-link exists but party never registered an online account
    sum(case when has_same_as_link = 1 and has_account_link = 0                 then 1 else 0 end) as no_account_link,
    -- Bucket 4: account link exists but no email address populated
    sum(case when has_account_link = 1 and has_email        = 0                 then 1 else 0 end) as no_user_name,
    -- Resolved: at least one party on this policy has an email
    sum(has_email)                                                                                 as email_resolved
from #email_chain_by_policy
group by policy_symbol
order by total desc
;

--=========================================================================================================
-- SECTION 6: DEEP DIVE — no_account_link (36,768) and no_user_name (28,385)
--
-- no_account_link: duplicate_party_anchor_id exists in AWM but NO record in party_user_account_link
--                 These customers never registered an online account — structurally unrecoverable
--                 unless they register in future. Analysis helps prioritize outreach.
--
-- no_user_name:   account link exists but user_name is NULL in asp_user_account_detail
--                 These customers DID register but email is blank/inactive. Potentially recoverable.
--=========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 6a: no_account_link — breakdown by policy_symbol + HOH_IND
-- Shows whether the unregistered party is the head of household or a secondary policyholder
-- If most are ANI (secondary), the household may still be reachable via the NIN's email
----------------------------------------------------------------------------------------------------------

-- Note: HOH_IND is not available in #base_data (cif_join_validation.sql strips #view_ph to key cols only)
-- Grouped by policy_symbol only; run against paperless.sql's #base_data for HOH breakdown
select
    b.policy_symbol,
    count(distinct b.policy_term_key)   as policies,
    count(*)                            as party_rows
from #base_data b
left join #email_link el
    on el.party_anchor_id = b.duplicate_party_anchor_id
   and el.rn_link = 1
where b.duplicate_party_anchor_id is not null
  and el.party_anchor_id is null
group by b.policy_symbol
order by b.policy_symbol
;

----------------------------------------------------------------------------------------------------------
-- 6b: no_account_link — how many of these policies have ANOTHER party that DID resolve email
-- These are policies where one party is unregistered but another party on the same policy has email
-- These are NOT truly lost — the household is already covered via the other party
----------------------------------------------------------------------------------------------------------

select
    'no_account_link policies where another party HAS email'    as metric,
    count(distinct b.policy_term_key)                           as policies
from #base_data b
left join #email_link el
    on el.party_anchor_id = b.duplicate_party_anchor_id
   and el.rn_link = 1
where b.duplicate_party_anchor_id is not null
  and el.party_anchor_id is null
  -- Check if the same policy_term_key has at least one other party with email
  and exists (
    select 1
    from #base_data b2
    inner join #email_link   el2 on el2.party_anchor_id            = b2.duplicate_party_anchor_id and el2.rn_link   = 1
    inner join #email_detail ed2 on ed2.party_user_account_link_id = el2.party_user_account_link_id and ed2.rn_detail = 1
    where b2.policy_term_key = b.policy_term_key
      and ed2.user_name is not null
  )

union all

select
    'no_account_link policies with NO email on any party (truly unreachable)',
    count(distinct b.policy_term_key)
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
;

----------------------------------------------------------------------------------------------------------
-- 6c: no_account_link — age and state profile
-- Older customers and certain states may have lower online registration rates
-- Helps target digital adoption campaigns
----------------------------------------------------------------------------------------------------------

-- Note: mailing_address_state_code, Age, HOH_IND not in #base_data here
-- Using policy_symbol + inforce_indicator as available dimensions
-- For full age/state breakdown run this against paperless.sql's richer #base_data
select
    b.policy_symbol,
    b.policy_inforce_indicator,
    count(distinct b.policy_term_key)   as unregistered_policies,
    count(distinct b.household_id)      as unregistered_households
from #base_data b
left join #email_link el
    on el.party_anchor_id = b.duplicate_party_anchor_id
   and el.rn_link = 1
where b.duplicate_party_anchor_id is not null
  and el.party_anchor_id is null
group by b.policy_symbol, b.policy_inforce_indicator
order by unregistered_policies desc
;

----------------------------------------------------------------------------------------------------------
-- 6d: no_account_link — tenure profile
-- Policies with longer tenure that still haven't registered are least likely to self-register
-- Short-tenure policies may register soon naturally
----------------------------------------------------------------------------------------------------------

-- Note: original_effective_date and HOH_IND not available in #base_data here
-- Using effective_from_date (policy term start) as proxy for tenure
select
    case
        when datediff(year, b.effective_from_date, getdate()) < 1  then '< 1 year'
        when datediff(year, b.effective_from_date, getdate()) < 3  then '1-3 years'
        when datediff(year, b.effective_from_date, getdate()) < 5  then '3-5 years'
        when datediff(year, b.effective_from_date, getdate()) < 10 then '5-10 years'
        else '10+ years'
    end                                 as tenure_band,
    b.policy_symbol,
    count(distinct b.policy_term_key)   as unregistered_policies
from #base_data b
left join #email_link el
    on el.party_anchor_id = b.duplicate_party_anchor_id
   and el.rn_link = 1
where b.duplicate_party_anchor_id is not null
  and el.party_anchor_id is null
group by
    case
        when datediff(year, b.effective_from_date, getdate()) < 1  then '< 1 year'
        when datediff(year, b.effective_from_date, getdate()) < 3  then '1-3 years'
        when datediff(year, b.effective_from_date, getdate()) < 5  then '3-5 years'
        when datediff(year, b.effective_from_date, getdate()) < 10 then '5-10 years'
        else '10+ years'
    end,
    b.policy_symbol
order by b.policy_symbol, tenure_band
;

--=========================================================================================================
-- SECTION 7: DEEP DIVE — no_user_name (28,385) — potentially recoverable
-- Account link exists in party_user_account_link but user_name is NULL in asp_user_account_detail
-- Root causes: anonymous accounts, inactive/deactivated accounts, or accounts never fully set up
--=========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 7a: no_user_name — breakdown by is_anonymous_indicator + is_up_and_running_indicator
-- Anonymous or not-up-and-running accounts explain most NULL user_names
-- is_anonymous = 1 → guest/partial registration, email never collected
-- is_up_and_running = 0 → account created but not activated
----------------------------------------------------------------------------------------------------------

select
    isnull(cast(ed.is_anonymous_indicator as varchar(1)), 'NULL')        as is_anonymous,
    isnull(cast(ed.is_up_and_running_indicator as varchar(1)), 'NULL')   as is_up_and_running,
    count(distinct b.policy_term_key)                                  as policies,
    count(*)                                                           as party_rows
from #base_data b
inner join #email_link el
    on el.party_anchor_id = b.duplicate_party_anchor_id
   and el.rn_link = 1
left join #email_detail ed
    on ed.party_user_account_link_id = el.party_user_account_link_id
   and ed.rn_detail = 1
where ed.user_name is null
group by ed.is_anonymous_indicator, ed.is_up_and_running_indicator
order by policies desc
;

----------------------------------------------------------------------------------------------------------
-- 7b: no_user_name — breakdown by policy_symbol
----------------------------------------------------------------------------------------------------------

select
    b.policy_symbol,
    count(distinct b.policy_term_key)   as policies,
    -- Sub-classify: no detail record at all vs detail exists but user_name is NULL
    sum(case when ed.party_user_account_link_id is null then 1 else 0 end) as no_detail_record,
    sum(case when ed.party_user_account_link_id is not null and ed.user_name is null then 1 else 0 end) as detail_exists_null_email
from #base_data b
inner join #email_link el
    on el.party_anchor_id = b.duplicate_party_anchor_id
   and el.rn_link = 1
left join #email_detail ed
    on ed.party_user_account_link_id = el.party_user_account_link_id
   and ed.rn_detail = 1
where ed.user_name is null
group by b.policy_symbol
order by policies desc
;

----------------------------------------------------------------------------------------------------------
-- 7c: no_user_name — how many also have a BIM email (old system had their email, new doesn't)
-- These are the highest-value recovery candidates: BIM knows their email, AWM lost it
----------------------------------------------------------------------------------------------------------

select
    'no_user_name AND BIM has email (recoverable from BIM)'   as metric,
    count(distinct b.policy_term_key)                         as policies
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

union all

select
    'no_user_name AND BIM also missing email (not recoverable from BIM)',
    count(distinct b.policy_term_key)
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
;

--=========================================================================================================
-- SECTION 8: BACKFILL CANDIDATE LIST — 27,756 recoverable policies
--
-- These policies have NO email in AWM (incomplete account setup: is_up_and_running = N)
-- but the OLD BIM/Eloqua system has a valid email address on file.
--
-- Intended use:
--   - Hand to data team to patch asp_user_account_detail via AWM load process, OR
--   - Use BIM email directly in the Tableau report as a fallback EmailAddress column
--   - Do NOT blindly overwrite AWM — treat as a candidate list for manual/batch review
--=========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 8a: Full backfill candidate list
-- One row per policy — BIM email + both system identifiers for matching
----------------------------------------------------------------------------------------------------------

select
    b.policy_number                         as PolNumber,
    b.policy_symbol,
    b.household_id                          as new_HouseholdID,
    ob.HouseholdID                          as bim_HouseholdID,
    b.cif_id                                as new_CIFID,
    ob.CIFID                                as bim_CIFID,
    ob.EmailAddress                         as bim_email,          -- email to backfill
    el.party_user_account_link_id,                                  -- AWM link to patch
    b.duplicate_party_anchor_id             as party_anchor_id,
    b.policy_term_key,
    b.effective_from_date,
    b.effective_to_date,
    -- Account status flags — confirm these before any write-back
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
where ed.user_name is null                      -- AWM has no email
  and ob.EmailAddress is not null
  and ob.EmailAddress <> ''                     -- BIM has a valid email
order by b.policy_symbol, b.policy_number
;

----------------------------------------------------------------------------------------------------------
-- 8b: Backfill candidate summary by symbol
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

--=========================================================================================================
-- SECTION 9: REMAINING GAP SUMMARY — what cannot be recovered via data
--
-- These are the groups where no email exists in either system.
-- Resolution requires customer action (register online / provide email).
-- This section sizes each group to help prioritize outreach campaigns.
--=========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 9a: Full gap summary — all categories, mutually exclusive, adds up to total missing email
----------------------------------------------------------------------------------------------------------

select
    gap_category,
    policies,
    resolution
from (

    -- Gap 1: no_same_as_link (negligible)
    select
        'No same-as-link (AWM party not mapped)'            as gap_category,
        count(distinct b.policy_term_key)                   as policies,
        'Data fix: investigate party_id_same_as_link gaps'  as resolution,
        1                                                   as sort_order
    from #base_data b
    where b.party_key is not null
      and b.duplicate_party_anchor_id is null

    union all

    -- Gap 2: no_account_link — truly unreachable (no email on any party on the policy)
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

    -- Gap 3: account exists (is_up_and_running=N), BIM also has no email
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

    -- Gap 4: recoverable from BIM (already in Section 8 — listed here for completeness)
    select
        'Incomplete account setup — BIM email available (recoverable)',
        count(distinct b.policy_term_key),
        'Data fix: backfill email from BIM into AWM (see Section 8 list)',
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

----------------------------------------------------------------------------------------------------------
-- 9b: no_account_link truly unreachable — broken down by symbol + tenure band
-- Helps decide which segment to target first for a registration drive
----------------------------------------------------------------------------------------------------------

select
    b.policy_symbol,
    case
        when datediff(year, b.effective_from_date, getdate()) < 1  then '< 1 year'
        when datediff(year, b.effective_from_date, getdate()) < 3  then '1-3 years'
        when datediff(year, b.effective_from_date, getdate()) < 5  then '3-5 years'
        when datediff(year, b.effective_from_date, getdate()) < 10 then '5-10 years'
        else '10+ years'
    end                                     as tenure_band,
    count(distinct b.policy_term_key)       as unreachable_policies,
    count(distinct b.household_id)          as unreachable_households
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
group by
    b.policy_symbol,
    case
        when datediff(year, b.effective_from_date, getdate()) < 1  then '< 1 year'
        when datediff(year, b.effective_from_date, getdate()) < 3  then '1-3 years'
        when datediff(year, b.effective_from_date, getdate()) < 5  then '3-5 years'
        when datediff(year, b.effective_from_date, getdate()) < 10 then '5-10 years'
        else '10+ years'
    end
order by b.policy_symbol, tenure_band
;

--=========================================================================================================
-- SECTION 10: CIF Fix Validation — Quantify actual impact of Issues 2 & 3
--
-- Issue 2: valid_to_date filter (superseded CIF records)
--   Fix: added valid_to_date = '9999-12-31' to exclude superseded rows
--   Risk: stale paperless indicator from an old load survives and overrides the current value
--
-- Issue 3: update_date sort key (CIF dedup ordering)
--   Fix: changed ROW_NUMBER ORDER BY from effective_from_date DESC to update_date DESC
--   Risk: when two records share the same effective_from_date, the wrong one wins
--
-- Run these directly against AWM (no temp table prereqs required)
--=========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 10a: Issue 2 — Superseded CIF records with a DIFFERENT indicator than the current record
--
-- If indicator_mismatch > 0 → the valid_to_date fix changed real paperless outcomes
-- If indicator_mismatch = 0 → fix was defensive; superseded rows happened to agree with current
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
    on  c.policy_party_link_id         = s.policy_party_link_id
    and c.output_document_type_code    = s.output_document_type_code
    and c.effective_to_date            = '9999-12-31'
    and c.valid_to_date                = '9999-12-31'           -- current record
where s.effective_to_date             = '9999-12-31'
  and s.valid_to_date                != '9999-12-31'            -- superseded rows only
  and s.output_document_type_code    in ('BIL', 'POL')
;

----------------------------------------------------------------------------------------------------------
-- 10b: Issue 2 — Breakdown by document type (BIL vs POL)
----------------------------------------------------------------------------------------------------------

select
    s.output_document_type_code,
    count(*)                                                                        as superseded_rows,
    sum(case when s.paper_notify_indicator
             != c.paper_notify_indicator then 1 else 0 end)                        as indicator_mismatch
from AWM.dbo.cif_policy_party_detail s
join AWM.dbo.cif_policy_party_detail c
    on  c.policy_party_link_id         = s.policy_party_link_id
    and c.output_document_type_code    = s.output_document_type_code
    and c.effective_to_date            = '9999-12-31'
    and c.valid_to_date                = '9999-12-31'
where s.effective_to_date             = '9999-12-31'
  and s.valid_to_date                != '9999-12-31'
  and s.output_document_type_code    in ('BIL', 'POL')
group by s.output_document_type_code
;

----------------------------------------------------------------------------------------------------------
-- 10c: Issue 3 — CIF records tied on effective_from_date but with different paper_notify_indicator
--
-- These are the records where effective_from_date sort is non-deterministic.
-- If count > 0 → update_date sort fix matters; without it, the wrong indicator could win.
-- If count = 0 → fix was defensive; tied dates always agreed on the indicator value.
----------------------------------------------------------------------------------------------------------

select
    count(*)                                                                        as groups_with_tied_date_and_different_indicator
from (
    select
        policy_party_link_id,
        output_document_type_code,
        effective_from_date,
        min(paper_notify_indicator)                                                 as min_indicator,
        max(paper_notify_indicator)                                                 as max_indicator,
        count(distinct update_date)                                                 as distinct_update_dates,
        count(*)                                                                    as row_count
    from AWM.dbo.cif_policy_party_detail
    where output_document_type_code   in ('BIL', 'POL')
      and effective_to_date            = '9999-12-31'
      and valid_to_date                = '9999-12-31'
    group by
        policy_party_link_id,
        output_document_type_code,
        effective_from_date
    having count(*) > 1                                                             -- tied on effective_from_date
       and min(paper_notify_indicator) != max(paper_notify_indicator)               -- disagreeing indicators
) ties
;

----------------------------------------------------------------------------------------------------------
-- 10d: Issue 3 — Detail rows for tied groups (sample — top 50)
-- Shows exactly which records would pick a different winner under each sort strategy
----------------------------------------------------------------------------------------------------------

select top 50
    d.policy_party_link_id,
    d.output_document_type_code,
    d.effective_from_date,
    d.update_date,
    d.paper_notify_indicator,
    row_number() over (
        partition by d.policy_party_link_id, d.output_document_type_code, d.effective_from_date
        order by d.effective_from_date desc, d.update_date desc                     -- AFTER fix: update_date wins
    )                                                                               as rn_after_fix,
    row_number() over (
        partition by d.policy_party_link_id, d.output_document_type_code, d.effective_from_date
        order by d.effective_from_date desc                                         -- BEFORE fix: non-deterministic
    )                                                                               as rn_before_fix
from AWM.dbo.cif_policy_party_detail d
where output_document_type_code  in ('BIL', 'POL')
  and effective_to_date           = '9999-12-31'
  and valid_to_date               = '9999-12-31'
  and exists (
    select 1
    from AWM.dbo.cif_policy_party_detail d2
    where d2.policy_party_link_id       = d.policy_party_link_id
      and d2.output_document_type_code  = d.output_document_type_code
      and d2.effective_from_date        = d.effective_from_date
      and d2.effective_to_date          = '9999-12-31'
      and d2.valid_to_date              = '9999-12-31'
      and d2.paper_notify_indicator    != d.paper_notify_indicator
  )
order by d.policy_party_link_id, d.output_document_type_code, d.effective_from_date desc, d.update_date desc
;

--=========================================================================================================
-- SECTION 11: CIF (AWM) vs BIM/Eloqua — Direct Paperless Indicator Comparison
--
-- Purpose: Compare BIL and POL paperless indicators between the two source systems side by side.
--          Identify discrepancies, understand population differences, and surface root causes.
--
-- Sources:
--   AWM  : AWM.dbo.cif_policy_party_detail  (paper_notify_indicator, output_document_type_code)
--   BIM  : BIM_Reporting_Weekly.Eloqua.POLICY (PPRLESS_BIL_IND, PPRLESS_POL_IND)
--
-- Key definitions:
--   CIF BIL  : paper_notify_indicator = 0 → paperless billing     (suppress paper bill)
--   CIF POL  : paper_notify_indicator = 0 → paperless policy docs (suppress paper policy)
--   BIM BIL  : PPRLESS_BIL_IND = 'Y'      → paperless billing
--   BIM POL  : PPRLESS_POL_IND = 'Y'      → paperless policy docs
--
-- PREREQUISITE: Run cif_join_validation.sql first — reuses #old_bim and #CIF_POLICY_Detail
--=========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 11a: Overall agreement summary — how often do CIF and BIM agree per indicator?
--
-- Compares policies present in BOTH sources on the matched policy_number key.
-- Buckets: both agree Y, both agree N/NULL, one says Y the other does not.
----------------------------------------------------------------------------------------------------------

select
    -- BIL indicator agreement
    sum(case when bim.PaperlessBillInd = 'Y' and cif.Paperless_Bil_Ind = 'Y' then 1 else 0 end)   as BIL_both_paperless,
    sum(case when bim.PaperlessBillInd = 'Y' and isnull(cif.Paperless_Bil_Ind,'N') <> 'Y' then 1 else 0 end) as BIL_bim_yes_cif_no,
    sum(case when isnull(bim.PaperlessBillInd,'N') <> 'Y' and cif.Paperless_Bil_Ind = 'Y' then 1 else 0 end) as BIL_cif_yes_bim_no,
    sum(case when isnull(bim.PaperlessBillInd,'N') <> 'Y' and isnull(cif.Paperless_Bil_Ind,'N') <> 'Y' then 1 else 0 end) as BIL_both_not_paperless,

    -- POL indicator agreement
    sum(case when bim.PaperlessPolInd  = 'Y' and cif.Paperless_Pol_Ind = 'Y' then 1 else 0 end)   as POL_both_paperless,
    sum(case when bim.PaperlessPolInd  = 'Y' and isnull(cif.Paperless_Pol_Ind,'N') <> 'Y' then 1 else 0 end) as POL_bim_yes_cif_no,
    sum(case when isnull(bim.PaperlessPolInd,'N') <> 'Y' and cif.Paperless_Pol_Ind = 'Y' then 1 else 0 end)  as POL_cif_yes_bim_no,
    sum(case when isnull(bim.PaperlessPolInd,'N') <> 'Y' and isnull(cif.Paperless_Pol_Ind,'N') <> 'Y' then 1 else 0 end) as POL_both_not_paperless,

    count(*)                                                                                        as total_matched_policies
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
-- 11b SETUP: Deduplicate #old_bim to one row per policy_number
--
-- FIX: #old_bim has multiple contact rows per POL_KEY (one per household member).
-- Joining directly caused fan-out — BIL_agree_Y counts exceeded total_policies.
-- MAX() picks 'Y' over NULL/N so any paperless opt-in on any contact survives.
----------------------------------------------------------------------------------------------------------

drop table if exists #bim_deduped_ind;

select
    PolNumber                                                                        as policy_number,
    max(PaperlessBillInd)                                                           as PaperlessBillInd,
    max(PaperlessBillDate)                                                          as PaperlessBillDate,
    max(PaperlessPolInd)                                                            as PaperlessPolInd,
    max(PaperlessPolDate)                                                           as PaperlessPolDate
into #bim_deduped_ind
from #old_bim
group by PolNumber
;

----------------------------------------------------------------------------------------------------------
-- 11b: Agreement summary by policy symbol (fixed — uses #bim_deduped_ind, one row per policy)
-- Shows which product lines have the most indicator disagreement between CIF and BIM
----------------------------------------------------------------------------------------------------------

select
    b.policy_symbol,
    count(distinct b.policy_term_key)                                                               as total_policies,

    -- BIL
    sum(case when bim.PaperlessBillInd = 'Y' and cif.Paperless_Bil_Ind = 'Y' then 1 else 0 end)   as BIL_agree_Y,
    sum(case when bim.PaperlessBillInd = 'Y' and isnull(cif.Paperless_Bil_Ind,'N') <> 'Y' then 1 else 0 end) as BIL_bim_yes_cif_no,
    sum(case when isnull(bim.PaperlessBillInd,'N') <> 'Y' and cif.Paperless_Bil_Ind = 'Y' then 1 else 0 end) as BIL_cif_yes_bim_no,

    -- POL
    sum(case when bim.PaperlessPolInd  = 'Y' and cif.Paperless_Pol_Ind = 'Y' then 1 else 0 end)   as POL_agree_Y,
    sum(case when bim.PaperlessPolInd  = 'Y' and isnull(cif.Paperless_Pol_Ind,'N') <> 'Y' then 1 else 0 end) as POL_bim_yes_cif_no,
    sum(case when isnull(bim.PaperlessPolInd,'N') <> 'Y' and cif.Paperless_Pol_Ind = 'Y' then 1 else 0 end)  as POL_cif_yes_bim_no
from #base_data b
inner join #bim_deduped_ind bim                                                     -- fixed: one row per policy
    on bim.policy_number = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
            substring(
                b.policy_number,
                case when b.policy_number like 'UMB%' then 5 else 4 end,
                len(b.policy_number)
            ) as bigint)
group by b.policy_symbol
order by b.policy_symbol
;

----------------------------------------------------------------------------------------------------------
-- 11c: Mismatch detail rows — policies where BIM and CIF disagree on BIL or POL
--
-- Shows both values side by side with the direction of disagreement.
-- Use this to manually inspect root cause for a sample of policies.
----------------------------------------------------------------------------------------------------------

select
    b.policy_number,
    b.policy_symbol,
    b.policy_inforce_indicator,

    -- BIM values (from Eloqua)
    bim.PaperlessBillInd                                                            as bim_BIL_ind,
    bim.PaperlessBillDate                                                           as bim_BIL_date,
    bim.PaperlessPolInd                                                             as bim_POL_ind,
    bim.PaperlessPolDate                                                            as bim_POL_date,

    -- CIF values (from AWM)
    cif.Paperless_Bil_Ind                                                           as cif_BIL_ind,
    cif.PaperlessBillDate                                                           as cif_BIL_date,
    cif.Paperless_Pol_Ind                                                           as cif_POL_ind,
    cif.PaperlessPolDate                                                            as cif_POL_date,

    -- Mismatch flags
    case
        -- normalize BIM blank/space to NULL for comparison
        when nullif(ltrim(bim.PaperlessBillInd),'') = 'Y' and isnull(cif.Paperless_Bil_Ind,'N') <> 'Y'    then 'BIM_only'
        when isnull(nullif(ltrim(bim.PaperlessBillInd),''),'N') <> 'Y' and cif.Paperless_Bil_Ind = 'Y'    then 'CIF_only'
        when nullif(ltrim(bim.PaperlessBillInd),'') = 'N' and cif.Paperless_Bil_Ind is null               then 'BIM_N_CIF_missing'
        when nullif(ltrim(bim.PaperlessBillInd),'') is null and cif.Paperless_Bil_Ind = 'N'               then 'CIF_N_BIM_missing'
        else 'agree'
    end                                                                             as BIL_mismatch_direction,

    case
        -- normalize BIM blank/space to NULL for comparison
        when nullif(ltrim(bim.PaperlessPolInd),'')  = 'Y' and isnull(cif.Paperless_Pol_Ind,'N') <> 'Y'    then 'BIM_only'
        when isnull(nullif(ltrim(bim.PaperlessPolInd),''),'N') <> 'Y' and cif.Paperless_Pol_Ind = 'Y'     then 'CIF_only'
        when nullif(ltrim(bim.PaperlessPolInd),'')  = 'N' and cif.Paperless_Pol_Ind is null               then 'BIM_N_CIF_missing'
        when nullif(ltrim(bim.PaperlessPolInd),'')  is null and cif.Paperless_Pol_Ind = 'N'               then 'CIF_N_BIM_missing'
        else 'agree'
    end                                                                             as POL_mismatch_direction,

    -- NULL population flags — helps identify if absence of record is the root cause
    case when cif.Paperless_Bil_Ind is null then 'Y' else 'N' end                  as cif_BIL_record_missing,
    case when cif.Paperless_Pol_Ind is null then 'Y' else 'N' end                  as cif_POL_record_missing

from #base_data b
inner join #old_bim bim
    on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
            substring(
                b.policy_number,
                case when b.policy_number like 'UMB%' then 5 else 4 end,
                len(b.policy_number)
            ) as bigint)
where
    -- at least one indicator disagrees
    isnull(bim.PaperlessBillInd,'') <> isnull(cif.Paperless_Bil_Ind,'')
    or isnull(bim.PaperlessPolInd,'')  <> isnull(cif.Paperless_Pol_Ind,'')
order by b.policy_symbol, BIL_mismatch_direction, POL_mismatch_direction
;

----------------------------------------------------------------------------------------------------------
-- 11d: Root cause breakdown — for BIM_only mismatches, is the CIF record missing or does it disagree?
--
-- BIM says 'Y' but CIF does not — two possible causes:
--   a) CIF has no record at all for this policy (missing population)
--   b) CIF has a record but paper_notify_indicator != 0 (genuine disagreement)
----------------------------------------------------------------------------------------------------------

select
    'BIL — CIF record missing (NULL)'                                               as root_cause,
    count(distinct b.policy_term_key)                                               as policy_count
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
            substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessBillInd = 'Y'
  and cif.Paperless_Bil_Ind is null                                                 -- CIF has no BIL record

union all

select
    'BIL — CIF record exists but disagrees',
    count(distinct b.policy_term_key)
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
            substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessBillInd = 'Y'
  and cif.Paperless_Bil_Ind = 'N'                                                   -- CIF has record, disagrees

union all

select
    'POL — CIF record missing (NULL)',
    count(distinct b.policy_term_key)
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
            substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessPolInd = 'Y'
  and cif.Paperless_Pol_Ind is null                                                 -- CIF has no POL record

union all

select
    'POL — CIF record exists but disagrees',
    count(distinct b.policy_term_key)
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
            substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessPolInd = 'Y'
  and cif.Paperless_Pol_Ind = 'N'                                                   -- CIF has record, disagrees
;

----------------------------------------------------------------------------------------------------------
-- 11e: CIF-only direction — policies where CIF says paperless but BIM does not
-- These are candidates where AWM is more up-to-date than BIM (expected for recent opt-ins)
----------------------------------------------------------------------------------------------------------

select
    b.policy_symbol,
    count(distinct case when cif.Paperless_Bil_Ind = 'Y'
                         and isnull(bim.PaperlessBillInd,'N') <> 'Y' then b.policy_term_key end) as BIL_cif_only,
    count(distinct case when cif.Paperless_Pol_Ind = 'Y'
                         and isnull(bim.PaperlessPolInd,'N') <> 'Y'  then b.policy_term_key end) as POL_cif_only,
    count(distinct b.policy_term_key)                                               as total_matched
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
            substring(
                b.policy_number,
                case when b.policy_number like 'UMB%' then 5 else 4 end,
                len(b.policy_number)
            ) as bigint)
group by b.policy_symbol
order by b.policy_symbol
;

----------------------------------------------------------------------------------------------------------
-- 11f: Population coverage — how many policies have a CIF BIL/POL record at all vs BIM record?
-- Explains structural differences: BIM only stores opted-in contacts; CIF stores all parties
----------------------------------------------------------------------------------------------------------

select
    'Has BIM BIL record (PPRLESS_BIL_IND not null)'                                as metric,
    count(distinct b.policy_term_key)                                               as policy_count
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
where bim.PaperlessBillInd is not null

union all

select
    'Has CIF BIL record (Paperless_Bil_Ind not null)',
    count(distinct b.policy_term_key)
from #base_data b
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
            substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where cif.Paperless_Bil_Ind is not null

union all

select
    'Has BIM POL record (PPRLESS_POL_IND not null)',
    count(distinct b.policy_term_key)
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
where bim.PaperlessPolInd is not null

union all

select
    'Has CIF POL record (Paperless_Pol_Ind not null)',
    count(distinct b.policy_term_key)
from #base_data b
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
            substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where cif.Paperless_Pol_Ind is not null

union all

select
    'Has BOTH BIM and CIF BIL record',
    count(distinct b.policy_term_key)
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
            substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessBillInd is not null
  and cif.Paperless_Bil_Ind is not null

union all

select
    'Has BOTH BIM and CIF POL record',
    count(distinct b.policy_term_key)
from #base_data b
inner join #old_bim bim on bim.PolNumber = b.policy_number
inner join #CIF_POLICY_Detail cif
    on cif.policy_number_int = try_cast(
            substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessPolInd is not null
  and cif.Paperless_Pol_Ind is not null
;

--=========================================================================================================
-- SECTION 11 — RESOLUTION INVESTIGATIONS
-- Purpose: Deeper root cause analysis for the three mismatch categories identified in 11a–11f.
--   11g : Category 1 — timing lag measurement (how many days is BIM ahead of CIF?)
--   11h : Category 2 — missing CIF records: broken join path vs truly absent data
--   11i : Category 3 — CIF-only opt-ins by date (integration gap spike detection)
--   11j : Category 3 — CIF-only opt-ins by policy symbol + date band (scope for marketing team)
--=========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 11g: Category 1 — Timing lag measurement
--
-- For policies where BIM says paperless but CIF has a record that disagrees (genuine disagreement bucket):
-- Measure how many days BIM is ahead of CIF using the opt-in dates.
--
-- Interpret:
--   avg_days_bim_ahead  1–7   → normal batch lag, no action needed
--   avg_days_bim_ahead 30+   → AWM batch may be failing to pick up recent preference changes
--   min_days negative        → some CIF dates are NEWER than BIM (CIF is ahead for a subset)
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
  and cif.Paperless_Bil_Ind = 'N'                                                   -- genuine disagreement: CIF has record but says N
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
-- 11h: Category 2 — Missing CIF records: broken join path vs truly absent
--
-- For policies where BIM says paperless but CIF has NO record (NULL):
-- Check whether a CIF record exists in cif_policy_party_detail under a DIFFERENT party link
-- for the same policy number.
--
-- Interpret:
--   cif_records_on_other_links > 0  → join path is wrong; fix the join, not the data
--   cif_records_on_other_links = 0  → record truly absent in AWM; escalate to data team
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
-- Look for CIF records on any party link for this policy number (not just the current join path)
left join (
    select distinct
        try_cast(
            case when pa.policy_number like '% %'
                then substring(pa.policy_number, charindex(' ', pa.policy_number) + 1, len(pa.policy_number))
                else pa.policy_number
            end as bigint
        )                                                                           as policy_number_int,
        pa.policy_number
    from AWM.dbo.cif_policy_party_detail cppd
    inner join AWM.dbo.policy_party_link ppl
        on ppl.policy_party_link_id = cppd.policy_party_link_id
    inner join AWM.dbo.policy_anchor pa
        on pa.policy_anchor_id = ppl.policy_anchor_id
    where cppd.output_document_type_code = 'BIL'
      and cppd.effective_to_date          = '9999-12-31'
      and cppd.valid_to_date              = '9999-12-31'
      and cppd.paper_notify_indicator     = 0               -- only records where CIF agrees = paperless
) alt
    on alt.policy_number_int = try_cast(
           substring(b.policy_number, case when b.policy_number like 'UMB%' then 5 else 4 end, len(b.policy_number)) as bigint)
where bim.PaperlessBillInd = 'Y'
  and cif.Paperless_Bil_Ind is null                                                 -- CIF record missing on current join
group by b.policy_symbol
order by b.policy_symbol
;

----------------------------------------------------------------------------------------------------------
-- 11i: Category 3 — CIF-only opt-ins by date (integration gap spike detection)
--
-- Policies where CIF says paperless but BIM does not.
-- If a spike exists at a specific date → a one-time integration failure; can be backfilled.
-- If spread evenly → ongoing channel gap (agent portal not sending to Eloqua).
--
-- Shows top 30 opt-in dates by volume for BIL indicator.
----------------------------------------------------------------------------------------------------------

select top 30
    cast(cif.PaperlessBillDate as date)                                             as cif_opt_in_date,
    count(distinct b.policy_term_key)                                               as cif_only_policies,
    count(distinct case when b.policy_symbol = 'HO' then b.policy_term_key end)    as HO,
    count(distinct case when b.policy_symbol = 'CA' then b.policy_term_key end)    as CA,
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
-- 11j: Category 3 — CIF-only opt-ins by symbol + date band (scope for marketing/Eloqua team)
--
-- Aggregates CIF-only policies into date bands to identify if the gap is recent or long-standing.
-- Recent gaps (< 30 days) may be a processing delay; older gaps (> 90 days) are structural.
----------------------------------------------------------------------------------------------------------

select
    b.policy_symbol,
    case
        when cif.PaperlessBillDate >= dateadd(day, -30,  getdate()) then 'Last 30 days'
        when cif.PaperlessBillDate >= dateadd(day, -90,  getdate()) then '31–90 days ago'
        when cif.PaperlessBillDate >= dateadd(day, -180, getdate()) then '91–180 days ago'
        when cif.PaperlessBillDate >= dateadd(day, -365, getdate()) then '181–365 days ago'
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
        when cif.PaperlessBillDate >= dateadd(day, -90,  getdate()) then '31–90 days ago'
        when cif.PaperlessBillDate >= dateadd(day, -180, getdate()) then '91–180 days ago'
        when cif.PaperlessBillDate >= dateadd(day, -365, getdate()) then 'Over 1 year ago'
        else 'Over 1 year ago'
    end
order by b.policy_symbol, opt_in_age_band
;
