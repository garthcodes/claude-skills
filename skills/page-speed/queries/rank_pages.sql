-- Rank page actions by EXCESS WAIT: total seconds people waited beyond a 300 ms target,
-- over successful GETs, with app-wide stall minutes removed. A stall = a minute in which
-- 3+ different actions each had a request over 2 s (infra, not page code); loads within
-- ±1 minute of one are excluded. stall_hits > 0 anywhere? run stalls.sql.
-- Usage: bin/prod-sql -v days=14 -v min_hits=5 -f .claude/skills/page-speed/queries/rank_pages.sql
\pset footer off
with stall_minutes as materialized (
  select date_trunc('minute', occurred_at) as m
  from rails_pulse_requests
  where occurred_at > now() - (:'days' || ' days')::interval and duration > 2000
  group by 1 having count(distinct controller_action) >= 3
), stall_set as materialized (
  select distinct m + k * interval '1 minute' as m from stall_minutes, generate_series(-1, 1) k
), tagged as (
  select q.controller_action, q.duration, (s.m is not null) as in_stall
  from rails_pulse_requests q
  left join stall_set s on s.m = date_trunc('minute', q.occurred_at)
  where q.occurred_at > now() - (:'days' || ' days')::interval
    and q.method = 'GET' and q.status between 200 and 299
    and coalesce(q.controller_action, '') <> ''
)
select controller_action as action,
       count(*) filter (where not in_stall)                                                   as hits,
       round(percentile_cont(0.50) within group (order by duration) filter (where not in_stall)::numeric) as p50_ms,
       round(percentile_cont(0.95) within group (order by duration) filter (where not in_stall)::numeric) as p95_ms,
       round(sum(greatest(duration - 300, 0)) filter (where not in_stall) / 1000)             as excess_wait_s,
       count(*) filter (where in_stall)                                                       as stall_hits,
       round(percentile_cont(0.95) within group (order by duration)::numeric)                 as raw_p95_ms
from tagged
group by 1
having count(*) filter (where not in_stall) >= :min_hits
order by excess_wait_s desc nulls last
limit 20;
