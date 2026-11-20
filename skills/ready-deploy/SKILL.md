---
name: ready-deploy
description: Get main ready for a production deploy and walk the user through it — check local main matches origin/main, run bin/ci and report any failures, then read every PR and direct commit between the live production revision and main, work out the deploy strategy (migrations, destructive changes that need a snapshot, rake tasks or runner scripts to run, new secrets, recurring jobs, mediasoup/native/log-shipper pieces that don't ship with bin/deploy), show a short plan, and after the user says go, take them through it one step at a time, checking each step before the next. Use whenever the user says "/ready-deploy", "is main ready to deploy", "let's deploy", "ship main to prod", "what's in this deploy", "deploy plan", or asks what has to run after the next deploy, even if they don't say "ready".
---

# Ready Deploy

One run = main proven deployable → a plan built from everything that ships → the user runs each step, Claude checks it, then the next.

Claude never writes to production (CLAUDE.md "Production Safety"). Every deploy, secret, rake task and snapshot is a command the **user** runs — in their own terminal or with `! <command>` so the output lands here. Claude's job is to know what must happen, in what order, and to check each result.

## Step 1: Main matches origin

Run from the main checkout (not a worktree — `bin/deploy` refuses to ship from `.claude/worktrees/`):

```bash
git fetch origin
git rev-parse --abbrev-ref HEAD          # must be main
git status --porcelain                   # must be empty (untracked files ship into the image)
git rev-parse HEAD origin/main           # must be equal
```

Off main, dirty, ahead, behind or diverged → stop and say exactly which. Behind with a clean tree: offer `git pull --ff-only`. Never reset, stash or discard anything yourself.

## Step 2: What's live, what ships

Read production's revision from the public sign-in page (never `fly` for this):

```bash
DEPLOYED=$(curl -sL --max-time 20 "https://<app-host>/users/sign_in" \
  | grep -o '<meta name="honeybadger-revision" content="[a-f0-9]*"' | grep -o '[a-f0-9]\{40\}')
git merge-base --is-ancestor "$DEPLOYED" origin/main && echo ancestor
```

- No SHA → stop; don't guess a range.
- `DEPLOYED == HEAD` → nothing to deploy; say so and stop.
- Not an ancestor (rollback/hotfix) → stop and report.

The recording servers ship separately, so check them against main on every run, not just the range (a mediasoup change merged before `$DEPLOYED` sat undeployed on both droplets for 10 days, 10/13–10/22):

```bash
for h in deploy@<mediasoup-primary-host> deploy@<mediasoup-standby-host>; do
  REV=$(ssh -o BatchMode=yes "$h" cat /opt/mediasoup/REVISION)
  git diff --quiet "$REV" origin/main -- mediasoup/ && echo "$h current" || echo "$h BEHIND ($REV)"
done
```

Any `BEHIND` → a plan step: `bin/mediasoup-deploy production`, then `bin/mediasoup-deploy standby`, after clinic hours. A failed ssh → say the droplet couldn't be checked; don't skip it silently.

## Step 3: bin/ci

Run `bin/ci` in the background (it takes a while; don't run any other rspec while it runs). While it runs, do Step 4's reading — it doesn't depend on the result.

If it fails: report each failure (spec file:line, error, one-line likely cause, and which PR in the range touched that area). Stop there — no plan for a red main. Offer `/green-ci`. If a failure looks flaky (passes on a single rerun of that file), say so and let the user decide.

## Step 4: Read everything in the range

```bash
git log --first-parent --format='%h %s' "$DEPLOYED"..origin/main     # merges + direct pushes
git diff --stat "$DEPLOYED"..origin/main
git diff --name-only "$DEPLOYED"..origin/main
```

For each `Merge pull request #N`: `gh pr view N --json title,body,comments,files`. Read the body *and* comments — the "Cold review" and "Review decisions" comments list after-deploy chores. Direct pushes to main count too; read their diffs.

Look for every one of these; each one found becomes a plan step or a note:

| Signal | Where | What it means |
|---|---|---|
| Migrations | `db/migrate/` | `release_command` runs `db:prepare` **before** new machines start, so old code runs against the new schema briefly. Drop/rename column or table, `change_column`, `NOT NULL` on an existing column, data backfill → **destructive**: snapshot before deploy, and confirm the column is in `ignored_columns` in an earlier deploy (or the code already doesn't touch it). Big-table index without `algorithm: :concurrently`, or a long backfill → warn about lock/timeout. |
| Rake tasks / runner scripts | `lib/tasks/`, `tmp/…/*.rb`, PR body "after deploy", "run in prod", `APPLY=1` | A post-deploy step with dry run → snapshot → apply, using the go/no-go blurb from the task header or PR body. If the PR has no blurb, write one from the task's `RESULT:` line before the step. |
| New env vars | `ENV.fetch`/`ENV[` added in the diff, `config/*.yml` | Must exist before the new code boots. Run `bin/prod-secret-names` (names + status only, allow-listed) and compare. `Staged` = set but not live until the next deploy. Missing → `flyadmin secrets set --stage NAME=… -a <app-name>` **before** deploy (never plain `set`: it redeploys the old image). Derive values in-command; no placeholders. |
| Recurring jobs / queues | `config/recurring.yml`, `config/queue*.yml` | Queues must be YAML arrays, not `"a,b"`. Note new schedules; after deploy check they're registered in `/admin/jobs`. |
| Process / infra | `fly.toml`, `Dockerfile`, `Procfile`, `config/database.yml` | New process group or scale change may need `flyadmin scale …`; hand-set rootfs sizes (workers 30 GB, importer 50 GB) must survive. |
| Rails Pulse upgrade | `rails_pulse` in `Gemfile.lock` | Restart ALL processes after (not rolling). |
| Pieces bin/deploy doesn't ship | `mediasoup/`, `native/`, `log-shipper/`, `.github/` | Separate deploy (mediasoup droplet, app-store build, log-shipper app) — list it as its own step or as "not part of this deploy". Mediasoup is decided by the droplet check in Step 2, not by this range. |
| Long-running work | in-progress video meetings, legacy-system imports on `importer` | `bin/deploy` prints the meeting count; a running import resumes but say so. Suggest a quiet window if either is likely. |
| Follow-ups | HB fault ids in PRs, user-facing changes | After deploy: `/resolve-honeybadger`, `/sync-user-docs`. |

## Step 5: Show the plan, then wait

Only after bin/ci is green. A short terminal plan, no artifact page:

```
Deploy <DEPLOYED short>..<HEAD short> — N PRs, M direct commits
Risk: low | medium (migrations) | high (destructive migration / prod data change)

PRs: #880 video reconnect · #872 hotwire native app · …

| # | Step | Who runs it | Check |
|---|------|-------------|-------|
| 1 | Stage secret FOO | user | `bin/prod-secret-names FOO` shows `Staged` |
| 2 | Snapshot DB | user, then Claude watches | backup shows `completed` |
| 3 | bin/deploy production | user | "Verified: <app-name> is running <sha>" |
| 4 | Dry run foo:bar | user | RESULT: would_fix=6 errors=0 (dry run) |
| 5 | Apply foo:bar | user | RESULT: fixed=6 errors=0 |
| 6 | Smoke check | Claude | revision, HB, logs |

Not in this deploy: mediasoup/ change in #870 (droplet deploy, separate)
```

Order: staged secrets → snapshot (only if a destructive migration or a data write follows) → `bin/deploy production` → each post-deploy task (dry run → snapshot → apply) → smoke check → follow-ups. Then wait for "go" or adjustments.

## Step 6: Walk it, one step per message

For each step: say what it does in one line, give the exact command to paste (runnable as-is, no placeholders), and the go/no-go for its output. Wait for the user to run it, then check before moving on:

- **Deploy**: `bin/deploy production` (prompts for the Keychain password). Go = last lines show `Verified: <app-name> is running <HEAD sha>` and the Honeybadger notification. Re-read the revision with the curl in Step 2 — it must equal HEAD.
- **Snapshot**: `flyadmin mpg backup create <cluster-id>`. It only *queues* the backup (`Backup queued successfully!` + an id) — that is not yet a restore point. Claude then polls `fly mpg backup list <cluster-id>` (read-only token works) in the background until that id's STATUS is `completed`, and only then hands over the write step. A full backup takes several minutes. Go = `completed`; no-go = `failed`/any other end state, or still `running` after 20 min — stop and ask.
- **Rake task / runner script**: dry run first; compare its last `RESULT:` line to the blurb. Apply only on go. Then verify with a read through `bin/prod-read` / `bin/prod-sql` if a count can confirm it.
- **Smoke check** (Claude runs): revision matches HEAD; `bin/prod-logs --status 5xx --since 15m` and `bin/prod-logs --errors --since 15m`; Honeybadger `list_faults` for faults first seen since the deploy. Report anything new and which PR it likely belongs to.

Any no-go → stop the walk, say what was seen, and help decide (fix forward, rollback with `flyadmin releases`/`deploy --image <previous>`, or leave as is). Never skip ahead.

Finish with one line: what shipped (`<old>..<new>`), what ran, and any follow-up still owed.
