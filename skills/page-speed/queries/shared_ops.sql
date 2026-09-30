-- Costs shared across pages: the same operation (SQL shape, partial, cache key, job) seen in
-- 5+ different actions. Fixing one of these speeds up every page it appears on, which the
-- one-page rotation can't see. Ranked by total ms across all stall-free GET loads.
-- Operation rows are capped at 100k (under a day of history), so `days` barely matters here:
-- compare s_per_day, not total_s, with a page's excess_wait_s / days.
-- Usage: bin/prod-sql -v days=14 -f .claude/skills/page-speed/queries/shared_ops.sql
-- Labels are normalized SQL / template paths only (capture_actual_sql is off), so no PHI.
\pset footer off
with stall_minutes as materialized (
  select date_trunc('minute', occurred_at) as m
  from rails_pulse_requests
  where occurred_at > now() - (:'days' || ' days')::interval and duration > 2000
  group by 1 having count(distinct controller_action) >= 3
), stall_set as materialized (
  select distinct m + k * interval '1 minute' as m from stall_minutes, generate_series(-1, 1) k
), reqs as materialized (
  select q.id, q.controller_action from rails_pulse_requests q
  left join stall_set s on s.m = date_trunc('minute', q.occurred_at)
  where q.occurred_at > now() - (:'days' || ' days')::interval
    and q.method = 'GET' and q.status between 200 and 299
    and coalesce(q.controller_action, '') <> ''
    and s.m is null
)
select o.operation_type as type, left(o.label, 90) as label, o.codebase_location as location,
       count(distinct q.controller_action) as actions,
       round(count(*)::numeric / nullif(count(distinct o.request_id), 0), 1) as per_load,
       round(sum(o.duration) / nullif(count(distinct o.request_id), 0)) as ms_per_load,
       round(sum(o.duration) / 1000) as total_s,
       round((sum(o.duration) / 1000 / greatest(extract(epoch from now() at time zone 'UTC' - (select min(occurred_at) from rails_pulse_operations)) / 86400, 0.25))::numeric) as s_per_day
from rails_pulse_operations o join reqs q on q.id = o.request_id
where o.operation_type not in ('controller', 'template', 'layout')
group by 1, 2, 3
having count(distinct q.controller_action) >= 5
order by total_s desc nulls last
limit 15;
