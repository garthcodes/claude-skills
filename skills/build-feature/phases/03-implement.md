# B1 — Implement

## Inputs

- Bootstrap per `_shared.md`. From the state file: the exact tickets path (do not let `/code` guess).
- Read the tickets doc's **Summary**, **Dependency Graph**, **Execution Order**, and
  **Phase Schedule** sections and each `## Phase N` heading's `**After:**` / `**Owns:**` lines.
  You do not need to read every ticket — the workers do.

## Steps

### Step 1: Implement, wave by wave, one worker per ticket phase

Follow the **Implementation workers** recipe in `_shared.md`. Every worker's `/code` argument is:

```
.claude/tickets-<actual-name>.md — scope: Phase N. Contract: .claude/acceptance-criteria/${FEATURE_NAME}.md
```

Walk the `## Phase Schedule` wave by wave. **No schedule** (older tickets doc) → treat every phase
as its own serial wave, in Execution Order.

- **Serial wave** (one phase, or Mode `serial`): launch one worker per phase, one after another,
  as the plain recipe says. Its specs use the default test DB.
- **Parallel wave** (Mode `parallel`, 2–3 phases): first make sure the per-worker test databases
  hold the current schema — run this once before the first parallel wave, and again before any
  later parallel wave if a serial wave since then added a migration:
  ```bash
  PARALLEL_TEST_PROCESSORS=3 bundle exec rake parallel:prepare_with_seeds 2>&1 | tail -5
  ```
  Then launch all of the wave's workers **in one message** (one Agent call each,
  `run_in_background: false`), giving the k-th worker `TEST_ENV_NUMBER` = `""`, `2`, `3` and its
  phase's `Owns:` globs (the *Parallel-wave additions* in `_shared.md`). Wait for all of them.
- **After each parallel wave**, check ownership before committing:
  `git status --short` → every changed path must match the `Owns:` of exactly one phase in the
  wave. A path outside every `Owns:` or touched by two workers: read its diff; keep it if the
  edits are compatible and correct, otherwise `git checkout -- <path>` (or delete the new file),
  untick the affected tickets, and re-run them in a serial follow-up worker. Record every such
  path under Known Issues → "Lane overlap" so the schedule rules can be tightened.
- **Commit after every wave** (serial or parallel) with specific paths:
  `feat: ${FEATURE_NAME} — wave <n> (Phase <a>, Phase <b>)`. Smaller commits make a relaunch
  resume cleanly.

Verify each worker's return (see `_shared.md`) before the next wave. If a worker ever comes back
while its own work is still running, wait on it (poll `git status` / its processes) — never start
a second worker for the same scope, and never return B1 while a worker is live (see `_shared.md`).
A parallel worker that died → relaunch that phase alone, once, with the same `TEST_ENV_NUMBER`;
its siblings' results stand.

**Resuming as a relaunch:** before launching anything, check for leftovers of the previous B1:
`pgrep -fl "rspec" | grep -v grep`, `git log --oneline main..HEAD` (wave commits), and the tickets
doc's checkboxes. Wait for (or kill) any rspec still running against this worktree's databases,
then resume at the first wave with an unticked ticket — relaunching only its unfinished phases.

**CRITICAL CONSTRAINTS (relay them; the template already does):**
- **Build to the contract** — nothing a ticket's ACs don't require, nothing a guard AC forbids. If a
  ticket needs something outside the contract, implement only the contract part and note the gap in
  the state file (B3's trace and Step 7.6 check it).
- **NO system tests** (`spec/system/`) and **NO feature specs** (`spec/features/`) — system tests are
  written in C1 against the reviewed code. All other specs (model, service, controller, component,
  policy, request) are expected.

Track per phase in your notes: completed / skipped / failed items and any deviations the worker
reported. A worker that reports BLOCKED items (dependency outside its scope not done) means a phase
ordering problem — run those items in a follow-up worker with `scope: TICKET-…` after their
dependency's phase completes. In a parallel wave, BLOCKED also means "needs a file outside my
`Owns:`" — run those items in a serial follow-up worker after the wave commits.

### Step 2: Branch specs once, then commit the fixes

Never run the whole suite here — a serial `bundle exec rspec` (system specs included) takes hours,
and `bin/ci` in C4 is the full-suite gate. Run only the non-system specs this branch touched or
added, plus the specs paired with every changed app file:

```bash
SPECS=$( { git diff --name-only origin/main...HEAD; git status --short | awk '{print $2}'; } \
  | sort -u | grep -E '^spec/.*_spec\.rb$' | grep -vE '^spec/(system|features)/' )
bundle exec rspec $SPECS 2>&1 | grep -E "examples?,|^rspec " | head -60
```

Fix failures introduced by this branch (max 3 cycles; delegate a non-trivial fix to a worker with the
failing spec paths and their output — direct edits are fine for one-liners). Pre-existing failures on
files this branch didn't touch: note them, don't chase them (memory: UTC date-boundary flakes in
`upsert_session_outcome_tasks_service_spec`, `generate_claim_for_appointment_service_spec`,
`recurring_appointment_service_spec` in the evening hours when the local date and the UTC date differ — confirm in `${PRIMARY_DIR}` if seen).

The wave commits already hold the implementation; commit whatever this step fixed (skip if
nothing changed):

```bash
git add <specific files>        # never -A
git commit -m "$(cat <<'MSG'
fix: ${FEATURE_NAME} branch spec failures

Fixes found by the branch-spec run after all implementation waves.

Co-Authored-By: [your standard Claude Code co-author line]
MSG
)"
```

### Step 3: Quick gates

Run the cheap CI gates NOW rather than discovering failures in C4 (after QA has blessed the code):

```bash
bin/standardrb --fix 2>&1 | tail -20      # then fix anything it can't auto-fix
bundle exec brakeman -q 2>&1 | tail -40   # fix any new warnings introduced by this branch
```

Commit any resulting fixes as a small `fix:` commit. Pre-existing brakeman warnings on untouched
files: note them, don't chase them. (`bin/ci` is C4's final gate — don't run it here.)

## CHECKPOINT

Update the state file: Phase Log B1 checked; Results with the wave commit hashes
(`git log --oneline main..HEAD`), waves run (and their width), a 2–3 line summary of what was built, per-phase worker outcomes
(completed/skipped/failed counts, SKIPPED items with reasons), suite result, lint/brakeman fixes;
Known Issues for anything skipped and every lane overlap.

## RETURN

```
B1 DONE
COMMITS: <hash> feat wave 1 … <hash> feat wave n, <hash> fix (if any)
TICKETS: <completed>/<total> completed; skipped: <ids or none>; failed: <ids or none>
SUITE: <n examples, m failures> (pre-existing: <list or none>)
WORKERS: <n> phases in <w> waves (max width <k>) on <IMPLEMENT_MODEL>, <relaunches>, <lane overlaps or none>
SUMMARY: <3–5 lines>
```
