---
name: spec-sweep
description: Orchestrate a whole-suite quality sweep of the application's unit specs (models, services, components, policies, jobs, mailers, helpers, lib, tasks, channels, initializers). Ranks every spec by bloat, then fans batches out to parallel workers that each use the matching test skill (model-test, service-test, policy-test, viewcomponent-test-expert, rspec-test-expert) to trim the fat and prove what remains really tests the code (coverage never drops, every mutation probe is killed). Commits one batch at a time on chore/spec-sweep and is resumable through a ledger. At the end it opens the sweep PR plus two PRs stacked on it: one fixing the application bugs workers found (/fix-spec-bugs, test-first) and one cleaning up the dead code and duplication they found (/plan, /architect-review, /code, /full-review), with behavior-changing findings turned into questions for the user. Each follow-up PR gets a cold review posted as a PR comment. Use when the user wants to clean up, trim, de-bloat, audit, or "make sure the unit tests are actually good" across the test suite or a whole folder of specs, asks how much of the suite is fat, or says /spec-sweep. For only the specs touched by the current branch, use /test-changed.
argument-hint: '[category|spec-glob ...] [--audit] [--dry-run] [--workers 4] [--batch-size 8] [--max-lines 2500] [--batches 8] [--no-followups]'
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
- `--no-followups`: stop after the sweep PR (step 4); don't open the bugs and findings PRs.

Paths below: `SKILLS` = the absolute path of the directory containing this skill's parent (i.e.
`<repo>/.claude/skills` in the checkout where this skill was loaded). Resolve it once and pass
absolute paths to workers. Their worktrees branch from `chore/spec-sweep` and may predate these
skill files.

## 0. Preflight

1. `bash $SKILLS/spec-sweep/scripts/worktrees.sh setup <workers>`. This creates or reuses the
   integration worktree `.claude/worktrees/spec-sweep` (branch `chore/spec-sweep`, cut from `main`
   the first time) and the worker worktrees `spec-sweep-w1..N`, reset to the branch tip. It aborts
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
4. Collect answers to earlier questions. List the ids in `.claude/audits/spec-sweep/findings.jsonl`
   whose latest status is `decide`. An answer can come three ways: a comment on the last findings
   PR naming the id (`gh pr view <n> --comments`), a filled-in `**Answer:**` line under the id in
   its `findings-*.md` (setup lets that file be dirty; commit it now as `chore(spec-sweep): record
   answers`), or the user telling you in this conversation. Append an `answered` line (with
   `"answer"`) for each, or `wontfix` when the answer is to leave it as is. Say in one line how many
   were answered and how many still wait, and don't block on the rest: unanswered questions carry
   over, and step 3b builds the answered ones.
5. Settle earlier follow-up PRs. For each `in_pr` entry, `gh pr view <n> --json state,baseRefName`:
   append `fixed` for the merged ones. If the sweep PR has merged while a follow-up PR still
   targets `chore/spec-sweep`, retarget it (`gh pr edit <n> --base main`) and say so. The repo
   keeps merged branches, so GitHub won't retarget it, and merging it as it stands would land it on
   the stale sweep branch instead of `main`.

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

Workers trip over two kinds of problems in the application code while pinning behavior. Both are
worth more than the spec trimming, and both get turned into work here:

- **bugs**: code that behaves wrong. They go to a bug index that `/fix-spec-bugs` fixes test-first;
- **findings**: code that works but shouldn't stay (dead code, duplication, unreachable guards,
  questionable design). They go to a work order that the findings PR implements.

Use a stamp `STAMP=$(date +%Y%m%d-%H%M)` for this run's files. All of them live in the integration
worktree and are committed to `chore/spec-sweep`, so they travel with the sweep PR.

### 3a. Bugs

1. **Collect** every `kind: "bug"` finding from this run's worker reports. Also take `design`
   findings that describe wrong behavior a user would experience (e.g. a limit that locks out
   legitimate users). Carry over earlier runs' bugs too: any `docs/bug-reports/spec-sweep-*/BUG-*.md`
   on this branch without a `## Fix Applied` section goes into this run's index as a link to its
   original file (`../spec-sweep-<old stamp>/BUG-…md`), after the 3a.3 check below.
2. **Verify each one yourself.** Read the cited lines and their callers. When cheap, confirm with
   a throwaway script (`echo '…' | TEST_ENV_NUMBER=9 bin/rails runner -`), or with an example run in
   the integration worktree that you then delete. Mark it **Confirmed** (you saw it happen, or the
   code path is unambiguous) or **Likely** (reasoned from code, not reproduced). Drop findings that
   don't hold up, and count them for the report. An unverified bug list wastes the user's time.
3. **Drop what's already handled.** Check `git log main --oneline -- <file>` since the batch's
   commit, and the open PRs that touch the file (`gh pr list --state open --json number,title,files
   --jq '.[] | select(any(.files[]; .path == "<file>")) | "\(.number) \(.title)"'`, then read
   that PR's diff for the lines). A bug fixed on `main` or in an open PR is noted in the report,
   not fixed again.
4. **Write** `docs/bug-reports/spec-sweep-$STAMP/`: one `BUG-NNN-<slug>.md` per bug, numbered in
   severity order, plus `INDEX.md`. Severity: **High** = security, PHI, money, or data loss;
   **Medium** = a user is blocked or sees wrong data; **Low** = cosmetic, edge case, or latent (no
   caller today). No PHI: ids and roles, never names. Each bug file:

   ```markdown
   # BUG-NNN: <title>

   **Severity:** High | Medium | Low  **Status:** Confirmed | Likely
   **Area:** <feature>  **Found by:** <batch id> (`<spec path>`)

   ## Where
   `<file>:<line>` (`<Class#method>`)

   ## What happens
   <the concrete scenario in plain language: who does what, what they see>

   ## Why
   <the code mechanism in 2–4 lines, quoting the line>

   ## Evidence
   <the repro, or the reasoning plus the example that would fail>

   ## Regression spec
   `<spec file the fix's example belongs in>`: <the assertion in one line, e.g.
   `Scope.new(platform_admin, FeeSchedule).resolve` contains the practice's schedule>

   ## Suggested fix
   <one or two sentences, not a patch>
   ```

   `INDEX.md`: a title (`# Spec-sweep bugs: <run>`), a severity count table, then
   `### High` / `### Medium` / `### Low` sections of
   `- [BUG-NNN: <title>](BUG-NNN-<slug>.md) — <area>, <Confirmed|Likely>` bullets. That shape is
   what `/fix-spec-bugs` reads; the user can add `[SKIP]` to a bullet to hold a bug back.

### 3b. Findings

1. **Collect** this run's `dead_code` and `design` findings that aren't bugs, plus every finding in
   `.claude/audits/spec-sweep/findings.jsonl` whose latest status is `answered` (the user decided an
   earlier question; see Preflight 4).
2. **Drop repeats and what's handled.** A finding whose file and subject match a ledger entry with
   status `fixed`, `in_pr`, `wontfix`, or `decide` is a repeat. Don't list it again (a still-open
   `decide` question stays in its original file). Then apply 3a.3: skip anything fixed on `main` or
   in an open PR, and say which.
3. **Prove dead code is dead** before calling anything unused. Deleting code that's reached in a way
   grep misses is the main risk of this PR, so a plain `grep -rn Name app lib` isn't enough. Check
   each place Rails reaches code indirectly, and write down what you checked:
   - the name as a string or symbol: `grep -rn "Name\|name_snake\|:method_name" app lib config db
     spec/support` (`constantize`, `send`, `public_send`, `try`, `delegate`, callbacks named by
     symbol, `policy_class`, `policy_scope` resolution by model name);
   - routes (`bin/rails routes -g <name>`), `config/recurring.yml`, `lib/tasks`, `app/avo`,
     `config/initializers`, mailer previews, `app/javascript` (Stimulus data attributes, fetch
     URLs), views and components (helpers and partials by name), and `docs/user_docs` mentions.

   Any hit you can't explain means it isn't dead: it becomes a `decide` item or is dropped.

   Code that has an entry point of its own (a routed controller action, a job, a rake task, an Avo
   resource or action, a mailer action, a webhook handler) is never `fix`, however quiet the
   search: something outside the codebase (a bookmark, a cron, an operator, a yearly billing run) can
   still reach it, and no repo search can rule that out. It is always a `decide` item. Only code
   with no entry point and no caller is `fix` dead code.
4. **Triage** each finding into one of two groups:
   - **fix**: the change can't alter what any user sees or what any record ends up holding.
     Deleting proven-dead code, merging copies of the same check into one, removing guards that
     can't be reached, replacing a hand-rolled helper with the existing one. These are built
     automatically;
   - **decide**: the change alters behavior, or only someone who knows the product can say what's
     right (who may see what, a limit, a default). These become questions for the user. Each gets
     a **recommendation** and a one-line **consequence** of each option, so the user can answer in a
     few words.
5. **Name each fix item's guard**: the spec that would catch a mistake in the refactor, and whether
   it is trustworthy: `swept` (the ledger has it `done`), `unswept` (exists but hasn't been
   reviewed), or `none`. Refactoring under an untrustworthy spec is hoping, not checking, so the
   findings PR writes or sweeps the guard first for `unswept` and `none` items (see
   `references/followups.md`).
6. **Write** `.claude/audits/spec-sweep/findings-$STAMP.md`:

   ```markdown
   # Spec-sweep findings: <run>

   ## Fix (built in the findings PR)
   ### F-$STAMP-01: <title>
   - **Where:** `<file>:<line>`  **Kind:** dead_code | duplication | unreachable | design
   - **Change:** <what to do, one or two lines; for deletions, everything that goes with it>
   - **Guard:** `<spec path>` (swept | unswept | none)
   - **Evidence:** <for dead code: what was searched and came up empty>

   ## Decide (your call: write an answer under any item, the next run builds it)
   ### F-$STAMP-07: <question>
   - **Where:** `<file>:<line>`
   - **Today:** <what happens now, one line>
   - **Recommend:** <option> — <why, one line>
   - **If <option A>:** <consequence>  **If <option B>:** <consequence>
   - **Answer:**
   ```

   Ids are `F-<stamp>-NN`, unique across runs, and an answered item from an earlier run keeps its
   original id. Then append one line per finding to `findings.jsonl`:
   `{"id":"F-…","source":"<file>:<line>","kind":"…","subject":"<the method, class or rule it is about>","triage":"fix|decide","status":"open|decide","run":"$STAMP","at":"<ISO>"}`.
   The latest line per id is its current state. Statuses: `open` (fix item, not built yet),
   `decide` (question asked), `answered` (user answered; add `"answer"`), `in_pr` (add `"pr"`),
   `fixed` (merged), `wontfix` (user said leave it). Nothing reads it but this skill, so keep it
   append-only and never rewrite history.
7. Commit both 3a and 3b on `chore/spec-sweep`:
   `chore(spec-sweep): bugs and findings for <run>`. Also keep appending raw worker findings to
   `FINDINGS.md` per round (step 2.6). That file is the unverified log; the files above are the
   verified work.

In `--audit` mode there are no commits: put the bugs and findings sections in the audit report
(section 6) instead and skip the follow-up PRs.

## 4. The sweep PR

`bash $SKILLS/spec-sweep/scripts/worktrees.sh teardown` (keeps the integration worktree). Then:

1. `git -C <integration worktree> push -u origin chore/spec-sweep`.
2. `gh pr list --head chore/spec-sweep --state open --json number,url`. If there's no PR, open one
   against `main` (`gh pr create --base main --head chore/spec-sweep`), modelled on the earlier
   sweep PRs: a per-category table (specs done/skipped, lines and examples before→after, probes
   killed/total), coverage notes, what the old specs hid, a short bugs-found list linking the bug
   index, and a test plan. If the PR exists, don't rewrite its body: the user may have edited it.
   Add this run as a PR comment (`gh pr comment`) with the same table and links.

Never trigger CI (`gh workflow run` and friends): on GitHub it is user-triggered only (CLAUDE.md).

## 5. Follow-up PRs (skip with `--no-followups`, `--audit`, `--dry-run`)

Two PRs stacked on the sweep PR, each built by a helper agent in its own worktree:

- **Bugs PR** (`fix/spec-sweep-bugs-<YYYYMMDD>`): `/fix-spec-bugs` on the bug index, then
  `/full-review`. Skip it when the index has no bugs left to fix.
- **Findings PR** (`chore/spec-sweep-findings-<YYYYMMDD>`): `/plan` → `/architect-review` →
  `/code`, one commit per finding, then `/full-review`. Skip it when there are no fix items
  (answered questions count as fix items).

Both branch from the tip of `chore/spec-sweep` and both target it, so each PR's diff shows only its
own work. They are siblings, not a chain: either can merge first once the sweep PR is in.

Read `references/followups.md` now: it has the setup commands, both helper prompts, the checks you
run when they return, the PR body templates, and the cold review each follow-up PR gets once its body is up. The helpers run the long skill chains in their own
context, which matters this late in a sweep: by now yours holds every round.

## 6. Final report

In the terminal:

- table per category: specs done / skipped / failed, lines before→after, examples before→after,
  probes killed/total;
- the specs that failed or were skipped, with one-line reasons;
- bugs: count by severity and status, each listed with file:line, plus how many were dropped in
  verification and why;
- findings: fix / decide counts, and the decide questions listed one line each with where to
  answer them;
- the three PRs (sweep, bugs, findings) with links and status: ready, draft (and why), or skipped
  (and why), plus each follow-up's `bin/ci` result and cold review (comment link, tag counts, verify
  results), and `/settle-pr-review <n>` as the next step for any review with more than `verify` lines;
- how much of the queue remains (`inventory.rb` with no `--out` prints it) and the exact command to
  continue.

In `--audit` mode there are no commits, no ledger writes and no PRs (audit entries would otherwise
close specs before they are ever rewritten; `inventory.rb` ignores `mode: audit` lines as a
backstop). Write `.claude/audits/spec-sweep/AUDIT-<date>.md` with the same table, per-spec probe
survivors, the bugs and findings in the 3a/3b formats, and report its path.
