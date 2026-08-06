---
description: Orchestrator that fixes every bug found by /full-qa. Walks a full-app-qa session's MASTER_INDEX.md and, for each section that has bugs, spawns a serial sub-agent running /fix-bug-index on that section's INDEX.md. Verifies fixes with Playwright, then commits that section's changes. One commit per section.
argument-hint: [<path-to-full-app-qa-dir-or-MASTER_INDEX.md>]
---

# Full App QA Fix Command

You are the **fix-side counterpart to `/full-qa`**. Where `/full-qa` produced a `full-app-qa-*` session containing a `MASTER_INDEX.md` and one `INDEX.md` per feature section, this skill walks that session and **fixes every reported bug**, section by section. After each section's fixes are made and verified, **you commit that section's changes** as a single commit, then move to the next section.

This is a healthcare app. Fixes must be correct, minimal, and verified — not papered over. You delegate each section's fix-and-verify work to a fresh sub-agent so the orchestrator's context never fills with Playwright snapshots or code reads.

## Argument
$ARGUMENTS

- **Empty:** auto-select the most recently modified `docs/bug-reports/full-app-qa-*/` directory that contains a `MASTER_INDEX.md`.
- **A path to a `full-app-qa-*` directory:** use its `MASTER_INDEX.md`.
- **A path to a `MASTER_INDEX.md`:** use it directly; the session dir is its parent.

If no `MASTER_INDEX.md` can be located, stop with a clear message naming what you looked for.

---

## CRITICAL: Continuous Execution (Non-Negotiable)

**This skill must run to completion in a single user invocation.** The most common failure mode of orchestrator skills is stopping after one section and waiting for the user to say "continue." DO NOT DO THIS.

After each section's sub-agent returns, the next thing you do — **in the same response** — is mark that section's task done and spawn the sub-agent for the next pending section, until every non-skipped section in your TaskList is `completed` or `error`.

### Banned phrasings (do not write any of these until the run is complete)

- "ready to continue?"
- "let me know if you want me to proceed"
- "I'll start the next section next"
- "should I continue?"
- "I'll pause here so you can review"
- "the next step would be to..."

If you feel the urge to write a sentence like any of these, instead **spawn the next section's sub-agent**.

### Legitimate stop conditions (exhaustive — no others are valid)

1. Every non-skipped section in your TaskList shows `completed` or `error` → write `FIX_ALL_SUMMARY.md`, print the final recap, stop.
2. The same hard environmental block occurs on three consecutive sections and cannot be auto-recovered (e.g., dev server unreachable after retries on three different section attempts) → write what's done clearly, stop.

"Wait for the user" is not a stop condition.

### Resume-from-compaction / re-invocation

If you reach this skill mid-run after a context compaction, or the user re-invokes it against a partially-fixed session:
- Re-read `MASTER_INDEX.md`.
- A section counts as **already fixed** if its subdir contains a `FIX_SUMMARY.md` (written by `/fix-bug-index`). Treat those as `completed` and do not re-run them.
- Rebuild your TaskList from the remaining sections-with-bugs.
- Resume by spawning the next pending section's sub-agent. **Do not ask the user "should I resume?"** — you have enough info to act.

### Retry policy for sub-agent failures

On any transient sub-agent failure (timeout, MCP error, browser crash, child skill error):
1. Retry once immediately.
2. Retry again after a 30-second wait.
3. If both retries fail, mark the section's task `error` with a one-line reason and move to the next section.
4. **Never report run failure to the user** unless an environmental block prevents progress on three consecutive sections.

---

## Phase 0: Pre-flight

The sub-agents drive Playwright to verify fixes (via `/bug-hunt-fix`), so the dev server must be up.

### Step 0.1: Dev server

```bash
curl -sk -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "not running"
```

If not 200: start `bin/dev` in the background and wait until curl returns 200 (10–15s typical). If after 60s the server is still unreachable, stop with: "Dev server failed to start. Run `bin/dev` in another terminal, then re-invoke."

### Step 0.2: `STAGING_MAGIC_LINK` is `true`

Read `config/environments/development.rb` and confirm the line ≈49 `ENV["STAGING_MAGIC_LINK"] ||= "true"` is present and uncommented. If missing/commented, report the exact line to add/uncomment and stop — sub-agents need the dev-shortcut "Sign in now" button to authenticate.

### Step 0.3: Print pre-flight summary

One line: "Pre-flight passed. Fixing bugs across <N> sections with reported bugs in <session-dir>." Do not ask the user to confirm. Proceed to Phase 1.

---

## Phase 1: Locate the Session and Parse the Master Index

### Step 1.1: Resolve the session

Per the Argument rules above, resolve to an absolute `MASTER_INDEX.md` path and its parent session directory. All section `INDEX.md` paths are relative to the session directory.

### Step 1.2: Parse the Progress table

Read `MASTER_INDEX.md`. Parse the `## Progress` table. Each row looks like:

```
| 01 | Client Management | done | admin, coordinator, ... | 0 | 3 | 4 | 1 | 8 | [01-client-management/](01-client-management/INDEX.md) |
```

For each row extract:
- `number` (e.g. `01`), `title`, `status` (e.g. `done` / `pending` / `error`)
- the **Total** bug count (the column before the Subdir link)
- the **Subdir INDEX.md path** from the markdown link in the last column

### Step 1.3: Determine which sections to fix

A section is **in scope for fixing** only if ALL of the following hold:
1. Its `INDEX.md` file actually exists on disk (resolve relative to the session dir).
2. Its parsed **Total** bug count is greater than 0 (a `done` row with Total `0`, or a `pending`/`–` row, has no bugs to fix — skip it).
3. It is not **skip-marked** — the row line does NOT contain `[SKIP]` (case-insensitive), `<!-- skip -->`, or `~~strikethrough~~`. (Same skip conventions `/fix-bug-index` honors.)
4. Its subdir does NOT already contain a `FIX_SUMMARY.md` (already fixed in a prior run — skip on resume).

Sections that are `pending`/`error` in the master index, have zero bugs, are skip-marked, or already carry a `FIX_SUMMARY.md` are **excluded** and recorded in the plan as skipped (with the reason).

### Step 1.4: Preserve order

Process sections in **numeric order** (01, 02, …) — same order they appear in the Progress table.

---

## Phase 2: Plan and Create the TaskList

Print a concise plan to the user:
- Session dir being processed
- Total sections in the master index
- Count to fix (sections with bugs, not skipped, not already fixed), with their numbers/titles and bug totals
- Count skipped, with reasons (no bugs / skip-marked / already fixed / INDEX missing)

**Then immediately create a TaskList** — one task per in-scope section, in numeric order. Use `TaskCreate` with titles like `Fix-all section 01: Client Management (8 bugs)`. The TaskList is your loop state — it is how you know what is left when control returns from a sub-agent.

Do not ask the user to confirm. Proceed directly into Phase 3.

---

## Phase 3: The Per-Section Fix Loop

Work through the TaskList one section at a time, in numeric order.

### Step 3.1: Mark the section task `in_progress`

`TaskUpdate` the section task you are about to work on so the live TaskList shows which section is being fixed right now.

### Step 3.2: Delegate the section to a sub-agent — MANDATORY

**First, capture the git baseline** so Step 3.5 can scope the commit to only this section's changes:

```bash
git status --porcelain > /tmp/full-qa-fix-before-NN.txt
```

**Why a sub-agent:** `/fix-bug-index` invokes `/bug-hunt-fix` once per bug, and each `/bug-hunt-fix` reads many code files and drives Playwright (accessibility snapshots can be 50K–400K characters). Running that inline in the orchestrator would exhaust the context window after one or two sections. The Agent tool exists exactly to protect the main context from these results.

**Concurrency rule (CRITICAL):** Playwright MCP is a single shared browser session. Sub-agents that drive Playwright **must run serially** — call `Agent` synchronously (do **not** set `run_in_background: true`). Concurrent agents will collide on the browser and corrupt each other's verification state.

**How to spawn:**

```
Agent(
  description: "Fix-all section NN: <title>",
  subagent_type: "general-purpose",
  prompt: <the self-contained brief below>
)
```

**Self-contained agent prompt template** (substitute the bracketed values):

```
You are the bug-fix execution agent for ONE feature section of a /full-qa-fix run.

CONTEXT:
- Section: [NN] — "[section title]"
- Section bug index (absolute path): [absolute path to docs/bug-reports/full-app-qa-TS/NN-slug/INDEX.md]
- This index lists [Total] bugs across severity buckets, plus any observations.
- Dev server is running at http://localhost:3000 and STAGING_MAGIC_LINK=true, so the dev-shortcut "Sign in now" button is available after submitting the email on /passwordless/users/sign_in.

YOUR JOB (end-to-end):
1. Invoke the /fix-bug-index skill via the Skill tool, passing the absolute path to this section's INDEX.md as the argument.
2. /fix-bug-index will loop over every non-skipped bug and observation in the index, invoke /bug-hunt-fix on each (which fixes the code and verifies with Playwright), and finally write a FIX_SUMMARY.md into this section's subdirectory. Let it run to completion — do not stop it early.
3. After /fix-bug-index finishes, read the FIX_SUMMARY.md it wrote and extract the counts (Fixed / Attempted / Failed / Skipped).

CONTEXT DISCIPLINE (CRITICAL — you must follow these to fit):
- Do NOT take full-tree Playwright snapshots; use depth-limited snapshots (depth 4-6) and target=<ref> scoping, as /bug-hunt-fix and its children already do.
- Do NOT pull large file contents or Playwright output into a final message.

RETURN VALUE (this is what the orchestrator sees — keep it under 4 lines):
"Section [NN]: Fixed <f> | Attempted <a> | Failed <x> | Skipped <s>. Summary: [absolute path to that section's FIX_SUMMARY.md]"

ERROR HANDLING:
- If /fix-bug-index errors before writing a summary, retry it once, then once more after 30 seconds. After the second failure, return:
  "Section [NN]: ERROR — <one-line reason>. No FIX_SUMMARY written."

NEVER:
- Run git commit / push / reset / stash / add. Leave the working tree dirty.
- Modify any skill file (/full-qa-fix, /fix-bug-index, /bug-hunt-fix).
- Edit the MASTER_INDEX.md or any INDEX.md (only /bug-hunt-fix's own bug-file edits and FIX_SUMMARY.md are allowed, and the child skill handles those).
- Commit, and do NOT close the browser at the end — the next section's agent reuses the session. (/bug-hunt-fix may close it during its own cleanup; that is fine, the next agent re-authenticates.)
- Spawn additional sub-agents — you ARE the sub-agent.
```

### Step 3.3: Parse the sub-agent's return value

The agent's final message will be one of:
- `Section NN: Fixed f | Attempted a | Failed x | Skipped s. Summary: <path>` → success. Capture the counts.
- `Section NN: ERROR — <reason>. No FIX_SUMMARY written.` → apply the retry policy; if still failing, mark the section task `error` and continue.

Do **not** read the section's individual bug files or FIX_SUMMARY into your own context — you only need the one-line counts for the master rollup.

### Step 3.4: Mark the section task `completed` (or `error`)

- Success line → `TaskUpdate` the section task to `completed`, recording the counts in your tracking.
- ERROR line (after retries) → `TaskUpdate` to `error` with a one-line reason. **Skip the commit step for an errored section** (there may be partial, unverified changes — leave them for the user) and continue to the anti-stop check.

### Step 3.5: Commit this section's changes

After a section completes successfully, commit exactly the files that changed during this section's run — and nothing else. **The working tree is dirty with unrelated noise** (other untracked `docs/bug-reports/*` directories from prior runs, stray `.yml` files, etc.); a blanket `git add -A` would sweep that junk in. Scope the commit precisely using a before/after snapshot.

**Before spawning the section's sub-agent (back in Step 3.2)**, capture the baseline:

```bash
git status --porcelain > /tmp/full-qa-fix-before-NN.txt
```

**Now, after the sub-agent returns successfully**, capture the current state and commit only the delta:

```bash
git status --porcelain > /tmp/full-qa-fix-after-NN.txt
# Paths that are new or newly-changed relative to the baseline:
comm -13 <(sort /tmp/full-qa-fix-before-NN.txt) <(sort /tmp/full-qa-fix-after-NN.txt) \
  | sed 's/^...//' > /tmp/full-qa-fix-delta-NN.txt
```

Then:
1. If the delta is empty (e.g. every bug was skipped or failed with no edits), **skip the commit** — there is nothing to commit. Note "no changes" in your tracking and continue.
2. Otherwise, stage exactly those paths and commit:
   ```bash
   git add --pathspec-from-file=/tmp/full-qa-fix-delta-NN.txt
   git commit -m "$(cat <<'EOF'
   fix(qa): section NN <title> — <f> fixed, <a> attempted

   Bug fixes from /full-qa-fix for section NN of MASTER_INDEX.md.
   Verified via /fix-bug-index → /bug-hunt-fix (Playwright).

   Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```
   Substitute the real section number, title, and counts. The delta naturally includes the code fixes, the per-bug "Fix Applied" edits, and that section's `FIX_SUMMARY.md`, while excluding pre-existing untracked junk.
3. **Branch safety:** before the first commit, check the current branch (`git rev-parse --abbrev-ref HEAD`). If it is the default branch (`main`), create and switch to a working branch first (e.g. `qa-fixes-<session-timestamp>`). On any non-default branch, commit in place.
4. **Never `git push`, `git reset`, or `git stash`.** Committing locally is the only git-write action; pushing is the user's call.

### Step 3.6: Anti-stop check

If any section task remains `pending`, go back to Step 3.1 with the next section **right now**. Do not pause, summarize, ask the user, or write the rollup.

---

## Phase 4: Final Rollup

Only after every section task is `completed` or `error`:

### Step 4.1: Write `FIX_ALL_SUMMARY.md`

Write to `<session-dir>/FIX_ALL_SUMMARY.md`. Keep it short — it is an index over the per-section `FIX_SUMMARY.md` files, not a restatement of them.

```markdown
# Full App QA — Fix Rollup

**Source session:** MASTER_INDEX.md
**Date:** [YYYY-MM-DD HH:MM local]
**Sections fixed:** X of Y in-scope (Z skipped, E errored)

## Totals

| Outcome | Count |
|---------|-------|
| Fixed | F |
| Attempted (not verified) | A |
| Failed | X |
| Skipped (within sections) | S |

## By Section

| # | Section | Fixed | Attempted | Failed | Skipped | Summary |
|---|---------|-------|-----------|--------|---------|---------|
| 01 | Client Management | 6 | 1 | 1 | 0 | [FIX_SUMMARY](01-client-management/FIX_SUMMARY.md) |
| ... |

## Errored Sections

- **NN — <title>** — <one-line reason> (no FIX_SUMMARY written)

## Skipped Sections

- **NN — <title>** — <reason: no bugs / [SKIP] / already fixed / INDEX missing>

---

## Commits

Each fixed section was committed as one local commit (`fix(qa): section NN ...`) on branch `<branch>`. Nothing was pushed. Review with `git log --oneline` / `git diff origin/main`, then push or amend as you see fit. Errored sections (if any) left their partial changes uncommitted — review those with `git status`.
```

### Step 4.2: Final message to the user

Two lines:
1. `Full-QA-Fix done. Sections fixed: X | Skipped: Z | Errors: E | Bugs fixed: F | Attempted: A | Failed: Xn`
2. `Rollup: <session-dir>/FIX_ALL_SUMMARY.md — X commits on <branch>, nothing pushed`

---

## Important Guidelines

1. **Commit once per section, scoped to that section's changes only.** Use the before/after `git status` delta so unrelated untracked files (other bug-report dirs, stray `.yml`s) are never swept in. Never `git push`, `git reset`, or `git stash` — local commits only; pushing is the user's call. The sub-agents themselves never commit; the orchestrator commits at the section boundary so each commit is atomic and follows verification.
2. **One sub-agent per section.** The sub-agent runs `/fix-bug-index` for the whole section; that child loops over bugs via `/bug-hunt-fix`. Do not spawn a sub-agent per bug, and do not run `/fix-bug-index` inline in the orchestrator.
3. **Sub-agents run serially.** Playwright is a single shared browser — never `run_in_background: true` for these.
4. **The orchestrator never drives Playwright and never reads bug files.** It reads only the one-line summary each sub-agent returns. This is what keeps the run inside the context budget.
5. **Respect skip markers** exactly as `/fix-bug-index` defines them: `[SKIP]`, `<!-- skip -->`, `~~strikethrough~~` — applied here at the section-row level in `MASTER_INDEX.md`.
6. **Skip sections with zero bugs** and sections still `pending`/`error` in the master index — there is nothing to fix.
7. **Resume is automatic.** A section with a `FIX_SUMMARY.md` is already done; skip it.
8. **Process sections in numeric order.**
9. **Keep going on failures.** One section erroring does not abort the batch.
10. **Never write the banned phrasings** until the run is complete.

---

## Execution Flow (Summary)

1. Pre-flight (dev server, `STAGING_MAGIC_LINK`).
2. Resolve session dir + `MASTER_INDEX.md` from `$ARGUMENTS` (or most-recent session).
3. Parse the Progress table → sections, totals, INDEX.md paths.
4. Filter to sections with bugs that aren't skip-marked or already fixed.
5. Print plan; `TaskCreate` one task per in-scope section in numeric order.
6. **Loop**: while any section task is `pending`: snapshot the git baseline, mark `in_progress`, spawn a serial `general-purpose` sub-agent that runs `/fix-bug-index` on that section's INDEX.md and returns ONE LINE of counts, parse it, mark `completed`/`error`, **commit that section's delta** (one commit per section, scoped via the before/after `git status` diff), immediately continue to the next section.
7. After the last section: write `FIX_ALL_SUMMARY.md`, print the recap. Each section's fixes are already committed; nothing is pushed.

**Why this fits in context:** the orchestrator spawns ~one sub-agent per section (typically 20–30) and reads ~one line back from each. Each sub-agent gets a fresh context for one `/fix-bug-index` run — and all the `/bug-hunt-fix` code reads and Playwright snapshots stay inside that sub-agent. The orchestrator's running cost is ~30 short summaries plus scaffolding.

---

## Anti-stop checklist (run after every sub-agent returns)

- [ ] Did I parse the sub-agent's one-line counts (or ERROR sentinel)?
- [ ] Did I mark the current section task `completed` (or `error`)?
- [ ] Did I commit this section's delta (scoped via the before/after `git status` diff), or correctly skip the commit (errored section, or empty delta)?
- [ ] Are there any `pending` section tasks left?
- [ ] If yes → snapshot the next section's git baseline and spawn its sub-agent RIGHT NOW. Do not summarize, do not ask, do not write the rollup.
- [ ] If no → write `FIX_ALL_SUMMARY.md` and print the recap.

Begin by running the Phase 0 pre-flight.
