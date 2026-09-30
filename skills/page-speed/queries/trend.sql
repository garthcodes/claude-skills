-- One-row app-wide snapshot for the log's Trend table. Page-load numbers exclude
-- app-wide stall minutes (counted separately), so the trend tracks page code.
-- Usage: bin/prod-sql -v days=7 -f .claude/skills/page-speed/queries/trend.sql
\pset footer off
with stall_minutes as materialized (
  select date_trunc('minute', occurred_at) as m
  from rails_pulse_requests
  where occurred_at > now() - (:'days' || ' days')::interval and duration > 2000
  group by 1 having count(distinct controller_action) >= 3
), stall_set as materialized (
  select distinct m + k * interval '1 minute' as m from stall_minutes, generate_series(-1, 1) k
), gets as materialized (
  select q.controller_action, q.duration from rails_pulse_requests q
  left join stall_set s on s.m = date_trunc('minute', q.occurred_at)
  where q.occurred_at > now() - (:'days' || ' days')::interval
    and q.method = 'GET' and q.status between 200 and 299
    and coalesce(q.controller_action, '') <> ''
    and s.m is null
), per_action as (
  select controller_action, percentile_cont(0.95) within group (order by duration) as p95
  from gets group by 1 having count(*) >= 5
)
select (select count(*) from gets)                                                          as page_loads,
       (select round(percentile_cont(0.50) within group (order by duration)::numeric) from gets) as all_p50_ms,
       (select round(percentile_cont(0.95) within group (order by duration)::numeric) from gets) as all_p95_ms,
       (select count(*) from per_action where p95 > 1000)                                   as pages_p95_over_1s,
       (select round(sum(greatest(duration - 300, 0)) / 1000) from gets)                    as excess_wait_s,
       (select count(*) from stall_minutes)                                                 as stall_minutes;
