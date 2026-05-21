----------------------------------------------------------------------------------------------------------
-- self_service_accounts.sql
-- Purpose : Pull all inforce policies where the policyholder has an active Self-Service Account (SSA)
-- Grain   : One row per policy term (policy_term_key)
-- Source  : AWM.dbo.party_user_account_link + asp_user_account_detail
-- Note    : is_up_and_running_indicator = 255 (tinyint, NOT 1) means active account
----------------------------------------------------------------------------------------------------------

declare @as_of_date as date;
set @as_of_date = cast(dateadd(day, -1, getdate()) as date);

----------------------------------------------------------------------------------------------------------
-- Step 1: Inforce policies (as of yesterday)
----------------------------------------------------------------------------------------------------------

drop table if exists #ssa_policy;

select
    p.policy_term_key,
    p.policy_number,
    p.line_of_business,
    p.risk_state_code,
    p.effective_from_date,
    p.effective_to_date,
    p.policy_inforce_indicator
into #ssa_policy
from DWM.EDW.vw_policy p
where p.effective_from_date <= @as_of_date
  and p.effective_to_date   >  @as_of_date
;

----------------------------------------------------------------------------------------------------------
-- Step 2: Policyholder party_key per policy — one row per policy_term_key
-- Dedup: NIN (head of household) preferred over ANI; tiebreak by party_key DESC
-- join on policy_term_key ONLY — adding date conditions drops ~35k mid-term endorsement policies
----------------------------------------------------------------------------------------------------------

drop table if exists #ssa_party;

select
    it.policy_term_key,
    it.policy_number,
    it.line_of_business,
    it.risk_state_code,
    it.effective_from_date,
    it.effective_to_date,
    vph.party_key,
    vph.full_name,
    vph.policyholder_type_code
into #ssa_party
from #ssa_policy it
left join (
    select
        policy_term_key,
        party_key,
        full_name,
        policyholder_type_code,
        row_number() over (
            partition by policy_term_key
            order by
                case when policyholder_type_code = 'NIN' then 0 else 1 end,  -- NIN first
                party_key desc                                                 -- tiebreak
        ) as rn_ph
    from DWM.EDW.vw_policyholder
) vph
    on vph.policy_term_key = it.policy_term_key
   and vph.rn_ph = 1
;

----------------------------------------------------------------------------------------------------------
-- Step 3: AWM duplicate party anchor (bridge from EDW party_key to AWM party_anchor_id)
----------------------------------------------------------------------------------------------------------

drop table if exists #ssa_bridge;

select
    sp.policy_term_key,
    sp.policy_number,
    sp.line_of_business,
    sp.risk_state_code,
    sp.party_key,
    sp.full_name,
    sp.policyholder_type_code,
    pta.party_anchor_id as duplicate_party_anchor_id
into #ssa_bridge
from #ssa_party sp
left join (
    select
        party_anchor_id_master,
        party_anchor_id_duplicate,
        row_number() over (
            partition by party_anchor_id_master
            order by party_anchor_id_duplicate desc
        ) as rn
    from AWM.dbo.party_id_same_as_link
) pil
    on pil.party_anchor_id_master = sp.party_key
   and pil.rn = 1
left join AWM.dbo.party_anchor pta
    on pta.party_anchor_id = pil.party_anchor_id_duplicate
;

----------------------------------------------------------------------------------------------------------
-- Step 4: Active SSA accounts — one row per party_anchor_id
-- is_up_and_running_indicator = 255 (tinyint active flag, NOT 1)
-- Excludes known bad anchor IDs
----------------------------------------------------------------------------------------------------------

drop table if exists #ssa_accounts;

select
    l.party_anchor_id,
    a.user_name,
    a.is_anonymous_indicator,
    a.is_up_and_running_indicator,
    a.valid_from_date    as ssa_valid_from_date,
    a.valid_to_date      as ssa_valid_to_date,
    row_number() over (
        partition by l.party_anchor_id
        order by a.valid_from_date desc, a.valid_to_date desc
    ) as rn
into #ssa_accounts
from AWM.dbo.party_user_account_link l
inner join AWM.dbo.asp_user_account_detail a
    on a.party_user_account_link_id = l.party_user_account_link_id
where l.party_anchor_id not in ('7771543', '13322119')  -- known bad anchors
  and a.is_up_and_running_indicator = 255               -- active SSA (tinyint, NOT 1)
;

----------------------------------------------------------------------------------------------------------
-- Step 4b: Deduplicate to one username per party_anchor_id before joining
-- Materialising here prevents fan-out in the final SELECT
----------------------------------------------------------------------------------------------------------

drop table if exists #ssa_usernames;

select
    party_anchor_id,
    user_name,
    ssa_valid_from_date,
    ssa_valid_to_date
into #ssa_usernames
from #ssa_accounts
where rn = 1
;

----------------------------------------------------------------------------------------------------------
-- Output: Inforce policies with an active Self-Service Account
----------------------------------------------------------------------------------------------------------

select
    b.policy_term_key,
    b.policy_number,
    b.line_of_business,
    b.risk_state_code,
    b.party_key,
    b.full_name,
    b.policyholder_type_code,
    b.duplicate_party_anchor_id,
    su.user_name           as SSAUserName,
    su.ssa_valid_from_date as SSACreateDate,
    'Y'                    as SelfServiceInd
from #ssa_bridge b
inner join #ssa_usernames su  -- guaranteed 1 row per party_anchor_id — no fan-out
    on su.party_anchor_id = b.duplicate_party_anchor_id
order by b.policy_number
;
