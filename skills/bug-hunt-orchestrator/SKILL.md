---
description: Hunt for bugs and fix them in one run — calls /bug-hunt on a feature (or the current branch), then /fix-bug-index on the INDEX.md that hunt produced. Each phase runs in its own sub-agent. Does not commit. Use when the user says "/bug-hunt-orchestrator", "hunt and fix bugs in X", "find and fix the bugs on this branch", or wants /bug-hunt followed by /fix-bug-index without running them by hand.
argument-hint: [<feature-description> | <path-to-existing-bug-report-dir>]
---

# Bug Hunt Orchestrator

Chain `/bug-hunt` → `/fix-bug-index` in one invocation. You are only the orchestrator: you never drive the browser and never edit app code yourself. Each phase runs in a sub-agent so Playwright snapshots and code reads stay out of your context.

## Argument
$ARGUMENTS

- **Feature description** → hunt that feature (`/bug-hunt` Mode A).
- **Empty** → hunt the current branch's changes (`/bug-hunt` Mode B).
- **Path to an existing `docs/bug-reports/...` dir** (has `INDEX.md`, no `FIX_SUMMARY.md`) → skip Phase 1 and go straight to Phase 2. This is how a re-run resumes after the hunt already finished.

## Step 1: Set up the session

```bash
BASE_URL="$(bin/dev-url)"
STAMP="$(date +%Y%m%d-%H%M%S)"
```

Build a kebab-case slug from the feature text (≤ 5 words), or from `git branch --show-current` when the argument is empty. Then:

- `SESSION_DIR` = absolute path of `docs/bug-reports/<slug>-<STAMP>`
- `INDEX` = `$SESSION_DIR/INDEX.md`

You choose the directory and hand it to `/bug-hunt` through its `Output dir:` override, so you always know where the index is without parsing the child's output. `Base URL:` makes both phases hit the same server (this checkout may be a worktree on its own port).

## Step 2: Phase 1 — hunt

Spawn one `general-purpose` sub-agent and wait for it:

> Invoke the `bug-hunt` skill with the Skill tool, passing exactly these args:
> ```
> <feature description, or nothing if empty>
> Base URL: <BASE_URL>
> Output dir: <SESSION_DIR>
> ```
> Find and document bugs only — do not fix anything, do not commit. When the skill is done, reply with the INDEX.md path and the bug count per severity.

## Step 3: Gate

- `INDEX` missing → re-run Phase 1 once. Still missing → stop and tell the user what the sub-agent reported.
- The hunt found nothing (index lists no BUG-/OBS- items, or the branch diff was empty) → print "No bugs found" with the index path and stop. There is nothing to fix.
- Otherwise continue **in the same response**. Getting control back from the hunt is not the end of the task — the fixes are the point.

## Step 4: Phase 2 — fix

Spawn one `general-purpose` sub-agent and wait for it:

> Invoke the `fix-bug-index` skill with the Skill tool, passing the args `<absolute INDEX path>`. Process every non-skipped item to completion. Do not stage, commit, stash, reset or push. When the skill is done, reply with its `Fixed | Attempted | Failed | Skipped` line and the FIX_SUMMARY.md path.

If the sub-agent errors out before `FIX_SUMMARY.md` exists, retry once. `/fix-bug-index` has no resume logic of its own, so tell the retry to treat any bug file that already has a "Fix Applied" section as done and only fix the rest.

## Step 5: Recap

Print at most three lines:
1. Bugs found by severity (from `INDEX.md`).
2. `Fixed: X | Attempted: Y | Failed: Z | Skipped: W` (from `FIX_SUMMARY.md`).
3. Paths to `INDEX.md` and `FIX_SUMMARY.md`, and a reminder that nothing is committed — review with `git status` / `git diff`.

## Rules

- Never commit, stage, stash, reset or push. The user reviews the dirty tree.
- Don't pause between phases or ask "should I continue?" — the user chose a straight run.
- Don't re-do the children's work: no browser calls, no code edits, no rewriting `INDEX.md`.
