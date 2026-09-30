---
description: Remove EVERY worktree (pipeline .claude/worktrees/* and sibling ../<app>-*) with no checks — stops their servers, drops their databases, force-removes the worktrees
allowed-tools: Bash(bin/worktree-sweep:*), Bash(cd:*), Bash(git worktree:*)
---

# Worktree Sweep

Thin wrapper over `bin/worktree-sweep`. Takes no arguments, asks no confirmation, runs no checks.

## Run

```bash
bin/worktree-sweep
```

Print the script's output **verbatim** in the conversation — one line per worktree. If the
script does not exist (the checkout predates it), say so and stop.

For a preview that changes nothing, `bin/worktree-sweep --dry-run` prints `would remove` lines.

## What it does

Every worktree registered with the repo except the main checkout is removed — pipeline
`.claude/worktrees/*` and sibling `../<app>-*` alike — plus any stray directory left under
`.claude/worktrees/`. There are no PR, open-work, or dirty checks: uncommitted changes are
discarded (`git worktree remove --force`). For each worktree:

- the dev server on its own `PORT` (from its `.env`) is stopped — the main checkout's port is
  never touched;
- its `<app>_development<suffix>` / `<app>_test<suffix>*` databases are dropped (no
  `DATABASE_SUFFIX` → nothing dropped, so the shared databases are safe);
- the worktree is removed.

## Output lines

- `<name>: removed[, dbs <app>_*<suffix>]`
- `<name>: error — …` — a DB drop or worktree removal failed; that worktree is kept so it can be
  retried. The script exits 1 when any error line was printed.

## Rules

- Local and remote branches are never deleted — committed work survives on its branch.
- Never run automatically from another skill: it destroys in-flight worktrees.
