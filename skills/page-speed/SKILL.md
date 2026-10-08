---
name: page-speed
description: Find the page in the app where users wait the most, using production Rails Pulse data. Diagnose why it's slow, present a short plain-language plan in the terminal, and after the user says implement (or adjusts it), build the fixes (in the worktree the session is already in, e.g. one from /worktree, or a new one) through the same soundness chain as /resolve-issue (/plan → /architect-review → /code → /test-changed → /full-review → /simplify → /bug-hunt → /fix-bug-index → /merge-main → bin/ci → cold review) so the speed-up ships without new bugs, then open a PR. Keeps docs/PAGE_PERFORMANCE_LOG.md up to date so pages are worked in rotation and before/after gains are tracked. Use whenever the user asks to speed up the app, find or fix slow pages, look at Rails Pulse / page load times / p95, do a performance pass, check whether an earlier speed fix worked, or says "/page-speed", even if they don't name Rails Pulse.
argument-hint: "[controller#action to force a page | 'refresh' to only update the log]"
---

# Page Speed Rotation

One run = pick one page, find out why it's slow, show the user a 30-second plan in the terminal, and when they say so build it through a review-and-test chain that proves the page is faster *and still shows the same thing*, then record it. A speed fix that changes what a page shows is worse than a slow page, so the soundness steps (Steps 5–12) are the bulk of the run, not an afterthought. The log keeps this a rotation, so the same page isn't re-polished every run. It is also the only long-term record: Rails Pulse keeps 30 days of data, so any number not written down is lost.

All production reads go through `bin/prod-sql` (a read-only database role, allow-listed, no prompt). If the tunnel fails, ask the user to turn on WireGuard and stop. Never try another route.

## Files

| File | What it gives you |
|---|---|
| `queries/rank_pages.sql` | Pages ranked by **excess wait** (seconds users waited beyond 300 ms), with stall minutes removed. `-v days=14 -v min_hits=5` |
| `queries/drilldown.sql` | Where one page's time goes: a stall-free distribution (with `sql_per_load`), operation types, top SQL/partials with N+1 counts and file:line, slowest loads. `-v action='x#y' -v days=14` |
| `queries/shared_ops.sql` | Operations that show up on 5+ pages (tenant lookup, role checks, layout partials), ranked by total seconds. `-v days=14` |
| `queries/stalls.sql` | App-wide stall minutes, and whether jobs slowed too (DB) or not (web machine). `-v days=14` |
| `queries/page_window.sql` | Stall-free hits/p50/p95/`sql_per_load` between two UTC times, plus deploys (local time and UTC). `-v action=… -v from=… -v to=now` |
| `queries/trend.sql` | One-row app-wide snapshot for the Trend table. `-v days=7` |
| `patterns.md` | Known causes of slow pages: how each shows up in the drilldown, what to grep for, the fix. Its **How speed fixes break pages** table is the risk list every review step checks against |
| `log_template.md` | Starting content for `docs/PAGE_PERFORMANCE_LOG.md` |

Run as: `bin/prod-sql -v days=14 -v min_hits=5 -f .claude/skills/page-speed/queries/rank_pages.sql`

**Operation rows cover under two days.** Rails Pulse keeps request rows for 30 days, but it caps `rails_pulse_operations` at 100k rows (the gem default), and production writes several hundred thousand a day. So hits/p50/p95 cover the full window, while everything built from operations (the drilldown's per-operation sections, `sql_per_load`, `shared_ops.sql`) covers only since `ops_since`, which the drilldown prints. Name that shorter window in the plan ("SQL: last 40 h"), and record a Before query count at the time of the run, because it can't be recovered later.

**Why stalls are removed everywhere:** occasionally the whole app freezes for a minute or two (on 09/23 at 00:13 UTC, six pages hit 8–52 s at once). Those loads say nothing about any page's code, and they wreck p95 on low-traffic pages. A stall minute is one where 3+ different actions each had a request over 2 s. Every query here drops loads within ±1 minute of one, so rankings, before numbers and after numbers compare page code only.

## Step 0: Where the run happens

The user usually opens a worktree with `/worktree <name>` first and starts this skill inside it. Find out which case you're in before reading anything, because Steps 1–4 read the log from the checkout the run will commit to.

```bash
MAIN_DIR=$MAIN_DIR
TOP=$(git rev-parse --show-toplevel)
```

**Case A — already in a worktree** (`$TOP` is not `$MAIN_DIR`): this is the run's worktree. Never create a second one.

- `WT=$TOP`, `BRANCH=$(git -C "$WT" branch --show-current)`. Keep the branch name (`/worktree` names it after its argument, not `perf/…`). If `BRANCH` is `main` or empty (detached), stop: the PR needs its own branch.
- `/worktree` branches from the **local** `main`, which can be days behind. If the branch has no commits of its own and a clean tree (`git -C "$WT" log --oneline origin/main..HEAD` and `git status --short` both empty after `git -C "$WT" fetch origin main`), bring it up to date with `git -C "$WT" merge --ff-only origin/main`. Otherwise leave it: commits ahead will be part of the PR (say so), uncommitted changes are the user's, and `/merge-main` catches up in Step 10.
- Fill in only what's missing, never redo what's there:
  - no `.env`: `cp "$MAIN_DIR/.env" "$WT/.env" && cp -r "$MAIN_DIR/config/certs" "$WT/config/"`, then strip `DATABASE_SUFFIX=` and `PORT=` lines from the copy;
  - no `DATABASE_SUFFIX=` line: derive one from the directory name (`<app>-foo-bar` → `_foo_bar`), append it (`printf '\nDATABASE_SUFFIX=%s\n' …`, leading newline on purpose); Step 5 then creates the databases;
  - no `PORT=` line (`/worktree` doesn't assign one, so it would serve on 3001 and collide with the main checkout's server): `cd "$WT" && bin/worktree-port --assign .env`.

**Case B — in the main checkout**: Steps 1–4 read from the main checkout (after `git fetch origin main`, read the log as `git show origin/main:docs/PAGE_PERFORMANCE_LOG.md` so it's current), and Step 5 creates `.claude/worktrees/page-speed-<slug>` once the page is known.

Tell the user in one line: which case, worktree path, branch, port.

## Step 1: Settle earlier work

Read `docs/PAGE_PERFORMANCE_LOG.md` (copy `log_template.md` if it doesn't exist). Then find work the log can't see yet: `git worktree list` (any `page-speed-*` worktree, or a `../<app>-*` one whose branch touches a page's files) and `gh pr list --state open --search 'head:perf/'` plus `gh pr list --state open --search '"perf: speed up" in:title'` (runs from `/worktree` branches have other names). Those pages are `in progress` for Step 2, even without a roster row. Mention an abandoned-looking one (uncommitted changes, no PR) in the plan, but leave it alone: another session may own it.

For each roster or Shared row with status `shipped`:

1. Get the merge commit (`gh pr view <n> --json mergeCommit,mergedAt`). It is deployed once some `rails_pulse_deployments.revision` contains it (`git fetch` then `git merge-base --is-ancestor <sha> <revision>`).
2. Once it's deployed and there are ≥ 3 days and ≥ 20 hits since, run `page_window.sql` from the deploy time (`started_utc`), fill in **After** as `p50 / p95 · N q`, and set `measured`. Judge the fix mainly by `sql_per_load`. Traffic and client data keep growing (data imports), so p50 can drift up even when the fix worked, but queries per load only move when the code changes. If queries dropped and p50 didn't, say both. If neither improved, say so plainly in the run entry. That's a result too.
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

If they decline the whole plan, give the page `skip until` today + 30 days in the roster (with the reason in a one-line run entry), and put that plus the Step 1 updates on a small PR (from the worktree's branch in Case A, or a `chore/page-speed-log-<date>` branch in Case B). Otherwise the next run proposes the same page again.

The user should grasp it in about 30 seconds, so use tables and short lines, not paragraphs. Aim for about 20 lines. Explain it for a smart 18-year-old: plain words in the "why" column, with jargon defined in passing ("an N+1: one database trip per row instead of one for all rows"). Add an analogy only where it really helps, one line at most. All numbers are stall-free, and each one names its window (ranking and load times: 14 d; SQL and operations: since `ops_since`; trend: 7 d), so never mix windows in one sentence. Show times in the practice's local zone (pass `-v tz=<IANA zone>` to the queries that print times; they default to UTC) as MM/DD h:mm AM/PM, not UTC. The queries already print local-time columns, so copy those rather than converting by hand. Use this shape:

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
Risk check (patterns.md): #1 preloads only — no rows can drop · #2 SQL sum keeps the `active` scope and returns 0 for no invoices.
After **implement**: architect review → build → specs → full review → simplify → bug hunt (+ fixes) → bin/ci → PR + cold review.
Also noticed: app-wide stall 03/04 2:10 PM (jobs normal → web machine, not DB).

Reply **implement**, or tell me what to change.
```

That example is made up. It shows the shape only, so measure every number yourself.

The **Risk check** line is the plan's promise that nothing visible changes: for each change, name the row of `patterns.md`'s *How speed fixes break pages* table it falls under and why this change is safe from it. If you can't say why, the change isn't low risk, so say that in the Risk column instead.

If a user-named page turns out to be a spike, or nothing is worth doing, the "plan" is the finding plus the next-step options. Keep it just as short.

## After "implement": the soundness chain

From here the run goes end to end with no more stops, like `/resolve-issue`: the user approved the plan, and reviews the PR. Where the code can't settle a choice, take the option you'd recommend and list it in the PR under **Decisions**. Don't use AskUserQuestion.

| Step | Skill | Job |
|---|---|---|
| 5 | — | Full seed data in the worktree, and a **before snapshot** of what the page shows |
| 6 | `/plan` → `/architect-review` (→ `/frontend-review`) | Turn the approved terminal plan into a plan file; the reviews check it against the break table |
| 6 | `/code` | Build it |
| 7 | `/test-changed` + query-count specs | Every change guarded by a spec that would fail if it broke, run green |
| 8 | `/full-review` → `/simplify` | Find and fix P0–P2 findings, then clean up |
| 9 | `/bug-hunt` → `/fix-bug-index` | Click through the page against the before snapshot; fix **every** bug it finds |
| 10 | `/merge-main` → `bin/ci` (→ `/green-ci`) | Bring `origin/main` in; the whole suite green |
| 11 | — | Log, commit, PR |
| 12 | cold reviewer (`Explore` agent) | Reads the finished PR without having seen the build; `verify` points get checked, the rest becomes a PR comment |

Invoke the skills with the Skill tool. They know nothing about this skill and run unmodified. When a child skill reaches its own "final report" or "next steps", that is one step of this run, not the end of it: carry on. Their review artifacts (`.claude/reviews`, `.claude/scale-reviews`, `.claude/fix-plans`, `.claude/implementation-plan-*`, `.claude/architect-review-*`) stay uncommitted.

**Every child skill runs in the worktree.** Tell each one the worktree path (`$WT`) and branch (`$BRANCH`) and that every command must run there. A relative path, or a skill run from the main checkout, silently edits or reviews `main`. That's the most likely mistake in this skill, so double-check paths.

The early stops are the same as `/resolve-issue`'s: the fix turns out to need a different or much larger change than the plan (tell the user in two or three lines and stop), specs still red after two honest attempts, `bin/ci` still red after `/green-ci`. Everything else runs through. (A bug the hunt found that can't be fixed is not a stop: the PR opens as a draft, Step 9.)

## Step 5: Worktree data and before snapshot

**Case B only — create the worktree** (Case A already has one from Step 0):

```bash
SLUG=<action with # and / turned into ->   # e.g. appointments-index; shared-<name> for a shared cost
cd "$MAIN_DIR" && git fetch origin main
git worktree add .claude/worktrees/page-speed-$SLUG -b perf/$SLUG origin/main
WT=$MAIN_DIR/.claude/worktrees/page-speed-$SLUG; BRANCH=perf/$SLUG
cd "$WT"
cp -r ../../../config/certs ./config/ && cp ../../../.env ./.env
sed -i '' '/^DATABASE_SUFFIX=/d;/^PORT=/d' .env
# printf's leading newline matters: .env may not end in one, and a glued-on line is ignored
printf '\nDATABASE_SUFFIX=_ps_%s\n' "$(echo $SLUG | tr '-' '_' | cut -c1-24)" >> .env
# Own port (3010–3099): without it bin/dev here falls back to 3001 and collides with main
bin/worktree-port --assign .env
```

In Case A, set `SLUG` the same way (it names the bug-report folder and the CI slot); `BRANCH` stays the worktree's own.

**Both cases — load the full seed.** `/worktree` loads only `db:seed:mini`, which is too thin for this run: the bug hunt and the snapshot need enough rows for N+1s, pagination and empty-vs-full states to show. The worktree's databases are its own, so reload them, guarded:

```bash
cd "$WT" && SUFFIX=$(grep -E '^DATABASE_SUFFIX=' .env | cut -d= -f2)
# Refuse unless Rails really points at the suffixed database —
# schema:load against the shared <app>_development would wipe it.
bin/rails runner "n = ActiveRecord::Base.connection_db_config.database; abort(\"unsuffixed DB: #{n}\") unless n.end_with?(\"$SUFFIX\")" \
  && bin/rails db:create db:schema:load && bin/rails db:seed
```

`db:seed` takes ~1 min. If `bin/rails` fails on missing gems, `bundle install` in `$WT` once and retry. Never drop the `DATABASE_SUFFIX` line to get past a failure. Never share `<app>_development`/`<app>_test` with the main checkout. Use absolute `$WT` paths from here on.

**Before snapshot.** The worktree has none of this run's changes yet, so this is the one moment you can record what the page shows *before* any change. Start the worktree's server, stopping one already running there first so it picks up the new data (`cd "$WT" && nohup bin/dev > tmp/dev.log 2>&1 &`, URL from `env -u PORT bin/dev-url`) and save the visible text of the page's main content to `$WT/tmp/page-speed/before/<name>.txt` for 2–4 URLs that exercise the changed code: a long list, a filtered or second page, an empty state, and each role that sees the page differently (a therapist and an admin often see different rows). Write the URL and user at the top of each file. This is what Step 9 compares against, and it catches the worst speed-fix bug: rows that quietly vanish or a total that changes.

Browser notes (they cost minutes each to rediscover): Playwright MCP rejects the mkcert certificate on worktree servers, so use Selenium MCP headless Chrome with `--ignore-certificate-errors --allow-insecure-localhost --window-size=1280,800`. Sign in by minting a token: `bin/rails runner 'User.find_by!(email: "therapist@example.com").update_columns(magic_link_token: "ps-1", magic_link_sent_at: Time.current)'`, then visit `/passwordless/users/magic_link?email=therapist@example.com&token=ps-1`. Therapist users may have blocking CPT/outcome modals; clear them with `update_columns` in `bin/rails runner` and `Rails.cache.clear`. If no browser can reach the server, take the snapshot as the rendered HTML from an integration session in `bin/rails runner` instead, and say so in the PR.

## Step 6: Plan, review, build

1. `/plan Speed up <page> (<controller#action>) — approved plan: <the terminal plan's table rows, plus any adjustments the user made>; diagnosis: <causes with file:line>; worktree $WT, branch $BRANCH. Hard rule: no visible behaviour change. Check each change against the "How speed fixes break pages" table in .claude/skills/page-speed/patterns.md and say in the plan how each one stays safe.` Note the plan file path.
2. `/architect-review <plan path>`. Ask it to check the plan against the break table as well. Fold Critical Issues into the plan. A recommendation that widens scope (a different page, a refactor the speed-up doesn't need) goes under `## Review notes` as "not taken: <why>". A recommendation that shows a planned change can't be made safe drops that change, noted the same way and in the PR.
3. `/frontend-review <plan path>`, only if the plan touches views, components, Stimulus, Turbo Frames or Tailwind (lazy frames, pagination, moved partials).
4. `/code <plan path>` in `$WT`, with these rules on top of CLAUDE.md:
   - Only the approved changes. No refactoring nearby code the plan didn't mention.
   - `bin/rails generate migration` + `bin/rails db:migrate` in `$WT` (never hand-edit `db/schema.rb`). Large-table indexes use `algorithm: :concurrently` + `disable_ddl_transaction!`; a unique index first counts existing prod duplicates through `bin/prod-sql`. Anything destructive or a backfill ships as a dry-run-by-default rake task with CLAUDE.md's snapshot + go/no-go recipe.
   - No caching unless the approved plan has it, and then the key covers tenant, role and every field the fragment reads.
   - Leave profiling gems (`vernier`) out of the commit.

## Step 7: Specs that would catch a broken fix

Two kinds of spec, both run green:

- **Speed:** for each N+1 or repeated query, a spec counting SQL (`ActiveSupport::Notifications.subscribed(->(*){ n += 1 }, "sql.active_record") { … }`) that renders with 2 rows and with 6 and shows the count doesn't grow. For an index, put the `EXPLAIN` (through `bin/prod-sql`, no row data) in the PR instead.
- **Same output:** for each change, a spec that pins what the page or method returns, built on the break-table row it falls under: the parent with no children still listed, the soft-deleted and other-org rows still hidden, the empty-set total still `0`, an evening record in the practice's time zone on the right day. A query-count spec alone would pass on a fix that drops half the rows.

Then `/test-changed` in `$WT` (base `main`) for the changed models, services, components, policies and jobs. Run what the change touches:

```bash
cd "$WT"
bundle exec rspec <every spec added or changed, plus the existing specs of changed app files>
bin/standardrb <changed .rb files>                  # never bare `bundle exec standardrb`
npx prettier --check <changed app/javascript files>  # only if JS changed
```

`ls` every path first (one missing file aborts with "0 examples"); run `bin/rails tailwindcss:build` first if a system spec is in the list. Fix and re-run until green; something that also fails on `origin/main` is noted for the PR, not chased. Commit: `perf: <what changed>`.

## Step 8: /full-review, then /simplify

`/full-review` in `$WT`, telling it the branch is `$BRANCH`, that every command runs there, and that this is a performance-only change: any behaviour difference it spots is a P0. It fixes P0–P2 findings and leaves them uncommitted. Read its diff: keep what's about this run's code, revert the rest. Re-run the Step 7 specs and lint, commit `fix: address full-review findings`.

`/simplify` in `$WT` on the branch diff, same keep/revert rule, re-run, commit `refactor: simplify` (skip if nothing changed). Watch that it doesn't undo a speed fix in the name of simplicity (dropping a preload, inlining a memoized call back into a loop): the Step 7 query-count specs going red is the signal; revert that part.

## Step 9: /bug-hunt, then /fix-bug-index

Restart the worktree server so it runs the final code (`bin/dev` reloads code, but not migrations or initializers), then:

`/bug-hunt` with this as the feature description (Mode A, so its scope is the page and not a diff against a possibly stale local `main`):

```
Base URL: <env -u PORT bin/dev-url, run in $WT>
Output dir: $WT/docs/bug-reports/page-speed-<slug>-<YYYYMMDD-HHMMSS>
The <page name> page (<controller#action>) and everything reached from it that the
branch <BRANCH> changed: <changed views/partials/components/controllers>.
Worktree $WT; run every command there. This is a performance-only change, so ANY
difference from before is a bug:
 1. Before clicking anything, re-capture each URL in $WT/tmp/page-speed/before/ as
    the same user and diff the visible text. Rows, totals, labels, order or empty
    states that differ (other than times that moved) are High-severity bugs.
 2. Then hunt the page as usual, focusing on the ways in the "How speed fixes break
    pages" table (.claude/skills/page-speed/patterns.md): lazy-loaded parts that
    never load, pagination, filters, each role that sees the page.
Browser: Selenium MCP headless Chrome with --ignore-certificate-errors
--allow-insecure-localhost --window-size=1280,800 (Playwright rejects the cert);
sign in with a minted magic_link_token.
```

If it found nothing, note "bug hunt: clean (N pages, M interactions)" for the PR and go on.

Otherwise **every** bug and observation in its `INDEX.md` gets fixed in this PR, including ones that already exist on `origin/main`: the user wants the page left with no known bugs, not just no new ones. Don't add `[SKIP]` markers.

1. `/fix-bug-index <that INDEX.md>`, telling it the worktree and that every command runs there. It fixes each item through `/bug-hunt-fix` and leaves everything uncommitted. When it returns, carry on (its "review and commit manually" ending is for standalone runs).
2. Read its `FIX_SUMMARY.md`. Any item not fixed gets one more `/bug-hunt-fix <that BUG file>`. Still not fixed → keep going, but the PR opens as a **draft** with that bug at the top of the body, because "all bugs fixed" is this step's bar.
3. Tag each item `new` (the before snapshot or `origin/main`'s code doesn't show it, so this branch caused it) or `pre-existing`. Both get fixed; the tag goes in the PR so the reviewer knows which fixes go beyond the speed-up. Each fix keeps the page's behaviour as the user expects it; a pre-existing bug whose right behaviour is a product choice takes the option you'd recommend, under **Decisions**.
4. Every fix gets a spec that fails without it: the hunt found something the specs missed, so close that gap. Re-run the Step 7 specs, plus the new ones, and lint.
5. Commit the fixes as `fix: address bug-hunt findings`, with the bug report folder (`docs/bug-reports/` is tracked).
6. If any fix touched the page's code, re-capture the before-snapshot URLs once more: a bug fix must not undo the speed-up (Step 7's query-count specs) or change rows the snapshot shows, unless that difference *is* the fixed bug.

## Step 10: Merge main and pass bin/ci

1. `/merge-main` in `$WT`. Record the `origin/main` SHA merged.
2. `bin/ci` in `$WT`, one at a time on this machine, holding the shared CI slot:

```bash
"$MAIN_DIR/.claude/skills/resolve-issues/scripts/ci-slot" acquire page-speed-$SLUG   # run in the background; it wakes you when the slot is yours
cd "$WT" && bin/ci > tmp/ci.log 2>&1
"$MAIN_DIR/.claude/skills/resolve-issues/scripts/ci-slot" release page-speed-$SLUG   # after the last bin/ci of this step, red or green
```

Read `tmp/ci.log` afterwards (`grep -nE "examples,|^rspec \./|Failures:|FAILED|error" tmp/ci.log`); never pipe a running `bin/ci` through `grep`/`tail`.

3. Red: `/green-ci` in `$WT`, commit as `test: get bin/ci green`, run `bin/ci` once more. Still red: **no PR**. Report the failing specs with their output and stop.

Never trigger GitHub Actions (`gh workflow run`, `gh run rerun`, …). The user runs CI on GitHub.

## Step 11: Log, push, PR

Edit `docs/PAGE_PERFORMANCE_LOG.md` on the branch:

- **Roster:** the page's row gets `Last worked` = today, status `shipped`, **Before** = `p50 / p95 · N q` from the drilldown's stall-free distribution, and the PR number (it exists only after `gh pr create`, so add it then in a small follow-up commit and push). Add or refresh rows for pages marked `spike`, or `watch` for pages noticed in passing.
- **Shared:** add the Shared section from `log_template.md` if the log doesn't have one yet. A shared-cost run updates its row the same way (Before = its `ms_per_load` and `per_load` from `shared_ops.sql`). Add `watch` rows for shared costs you noticed.
- **Runs:** a new entry at the top, **four lines max**, each one sentence (template in the file). The PR holds the detail.
- Include the Step 1 updates.

Stage specific paths (never `-A`; never the review artifacts or `tmp/`), end each commit message with the session's attribution line, push, and open the PR:

```bash
cd "$WT" && git push -u origin $BRANCH
gh pr create --title "perf: speed up <page name>" --body-file <scratchpad>/page-speed-$SLUG-pr.md
```

```markdown
## Why
<page> (<controller#action>): typical <p50> · p95 <p95> · <N> q/load, stall-free, <window>.

## What
| # | Change | Saves | Where |
|---|---|---|---|

## Same output
| # | Break risk (patterns.md) | Guarded by |
|---|---|---|

## Decisions
<choices the plan left open, with the option taken — or "none">. Dropped by the user or the reviews: <…>

## Reviews
- architect: <ok | N folded in> · frontend: <ok | skipped: no UI>
- /full-review: <n> fixed, <n> left (P3) · /simplify: <n files | no changes>
- bug hunt: <clean | n found (n new, n pre-existing), all fixed | n unfixed → draft> — `docs/bug-reports/<dir>/`
- before snapshot: <identical | differences, all fixed>
- cold review: posted as a comment on this PR

## Tests
- query-count + same-output specs: <files> — pass
- /test-changed: <files> · `bin/standardrb` — pass
- `bin/ci` green after merging origin/main (<sha>)

## Deploy
<"additive, no data change" | the index/migration notes, and CLAUDE.md's snapshot + go/no-go recipe if data changes>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## Step 12: Cold review

Follow `.claude/skills/resolve-issue/references/cold-review.md` with:

- `<WHAT>`: "made a performance-only change to <page>"; `<WT>`: `$WT`; slug `page-speed-$SLUG`
- `<ASK>`: `1. $MAIN_DIR/.claude/skills/page-speed/patterns.md, the "How speed fixes break pages" table: check the diff against every row`
- `<NOTES>`: what the speed claim rests on (the drilldown numbers, the ops window), which break-table risks each change carries and how you ruled them out, what you did not verify (a role you didn't snapshot, data the seeds don't have, such as legacy-system-imported records), decisions, and anything noticed outside this page
- `<FOCUS>`: "A speed fix that changes what the page shows, or who can see it, is the failure that matters most here."
- `<STOP>`: "the PR changes behaviour, not just speed". Merging a behaviour change dressed as a speed fix is the outcome this whole chain exists to prevent.
- `<RECHECK>`: add the spec that settles it, re-run Step 7's specs and lint, and re-run `bin/ci` (Step 10.2) because app code changed

## Step 13: Hand off

Keep the worktree (the user tests in it; `/worktree-sweep` cleans up later) and its server running. In Case B, open it (in Case A it's already open):

```bash
open -n -a "Visual Studio Code" "$WT"
```

Finish with these lines and nothing else: the PR link (say "draft" and why if Step 9 left a bug unfixed or Step 12 stopped it); the worktree's URL (`cd "$WT" && env -u PORT bin/dev-url`); the chain's counts (architect, full-review, simplify, bug hunt found/new/pre-existing/fixed, before snapshot identical or not); `bin/ci` green against which main SHA, plus anything skipped and why; the cold review (comment link, tag counts, what each `verify` check found); what's next in the rotation.

## Guardrails

- Production is read-only here, always: `bin/prod-sql` / `bin/prod-read` only. No `bin/rails console`, no `fly ssh`.
- Keep PHI out of the plan, the log, the PR and your output. Rails Pulse labels are normalized SQL and template paths, which is fine; never select row data from app tables in production. The before snapshots are local seed data and stay in `tmp/`.
- One worktree per run: the one the session is in, or the one Step 5 creates. One page (or one shared cost) per run. Put other slow pages you notice in the roster as `watch`.
- One stop for the user: the plan. After "implement", the only early stops are the three under *After "implement"*.
- Never `bin/ci` in parallel with another (hold the CI slot), and never trigger GitHub Actions.
- The cold review decides nothing for the user: it files no issues and changes no scope. Only `verify` checks (and the fix when one fails) happen on their own.
