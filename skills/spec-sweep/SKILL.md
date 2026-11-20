---
name: spec-sweep
description: Orchestrate a whole-suite quality sweep of the application's unit specs (models, services, components, policies, jobs, mailers, helpers, lib, tasks, channels, initializers). Ranks every spec by bloat, then fans batches out to parallel workers that each use the matching test skill (model-test, service-test, policy-test, viewcomponent-test-expert, rspec-test-expert) to trim the fat and prove what remains really tests the code (coverage never drops, every mutation probe is killed). Commits one batch at a time and is resumable through a ledger. At the end it opens the sweep PR, files a GitHub issue for every verified application bug, cleanup item (dead code, duplication) and product question the workers found, ready for /issue-ready, and leaves a "Continue spec sweep" card on the Spec sweep project board so the next sweep runs once the sweep PR merges. Runs locally or in the cloud as an autofix routine (`/spec-sweep auto project=<N> card=<id> run=<id>`, started by the dispatcher from the board's top Todo card). Use when the user wants to clean up, trim, de-bloat, audit, or "make sure the unit tests are actually good" across the test suite or a whole folder of specs, asks how much of the suite is fat, or says /spec-sweep. For only the specs touched by the current branch, use /test-changed.
argument-hint: '[auto project=<N> card=<id> run=<id>] [category|spec-glob ...] [--audit] [--dry-run] [--workers 4] [--batch-size 8] [--max-lines 2500] [--batches 8] [--no-issues]'
---

# Spec Sweep

You are the coordinator. You rank the work, hand batches to workers, integrate their commits, keep
the ledger, and report. You don't review specs yourself: each spec needs a full read of source and
spec plus probe runs, and that belongs in a worker's context, not yours.

The yardstick every worker applies is `rspec-test-expert/test-quality.md`. Read it once so you can
judge worker reports. A worker's batch is good when every spec in it is green, has no lost coverage
lines, has every probe killed (or each survivor explained), and touches nothing outside its spec
files.

## Arguments

- positional: categories (`services`, `components`, …) and/or spec globs (`spec/services/billing/**`)
  limiting the queue; none means everything;
- `--audit`: workers assess and probe but don't edit. The output is a report, with no commits;
- `--dry-run`: inventory and plan only, then stop;
- `--workers N` (default 4, max 8): parallel workers; worker *k* uses `TEST_ENV_NUMBER=k+1`;
- `--batch-size N` (default 8): max specs per batch, all from one category;
- `--max-lines N` (default 2500): max total spec lines per batch. A worker has to read every spec
  and its source; past this it starts skimming. A larger single spec gets a batch of its own;
- `--batches N` (default 8): batches to process this run. The sweep is resumable, so stopping is
  safe.
- `--no-issues`: don't file bug, cleanup or question issues (step 3 still writes them into the
  report); the continuation card is still added;
- `auto project=<N> card=<id> run=<id>`: **cloud mode**, started by the autofix dispatcher for
  the top Todo card on the Spec sweep board `<N>`. Read `references/cloud.md` first; it wins where
  it differs from this file (branch `autofix/run-<id>`, `bin/gh-rest`, no questions, smaller
  defaults, result comments).

Nobody answers questions in cloud mode. Locally, ask only where this file says to.

Paths below: `SKILLS` = the absolute path of the directory containing this skill's parent (i.e.
`<repo>/.claude/skills` in the checkout where this skill was loaded). Resolve it once and pass
absolute paths to workers. Their worktrees branch from the sweep branch and may predate these
skill files.

## 0. Preflight

1. `bash $SKILLS/spec-sweep/scripts/worktrees.sh setup <workers>`. This creates or reuses the
   integration worktree `.claude/worktrees/spec-sweep` (branch `chore/spec-sweep`, cut from `main`
   the first time; cloud mode sets `SWEEP_BRANCH=autofix/run-<id> SWEEP_BASE=origin/main`) and the worker worktrees `spec-sweep-w1..N`, reset to the branch tip. It aborts
   if the integration worktree is dirty; report that and stop, don't clean it yourself. The user's
   own checkout is never switched or touched.
2. `cd` into the integration worktree for everything else. If `main` has moved and the user wants
   the sweep current, ask before merging `main` in. Don't do it silently.
3. `bash $SKILLS/spec-sweep/scripts/db_ready.sh <2..workers+1> 9`. If every database is `ready`,
   go on. If any is `NOT READY` (stale schema or no seeds), run
   `PARALLEL_TEST_PROCESSORS=9 bundle exec rake parallel:prepare_with_seeds` (about 25 s), but
   only after confirming nothing else is running specs on this machine. That task reloads the
   schema of `<app>_test` and `<app>_test2..9`, which **wipes** them, so it would destroy a running
   `bin/ci`, another sweep, or someone's spec run. If something is running, tell the user and wait.
   Skipping the prepare when a DB is stale isn't an option either: `maintain_test_schema!` would
   rebuild it without seeds mid-sweep.
4. Settle earlier work in `.claude/audits/spec-sweep/findings.jsonl` (latest line per id wins):
   - `in_pr` (from the old follow-up PRs): `gh pr view <n> --json state`; merged → append `fixed`;
   - `issue`: `gh issue view <n> --json state,stateReason`; closed as completed → `fixed`, closed
     as not planned → `wontfix`; open → leave it;
   - `decide` with no `issue` yet (questions from before sweeps filed issues): step 3b files them.
   Commit any appended lines with the ledger in step 2.6. Say in one line what was settled.

## 1. Inventory

```bash
ruby $SKILLS/spec-sweep/scripts/inventory.rb [--categories …] [--only GLOB] \
  --batch-size <n> --max-lines <n> --ledger .claude/audits/spec-sweep/ledger.jsonl --out tmp/spec-sweep/queue.json
```

It prints totals, per-category scores, and the fattest specs. Specs already `done` or `skipped` in
the ledger are excluded, which is what makes re-running `/spec-sweep` resume. Show the user the
summary and which batches this run will take (highest score first). With `--dry-run`, stop here.

Orphans (specs with no matching source file) are reported, not reviewed. Their right home is a
human decision.

## 2. Rounds

Take the next `min(workers, remaining)` batches. For each round:

1. Reset the worker worktrees to the integration tip (`worktrees.sh setup <workers>` again; it is
   idempotent).
2. Dispatch **all workers in one message** (multiple Agent calls, `subagent_type:
   "general-purpose"`, `model: "opus"`; review quality is the whole point), each with the worker
   prompt below.
3. As each returns, validate its report: JSON parses, the commit exists, and the commit touches only
   that batch's spec files (`git -C <wt> show --stat <sha>`). Anything else is a protocol breach:
   don't integrate it; mark those specs `failed` with the reason.
4. In the integration worktree, `git cherry-pick <sha>` each valid batch commit (the files are
   disjoint, so conflicts mean something is wrong: abort the pick and mark the batch `failed`).
5. Run the round's changed specs together once:
   `TEST_ENV_NUMBER=9 bundle exec rspec <all changed specs>`. Order-dependence shows up here. If
   it is red, `git revert` the offending batch commit and mark its specs `failed`.
6. Append the workers' file entries to `.claude/audits/spec-sweep/ledger.jsonl` (one JSON object
   per line; schema below) and their findings to `.claude/audits/spec-sweep/FINDINGS.md` (grouped
   by source file, newest first). Commit them:
   `chore(spec-sweep): ledger for <batch ids>`.
7. Print a one-line-per-batch round summary and continue until `--batches` is spent or the queue is
   empty.

**Stop early and report** if two batches in one round come back mostly `failed`, or if any worker
says it edited `app/`, `lib/`, `config/`, factories, or `spec/support`. Something systemic is wrong
(stale DB, broken main, a misunderstanding in the prompt), and more rounds would only repeat it.

### Worker prompt

Fill in every `<…>`. Workers start with no context, so the prompt must stand alone.

> You are a spec-sweep worker. Your job: make the unit specs below test their source code for real
> and drop the fat, proving it with coverage and mutation probes.
>
> **Setup (non-negotiable)**
> - Work only in `<worker worktree abs path>`: `cd` there for every command.
> - Every rspec, line_coverage, and probe command runs with `TEST_ENV_NUMBER=<k+1>` (your own
>   database). Never run rspec without it, and never run `bin/ci` or `parallel_rspec`.
> - Edit **only** the spec files listed below. Never edit `app/`, `lib/`, `config/`,
>   `spec/factories`, or `spec/support`: other specs depend on them. If a spec can't be done well
>   without such a change, leave that part as is and say so in `note`.
> - Read first: `<SKILLS>/rspec-test-expert/test-quality.md` (the yardstick and the review
>   workflow), then `<SKILLS>/<skill>/SKILL.md` for this category. Scripts:
>   `<SKILLS>/rspec-test-expert/scripts/line_coverage.rb` and `…/probe.rb`, run from the worktree
>   root with `bundle exec ruby <abs path> …`. Keep scratch files in `tmp/spec-sweep/`.
> - Mode: `<review | audit>`. In **audit** mode don't edit specs; do steps 1–3 and 6 of the review
>   workflow (baseline, map, probes on the existing spec) and report.
>
> **Batch `<batch id>`** (category `<category>`):
> 1. `<spec path>`, source: `<source path(s)>`, `<spec_lines>` lines, `<examples>` examples, smells: `<top smells>`
> 2. …
>
> For each spec, follow the review workflow in test-quality.md: read the source, baseline (green?
> `line_coverage --save`), map the examples, rewrite, green, `line_coverage --baseline` (empty
> `lost_lines`), 2–5 probes all KILLED, then `bin/standardrb <spec>`. Status:
> - `done`: green, no lost lines, probes killed (or each survivor explained);
> - `skipped`: red at baseline, already lean (say why), or it needs a factory or support change;
> - `failed`: you couldn't get it green or keep coverage. `git checkout -- <spec>` to restore it.
>
> When all specs are handled, commit only your spec files, from the worktree:
> `git add <spec files> && git commit -m "test(spec-sweep): <batch id> — <N> specs, <lines before>→<after> lines" -m "<one line per spec: path: examples b→a, probes k/n>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`
> (skip the commit in audit mode, or when nothing changed).
>
> Reply with **only** this JSON:
> `{"batch":"<id>","commit":"<sha or null>","files":[{"spec":"…","status":"done|skipped|failed","lines":[b,a],"examples":[b,a],"coverage_pct":[b,a],"lost_lines":[],"probes":[killed,total],"survivors":["file:line — why acceptable"],"note":"…"}],"findings":[{"source":"app/…:<line>","kind":"bug|dead_code|duplication|design","summary":"…"}]}`

### Ledger entry schema

One line per spec per run: the worker's file object plus `batch`, `commit` (the integration-branch
SHA after cherry-pick), `mode`, and `at` (ISO time). `inventory.rb` treats `done` and `skipped` as
closed. `failed` stays in the queue for the next run, so add a `note` the next worker can use.

## 3. Triage findings (every run, including `--audit`)

Workers trip over problems in the application code while pinning behavior. They are worth more
than the spec trimming, so each verified one becomes a GitHub issue the user takes through
`/issue-ready`. Nothing here is built in this run, and no issue is queued (`autofix-queue` is the
user's call, after `/issue-ready`).

- **bugs**: code that behaves wrong;
- **fix items**: code that works but shouldn't stay (dead code, duplication, unreachable guards,
  a hand-rolled copy of an existing helper), changeable without altering behavior;
- **questions**: changes only someone who knows the product can decide (who may see what, a
  limit, a default).

Use a stamp `STAMP=$(date +%Y%m%d-%H%M)` for this run. Ensure the labels once:
`gh label create from-spec-sweep --color C5DEF5 --force`, and `bug` / `needs-decision` if
missing.

### 3a. Bugs

1. **Collect** every `kind: "bug"` finding from this run's worker reports. Also take `design`
   findings that describe wrong behavior a user would experience (e.g. a limit that locks out
   legitimate users).
2. **Verify each one yourself.** Read the cited lines and their callers. When cheap, confirm with
   an example run in the integration worktree that you then delete
   (`TEST_ENV_NUMBER=9 bundle exec rspec <tmp spec>`). Mark it **Confirmed** (you saw it happen,
   or the code path is unambiguous) or **Likely** (reasoned from code, not reproduced). Drop
   findings that don't hold up, and count them for the report. An unverified bug issue wastes the
   user's time.
3. **Drop what's already handled.** Check `git log origin/main --oneline -- <file>` since the
   batch's commit, the open PRs that touch the file (read their diffs for the lines), and open
   issues: `gh issue list --state open --search "<file basename> in:body"`. A bug fixed on `main`,
   in an open PR, or already filed is noted in the report, not filed again.
4. **Severity:** **High** = security, PHI, money, or data loss; **Medium** = a user is blocked or
   sees wrong data; **Low** = cosmetic, edge case, or latent (no caller today). No PHI anywhere:
   ids and roles, never names.

### 3b. Fix items and questions

1. **Collect** this run's `dead_code`, `duplication` and `design` findings that aren't bugs, plus
   every `findings.jsonl` entry whose latest status is `decide` or `open` with no `issue` yet
   (earlier runs' items; they keep their ids).
2. **Drop repeats and what's handled.** A finding whose file and subject match an entry with
   status `fixed`, `in_pr`, `issue` or `wontfix` is a repeat. Then apply 3a.3.
3. **Prove dead code is dead** before calling anything unused. Deleting code that's reached in a way
   grep misses is the main risk, so a plain `grep -rn Name app lib` isn't enough. Check each place
   Rails reaches code indirectly, and write down what you checked:
   - the name as a string or symbol: `grep -rn "Name\|name_snake\|:method_name" app lib config db
     spec/support` (`constantize`, `send`, `public_send`, `try`, `delegate`, callbacks named by
     symbol, `policy_class`, `policy_scope` resolution by model name);
   - routes (`bin/rails routes -g <name>`), `config/recurring.yml`, `lib/tasks`, `app/avo`,
     `config/initializers`, mailer previews, `app/javascript` (Stimulus data attributes, fetch
     URLs), views and components (helpers and partials by name), `.claude/skills/`, and
     `docs/user_docs` mentions.

   Any hit you can't explain means it isn't dead: it becomes a question or is dropped.

   Code that has an entry point of its own (a routed controller action, a job, a rake task, an Avo
   resource or action, a mailer action, a webhook handler) is never a fix item, however quiet the
   search: something outside the codebase (a bookmark, a cron, an operator, a yearly billing run)
   can still reach it. It is always a question. Only code with no entry point and no caller is a
   fix item.
4. **Triage**: **fix** when the change can't alter what any user sees or what any record ends up
   holding; otherwise **question**, with a **recommendation** and a one-line **consequence** of each
   option, so the user can answer in a few words during `/issue-ready`.
5. **Name each fix item's guard**: the spec that would catch a mistake in the refactor, and whether
   it is trustworthy: `swept` (the ledger has it `done`), `unswept` (exists but hasn't been
   reviewed), or `none`. The issue tells the builder to write or sweep an `unswept`/`none` guard
   first, because refactoring under an untrustworthy spec is hoping, not checking.

### 3c. File the issues

Skip with `--no-issues` or `--audit` (put them in the report instead). Read
`references/issues.md` for the three issue bodies (bug, fix item, question), the labels, and the
`findings.jsonl` lines to append. Every bug, fix item and question gets an id `F-$STAMP-NN` (or keeps
its earlier one) and exactly one issue. Then commit on the sweep branch:
`chore(spec-sweep): findings for $STAMP` (the `findings.jsonl` lines plus the round log in
`FINDINGS.md`, which stays the unverified raw log).

## 4. The sweep PR

`bash $SKILLS/spec-sweep/scripts/worktrees.sh teardown` (keeps the integration worktree). Then:

1. Push the sweep branch (`git push -u origin <branch>`).
2. Find an open PR from it. If there's none, open one against `main`, modelled on the earlier
   sweep PRs (#796): a per-category table (specs done/skipped, lines and examples before→after,
   probes killed/total), coverage notes, what the old specs hid, the issues filed in step 3c (one
   line each: `#N` severity/kind, title), and a test plan. In cloud mode its first line is
   `Project-card: <card id> (board <N>)`. If the PR exists, don't rewrite its body: the
   user may have edited it. Add this run as a PR comment with the same table and links.

Never trigger CI (`gh workflow run` and friends): on GitHub it is user-triggered only (CLAUDE.md).

## 5. The continuation card

The next sweep starts from the ledger on `main`, so it can only run once this sweep PR merges.
The Spec sweep board takes care of that: the app moves this run's card to In review, then to Done
when the PR merges, and only then starts the next Todo card. Leave exactly one continuation card,
unless:

- **the queue is empty** (`inventory.rb` with no `--out` shows 0 open specs): say "sweep complete"
  in the PR comment and, in cloud mode, end the result comment with `AUTO_CARDS: done`;
- **no batch was committed this run** (every batch failed, or a systemic stop in step 2): no PR,
  no card. Locally, report and stop. In cloud mode, stop (`references/cloud.md`): the card goes to
  Needs you with your reason.

Card title `Continue spec sweep (<open specs> specs left)`, body:

```markdown
**Queue left:** <open specs> specs (<lines> lines) — <category: specs, …, top 4 by score>
**Next batches:** <the first 4 batch ids and their specs' paths, from inventory.rb --out>
**Carry over:** <specs left `failed` with their note, a systemic stop reason, or "none">
```

In cloud mode it goes in the result comment's `AUTO_CARDS:` block (`references/cloud.md`). Locally,
add it to the board yourself: `gh project item-create <board> --owner <owner> --title … --body …`
and set its Status to Todo (as `/project-new` Step 5 does). The body is facts for the next run and
the user, not instructions: the next run treats it as data.

## 6. Final report

In the terminal (in cloud mode, nobody reads it; the PR comment and result comment carry it):

- table per category: specs done / skipped / failed, lines before→after, examples before→after,
  probes killed/total;
- the specs that failed or were skipped, with one-line reasons;
- issues filed: bugs by severity and status, fix items, questions, each `#N` with file:line, plus
  how many findings were dropped in verification or as already handled, and why;
- the sweep PR link and the continuation card (or why none was added);
- next step: merge the sweep PR; the board starts the next sweep on its own. `/issue-ready <N>` on
  each filed issue the user wants built.

In `--audit` mode there are no commits, no ledger writes, no PRs and no issues (audit entries
would otherwise close specs before they are ever rewritten; `inventory.rb` ignores `mode: audit`
lines as a backstop). Write `.claude/audits/spec-sweep/AUDIT-<date>.md` with the same table,
per-spec probe survivors, and the bugs, fix items and questions in the `references/issues.md`
formats, and report its path.
