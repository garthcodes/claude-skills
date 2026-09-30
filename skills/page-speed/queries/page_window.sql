-- Before/after numbers for one action between two timestamps, app-wide stall minutes excluded.
-- sql_per_load (database trips per load) is the fairest before/after signal: it doesn't move with
-- traffic mix or data growth the way p50 does, and it's what most fixes here change. It only
-- covers the last ~day (operation rows are capped), so read it only when ops_loads >= 20.
-- Usage: bin/prod-sql -v action='charts#show' -v from='2026-10-01 00:00' -v to=now -f .claude/skills/page-speed/queries/page_window.sql
-- from/to are UTC (rails_pulse_deployments.started_at is UTC).
\pset footer off
with win as (
  select :'from'::timestamp as lo, (case when :'to' = 'now' then now()::timestamp else :'to'::timestamp end) as hi
), stall_minutes as materialized (
  select date_trunc('minute', occurred_at) as m
  from rails_pulse_requests, win
  where occurred_at >= win.lo and occurred_at < win.hi and duration > 2000
  group by 1 having count(distinct controller_action) >= 3
), stall_set as materialized (
  select distinct m + k * interval '1 minute' as m from stall_minutes, generate_series(-1, 1) k
), reqs as materialized (
  select q.id, q.duration
  from rails_pulse_requests q
  cross join win
  left join stall_set s on s.m = date_trunc('minute', q.occurred_at)
  where q.controller_action = :'action'
    and q.method = 'GET' and q.status between 200 and 299
    and q.occurred_at >= win.lo and q.occurred_at < win.hi
    and s.m is null
), ops as (
  -- Operation rows are capped (100k, nightly cleanup: under a day of history), so per-load SQL
  -- numbers come only from loads that still have operation rows (ops_loads).
  select count(distinct o.request_id) as loads,
         count(*) filter (where o.operation_type = 'sql') as n,
         sum(o.duration) filter (where o.operation_type = 'sql') as ms
  from rails_pulse_operations o join reqs q on q.id = o.request_id
)
select (select count(*) from reqs) as hits,
       (select round(percentile_cont(0.50) within group (order by duration)::numeric) from reqs) as p50_ms,
       (select round(percentile_cont(0.95) within group (order by duration)::numeric) from reqs) as p95_ms,
       (select count(*) from reqs where duration > 1000) as over_1s,
       (select loads from ops) as ops_loads,
       (select round(n::numeric / nullif(loads, 0)) from ops) as sql_per_load,
       (select round(ms / nullif(loads, 0)) from ops) as sql_ms_per_load;

\echo '== Deploys since from (MST) =='
select id, left(revision, 12) as revision,
       to_char(started_at at time zone 'UTC' at time zone 'America/Phoenix', 'MM/DD HH12:MI AM') || ' MST' as started_mst,
       started_at as started_utc
from rails_pulse_deployments
where started_at >= :'from'::timestamp order by started_at;
