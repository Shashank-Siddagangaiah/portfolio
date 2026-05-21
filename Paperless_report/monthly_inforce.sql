----------------------------------------------------------------------------------------------------------
-- Initial SQL: Set variables
----------------------------------------------------------------------------------------------------------

declare @years as tinyint;
declare @calendar_start as date;
declare @calendar_end as date;
declare @now as datetime;

set @years = 5;
set @now = getdate();
set @calendar_end = cast(dateadd(day, -1, @now) as date); -- yesterday
set @calendar_start = dateadd(year, @years * -1, dateadd(year, datediff(year, 0, @calendar_end), 0)); -- year start date @years prior to yesterday


----------------------------------------------------------------------------------------------------------
-- Initial SQL: Get inforce policies
----------------------------------------------------------------------------------------------------------

drop table if exists #pol
;

select pol.exceed_policy_id
,pol.policy_term_key

    , pol.policy_number
    , pol.effective_from_date
    , pol.effective_to_date
    , pol.pemco_tenure_date
    , pol.policy_tenure_date
    , pol.term_effective_date
    , pol.term_expiration_date
    , pol.premium_ratebook_date
    , pol.new_policy_indicator
    , pol.line_of_business
    , pol.policy_symbol
    , pol.product
    , pol.policy_form
    , pol.risk_state_code
    , pol.policy_origin_type
    , pol.quote_source
    , pol.quote_source_code
    , pol.payment_plan
    , pol.payment_plan_code
    , case when cast(pol.insurance_score as integer) > 0 -- exclude "not ordered", "format reject", etc.
        then cast(pol.insurance_score as integer)
        end as insurance_score
    , case when cast(pol.insurance_score as integer) <= 0 then cast(pol.insurance_score as integer)
        when cast(pol.insurance_score as integer) < 550 then 1
        when cast(pol.insurance_score as integer) >= 900 then 900
        else floor(cast(pol.insurance_score as integer) / 50) * 50
        end as insurance_score_bin_lower_bound
    , pol.sum_term_premium_amount as term_premium_amount
	, b.mailing_address_zip_code
into #pol
from dwm.edw.vw_policy (nolock) as pol
left join (
		select
		* from
			(select 
				policy_term_key
				, policy_number
				, process_date
				,[mailing_address_zip_code]
				, row_number() over(partition by policy_term_key order by process_date desc) as rn
			  FROM [DWM].[EDW].[vw_policyholder]
			  where policyholder_type_code='NIN'
			  and process_date >= CAST(DATEADD(yy, DATEDIFF(yy, 0, DATEADD(year,-5,getdate())), 0) as date) 
			  --and policy_number = 'HO 1354401'
			  )a where rn=1
	  )b on pol.policy_term_key=b.policy_term_key
where pol.policy_inforce_indicator = 1 -- policy is inforce
    and @calendar_start < pol.effective_to_date
    and pol.effective_from_date <= @calendar_end
;
--select top 10 * from dwm.edw.vw_policy (nolock) as pol
--select * from #pol
-- =============================================
-- Create indices for #pol
-- =============================================

CREATE CLUSTERED INDEX IX_pol_exceed_policy_id
ON #pol
(
	exceed_policy_id,
   effective_from_date,
   effective_to_date
)
;

CREATE INDEX IX_pol_policy_number
ON #pol
(
	policy_number,
   effective_from_date,
   effective_to_date
)
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Get inforce policy agents
----------------------------------------------------------------------------------------------------------

drop table if exists #agt
;

select pol_agt.exceed_policy_id
    , pol_agt.effective_from_date
    , pol_agt.effective_to_date
    , coalesce(agt.agency_name, '*Unknown') as agent
    , coalesce(agt.agency_number, -1) as agent_number
    , pol_agt.agent_name as producer
    , pol_agt.agent_number as producer_number
    , pol_agt.sales_channel
into #agt
from dwm.edw.vw_policy_agent (nolock) as pol_agt
left join dwm.edw.vw_agent (nolock) as agt
    on pol_agt.agent_number = agt.producer_number
where pol_agt.policy_agent_type_code = 'AGT' -- A policy has two agents during it's first term: AGT & PGT.  See data dictionary for details.
    and pol_agt.policy_agent_inforce_indicator = 1 -- agent is inforce
    and @calendar_start < pol_agt.effective_to_date
    and pol_agt.effective_from_date <= @calendar_end
;

-- =============================================
-- Create indices for #pol
-- =============================================

CREATE CLUSTERED INDEX IX_agt_exceed_policy_id
ON #agt
(
	exceed_policy_id,
   effective_from_date,
   effective_to_date
)
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Get calendar dates
----------------------------------------------------------------------------------------------------------

drop table if exists #cal
;

select cal.calendar_date
    , cal.calendar_month_id
    , min(cal.calendar_date) over (partition by cal.calendar_month_id) as calendar_month_start_date
    , max(cal.calendar_date) over (partition by cal.calendar_month_id) as calendar_month_end_date
    , case when cal.first_day_of_month_indicator = 'Y'
        then cast(1 as bit)
        else cast(0 as bit)
        end as first_day_of_month_indicator
    , case when cal.last_day_of_month_indicator = 'Y'
        or cal.calendar_date = @calendar_end
        then cast(1 as bit)
        else cast(0 as bit)
        end as last_day_of_month_indicator
    , case when cal.first_day_of_quarter_indicator = 'Y'
        then cast(1 as bit)
        else cast(0 as bit)
        end as first_day_of_quarter_indicator
    , case when cal.last_day_of_quarter_indicator = 'Y'
        or cal.calendar_date = @calendar_end
        then cast(1 as bit)
        else cast(0 as bit)
        end as last_day_of_quarter_indicator
    , case when cal.day_of_calendar_year = 1
        then cast(1 as bit)
        else cast(0 as bit)
        end as first_day_of_year_indicator
    , case when (cal.leap_year_indicator = 0 and cal.day_of_calendar_year = 365)
        or cal.day_of_calendar_year = 366
        or cal.calendar_date = @calendar_end
        then cast(1 as bit)
        else cast(0 as bit)
        end as last_day_of_year_indicator
    , cast(cal.leap_year_indicator as bit) as leap_year_indicator
into #cal
from dwm.dim.calendar_date (nolock) as cal
where (cal.first_day_of_month_indicator = 'Y' or cal.last_day_of_month_indicator = 'Y' or cal.calendar_date = @calendar_end)
    and cal.calendar_date between @calendar_start and @calendar_end
;

----------------------------------------------------------------------------------------------------------
-- Initial SQL: Metadata
----------------------------------------------------------------------------------------------------------

drop table if exists #meta
;

select @calendar_start as inforce_start_date
    , @calendar_end as inforce_end_date
    --, dateadd(year, 1, @calendar_start) as retention_start_date
    --, @calendar_end as retention_end_date
    , dateadd(second, -1, dateadd(day, 1, cast(@calendar_end as datetime))) as data_as_of -- 11:59:59pm on @calendar_end
    , @now as query_as_of
into #meta
;