---
description: Walk a QA bug-report INDEX.md and run /bug-hunt-fix on each unskipped item, then write a summary of what was fixed. Does not commit.
argument-hint: <path-to-INDEX.md>
---

# Fix Bug Index Command

You are tasked with walking a QA bug-report `INDEX.md` and invoking `/bug-hunt-fix` on each referenced bug/observation file that the user has not marked to skip. After all items are processed, write a short summary document describing what was fixed and what was skipped. **Do NOT stage, commit, or push any changes** — leave the working tree dirty for the user to review.

## Index to Process
$ARGUMENTS

## CRITICAL: You Are The Orchestrator

You will invoke `/bug-hunt-fix` via the Skill tool once per non-skipped item. That child skill's instructions look like a complete end-to-end task ("Clean Up", "Error Handling", final verification message) — **they are not the end of YOUR task**. They are one iteration of a loop.

When a `/bug-hunt-fix` invocation finishes:
- **DO NOT stop, summarize, or report completion.**
- **DO NOT treat its final "cleanup" step as the end of the batch.**
- Update your TaskList to mark that item done, then **immediately invoke `/bug-hunt-fix` for the next non-skipped item** in the same response, if there is one.
- Only after the TaskList shows every non-skipped item completed do you proceed to Phase 3 (write FIX_SUMMARY.md).

The single most common failure mode of this skill is stopping after the first item. Guard against it by checking the TaskList every time control returns to you: if there are any pending bug-fix tasks, the next thing you do is invoke `/bug-hunt-fix` on the next one — no exceptions, no asking the user.

## Phase 1: Parse the Index

### Step 1: Read the Index
Read the `INDEX.md` file at the argument path. The index contains markdown bullet lines linking to individual bug/observation files, typically in sections like `### High`, `### Medium`, `### Low` under `## Bugs` and `## Observations`.

Example bullet line shapes:
```
- [BUG-002: Edit form swaps...](BUG-002-edit-form-swaps-primary-and-collateral-clients.md) — Data integrity...
- [OBS-001: quick_book uses :create?...](OBS-001-quick-book-authorization-inconsistent-with-scheduler.md)
```

### Step 2: Extract Items
Build an ordered list of items to process. For each bullet in the index:
- Extract the **ID** (e.g. `BUG-002`, `OBS-001`), the **title**, and the **relative file path** from the markdown link.
- Resolve the file path relative to the `INDEX.md`'s directory (not the current working directory).
- Record which section (severity bucket) the item came from.

Process **both `## Bugs` and `## Observations`** sections. The user expects observations to be attempted as fixes too.

### Step 3: Apply Skip Markers
The user may have pre-annotated lines they want skipped. Treat an item as SKIPPED if **any** of the following are true on that item's bullet line:
- The line contains the literal marker `[SKIP]` (case-insensitive)
- The line contains the HTML comment `<!-- skip -->` (case-insensitive)
- The link text or description is wrapped in `~~strikethrough~~`

Record the skip reason as the raw marker seen. Do not attempt to fix skipped items.

### Step 4: Preserve Order
Execute items in the order they appear in the index. Within the index, bugs typically appear before observations and higher severity appears first — respect that order.

### Step 5: Report the Plan and Create Tasks
Before executing, print a concise plan to the user:
- Total items found
- Count to fix vs. count to skip
- The skip list with reasons

**Then immediately create a TaskList** with one task per non-skipped item, in index order. Use `TaskCreate` with titles like `Fix BUG-002: Edit form swaps primary and collateral clients`. The TaskList is your loop state — it is how you know what is left to do when control returns from `/bug-hunt-fix`.

Do not ask the user to confirm. Proceed directly into Phase 2.

## Phase 2: Execute Fixes (Loop)

### Step 6: The Fix Loop
Work through the TaskList one item at a time:

1. Find the first task with status `pending`. Mark it `in_progress` via `TaskUpdate`.
2. Invoke `/bug-hunt-fix` via the Skill tool, passing the resolved absolute path to that item's markdown file as the argument.
3. When `/bug-hunt-fix` returns control to you (after its own Cleanup step), do the following **in the same response**:
   - Read `git status` / the item's updated markdown file to record outcome:
     - **Status**: `FIXED` if `/bug-hunt-fix` verified the fix, `ATTEMPTED` if it made changes but verification was incomplete, `FAILED` if it could not fix the issue
     - **Files changed** (from the "Fix Applied" section the child skill writes, or from `git status`)
     - **Short note** on what was done
   - Mark the current task `completed` via `TaskUpdate`.
   - Check the TaskList. If any task is still `pending`, immediately go back to substep 1 and invoke `/bug-hunt-fix` on the next one. **Do not pause, do not summarize, do not hand back to the user.**
4. Only when every non-skipped task is `completed` do you leave the loop and move to Phase 3.

### Step 7: Do Not Commit
`/bug-hunt-fix` edits code and also appends a "Fix Applied" section to each bug file. **Leave all of these changes uncommitted.** Do not run `git add`, `git commit`, `git stash`, `git reset`, or `git push` at any point. The user will review and commit manually.

If you need to inspect state between items, use read-only git commands (`git status`, `git diff`) only.

### Step 8: Keep Going on Failures
If one item fails to fix, record the failure, mark the task `completed` (it is done from the loop's perspective — the outcome is just FAILED), and continue with the next item. Do not abort the batch. Capture enough detail (error messages, partial changes) in your tracking so the summary is useful.

## Phase 3: Write Summary

### Step 9: Create FIX_SUMMARY.md
Write a new file at `<index-directory>/FIX_SUMMARY.md` (same directory as the input `INDEX.md`). Keep it short — this is a summary, not a report.

Template:

```markdown
# Fix Summary

**Source index:** INDEX.md
**Date:** [YYYY-MM-DD HH:MM ISO local]
**Items processed:** X of Y (Z skipped)

---

## Fixed

- **BUG-002** — Edit form swaps primary and collateral clients
  - Files: `app/controllers/appointments_controller.rb`, `app/views/appointments/_edit_form.html.erb`
  - Change: Filter `appointment_clients` by `primary: true` in edit prefill.

- **OBS-001** — quick_book authorization inconsistent with scheduler
  - Files: `app/controllers/appointments_controller.rb`
  - Change: Switched `authorize` predicate from `:create?` to `:scheduler?`.

## Attempted (not verified)

- **BUG-XXX** — [title]
  - Reason verification incomplete: [short reason]

## Failed

- **OBS-XXX** — [title]
  - Reason: [short reason]

## Skipped

- **OBS-002** — [title] — marker: `[SKIP]`
- **OBS-004** — [title] — marker: `~~strikethrough~~`

---

## Working tree

All changes are uncommitted. Review with `git status` / `git diff`, then commit or discard manually.
```

Keep entries to one or two lines each. Do not paste diffs. Do not restate the bug descriptions — just what was done.

### Step 10: Final Message
After writing the summary, print a two-line recap to the user:
1. Counts: `Fixed: X | Attempted: Y | Failed: Z | Skipped: W`
2. Path to the summary file, plus a reminder that nothing is committed.

## Important Guidelines

1. **Do not commit, stage, stash, or push anything.** The user explicitly wants to review manually.
2. **Respect skip markers** exactly as specified — do not invent new skip conventions.
3. **Process both bugs and observations** unless explicitly skipped.
4. **Keep going on failures** — one broken item should not abort the batch.
5. **Do not re-do what `/bug-hunt-fix` already does.** Delegate the per-item fix+verify work to that skill; this skill is the orchestrator.
6. **Resolve file paths relative to the INDEX** — links inside the index are relative to the index file's directory, not the CWD.
7. **Summary is short.** One or two lines per item. No retrospectives, no recommendations, no screenshots.
8. **Do not edit the INDEX.md itself.** The user maintains it as the source of truth.

## Execution Flow

1. Read the index file
2. Parse items (bugs + observations) with skip markers applied
3. Print plan and create one task per non-skipped item via TaskCreate
4. **Loop**: while any task is `pending`, pick the next one, mark it `in_progress`, invoke `/bug-hunt-fix` with the resolved absolute path, then — in the response after it returns — record outcome, mark it `completed`, and immediately continue with the next pending task
5. Only when zero tasks remain pending, write `FIX_SUMMARY.md` next to the index
6. Print recap — remind the user nothing is committed

**Anti-stop checklist after every `/bug-hunt-fix` invocation returns:**
- [ ] Did I mark the current task `completed`?
- [ ] Are there any `pending` tasks left in the TaskList?
- [ ] If yes → invoke `/bug-hunt-fix` for the next one right now. Do not write a summary, do not stop, do not ask the user.
- [ ] If no → proceed to write FIX_SUMMARY.md.

Begin by reading the index file.
