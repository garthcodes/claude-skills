-- What happened during app-wide stalls: web requests vs background jobs in the same minutes.
-- Jobs slow too  -> the database (shared) is the likely bottleneck.
-- Jobs normal    -> the web machine (memory/CPU/swap) is the likely bottleneck.
-- Usage: bin/prod-sql -v days=14 -f .claude/skills/page-speed/queries/stalls.sql
-- Local times use -v tz=<IANA zone> (default UTC), e.g. -v tz=America/Chicago.
\if :{?tz}
\else
\set tz UTC
\endif
\pset footer off
with stall_minutes as (
  select date_trunc('minute', occurred_at) as m
  from rails_pulse_requests
  where occurred_at > now() - (:'days' || ' days')::interval and duration > 2000
  group by 1 having count(distinct controller_action) >= 3
)
select to_char(s.m at time zone 'UTC' at time zone :'tz', 'MM/DD HH12:MI AM') as minute_local,
       (select count(*) from rails_pulse_requests q where date_trunc('minute', q.occurred_at) = s.m) as requests,
       (select round(max(duration)) from rails_pulse_requests q where date_trunc('minute', q.occurred_at) = s.m) as worst_request_ms,
       (select count(*) from rails_pulse_job_runs j where date_trunc('minute', j.occurred_at) = s.m) as job_runs,
       (select round(percentile_cont(0.5) within group (order by j.duration)::numeric) from rails_pulse_job_runs j where date_trunc('minute', j.occurred_at) = s.m) as job_p50_ms,
       (select round(percentile_cont(0.5) within group (order by j.duration)::numeric) from rails_pulse_job_runs j
         where j.occurred_at > now() - (:'days' || ' days')::interval) as job_p50_normal_ms,
       (select left(max(revision), 12) from rails_pulse_deployments d where d.started_at between s.m - interval '15 minutes' and s.m + interval '5 minutes') as deploy_nearby
from stall_minutes s order by s.m;
