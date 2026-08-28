---
description: Remove pipeline worktrees (.claude/worktrees/*) whose PR is merged or closed — stops their server, drops their databases, removes the worktree
allowed-tools: Bash(bin/worktree-sweep:*), Bash(cd:*), Bash(git worktree:*), Bash(gh auth:*)
---

# Worktree Sweep

Thin wrapper over `bin/worktree-sweep`. Takes no arguments and asks no confirmation.

## Run

```bash
bin/worktree-sweep
```

Print the script's output **verbatim** in the conversation — one line per worktree. If the
script does not exist (the checkout predates it), say so and stop.

For a preview that changes nothing, `bin/worktree-sweep --dry-run` prints the same verdicts
with `would remove` in place of `removed`.

## What the verdict lines mean

- `<name>: removed (PR #n merged|closed)` — server on the worktree's `PORT` stopped, its
  `<app>_development<suffix>` / `<app>_test<suffix>*` databases dropped, `git worktree remove` done.
- `<name>: kept (open PR #n)` / `<name>: kept (no PR)` / `<name>: kept (not a git worktree)` —
  untouched.
- `<name>: skipped — dirty (PR #n merged|closed)` — has uncommitted changes; never force-removed.
  The developer cleans it by hand (`git -C <path> status`).
- `<name>: error — …` — a DB drop or worktree removal failed; the worktree is kept so it can be
  retried. The script exits 1 when any error line was printed.

## Rules

- Only `.claude/worktrees/*` is considered. Sibling `../<app>-*` worktrees from `/worktree` are
  never listed or touched.
- A worktree is removed only when its branch's PR is **merged or closed** (any OPEN PR on the
  branch keeps it) **and** the worktree is clean.
- Requires an authenticated `gh`. If `gh auth status` fails the script prints
  `Sweep skipped: GitHub CLI is not authenticated …` and changes nothing.
- Local and remote branches are never deleted.
