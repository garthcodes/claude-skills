# /build-feature — shared instructions for every phase agent

Read this file first, then your own phase file (`phases/NN-*.md`). Together they are your complete
instructions; the coordinator prompt only carries identity values. Nothing in the coordinator's
context is available to you — the repo, `.claude/pipeline-state.md`, and these files are all you have.

## Identity (from the coordinator prompt)

| Value | Meaning |
|---|---|
| `PHASE` | Your agent ID: `A1 A2 B1 B2 B3 C1 C2 C3 C4` |
| `FEATURE_NAME` | kebab-case slug; branch is `feature/${FEATURE_NAME}` |
| `MAIN_DIR` | The launching checkout (the main repo checkout, or a `/prd-worktree` sibling like `../<repo>-<name>`). Source of the PRD and these phase files. Never run project commands there. |
| `PRIMARY_DIR` | The primary checkout (the main repo, even when launched from a `/prd-worktree`). Source of `.env` and certs; pipeline worktrees live under its `.claude/worktrees/`; pre-existing flakes are confirmed here. |
| `WORKTREE_PATH` | The pipeline worktree. A1 creates it (`pwd`); everyone else `cd`s into it first. |
| `PRD` | `.claude/prds/${FEATURE_NAME}.md` (relative to both checkouts) |
| `AC_PATH` | `.claude/acceptance-criteria/${FEATURE_NAME}.md` — the reviewed contract |
| `AC_REVIEW` | The contract review report path |
| `IMPLEMENT_MODEL` | Model for implementation workers (`sonnet` by default, or `inherit`) |

## Autonomous Execution Policy

**This pipeline runs end-to-end without stopping to ask the user for confirmation.** Do not pause at
retry limits or when issues are found. When a retry limit is reached, when a review still has open
feedback, or when a step partially fails:
- Make the best reasonable decision and keep going
- Record the remaining issue in `.claude/pipeline-state.md` (it becomes the PR's **Known Issues**)
- Only stop if a step is truly blocking (no worktree, git push rejected, `bin/ci` fails after all retry
  cycles) — and even then leave everything on disk and return a clear RETURN block

**The one deliberate exception to "always produce a PR" is the Acceptance Gate (C3/C4).** The reviewed
contract (`AC_PATH`, stamped PASS by `/review-acceptance-criteria`) is what the feature is built to
and gated on: if any **Must** criterion is still not VERIFIED after the bounded fix cycles, C4 pushes
the branch, keeps the worktree and state file for a resumable relaunch, and **stops without creating
a PR**. Unverified **Should** criteria open the PR as a draft. Every other gate degrades to "record it
and ship".

## Phase Agent Bootstrap (every agent except A1, which creates the worktree)

1. `cd ${WORKTREE_PATH}` — run EVERY command from this directory for the rest of your run.
2. Read `.claude/pipeline-state.md` — the authoritative record of what prior agents did: artifact
   paths, review verdicts, commit hashes, known issues.
3. Verify: `git branch --show-current` shows `feature/${FEATURE_NAME}`;
   `grep -E '^(DATABASE_SUFFIX|PORT)=' .env` shows both values. **Always read `WORKTREE_PORT` from
   `PORT=` in `.env`** — never from a number an earlier agent returned (ports can be reassigned).
4. Read the PRD at `${PRD}` and the contract at `${AC_PATH}`. The contract is what you are building
   to: every row must end up observable, and every `guard` row is a prohibition.
5. `git log --oneline main..HEAD` — if the state file says a step you're about to do is already done,
   don't redo it (you may be a relaunch after a failed run).

All skills you invoke (via the Skill tool) operate on your current working directory — as long as you
stay in the worktree, they need no special configuration. `DATABASE_SUFFIX` and `PORT` in the
worktree's `.env` isolate its databases and dev server automatically.

## The handoff contract: `.claude/pipeline-state.md`

Each agent finishes by bringing it up to date; each subsequent agent starts by reading it. Update it
with `Edit` (never re-print the whole file). Required structure:

```markdown
# Pipeline State: ${FEATURE_NAME}

## Identity
- FEATURE_NAME: <slug>
- BRANCH: feature/<slug>
- WORKTREE_PATH: <absolute path>
- MAIN_DIR: <absolute path>
- PRIMARY_DIR: <absolute path>
- WORKTREE_PORT: <PORT= in .env>
- DB_SUFFIX: <suffix>
- IMPLEMENT_MODEL: <sonnet | inherit>
- PRD: .claude/prds/<slug>.md
- AC_PATH: .claude/acceptance-criteria/<slug>.md
- AC_REVIEW: <path> (verdict, Must/Should/guard counts)

## Phase Log
- [ ] A1 Setup & plan
- [ ] A2 Plan reviews & tickets
- [ ] B1 Implement
- [ ] B2 Code review
- [ ] B3 Security & trace
- [ ] C1 System tests
- [ ] C2 QA
- [ ] C3 Acceptance gate
- [ ] C4 Ship

## Artifacts
- Implementation plan: <path>
- Tickets: <path>
- (later agents append: fix plan, trace report, test plan, QA plan, scorecard paths, commit hashes)

## Results
- (verdicts, counts, and summaries appended per phase — see each phase file's CHECKPOINT)

## Acceptance
- Contract: <AC_PATH> (review PASS <date>; N rows — Must X / Should Y / guards Z)
- Verdict: (PASS | PASS WITH SHOULD GAPS | FAIL) — scorecard: <path>
- Must: X/Y • Should: X/Y • Guards: X/Y
- (one line per non-VERIFIED AC: `AC-n (Must, FAILED|UNVERIFIED) — reason`)

## Scope Drift
- (B3 Step 7.6: surfaces in the diff with no AC/FR justification — removed or kept-with-reason)

## Known Issues
- (subsections per source: Architect Review, Frontend Review, Review, Security,
  Requirements Trace, System Tests, CI, QA)

## Deferred
- (P3 review tickets etc.)
```

**Recovery:** all work is committed or on disk and the state file is authoritative, so a phase agent
that dies or returns unusable output is relaunched with the same prompt — it re-reads the state file
and `git log` and continues where the last one stopped. Never restart the pipeline from scratch.

## Parallel pairs (B2 ‖ B3, C1 ‖ C2)

The coordinator launches B2 with B3, and C1 with C2, at the same time in the same worktree. The first
of each pair is the **lead**, the second the **follower**.

- **Lead (B2, C1):** work exactly as your phase file says. Check your Phase Log box in the state file
  as your **very last** action, after your final commit — the follower is waiting on that box, so
  never check it early, and never leave it unchecked when you return (even on partial failure: check
  it and record what is incomplete).
- **Follower (B3, C2):** do the read-only / non-conflicting part of your phase immediately (your
  phase file marks where it ends). Until the lead's box is checked you may write only untracked
  scratch and your own report files (`tmp/`, `log/`, `.claude/requirement-traces/`, security notes,
  `docs/qa-plans/`, `docs/bug-reports/`, `tmp/pr-screenshots/`) — no edits to tracked app/spec files,
  no `git add`/`commit`, no state-file edits, no rspec runs against the test DB (C2's dev-DB work is
  fine). Then wait:
  ```bash
  LEAD=B2   # or C1
  for i in $(seq 1 54); do grep -qE "^- \[x\] ${LEAD} " .claude/pipeline-state.md && break; sleep 10; done
  grep -qE "^- \[x\] ${LEAD} " .claude/pipeline-state.md && echo LEAD_DONE || echo STILL_WAITING
  ```
  Repeat the call until `LEAD_DONE` (up to ~90 min; past that, record "lead did not finish" under
  Known Issues and continue on the current HEAD). Then `git log --oneline -5` and
  `git diff --name-only <HEAD before the wait>..HEAD`: re-check each of your findings against the new
  HEAD (the lead may already have fixed or moved the code), and re-run whatever your phase file says
  to re-run when the lead changed app files. Only then apply fixes, commit, and write the state file.
- Both members: commit with specific paths only (never `-A`), so neither sweeps up the other's files.

## Context hygiene (why there are nine agents)

Every tool call re-reads your whole context, so total tokens grow with the square of what you let in.
Keep tool output small; the work is the same.

- **rspec**: `bundle exec rspec <files> 2>&1 | tail -40`. Never run a bare `bundle exec rspec`
  (whole suite, serial, system specs included — hours); `bin/ci` in C4 is the only full-suite run.
- **bin/ci** (C4 only): run it detached and poll — never return while it is running:
  ```bash
  mkdir -p log tmp; nohup bin/ci > log/ci-run1.log 2>&1 & echo $! > tmp/ci.pid
  # repeat this poll (each call ≤ 9 min) until it prints DONE
  for i in $(seq 1 54); do kill -0 "$(cat tmp/ci.pid)" 2>/dev/null || break; sleep 10; done
  kill -0 "$(cat tmp/ci.pid)" 2>/dev/null && echo STILL_RUNNING || echo DONE
  grep -nE "examples, [0-9]+ failures?|^rspec \./|FAILED|rror|Offenses|warnings? found" log/ci-run1.log | head -60
  ```
- **Waiting on a process**: poll its pid (`for i in $(seq 1 54); do kill -0 $PID 2>/dev/null || break; sleep 10; done`)
  or grep its log for the completion line — never a fixed `sleep 240`, which wastes time after the
  process ends.
- **Never return while anything you started is still running** — a worker sub-agent, a background
  `rspec`, a poll loop. Wait for it (poll as above) or stop it (`kill`) and say so in the RETURN
  block (the one exception: C2's detached `bin/dev` server, which is meant to outlive the pipeline). A RETURN with live children makes the coordinator relaunch you on top of them (duplicate
  workers, `PG::TRDeadlockDetected` on the shared test DB). Before returning, confirm:
  `pgrep -fl "rspec|bin/ci" | grep -v grep` shows nothing started by you.
- **Edit docs with Edit/Write, not Bash.** Plans, tickets, reports, the state file, and PR bodies are
  changed with the `Edit` / `Write` tools — never `python3 - <<'EOF'`, `sed`, or `cat > … <<EOF`.
  These docs quote deploy commands (`bin/deploy production`, `fly … -a <app-name>`), and the
  `claude-hook-prod-guard.py` PreToolUse hook scans the whole Bash command text: a doc edit through
  Bash triggers a production-approval prompt that no one answers (cost: 18 min + a denied edit in
  the 2026-09-22 run). Commit messages: keep deploy commands out of them, or use `git commit -F <file>`
  with the file written by `Write`.
- **git**: `git diff --stat` / `--name-only` first; a full diff only per file.
- **Read**: reports, plans, tickets, and the contract once in full; code files by `offset`/`limit`
  when you know the region. Don't re-read what you just wrote.
- **Sub-agents and workers**: ask for a structured return ≤ ~40 lines. Don't paste their output into
  your own text; summarize into the state file.
- **Browser** (C2/C3): follow `/execute-qa`'s snapshot discipline (depth 5, `target:`, `filename:`).
- **Skill output**: when a skill offers a report file, read the file's verdict section, not the whole
  transcript again.

## Implementation workers (B1, B2, B3)

All `/code` work runs in **fresh worker sub-agents** on `IMPLEMENT_MODEL`, one per scope, launched
with `run_in_background: false`. You order, verify, and commit; the worker implements. Workers run
**sequentially**, with one exception: B1 launches the 2–3 phases of a tickets doc's `parallel` wave
together (several Agent calls in one message), per `03-implement.md`. B2 and B3 workers are always
sequential.

```
Agent(
  subagent_type: "general-purpose",
  model: "${IMPLEMENT_MODEL}",          # omit the model parameter when IMPLEMENT_MODEL=inherit
  run_in_background: false,
  description: "Implement <scope> ${FEATURE_NAME}",
  prompt: <template below>
)
```

Worker prompt template (fill every placeholder; paste nothing else):

> Work in `${WORKTREE_PATH}` — `cd` there first and run every command from that directory. Feature:
> `${FEATURE_NAME}`. Read `CLAUDE.md` conventions as you go.
> Invoke the `/code` skill via the Skill tool with the argument:
> `<work doc path> — scope: <Phase N | TICKET-x, TICKET-y | P0–P2>. Contract: ${AC_PATH}.`
> Rules: implement exactly what the scoped items' cited ACs require; `guard` ACs are prohibitions.
> Do NOT create files under `spec/system/` or `spec/features/`. Do NOT commit.
> Spec runs: only the spec files you created or edited plus the specs paired with the app files you
> changed (`bundle exec rspec <those files>`) — never a bare `bundle exec rspec` and never whole
> directories (`spec/models`, `spec/services`, `spec/components`, … are ~40k examples; the caller
> runs the branch set). Every spec example you add names the contract rows it proves in its
> description, e.g. `it "blocks with the FR-11 message (AC-25, AC-125)"`.
> Run nothing in the background and leave no process running when you return. When `/code` finishes,
> return ONLY: its report block verbatim, then the output of `git status --short`.

**Parallel-wave additions** (B1 only; append to the Rules line for each worker of a `parallel` wave):

> Other workers are editing this working tree at the same time. You own only these paths:
> `<the phase's Owns: globs>` — create or modify no other tracked file. No migrations, no
> `bin/rails db:*`, no `bin/rails generate` that touches `config/routes.rb` or `db/`. If an item needs
> a file outside your paths, don't implement it; report it BLOCKED with the file it needs.
> Prefix every spec run with `TEST_ENV_NUMBER=<n>` (your own test database), e.g.
> `TEST_ENV_NUMBER=2 bundle exec rspec <files>`. Run `bin/standardrb --fix` only on files you
> changed.

(Worker 1 of a wave gets `TEST_ENV_NUMBER=` empty, i.e. the default test DB; workers 2 and 3 get
`2` and `3`.)

For non-`/code` work (trace-gap tickets in B3) use the same template but replace the `/code` line with
the ticket text pasted verbatim plus "write the unit/controller/component/policy specs for each fix".

**Verify each worker's return before the next one:** no unexplained `Failed`/`Skipped`; `git status
--short` touches the ticket's files (and not `db/schema.rb` by hand, not `spec/system/`); `/code`
ticked the items' checkboxes in the work doc. Spot-run a spec only when the report is suspicious — the
branch-spec run at the end is the real check. Worker died or returned nothing usable → relaunch
that scope **once** (`/code` resumes from the ticked checkboxes); still failing → mark those items
SKIPPED in the state file with the reason and continue.

## Important Guidelines

1. **Nine phase agents, one worktree** — A1 (`isolation: "worktree"`) creates the worktree; every
   other agent `cd`s into it. `.claude/pipeline-state.md` is the only handoff — leave it complete
   enough that the next agent (or a relaunch of you) can proceed without any other context.
2. **System tests have a dedicated phase** (C1) — excluded from `/plan`, `/tickets`, and `/code`,
   then written against the reviewed code. Feature specs (`spec/features/`) are never created.
   Playwright QA (C2) is a separate, additional verification layer.
3. **Incorporate review feedback into the plan** — edit the plan, don't just note the feedback.
4. **Maximum retry cycles** — plan reviews 2 parallel rounds (one merge pass each); security review
   and requirements-trace gate 1 fix cycle each; QA bug fixes 2 cycles; acceptance-gap closing 2
   cycles; system-test fixes 2 rounds; CI 3 cycles. At a limit: record the issue in the state file
   and continue. Never pause to ask the user.
5. **The reviewed contract is the spec** — only `/review-acceptance-criteria` may edit it, and only
   before `/plan`. Never weaken a spec, delete a QA scenario, or mark a row VERIFIED from code reading
   to turn a row green. A contract that turns out wrong mid-pipeline is a `GATE FAILED` outcome.
6. **Nothing left out, nothing extra** — every AC gets a plan step, a ticket, code, and evidence;
   every new surface in the diff names the AC that requires it (B3 Step 7.6); every `guard` AC is a
   prohibition at every phase. "Helpful" additions no AC/FR asks for are declined and noted.
7. **UI Copy Discipline** — new UI carries labels, values, headings, button verbs, and validation
   errors; every other visible string needs an AC that names it or a one-line reason in the plan's
   `### Copy` table (CLAUDE.md). A copy finding is never resolved by adding text.
8. **Commit incrementally** with specific `git add <files>` (never `-A`); end every commit message
   with your standard Claude Code co-author trailer.
9. **Per-worktree port and databases** — `PORT=` and `DATABASE_SUFFIX=` in the worktree `.env`;
   never hardcode a port, never remove the suffix, never run against the shared databases.
10. **Clean up after yourself** — close the browser, delete temp files; the worktree dev server is
    deliberately **left running** for review.

## Error Handling

Record issues and keep moving — do NOT pause mid-pipeline to ask the user.

- **Worktree setup fails** (A1): retry once, then return the error (the pipeline cannot continue).
- **Isolated database setup fails** (A1's `db:schema:load` / `db:seed:mini`): `bundle install`, retry
  once; still failing → return the error. Never fall back to the shared `<app>_development`.
- **Port range exhausted** (`bin/worktree-port` exits 1): return its message; suggest the user run `/worktree-sweep`
  (removes every pipeline worktree).
- **Plan reviews still have open findings after 2 rounds**: final merge pass, record the rest under
  Known Issues (Architect/Frontend Review), proceed.
- **Worker fails on specific tickets**: relaunch that scope once, then SKIP those tickets, log them
  under Known Issues, continue with the rest.
- **Security Critical/High finding unfixable in one cycle**: record under Known Issues (Security)
  marked **UNRESOLVED — blocker for merge**; proceed.
- **Requirements trace still shows gaps after the fix cycle**: record each PARTIAL/MISSING FR under
  Known Issues (Requirements Trace); proceed (a Must gap must be prominent in the PR).
- **System test unfixable after 2 `/fix-system-test` rounds**: mark it `pending("<reason> — see PR
  Known Issues")`, record it, continue. Never delete the test or weaken its assertions.
- **Dev server won't start**: check `log/dev-server.log`, try `bundle install && bin/rails db:migrate`,
  then skip QA and note "QA skipped: dev server unavailable".
- **QA finds bugs after 2 fix cycles**: note the remaining bugs, continue.
- **A `guard` AC FAILS in `/verify-acceptance`**: an extra was built — remove the code, never the guard.
- **`/verify-acceptance` finds no QA report or no `Verifies:` tags**: browser ACs are UNVERIFIED, never
  assumed PASS — fix the coverage rather than arguing with the verdict.
- **Acceptance FAIL after 2 gap cycles**: C4 still runs through the push, then stops without a PR.
- **Acceptance PASS WITH SHOULD GAPS**: draft PR with the unverified Should rows at the top.
- **Simplification pass breaks tests**: fix within the CI cycles or `git revert` the simplify commit.
- **Tests fail after 3 CI cycles**: record them, open the PR as a draft (subject to the gate).
- **Screenshot publish fails**: write "Screenshots: not available" in the PR body, continue.
- **Rebase can't be resolved confidently**: `git rebase --abort`, push un-rebased, note "branch is
  behind main; rebase needed before merge".
- **PR creation fails**: check `gh auth status`, retry once; then leave the branch pushed and return
  the manual `gh pr create` command.
