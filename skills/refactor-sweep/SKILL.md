---
name: refactor-sweep
description: Refactor the application one target at a time toward the sustainability rules (app/services/CLAUDE.md, app/models/CLAUDE.md, app/jobs/CLAUDE.md, app/controllers/CLAUDE.md, app/views/CLAUDE.md, db/migrate/CLAUDE.md) — moving side-effect callbacks and workflow methods out of fat models into services, converting legacy Callable services to noun classes with verb methods, slimming fat jobs, and fixing smaller rule breaks (partials without strict locals, member routes, uniqueness validations without a unique index). Each run picks the top target from a ranked, resumable queue (or the one named), takes it to its own worktree, locks today's behavior with specs proven on the old code, audits every caller, then runs the /resolve-issue chain (/plan → /architect-review → /code → /test-changed → /full-review → /simplify → /merge-main → bin/ci → cold review) and opens one PR with no approval stops. Use whenever the user says "/refactor-sweep", "refactor the next thing", "keep chipping away at the fat models", "move Appointment's callbacks into a service", "convert this Callable service", "pay down some tech debt", or asks to make existing code follow the CLAUDE.md sustainability rules. For tests use /spec-sweep; for a GitHub issue use /resolve-issue.
argument-hint: '[target-id | kind | --dry-run | --list]'
---

# Refactor Sweep

One run = one target → one worktree → behavior locked → one reviewed, CI-green PR that changes **structure, not behavior**.

A refactor's whole promise is that nothing a user, a record, a job queue or an outside system sees is different afterwards. Production is live with real client data, so this skill spends most of its effort proving that promise. It does that in two ways that `/resolve-issue` doesn't have:

- **Behavior lock**: specs that pin every observable effect of the code being moved, proven green on the old code *before* any change, and passing unchanged afterwards.
- **Caller audit**: a table of every path that reaches the moved code, including the indirect ones grep misses, each with its status after the change.

You are the coordinator. There are **no approval stops**: the plan is printed for the record and the run continues. The user reviews the PR. Don't use AskUserQuestion. Where the code can't settle a choice, take the option that keeps behavior identical and list it under **Decisions** in the PR.

## Arguments

- none: take the top open target from the queue;
- a target id (`callback:Appointment[calendar]`, `callable:ValidateClaimService`, …): take that one;
- a kind (`callback`, `model_logic`, `callable`, `fat_job`, `locals`, `route`, `unique_index`): take the top target of that kind;
- `--list`: print the queue (top 20) and stop;
- `--dry-run`: run Steps 1–4 (pick, worktree, investigate and audit, plan) and stop before any code changes.

## Variables

```
MAIN_DIR = $(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
SKILLS   = $MAIN_DIR/.claude/skills
LEDGER   = .claude/audits/refactor-sweep/ledger.jsonl   (tracked in git; relative to the checkout)
WT, BRANCH, SLUG = resolved in Step 2
```

From Step 2 on, every read, edit, search, test, lint, git and skill command uses absolute `$WT` paths. Tell every child skill the worktree path and branch and that every command runs there. A skill run from the main checkout silently edits `main`; that is the easiest mistake to make here.

## The rules being enforced

Read these once per run; the target's rule is the plan's yardstick and the PR quotes it:

| Kind | Rule file | What "done" looks like |
|---|---|---|
| `callback` | `app/models/CLAUDE.md` | the model no longer enqueues/sends/broadcasts/calls out; a service does, called from every path that used to trigger it |
| `model_logic` | `app/models/CLAUDE.md`, `app/services/CLAUDE.md` | the workflow lives in a noun service with verb methods; the model keeps data access only |
| `callable` | `app/services/CLAUDE.md` | noun class, verb instance methods, `Result` from every public method, no `Callable`/`self.call`; siblings for the same process merged when they share helpers |
| `fat_job` | `app/jobs/CLAUDE.md` | the job looks up by ID, delegates to a service, raises on a failed Result |
| `locals` | `app/views/CLAUDE.md` | every partial in the folder declares `<%# locals: (...) %>`, defaults for optional ones |
| `route` | `app/controllers/CLAUDE.md` | the action is a resource (`resources :x, only: [...]`) with its own controller; the old path redirects or is removed only when nothing outside the app can hold it |
| `unique_index` | `db/migrate/CLAUDE.md` | a unique index backs the validation; existing duplicate rows handled first |

## Step 1: Pick the target

1. **Sync the queue with GitHub.** In-flight and finished work is known from PRs, so the queue never hands out a target someone is already on:
   ```bash
   gh pr list --state all --search "head:refactor/" --json number,state,headRefName,body,mergedAt --limit 100
   ```
   Every PR body carries a `Refactor-target: <id>` line (Step 10). Open PRs → their targets are taken. Merged PRs → their `done` ledger line is already on `main` once you've pulled. Closed-unmerged PRs → the target goes back in the queue (nothing to do; it was never recorded on `main`).
2. **Inventory**, reading the ledger as it is on `origin/main` (the main checkout may be on another branch or behind):
   ```bash
   cd "$MAIN_DIR" && git fetch origin main
   git show origin/main:.claude/audits/refactor-sweep/ledger.jsonl > tmp/refactor-sweep-ledger.jsonl 2>/dev/null || : > tmp/refactor-sweep-ledger.jsonl
   bundle exec ruby $SKILLS/refactor-sweep/scripts/inventory.rb --ledger tmp/refactor-sweep-ledger.jsonl --top 20 [--kinds K] [--out tmp/refactor-sweep-queue.json]
   bundle exec ruby $SKILLS/refactor-sweep/scripts/inventory.rb --show '<id>'   # one target's details
   ```
   It ranks by change frequency (commits in 180 days) × how many files reference the class × kind weight, skipping `done`/`skipped`/`wontfix` ledger entries. Remove targets taken by open PRs. With `--list`, print the table and stop.
3. **Check the target is real and PR-sized.** The inventory is static heuristics. Read the code. Then:
   - **Widen** to what must move together: sibling callbacks sharing state (`@calendar_event_id_to_delete` set in one, read in another), the sibling `Callable` services the inventory lists when they share helpers, the private methods only the moved code uses.
   - **Narrow** when it's too big for one reviewable PR (rough guide: more than ~15 app files or ~600 changed lines). Take one coherent slice (one callback cluster, one service of the siblings) and record the remainder as its own target id in the ledger (`status: "open"`, `note`) so a later run picks it up.
   - **Skip** a false positive or a target that can't be refactored without changing behavior (say why in one line). Append `{"id":…,"status":"skipped","note":…,"at":…}` to the ledger (it's committed with this run's PR) and pick the next target. After three skips in one run, stop and report: the queue heuristics need attention, not more skipping.
   - **Open PRs on the same files**: `gh pr list --state open --json number,title,files` and check for overlap with the target's files. Overlap means a merge conflict and a behavior lock against moving code; pick the next target instead.

## Step 2: Worktree

Follow `$SKILLS/resolve-issue/SKILL.md` **Step 2** exactly (Cases A/B/C, the `.env`/`DATABASE_SUFFIX`/`PORT` setup, and the guarded db setup), with these names:

- `SLUG` = the target id, lowercased, non-alphanumerics to `-`, trimmed to 40 chars (`callback:Appointment[calendar]` → `callback-appointment-calendar`);
- Case B/C path `../<app>-refactor-<SLUG>`, branch `refactor/<SLUG>`, `DATABASE_SUFFIX=_refactor_<SLUG with - → _>` (Postgres-safe; trim so the full database name stays under 63 chars).

Tell the user in one line: target, worktree path, branch, port.

## Step 3: Investigate, then audit every caller

Understand the code being moved well enough to name every effect it has and every path that reaches it. Read `references/caller-audit.md` now: it lists, per kind, the places Rails reaches code indirectly and the table format. In short:

1. **Effects**: list each observable thing the code does: records written (which columns), jobs enqueued (class + args + `wait`/queue), mails, broadcasts (stream + target), external calls, return values, errors raised, and *when* (inside the transaction, after commit, after rollback). This list is what Step 5 locks.
2. **Callers**: every entry point that reaches it, direct and indirect, including the ones that *don't* trigger it today (`update_column`, `update_all`, `insert_all` skip callbacks; imports may set flags that suppress them). Use an Explore agent for the sweep if it's broad, told to search `$WT`.
3. **After the change**: for each caller, what will happen: calls the new service / unaffected / no longer triggers (and why that's correct). A row that loses an effect it has today is a behavior change. Either the plan adds the service call there, or the row is a **Decision** in the PR with the reason (e.g. imports never wanted reminders and only got them by accident; keep the old behavior unless the code makes the accident unmistakable).

Write the effects list and caller table to `<scratchpad>/refactor-<SLUG>-audit.md`. They go into the plan, the PR and the cold reviewer's brief.

**Production facts that shape the plan** (always check; these are where refactors break a live app, not in the tests):

- **Queued jobs survive deploys.** Solid Queue holds serialized jobs by class name and arguments, some scheduled days ahead (reminders, `wait_until`). Never rename or delete a job class or change its `perform` signature in the same PR that stops enqueuing it. Keep the old class (delegating to the new code) and note a follow-up target to remove it later. The same goes for classes named in `config/recurring.yml`.
- **Runbooks and skills call services by name.** `grep -rn` the class/method names in `script/`, `lib/tasks/`, `.claude/skills/` (prod runner scripts inside operational skills), `docs/` and `tmp/` runbooks committed to the repo. A renamed service breaks the next production runbook run. Keep a thin alias, or update every caller in the same PR.
- **Avo and admin paths.** `app/avo/` resources and actions save records and call services outside any controller.
- **Transactions.** Moving a side effect from `after_commit` into a service call must keep it after commit (call it after the transaction block, or use `after_commit` on the service's own transaction). Moving it *inside* a transaction recreates the connection-holding problem the rules exist to prevent, and enqueuing inside an uncommitted transaction can run the job before the row exists.
- **Tenant context.** Callbacks run with whatever `ActsAsTenant.current_tenant` the caller set; a job or service may not. Keep `organization_id` explicit.
- **Data**: for `unique_index` (and any constraint), count rows that would violate it through `bin/prod-read` (counts only) and plan the cleanup per `db/migrate/CLAUDE.md`. For other kinds, read prod only if an effect depends on data shapes the code can't tell you (ids and counts, never names).

## Step 4: Plan and print it

1. `/plan Refactor <target id> per <rule file>: move <what> to <where>; effects to preserve: <list>; callers: <table path>; worktree <WT>`. Include the effects list and caller table in the request, plus: "structure only, no behavior change; keep old job class names and public service names callable (see production facts); the behavior-lock specs in Step 5 must pass unchanged."
2. `/architect-review <plan path>`. Fold its concerns in. It may not widen scope beyond the target. Recommendations that add features or touch other targets go in a `## Review notes` section as "not taken: <why>".
3. `/frontend-review <plan path>`, only for `locals`, `route`, or a plan that touches views, components or Stimulus.

Print the plan in the terminal (about 20 lines, tables, plain words) and **continue** (stop here only with `--dry-run`):

```
**callback:Appointment[calendar]** · ../<app>-refactor-callback-appointment-calendar (refactor/callback-appointment-calendar) · port 3014
Rule: app/models/CLAUDE.md — no side-effect callbacks

**Moves** — 6 calendar callbacks (push, delete on cancel, delete on destroy, cleanup, supervisor sync ×2) → `AppointmentCalendarSync#push/#remove`
**Effects locked** (7) — CalendarEventPushJob(appt id) on time/status change · CalendarEventDeletionJob(event id) on cancel/destroy · …
**Callers** (11) — 4 controllers, 2 services, 1 job, Avo AppointmentResource, recurring-series updater, legacy-system importer (no sync today; stays off), update_column paths (none fire today)
**Plan** | # | Change | Where | …
**Prod** — no data change · job classes unchanged · no runbook references
**Decisions** — legacy-system importer keeps skipping calendar sync (imported? guard, unchanged)

Locking behavior now.
```

(Illustrative. Every name comes from Step 3.)

## Step 5: Lock today's behavior (before touching app code)

Read `references/behavior-lock.md` now. In short:

1. For each effect in the audit, write an example that triggers it **through a caller boundary that survives the refactor**: the controller/request/system path, the job, or the public service/model API that stays. A spec that calls the callback method or asserts on the old private structure would break by design and prove nothing. Cover both sides: the effect happens when it should, and doesn't when it shouldn't (the `if:` conditions). Put lock examples in their own files, `spec/refactor_locks/<slug>/*_spec.rb`, so their diff is easy to check.
2. Run them on the **unchanged** code: all green. A red lock means you misunderstood today's behavior: fix the spec, not the app.
3. **Prove the lock catches a break**: for each effect, run `$SKILLS/rspec-test-expert/scripts/probe.rb` against the line that produces it (comment it out / change an argument). Every probe must be KILLED. A survivor means that effect isn't locked; strengthen the example.
4. Commit only the lock files: `test(refactor): lock behavior of <target id>`. Record the SHA as `LOCK_SHA`.

Existing specs that assert on the *old structure* (e.g. a model spec expecting `appointment.update` to enqueue a job) are expected to change in Step 6. Note them now, so the PR can explain each one. Lock specs never change.

## Step 6: Refactor with /code

`/code <plan path>` in `$WT`, telling it, on top of CLAUDE.md:

- structure only: no new behavior, no fixes to unrelated code (note anything found for the cold review notes instead);
- `spec/refactor_locks/` is read-only;
- keep job class names, `perform` signatures, `config/recurring.yml` entries and any service/method name referenced outside `app/` working (alias or delegate), per the production facts;
- move or rewrite the old-structure specs listed in Step 5 so they test the new home (the service), not delete them.

If the plan turns out wrong in a way that changes scope (a hidden caller that needs real design, an effect that can't be preserved), stop and report in two or three lines. That's the only mid-build stop.

## Step 7: Prove nothing changed

```bash
cd "$WT"
git diff --stat $LOCK_SHA -- spec/refactor_locks/          # must be empty
bundle exec rspec spec/refactor_locks/<slug>/               # must be green
```

Then re-walk the caller table against the diff: every "calls the new service" row really does (`grep` the call), and no row lost an effect without a Decision. Re-run 2–3 of the Step 5 probes against the **new** code's effect lines: they must still be KILLED, which proves the locks follow the effect to its new home rather than passing vacuously.

A lock that fails, a lock file that changed, or an effect with no caller left is a behavior change: fix the refactor (not the lock), and repeat. Two honest attempts, then stop and report with the output.

## Step 8: Specs, review, simplify, CI

These follow `$SKILLS/resolve-issue/SKILL.md` Steps 6–9, with these additions:

1. **`/test-changed`** (base `main`), then run every changed and affected spec file plus `spec/refactor_locks/<slug>/`, `bin/standardrb` on changed Ruby, prettier on changed JS. Commit.
2. **`/full-review`** on `$BRANCH`. Keep only fixes about this target's code. Re-run the lock specs after, since a "fix" from review can change behavior. Commit `fix: address full-review findings`.
3. **`/simplify`**. Same rule, then lock specs again. Commit `refactor: simplify` (skip if nothing changed).
4. **`/merge-main`**, then **`bin/ci`** through the CI slot (`$SKILLS/resolve-issues/scripts/ci-slot acquire refactor-<SLUG>` … `release refactor-<SLUG>`), `/green-ci` if red, one re-run. Still red: no PR, report and stop. Never run two `bin/ci` at once, and never trigger GitHub Actions.

After every step that touches app code, the lock specs run again. They're the reason this skill exists, and a late "simplification" that drops an effect is exactly the regression they catch.

## Step 9: Ledger

Append one line to `$WT/$LEDGER` (create the folder on the first run) and commit it with the PR (`chore(refactor-sweep): record <target id>`):

```json
{"id":"callback:Appointment[calendar]","kind":"callback","status":"done","branch":"refactor/callback-appointment-calendar","lock_examples":14,"callers":11,"note":"old job classes kept; follow-up target callback:Appointment#enqueue_calendar_cleanup alias removal","at":"2026-10-03T18:00:00Z"}
```

Also commit any `skipped` or `open` remainder lines from Step 1. The ledger is append-only; the latest line per id is its state. It reaches `main` when the PR merges, which is what removes the target from the queue for good; until then the open PR does.

## Step 10: PR

Push and open the PR as in `/resolve-issue` Step 10 (specific files staged, attribution lines, body via a file). Body:

```markdown
Refactor-target: <id>

## Why
<rule file and the one-line rule; why this target ranked: churn, fan-in>

## What moved
| From | To |
|---|---|

## Behavior lock
- <n> examples in `spec/refactor_locks/<slug>/`, green on the old code (<LOCK_SHA>) and unchanged after
- probes: <k>/<n> killed on the old code, <k>/<n> re-checked on the new code
- old-structure specs rewritten: <file — why>

## Callers
| Caller | Before | After |
|---|---|---|
(every row from the audit)

## Production
- queued jobs: <job classes and perform signatures unchanged | old class kept as a delegate>
- runbooks / skills / Avo referencing moved names: <none | kept working via …>
- data change: none  ← or the CLAUDE.md snapshot + go/no-go recipe for a constraint target
- revert: <safe — nothing is written in a new shape | what to check>

## Decisions
<one line each, or "none">

## Reviews and tests
- architect / frontend · /full-review counts · /simplify
- /test-changed: <files> · bin/ci green after merging origin/main (<sha>)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

`Refactor-target:` must be the first line; Step 1 reads it to know the target is taken.

## Step 11: Cold review

Follow `.claude/skills/resolve-issue/references/cold-review.md` with:

- `<WHAT>`: "refactored <target> toward <rule>, as a pure refactor"; `<WT>`: `$WT`; slug `refactor-<SLUG>`
- `<ASK>`: `1. The caller audit: <scratchpad>/refactor-<SLUG>-audit.md` (the effects list and caller table)
- `<NOTES>`: the default list, plus anything you noticed in unrelated code (Step 6 keeps it out of the PR)
- `<FOCUS>`:
  ```
  This PR claims to be a pure refactor. Hunt for behavior changes: a caller in the
  table whose "After" column is wrong, a caller missing from the table (grep the moved
  names across app/, lib/, config/, script/, .claude/skills/, app/avo/), an effect that
  moved inside or outside a transaction, a job class or perform signature that changed,
  a tenant or Current.* assumption that no longer holds. Each one you find is a `verify`.
  ```
- `<STOP>`: "the PR changes behavior instead of only structure"
- `<RECHECK>`: re-run the lock specs and lint, then `bin/ci`

## Step 12: Hand off

Keep the worktree. If this run created it, `open -n -a "Visual Studio Code" "$WT"`. Finish with one line each: the PR link; the target and its rule; lock (examples, probes); callers (rows, decisions); `bin/ci` against which main SHA; cold review (comment link, verify results); the next target in the queue (`inventory.rb --top 1`), so the user can run `/refactor-sweep` again.

## Guardrails

- Behavior changes are the failure this skill exists to prevent. When in doubt between "cleaner" and "identical", choose identical and note the cleaner option as a follow-up target.
- Production is read-only: `bin/prod-read`/`bin/prod-sql` only. Data changes ship as CLAUDE.md's dry-run rake task with the snapshot + go/no-go recipe, written for the user to run.
- No PHI in plans, specs, commits, the PR or the ledger.
- One target per run, one worktree per run, one `bin/ci` on the machine at a time, never GitHub Actions.
- Early stops: three skips in one run, scope changed mid-build, locks red after two attempts, `bin/ci` red after `/green-ci`. Everything else runs through.
