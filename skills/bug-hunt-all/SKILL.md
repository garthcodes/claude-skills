---
description: Hunt for bugs across every top-level feature section in docs/APP_FEATURES.md using Playwright. Sequential, resumable, one master index at the end. Does not fix bugs.
argument-hint: [<path-to-existing-full-app-sweep-dir-to-resume>]
---

# Bug Hunt All Command

You are tasked with running `/bug-hunt` against **every top-level section** of `docs/APP_FEATURES.md` and aggregating the results into a single, resumable session. **You do NOT fix bugs.** You orchestrate per-section hunts and produce a master index.

## Argument
$ARGUMENTS

- If `$ARGUMENTS` is empty: start a new sweep — create a fresh session directory.
- If `$ARGUMENTS` is a path to an existing `docs/bug-reports/full-app-sweep-*` directory: resume that sweep — pick up where it stopped.

## CRITICAL: You Are The Orchestrator

You will invoke `/bug-hunt` via the Skill tool once per non-skipped section. That child skill's instructions look like a complete end-to-end task (cleanup, final report, etc.) — **they are not the end of YOUR task**. They are one iteration of a loop.

When a `/bug-hunt` invocation returns:
- **DO NOT stop, summarize, or report completion.**
- **DO NOT treat its final cleanup step as the end of the batch.**
- Update your TaskList to mark that section done, refresh the MASTER_INDEX rollup row for that section, then **immediately invoke `/bug-hunt` for the next pending section** in the same response.
- Only after the TaskList shows every non-skipped section completed do you write the final MASTER_INDEX rollup and stop.

The single most common failure mode of this skill is stopping after the first section. Guard against it by checking the TaskList every time control returns to you: if there are any pending section tasks, the next thing you do is invoke `/bug-hunt` on the next one — no exceptions, no asking the user.

## Phase 1: Parse `docs/APP_FEATURES.md`

### Step 1: Read the catalog
Read `docs/APP_FEATURES.md` (repo-relative). The file is organized as:

```
## 1. Client Management

### 1.1 Subsection
- Feature bullet
- Feature bullet

### 1.2 Subsection
- ...

---

## 2. Appointments & Scheduling
...
```

### Step 2: Extract sections
Build an ordered list of top-level sections. For each `## N. Title` heading:
- `number` — the integer `N` (zero-padded to `NN` for filenames)
- `title` — the full heading text after `N. ` (e.g., `Client Management`, `BioPsychoSocial Assessment (BPS)`)
- `slug` — kebab-case slug from the title (e.g., `client-management`, `biopsychosocial-assessment-bps`). Strip parentheses, ampersands, slashes; collapse whitespace to single hyphens; lowercase.
- `body` — everything between this heading and the next `## ` heading (the subsections + bullets). Keep verbatim — it is what you pass to `/bug-hunt` as feature context.

Use `grep -nE '^## [0-9]+\.' docs/APP_FEATURES.md` to locate boundaries quickly. Parse every top-level section of `docs/APP_FEATURES.md` — do not hardcode a section count.

## Phase 2: Session Setup

### Step 3: Choose the session directory

**New sweep (`$ARGUMENTS` empty):**
1. Generate a timestamp `YYYYMMDD-HHMMSS` from local time.
2. Session dir: `docs/bug-reports/full-app-sweep-{YYYYMMDD-HHMMSS}/`
3. Create it. (Do not create per-section subdirs yet — `/bug-hunt` creates its own when it finds its first bug.)

**Resume (`$ARGUMENTS` is a path):**
1. Verify the path exists and matches `docs/bug-reports/full-app-sweep-*`. If not, abort with a clear error.
2. Use it as the session dir. Do not regenerate `MASTER_INDEX.md` from scratch — preserve user edits (skip markers especially).

### Step 4: Write the skeleton `MASTER_INDEX.md` (new sweep only)

Path: `<session-dir>/MASTER_INDEX.md`. Use this template — keep section lines on their own line so the user can pre-add `[SKIP]` markers before running:

```markdown
# Full App Bug Sweep

**Date started:** YYYY-MM-DD HH:MM
**Source:** docs/APP_FEATURES.md
**Base URL:** [the $BASE_URL used for this sweep]

This sweep runs `/bug-hunt` against each top-level section of `docs/APP_FEATURES.md`. Each section gets its own subdirectory with its own `INDEX.md` and `BUG-*.md` files. Open any section's `INDEX.md` to feed it to `/fix-bug-index`.

To skip a section, add `[SKIP]` to its line below before (re-)running this skill. Strikethrough (`~~...~~`) also works.

## Progress

| # | Section | Status | Crit | High | Med | Low | Total | Subdir |
|---|---------|--------|------|------|-----|-----|-------|--------|
| 01 | Client Management | pending | – | – | – | – | – | [01-client-management/](01-client-management/INDEX.md) |
| 02 | Appointments & Scheduling | pending | – | – | – | – | – | [02-appointments-scheduling/](02-appointments-scheduling/INDEX.md) |
| ... | ... | ... | ... | ... | ... | ... | ... | ... |
| NN | Last Section | pending | – | – | – | – | – | [nn-last-section/](nn-last-section/INDEX.md) |

## Sections

- [01. Client Management](01-client-management/INDEX.md)
- [02. Appointments & Scheduling](02-appointments-scheduling/INDEX.md)
- ...
- [NN. Last Section](nn-last-section/INDEX.md)

## Rollup

_Filled in after the sweep completes._
```

Populate every row from the parsed section list — do not abbreviate with `...`. The `Subdir` column links are pre-populated even though the directories don't exist yet; they will exist after `/bug-hunt` runs for that section.

### Step 5: Apply skip markers
Read the current `MASTER_INDEX.md` (the one you just wrote, OR the existing one when resuming). For each section row, a section is **SKIPPED** if its row contains any of:
- `[SKIP]` (case-insensitive)
- `<!-- skip -->` (case-insensitive)
- `~~strikethrough~~` wrapping any part of the row

Record the skip reason as the raw marker text. Skipped sections do not get hunted and do not appear in the TaskList.

### Step 6: Detect already-completed sections (resume only)
For each section, check whether `<session-dir>/{NN}-{slug}/INDEX.md` already exists. If it does, treat that section as **already completed**:
- Read its severity counts (parse the summary table at the top of the sub-INDEX)
- Update the MASTER_INDEX row to `status: done` with those counts
- Do NOT include it in the TaskList — there is nothing left to do

## Phase 3: Create the TaskList

Create one task per non-skipped, not-yet-completed section using TaskCreate. Task title format: `Bug-hunt section NN: <title>`. Order = section number ascending.

The TaskList is your loop state. It is the only reliable way to know what's left when control returns from a child `/bug-hunt` call.

Print a one-paragraph plan to the user: total sections, count to hunt, count skipped, count already done. Do not ask the user to confirm. Proceed directly to Phase 4.

## Phase 4: Pre-flight Once (Shared Setup)

Do these once, before the loop — `/bug-hunt` re-checks them, but doing them up front lets you fail fast and gives the child something to share.

### Step 7: Base URL and dev server
This checkout may be the main repo (default port) or a `/build-feature` worktree with its own
server and database (`PORT=` in `.env`). Resolve the URL first, then check the server —
and pass `$BASE_URL` down to each `/bug-hunt` child so the whole sweep stays on one app.

```bash
BASE_URL="$(bin/dev-url)"   # $PORT > PORT= in .env > 3000
curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL" 2>/dev/null || echo "not running"
```
If not 200, start `bin/dev` in the background (it reads `PORT=` from `.env`) and wait until the curl returns 200 (10–15s typical).

### Step 8: Browser
Resize for staff/admin (most sections):
```
mcp__playwright__browser_resize(width: 1280, height: 800)
```
Client Portal sections (13, parts of 11.4) require mobile (375x667). `/bug-hunt` will resize as needed per its viewport strategy — you do not need to switch ahead of time.

### Step 9: Authenticate once
Navigate to `$BASE_URL`, request a magic link for `admin@example.com` (full access covers nearly all sections), pull the link from `tail -100 log/development.log | grep -A5 "magic_link"`, and navigate to it. Verify you land on the dashboard.

Most sections work as admin. Two exceptions where the child should switch user:
- **13. Client Portal** — needs a client-side session. The child can re-auth via portal verification token from the dev logs.
- **9. Supervision** — supervisor role (`supervisor@example.com`) is more representative.

`/bug-hunt` is allowed to re-authenticate as a different user if needed. Do not block on this.

## Phase 5: The Hunt Loop

### Step 10: For each pending task

1. Pick the first task with status `pending`. Mark it `in_progress` via TaskUpdate.

2. Build the `$ARGUMENTS` for `/bug-hunt`. This MUST include the `Output dir:` override so the child writes into the master session dir instead of a fresh timestamped sibling, and the `Base URL:` override so the child hunts the same server this sweep resolved in Step 7:

   ```
   Section NN: <Title>

   Output dir: docs/bug-reports/full-app-sweep-<TS>/<NN>-<slug>/
   Base URL: <the $BASE_URL resolved in Step 7>

   Features in this section (from docs/APP_FEATURES.md):

   <verbatim body of the section: ### subsections and bullet lists>
   ```

   Pass that block as the argument to the Skill tool when invoking `/bug-hunt`. The child skill honors both `Output dir:` and `Base URL:` — confirm it wrote into the expected subdir after it returns.

3. When `/bug-hunt` returns:
   a. Read `<session-dir>/<NN>-<slug>/INDEX.md` if it exists (the child only creates it if it found at least one bug). If it does not exist, treat the section as **zero bugs found**.
   b. Parse the severity counts from the sub-INDEX summary table. If zero bugs, write a stub sub-INDEX at `<session-dir>/<NN>-<slug>/INDEX.md` with body:
      ```markdown
      # Bug Hunt Summary: <Title>

      **Date:** <ISO>
      **Result:** No bugs found.

      | Severity | Count |
      |----------|-------|
      | Critical | 0 |
      | High | 0 |
      | Medium | 0 |
      | Low | 0 |
      | **Total** | **0** |
      ```
      Creating the stub matters: it makes resume detection work correctly and gives the master INDEX a valid link.
   c. Update the MASTER_INDEX row for this section: set status to `done`, fill in the severity columns.
   d. Mark the task `completed` via TaskUpdate.
   e. **Anti-stop check** — see the checklist at the end of this file. If any task remains `pending`, immediately go back to substep 1. Do NOT pause, summarize, or hand back to the user.

4. If `/bug-hunt` errors or stops abnormally (crash, can't reach the app, child reports "diff empty" — shouldn't happen here since we're in Mode A, but defend against it):
   - Mark the section's MASTER_INDEX row as `error` and record a one-line reason in the row's notes column (you may add a `Notes` column to the table if useful).
   - Mark the task `completed` (it is done from the loop's perspective; the outcome is just `error`).
   - Continue with the next pending task.

### Step 11: Do not commit
Leave the working tree dirty for the user. Do not run `git add`, `git commit`, `git stash`, `git reset`, or `git push`. Read-only git commands are fine.

## Phase 6: Final Rollup

Only after every task is `completed`:

### Step 12: Write the rollup
Update `<session-dir>/MASTER_INDEX.md`:
- Add `**Date finished:** YYYY-MM-DD HH:MM` near the top
- Fill in the `## Rollup` section with:

```markdown
## Rollup

| Severity | Count |
|----------|-------|
| Critical | X |
| High | X |
| Medium | X |
| Low | X |
| **Total** | **X** |

**Sections hunted:** X
**Sections skipped:** Y (see [SKIP] markers above)
**Sections with errors:** Z
**Sections with zero bugs:** W

To fix bugs from a single section, run:
`/fix-bug-index docs/bug-reports/full-app-sweep-<TS>/<NN>-<slug>/INDEX.md`

To process every section's bugs sequentially, run `/fix-bug-index` against each sub-INDEX in turn. There is no flat master index of individual bugs by design — keeping per-section scope makes review and triage tractable.
```

### Step 13: Close the browser
`mcp__playwright__browser_close`.

### Step 14: Final message to the user
Two lines:
1. `Sweep done. Hunted: X | Skipped: Y | Errors: Z | Bugs found: <total>`
2. `Master index: docs/bug-reports/full-app-sweep-<TS>/MASTER_INDEX.md (nothing committed)`

## Resumability Notes

- The master session dir is the source of truth for progress. If the conversation crashes or is interrupted, the user re-invokes `/bug-hunt-all <path-to-session-dir>` and you pick up.
- TaskList state is NOT persisted across conversations. On resume you rebuild it from the disk: any section whose sub-INDEX.md exists counts as completed; everything else (minus skips) goes back into pending.
- Skip markers added between runs are honored — re-read MASTER_INDEX.md fresh on each resume.
- If a section has a sub-INDEX.md but the user wants to re-hunt it, they should delete that subdirectory before resuming.

## Important Guidelines

1. **DO NOT FIX BUGS.** Only find and document them. The user runs `/fix-bug-index` afterward.
2. **Do not commit, stage, stash, push.** The user reviews manually.
3. **Respect skip markers** exactly as `/fix-bug-index` defines them: `[SKIP]`, `<!-- skip -->`, `~~strikethrough~~`.
4. **Process sections in numeric order.** Do not reorder by severity or guesswork.
5. **Pass `Output dir:` in every `/bug-hunt` invocation.** Otherwise the child writes to a sibling timestamped dir and the master index links break.
6. **One section = one `/bug-hunt` invocation.** Do not split or merge sections. The catalog is the contract.
7. **Don't pre-read the section's app code yourself.** That's the child's job. Your job is dispatch + rollup. Reading the catalog body is enough.
8. **Don't replay authentication unless the child explicitly fails because the session expired.** The child shares the parent's browser session.
9. **Keep MASTER_INDEX.md edits idempotent.** Update the existing row in place rather than appending; the user may resume mid-sweep and stale duplicate rows would break parsing.

## Execution Flow

1. Parse `docs/APP_FEATURES.md` → ordered list of 30 sections
2. Decide new vs. resume from `$ARGUMENTS`
3. Write or read MASTER_INDEX.md skeleton (preserve skip markers on resume)
4. Detect already-completed sections from existing sub-INDEX.md files
5. Apply skip markers
6. TaskCreate one task per non-skipped, not-yet-done section
7. Print plan, do shared pre-flight (server, browser, auth)
8. **Loop**: while any task is `pending`, pick next, invoke `/bug-hunt` with `Output dir:` override, update MASTER_INDEX row from sub-INDEX, mark completed, **immediately continue**
9. After last task: write rollup, close browser, print recap

## Anti-stop checklist (after every `/bug-hunt` invocation returns)

- [ ] Did the sub-INDEX exist? If not, did I write a zero-bugs stub?
- [ ] Did I update the MASTER_INDEX row with the new counts and status?
- [ ] Did I mark the current task `completed`?
- [ ] Are there any `pending` tasks left?
- [ ] If yes → invoke `/bug-hunt` for the next one **right now**. Do not stop, do not write rollup, do not ask the user.
- [ ] If no → write rollup, close browser, print recap.

Begin by reading `docs/APP_FEATURES.md` and parsing the section list.
