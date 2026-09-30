---
name: page-speed
description: Find the page in the app where users wait the most, using production Rails Pulse data. Diagnose why it's slow, present a short plain-language plan in the terminal, and after the user says implement (or adjusts it), make the fixes on a branch and open a PR. Keeps docs/PAGE_PERFORMANCE_LOG.md up to date so pages are worked in rotation and before/after gains are tracked. Use whenever the user asks to speed up the app, find or fix slow pages, look at Rails Pulse / page load times / p95, do a performance pass, check whether an earlier speed fix worked, or says "/page-speed", even if they don't name Rails Pulse.
argument-hint: "[controller#action to force a page | 'refresh' to only update the log]"
---

# Page Speed Rotation

One run = pick one page, find out why it's slow, show the user a 30-second plan in the terminal, implement it when they say so, and record it. The log keeps this a rotation, so the same page isn't re-polished every run. It is also the only long-term record: Rails Pulse keeps 30 days of data, so any number not written down is lost.

All production reads go through `bin/prod-sql` (read-only `claude-ro`, allow-listed, no prompt). If the tunnel fails, ask the user to turn on WireGuard and stop. Never try another route.

## Files

| File | What it gives you |
|---|---|
| `queries/rank_pages.sql` | Pages ranked by **excess wait** (seconds users waited beyond 300 ms), with stall minutes removed. `-v days=14 -v min_hits=5` |
| `queries/drilldown.sql` | Where one page's time goes: a stall-free distribution (with `sql_per_load`), operation types, top SQL/partials with N+1 counts and file:line, slowest loads. `-v action='x#y' -v days=14` |
| `queries/shared_ops.sql` | Operations that show up on 5+ pages (tenant lookup, role checks, layout partials), ranked by total seconds. `-v days=14` |
| `queries/stalls.sql` | App-wide stall minutes, and whether jobs slowed too (DB) or not (web machine). `-v days=14` |
| `queries/page_window.sql` | Stall-free hits/p50/p95/`sql_per_load` between two UTC times, plus deploys (MST and UTC). `-v action=… -v from=… -v to=now` |
| `queries/trend.sql` | One-row app-wide snapshot for the Trend table. `-v days=7` |
| `patterns.md` | Known causes of slow pages: how each shows up in the drilldown, what to grep for, the fix |
| `log_template.md` | Starting content for `docs/PAGE_PERFORMANCE_LOG.md` |

Run as: `bin/prod-sql -v days=14 -v min_hits=5 -f .claude/skills/page-speed/queries/rank_pages.sql`

**Operation rows cover under two days.** Rails Pulse keeps request rows for 30 days, but it caps `rails_pulse_operations` at 100k rows (the gem default), and production writes several hundred thousand a day. So hits/p50/p95 cover the full window, while everything built from operations (the drilldown's per-operation sections, `sql_per_load`, `shared_ops.sql`) covers only since `ops_since`, which the drilldown prints. Name that shorter window in the plan ("SQL: last 40 h"), and record a Before query count at the time of the run, because it can't be recovered later.

**Why stalls are removed everywhere:** occasionally the whole app freezes for a minute or two (on 09/23 at 00:13 UTC, six pages hit 8–52 s at once). Those loads say nothing about any page's code, and they wreck p95 on low-traffic pages. A stall minute is one where 3+ different actions each had a request over 2 s. Every query here drops loads within ±1 minute of one, so rankings, before numbers and after numbers compare page code only.

## Step 1: Settle earlier work

Read `docs/PAGE_PERFORMANCE_LOG.md` (copy `log_template.md` if it doesn't exist). Then find work the log can't see yet: `git worktree list | grep page-speed-` and `gh pr list --state open --search 'head:perf/'`. Those pages are `in progress` for Step 2, even without a roster row. Mention an abandoned-looking one (uncommitted changes, no PR) in the plan, but leave it alone: another session may own it.

For each roster or Shared row with status `shipped`:

1. Get the merge commit (`gh pr view <n> --json mergeCommit,mergedAt`). It is deployed once some `rails_pulse_deployments.revision` contains it (`git fetch` then `git merge-base --is-ancestor <sha> <revision>`).
2. Once it's deployed and there are ≥ 3 days and ≥ 20 hits since, run `page_window.sql` from the deploy time (`started_utc`), fill in **After** as `p50 / p95 · N q`, and set `measured`. Judge the fix mainly by `sql_per_load`. Traffic and client data keep growing (SP imports), so p50 can drift up even when the fix worked, but queries per load only move when the code changes. If queries dropped and p50 didn't, say both. If neither improved, say so plainly in the run entry. That's a result too.
3. Otherwise leave it as `shipped`.

`sql_per_load` needs `ops_loads` ≥ 20. A Before logged without `· q` can't be backfilled because the operation rows are gone, so compare p50/p95 only and say so.

Run `trend.sql` and add a Trend row. If today already has one, replace it: one row per date keeps the trend readable. If the argument is `refresh`, stop here: open a small PR with the log change.

## Step 2: Pick the page

Run `rank_pages.sql`. It orders pages by excess wait, which weighs both how slow a page is and how often people open it. A 1-second page opened 200 times a day beats a 4-second page opened twice. Take the first **eligible** row:

- Not worked in the last 14 days, and not `in progress`/`shipped` within 14 days. A fix needs time in production before it can be judged.
- Not `skip until` a future date.
- **Worth doing.** If the best eligible page has a p50 under ~300 ms and a p95 under ~1 s, the app is in good shape. Say so, log the trend, and stop without a PR. Don't invent work to fill the run.

Also run `shared_ops.sql`. A cost that sits on 5+ pages (a policy role check, the tenant lookup, a layout partial) never tops the page ranking, yet fixing it once speeds up every page. #419's role memoization was found this way only by luck. If the top shared op not already `shipped` or resting in the log's Shared table has `s_per_day` above the chosen page's `excess_wait_s / 14`, and its location points at code you can fix without changing behaviour, make it this run's target instead. Say why in the "Picked" line. Otherwise mention it under "Also noticed" and add it to the Shared table as `watch`. The two numbers aren't the same measure (`s_per_day` counts all the op's time, excess wait only counts time beyond 300 ms), so only switch on a clear margin (≥ ~1.5×). A shared cost that a deploy since the data window already fixed will look big until the window rolls past it, so check the log first.

If any row has `stall_hits > 0`, run `stalls.sql` once and mention in the plan what it shows: the minutes, whether jobs slowed down too, and whether a deploy was nearby. The stall isn't this run's page, but the user should know about it. "Web machine, jobs normal" most likely means requests were waiting for a free Puma thread (2 workers × 5 threads). Rails Pulse doesn't count that wait, so call it a capacity issue, not page code.

**Page named by the user:** use it and skip the rotation checks. If its stall-free numbers show it's actually fast (the raw p95 came from stalls), say so. Mark it `spike` (skip 14 days) and offer two next steps: run the normal rotation, or look into the stall. Only propose a fix for it if a real steady-state cost shows up (≥ ~20% of its p50).

## Step 3: Diagnose

Run `drilldown.sql` for the page, then read the code it points at: `codebase_location` for SQL, and template/partial paths for rendering.

- **Where does the time go?** Controller time contains everything. SQL, template and partial times overlap because views issue queries. For the plan's headline, use `sql` ms per load; the rest of controller time is Ruby and page drawing. Judge an operation by `med_ms` (typical single run) as well as `ms_per_load`: a big average with a tiny median is one outlier, not a steady cost.
- **N+1:** `reps` > 1, or `per_load` far above 1 for one SELECT. Find the loop and the association it touches. A common trap: a preload on one association while the view reads a different one.
- **Single slow query:** high `med_ms` with `per_load` ≈ 1. Check `db/schema.rb` for the index, and use `EXPLAIN` through `bin/prod-sql` if needed. Never select row data.
- **Shared costs** (layout, `ApplicationController` before_actions, tenant lookup, policy role queries, cache writes on the request path) slow every page. Put them under "Also noticed" and in the log's Shared table, so they get picked in a later run instead of being forgotten.
- **Check the hot files against `patterns.md`.** Many N+1s hide behind an `includes` that is already there (`count`, `exists?`, or a scope called per row).
- **Ruby time:** if controller ms is well above SQL + view ms and no `http`/`job` op explains it, profile before guessing. In the worktree only, add `vernier` (never commit it), profile one load, and read the flamegraph.
- **Cache last:** propose caching only after the queries and wasted work are gone, and only if rendering is still the main cost. Never cache anything that renders in under ~10–20 ms, since a Solid Cache read is itself a database trip.
- Run `git log --oneline -10 -- <file>` on the hot files to check for recent changes.

Pick 1–4 changes, ranked by ms saved per load and by risk. Leave out anything saving under ~50 ms unless it's trivial.

## Step 4: Present the plan and wait

Write the plan in the terminal and **stop**. The user replies "implement", or tells you what to adjust. Don't ask for approval per change, don't use AskUserQuestion, and don't start Step 5 until they say to. If they adjust, apply it and show only what changed. Re-show the whole plan only if it changed a lot.

If they decline the whole plan, give the page `skip until` today + 30 days in the roster (with the reason in a one-line run entry), and put that plus the Step 1 updates on a small `chore/page-speed-log-<date>` PR. Otherwise the next run proposes the same page again.

The user should grasp it in about 30 seconds, so use tables and short lines, not paragraphs. Aim for about 20 lines. Explain it for a smart 18-year-old: plain words in the "why" column, with jargon defined in passing ("an N+1: one database trip per row instead of one for all rows"). Add an analogy only where it really helps, one line at most. All numbers are stall-free, and each one names its window (ranking and load times: 14 d; SQL and operations: since `ops_since`; trend: 7 d), so never mix windows in one sentence. Show times in the practice's local zone (the queries use America/Phoenix — change it to yours) as MM/DD h:mm AM/PM, not UTC. The queries already print local-time columns, so copy those rather than converting by hand. Use this shape:

```
**Client list** (`clients#index`): typical 0.9 s · 1 in 20 over 2.6 s · 41% of loads over 1 s · 140 loads / 14 d
Picked: most waiting in the app (96 s / 14 d). Skipped: Chart (resting), Invoice (spike).

**Why it's slow** (SQL: last 40 h): 180 database trips and ~520 ms of SQL per load
| Cause | Where | Cost / load |
|---|---|---|
| Each row looks up its therapist separately (an N+1: one trip per row, not one for all) | `clients/index.html.erb:40` | ~50 trips |
| Balance summed in Ruby after loading every invoice | `client.rb:212` | ~300 ms |

**Plan**
| # | Change | Saves | Risk |
|---|---|---|---|
| 1 | Preload therapists with the client list | ~250 ms | low |
| 2 | Sum balances in one SQL query | ~300 ms | low |

Expected: 0.9 s → ~0.4 s typical. Each change gets a spec proving the query count no longer grows with rows.
Also noticed: app-wide stall 03/04 2:10 PM MST (jobs normal → web machine, not DB).

Reply **implement**, or tell me what to change.
```

That example is made up. It shows the shape only, so measure every number yourself.

If a user-named page turns out to be a spike, or nothing is worth doing, the "plan" is the finding plus the next-step options. Keep it just as short.

## Step 5: Implement (after the user says so)

Work in a worktree so `main` stays clean:

```bash
SLUG=<action with # and / turned into ->   # e.g. appointments-index; shared-<name> for a shared cost
cd $MAIN_DIR && git fetch origin main
git worktree add .claude/worktrees/page-speed-$SLUG -b perf/$SLUG origin/main
cd .claude/worktrees/page-speed-$SLUG
cp -r ../../../config/certs ./config/ && cp ../../../.env ./.env
sed -i '' '/^DATABASE_SUFFIX=/d;/^PORT=/d' .env
# printf's leading newline matters: .env may not end in one, and a glued-on line is ignored
printf '\nDATABASE_SUFFIX=_ps_%s\n' "$(echo $SLUG | tr '-' '_' | cut -c1-24)" >> .env
# Own port (3010–3099): without it bin/dev here falls back to 3001 and collides with main
PORT=$(bin/worktree-port --assign .env)
# Refuse to load a schema unless Rails really points at the suffixed database —
# schema:load on the main <app>_development wipes it.
bin/rails runner 'n = ActiveRecord::Base.connection_db_config.database; abort("unsuffixed DB: #{n}") unless n.include?("_ps_")' \
  && bin/rails db:create db:schema:load && bin/rails db:seed:mini
```

`db:seed:mini` is enough to click through the page. When the fix needs realistic volume to show a
before/after locally (N+1s, pagination), run the full `bin/rails db:seed` (~10 min) instead.

Never share `<app>_development`/`<app>_test` with the main checkout. Use absolute worktree paths from here on.

- Follow CLAUDE.md: `bin/rails generate migration` (never hand-edit `db/schema.rb`), `includes`/`preload` for N+1s, scopes for query logic, no visible behaviour change.
- Prod has live data: large-table indexes use `algorithm: :concurrently` + `disable_ddl_transaction!`. Anything destructive or a backfill gets CLAUDE.md's snapshot + go/no-go recipe.
- **Back each fix with a spec, but don't run it.** Write a spec counting SQL (`ActiveSupport::Notifications.subscribed(->(*){ n += 1 }, "sql.active_record") { … }`) that shows the count no longer grows with rows, so the N+1 can't come back. For an index, show `EXPLAIN` through `bin/prod-sql`. Don't run specs, `bin/standardrb` or `bin/ci`, and don't time the page locally: the user tests in the worktree.
- Commit, push, and open a PR titled `perf: speed up <page name>`. Body: the plan table, the stall-free baseline, each fix with its spec (written, not run), anything the user dropped, and deploy notes.

## Step 6: Update the log

On the same branch, edit `docs/PAGE_PERFORMANCE_LOG.md`:

- **Roster:** the page's row gets `Last worked` = today, status `shipped`, **Before** = `p50 / p95 · N q` from the drilldown's stall-free distribution, and the PR. Add or refresh rows for pages marked `spike`, or `watch` for pages noticed in passing.
- **Shared:** add the Shared section from `log_template.md` if the log doesn't have one yet. A shared-cost run updates its row the same way (Before = its `ms_per_load` and `per_load` from `shared_ops.sql`). Add `watch` rows for shared costs you noticed.
- **Runs:** a new entry at the top, **four lines max**, each one sentence (template in the file). The PR holds the detail.
- Include the Step 1 updates.

Commit and push the log change. Then open the worktree in a new VS Code window:

```bash
open -n -a "Visual Studio Code" $MAIN_DIR/.claude/worktrees/page-speed-$SLUG
```

Finish with a 3-line terminal summary: what shipped, the PR link and the worktree's `https://localhost:$PORT` for testing, and what's next in the rotation.

## Guardrails

- Production is read-only here, always. No `bin/rails console`, no `fly ssh`.
- Keep PHI out of the plan, the log and your output. Rails Pulse labels are normalized SQL and template paths, which is fine; never select row data from app tables.
- One page (or one shared cost) per run. Put other slow pages you notice in the roster as `watch`.
