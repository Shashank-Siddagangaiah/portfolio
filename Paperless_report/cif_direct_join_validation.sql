--==========================================================================================================
-- cif_direct_join_validation.sql
-- Purpose : Validate whether CIF policy numbers now include LOB code after 4/30 data release fix
--           ("Fixed missing LOB code issue in policy numbers — table truncated and reloaded")
--           Goal: confirm direct join (policy_anchor.policy_number = base_data.policy_number)
--           works and produces the same indicators as the current stripped join.
--==========================================================================================================

----------------------------------------------------------------------------------------------------------
-- 1. CIF policy number format check
--    Expect: after the fix, nearly all rows should be 'XX XXXXXXX' (with space = LOB code present)
--    If majority have no space → fix did NOT land, keep stripped join
----------------------------------------------------------------------------------------------------------
select
    case
        when policy_number like '% %' then 'has_lob_code'      -- 'CA 0130957'
        else                               'no_lob_code'        -- '0130957'  (pre-fix format)
    end                                                          as format_type,
    count(*)                                                     as policy_anchor_count,
    count(distinct policy_number)                               as distinct_policy_numbers,
    min(policy_number)                                          as sample_min,
    max(policy_number)                                          as sample_max
from AWM.dbo.policy_anchor
group by
    case when policy_number like '% %' then 'has_lob_code' else 'no_lob_code' end
;

----------------------------------------------------------------------------------------------------------
-- 2. Sample CIF policy numbers — confirm format matches EDW policy_number format
--    EDW format: 'CA 0130957'  (2-char LOB + space + number)
--    Look at the top rows to eyeball alignment
----------------------------------------------------------------------------------------------------------
select top 20
    pa.policy_number                                             as cif_policy_number,
    case
        when pa.policy_number like '% %'
            then substring(pa.policy_number, charindex(' ', pa.policy_number) + 1, len(pa.policy_number))
        else pa.policy_number
    end                                                          as stripped,
    len(pa.policy_number)                                        as len_full,
    charindex(' ', pa.policy_number)                            as space_position
from AWM.dbo.policy_anchor pa
order by pa.policy_anchor_id
;

----------------------------------------------------------------------------------------------------------
-- 3. Indicator mismatch check: stripped join vs direct join
--    Builds both #cif_detail variants and compares Paperless_Bil_Ind / Paperless_Pol_Ind
--
--    Run AFTER confirming format check shows 'has_lob_code' is dominant (step 1)
--
--    Expected result: zero mismatches if the direct join is equivalent
----------------------------------------------------------------------------------------------------------

-- Build stripped-join CIF detail (current logic)
drop table if exists #cif_stripped;
select
    ppl.party_anchor_id,
    case
        when pa.policy_number like '% %'
            then substring(pa.policy_number, charindex(' ', pa.policy_number) + 1, len(pa.policy_number))
        else pa.policy_number
    end                                                          as policy_key,
    min(case when d.output_document_type_code = 'BIL' then d.paper_notify_indicator end) as bil_raw,
    min(case when d.output_document_type_code = 'POL' then d.paper_notify_indicator end) as pol_raw
into #cif_stripped
from (
    select
        cppd.policy_party_link_id,
        cppd.output_document_type_code,
        cppd.paper_notify_indicator,
        row_number() over (
            partition by cppd.policy_party_link_id, cppd.output_document_type_code
            order by cppd.update_date desc
        ) as rn
    from AWM.dbo.cif_policy_party_detail cppd
    where cppd.output_document_type_code in ('BIL', 'POL')
      and cppd.effective_to_date = '9999-12-31'
      and cppd.valid_to_date     = '9999-12-31'
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

-- Build direct-join CIF detail (post-fix candidate)
drop table if exists #cif_direct;
select
    ppl.party_anchor_id,
    pa.policy_number                                             as policy_key,   -- full 'CA 0130957'
    min(case when d.output_document_type_code = 'BIL' then d.paper_notify_indicator end) as bil_raw,
    min(case when d.output_document_type_code = 'POL' then d.paper_notify_indicator end) as pol_raw
into #cif_direct
from (
    select
        cppd.policy_party_link_id,
        cppd.output_document_type_code,
        cppd.paper_notify_indicator,
        row_number() over (
            partition by cppd.policy_party_link_id, cppd.output_document_type_code
            order by cppd.update_date desc
        ) as rn
    from AWM.dbo.cif_policy_party_detail cppd
    where cppd.output_document_type_code in ('BIL', 'POL')
      and cppd.effective_to_date = '9999-12-31'
      and cppd.valid_to_date     = '9999-12-31'
) d
inner join AWM.dbo.policy_party_link ppl
    on ppl.policy_party_link_id = d.policy_party_link_id
inner join AWM.dbo.policy_anchor pa
    on pa.policy_anchor_id = ppl.policy_anchor_id
where d.rn = 1
group by
    ppl.party_anchor_id,
    pa.policy_number
;

-- Summary: row counts + mismatch count
select
    'stripped_rows'   as metric, count(*) as value from #cif_stripped
union all
select 'direct_rows',            count(*) from #cif_direct
union all
select 'bil_indicator_mismatches',
    count(*)
from #cif_stripped s
inner join #cif_direct  d on d.party_anchor_id = s.party_anchor_id and d.policy_key = s.policy_key
where isnull(cast(s.bil_raw as int), -1) <> isnull(cast(d.bil_raw as int), -1)
union all
select 'pol_indicator_mismatches',
    count(*)
from #cif_stripped s
inner join #cif_direct  d on d.party_anchor_id = s.party_anchor_id and d.policy_key = s.policy_key
where isnull(cast(s.pol_raw as int), -1) <> isnull(cast(d.pol_raw as int), -1)
union all
-- Rows in stripped that don't exist in direct (unmatched by party+policy)
select 'stripped_only_rows',
    count(*)
from #cif_stripped s
where not exists (
    select 1 from #cif_direct d
    where d.party_anchor_id = s.party_anchor_id
      and d.policy_key      = s.policy_key
)
union all
-- Rows in direct that don't exist in stripped
select 'direct_only_rows',
    count(*)
from #cif_direct d
where not exists (
    select 1 from #cif_stripped s
    where s.party_anchor_id = d.party_anchor_id
      and s.policy_key      = d.policy_key
)
;

----------------------------------------------------------------------------------------------------------
-- 4. Sample mismatches (if any) — drill into what changed
--    Run only if step 3 shows non-zero mismatch counts
----------------------------------------------------------------------------------------------------------
select top 50
    s.party_anchor_id,
    s.policy_key                                                 as stripped_key,
    d.policy_key                                                 as direct_key,
    s.bil_raw                                                    as stripped_bil,
    d.bil_raw                                                    as direct_bil,
    s.pol_raw                                                    as stripped_pol,
    d.pol_raw                                                    as direct_pol
from #cif_stripped s
inner join #cif_direct d on d.party_anchor_id = s.party_anchor_id and d.policy_key = s.policy_key
where isnull(cast(s.bil_raw as int), -1) <> isnull(cast(d.bil_raw as int), -1)
   or isnull(cast(s.pol_raw as int), -1) <> isnull(cast(d.pol_raw as int), -1)
;
