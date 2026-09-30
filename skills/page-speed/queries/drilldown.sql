-- Where the time goes for one controller action. App-wide stall minutes are excluded from every
-- section except "Slowest 5" (which shows them, so you can see what the stall did).
-- Usage: bin/prod-sql -v action='appointments#index' -v days=14 -f .claude/skills/page-speed/queries/drilldown.sql
-- Labels are normalized SQL / template paths only (capture_actual_sql is off), so no PHI.
\pset footer off
\echo '== Distribution, stall-free (Before: p50 / p95 over the window · sql_per_load over ops_loads) =='
with stall_minutes as materialized (
  select date_trunc('minute', occurred_at) as m
  from rails_pulse_requests
  where occurred_at > now() - (:'days' || ' days')::interval and duration > 2000
  group by 1 having count(distinct controller_action) >= 3
), stall_set as materialized (
  select distinct m + k * interval '1 minute' as m from stall_minutes, generate_series(-1, 1) k
), reqs as materialized (
  select q.* from rails_pulse_requests q
  left join stall_set s on s.m = date_trunc('minute', q.occurred_at)
  where q.controller_action = :'action' and q.occurred_at > now() - (:'days' || ' days')::interval
    and s.m is null and q.status between 200 and 299
)
select count(*) as hits,
       count(*) filter (where duration > 1000) as over_1s,
       round(100.0 * count(*) filter (where duration > 1000) / nullif(count(*), 0)) as pct_over_1s,
       round(percentile_cont(0.50) within group (order by duration)::numeric) as p50_ms,
       round(percentile_cont(0.75) within group (order by duration)::numeric) as p75_ms,
       round(percentile_cont(0.95) within group (order by duration)::numeric) as p95_ms,
       round(avg(response_size_bytes) / 1024) as avg_kb,
       (select count(distinct o.request_id) from rails_pulse_operations o join reqs r on r.id = o.request_id) as ops_loads,
       round((select count(*) filter (where o.operation_type = 'sql')::numeric / nullif(count(distinct o.request_id), 0)
               from rails_pulse_operations o join reqs r on r.id = o.request_id)) as sql_per_load
from reqs;

\echo '== Operation rows are capped at 100k (under a day of history): the sections below cover only =='
select to_char(min(occurred_at) at time zone 'UTC' at time zone 'America/Phoenix', 'MM/DD HH12:MI AM') || ' MST' as ops_since,
       round(extract(epoch from now() at time zone 'UTC' - min(occurred_at)) / 3600) as hours
from rails_pulse_operations;

\echo '== Time per load by operation type (stall-free; view times include SQL issued from views) =='
with stall_minutes as materialized (
  select date_trunc('minute', occurred_at) as m
  from rails_pulse_requests
  where occurred_at > now() - (:'days' || ' days')::interval and duration > 2000
  group by 1 having count(distinct controller_action) >= 3
), stall_set as materialized (
  select distinct m + k * interval '1 minute' as m from stall_minutes, generate_series(-1, 1) k
), reqs as materialized (
  select q.* from rails_pulse_requests q
  left join stall_set s on s.m = date_trunc('minute', q.occurred_at)
  where q.controller_action = :'action' and q.occurred_at > now() - (:'days' || ' days')::interval
    and s.m is null
)
select o.operation_type, round(count(*)::numeric / nullif(count(distinct o.request_id), 0), 1) as ops_per_load,
       round(sum(o.duration) / nullif(count(distinct o.request_id), 0)) as ms_per_load
from rails_pulse_operations o join reqs q on q.id = o.request_id
group by 1 order by 3 desc;

\echo '== Top 20 operations (stall-free). per_load = times per load; med_ms = typical single run; reps = N+1 repetition =='
with stall_minutes as materialized (
  select date_trunc('minute', occurred_at) as m
  from rails_pulse_requests
  where occurred_at > now() - (:'days' || ' days')::interval and duration > 2000
  group by 1 having count(distinct controller_action) >= 3
), stall_set as materialized (
  select distinct m + k * interval '1 minute' as m from stall_minutes, generate_series(-1, 1) k
), reqs as materialized (
  select q.* from rails_pulse_requests q
  left join stall_set s on s.m = date_trunc('minute', q.occurred_at)
  where q.controller_action = :'action' and q.occurred_at > now() - (:'days' || ' days')::interval
    and s.m is null
)
select o.operation_type as type, left(o.label, 100) as label, o.codebase_location as location,
       max(o.repetition_count) as reps,
       round(count(*)::numeric / nullif(count(distinct o.request_id), 0), 1) as per_load,
       round(percentile_cont(0.5) within group (order by o.duration)::numeric, 1) as med_ms,
       round(sum(o.duration) / nullif(count(distinct o.request_id), 0)) as ms_per_load
from rails_pulse_operations o join reqs q on q.id = o.request_id
where o.operation_type <> 'controller'
group by 1, 2, 3 order by 7 desc limit 20;

\echo '== Slowest 5 loads, stalls INCLUDED; other_slow = other actions >2s within 60s (high = app-wide stall) =='
select q.id, to_char(q.occurred_at at time zone 'UTC' at time zone 'America/Phoenix', 'MM/DD HH12:MI AM') || ' MST' as at_mst,
       round(q.duration) as ms, q.status, r.path,
       (select count(*) from rails_pulse_requests o
         where o.duration > 2000 and o.id <> q.id
           and coalesce(o.controller_action, '') <> q.controller_action
           and o.occurred_at between q.occurred_at - interval '60 seconds' and q.occurred_at + interval '60 seconds') as other_slow
from rails_pulse_requests q join rails_pulse_routes r on r.id = q.route_id
where q.controller_action = :'action' and q.occurred_at > now() - (:'days' || ' days')::interval
order by q.duration desc limit 5;
