---
name: worktree-sweep
description: Clean up old worktrees (pipeline .claude/worktrees/* and sibling ../<app>-*) while keeping the current or relevant ones — stops their dev servers, drops their databases, removes the worktrees. Keeps any worktree with uncommitted or unpushed work, an open PR, a running Claude session, or no PR and changes in the last 24 hours. Use when the user says /worktree-sweep, "clean up worktrees", "kill the old worktrees", "remove merged worktrees", "free up ports", or bin/worktree-port reports no free port. `--all` removes every worktree with no checks.
allowed-tools: Bash(bin/worktree-sweep:*), Bash(cd:*), Bash(git worktree:*)
---

# Worktree Sweep

Thin wrapper over `bin/worktree-sweep`. The script decides what to keep. This skill runs it,
shows the result, and stops.

## Run

From the main checkout (`$MAIN_DIR`):

1. **Default (no argument):** run `bin/worktree-sweep` straight away. A dry run first isn't
   needed: by the rules below, it only removes worktrees that hold nothing you'd lose (every
   commit is on GitHub, nothing uncommitted).
2. **`all`** (the user wants *everything* gone, including work in progress): run
   `bin/worktree-sweep --all --dry-run`, then show which `would remove` lines belong to worktrees
   that the default rules would have kept. Those are the ones where work gets lost. Wait for the
   user to say "go", then run `bin/worktree-sweep --all`.
3. **`dry-run` / "what would it remove?":** run `bin/worktree-sweep --dry-run` and change nothing.

If the script doesn't exist (the checkout predates it), say so and stop.

Then report in the terminal:

- One line with the counts: `removed N, kept M, errors E`.
- A short table of the **kept** worktrees and the reason for each, since those are what the
  user may want to act on.
- Any `error —` lines, copied verbatim.

Don't print every `removed` line unless the user asks for them.

## Keep rules (default mode)

A registered worktree is **kept** when any of these is true, checked in this order:

| # | Keep when | Why |
|---|---|---|
| 1 | Uncommitted changes to tracked files, or untracked files outside `.claude/`, `tmp/` and `log/` | That work would be lost. Pipeline plan and review notes (`.claude/*.md`) and scratch files don't count. |
| 2 | Non-merge commits on no remote branch | Unpushed work. A local "merge origin/main" commit doesn't count. |
| 3 | The branch has an open PR | It's still in review. |
| 4 | A Claude Code session is running with its working directory inside it | Someone is working there now. |
| 5 | The branch has no PR, and its last commit or any file (ignoring tmp/, log/, node_modules/, build output) changed in the last 24 h | A fresh `/resolve-issue` or `/tweak` that hasn't committed or opened a PR yet. |

Everything else is removed, including worktrees whose PR is merged or closed and branches older
than a day with no PR where every commit is already on GitHub. Stray directories under
`.claude/worktrees/` that git no longer tracks are always removed.

For each removed worktree:

- its dev server is stopped. Servers are matched by the listening process's working directory,
  not by `.env` PORT, because worktrees reuse ports. The main checkout's server is never touched.
- its `<app>_development<suffix>` / `<app>_test<suffix>*` databases are dropped. With no
  `DATABASE_SUFFIX` nothing is dropped, so the shared databases are safe.
- the worktree is removed with `git worktree remove --force`.

## Output lines

- `<name>: kept — <reason>`
- `<name>: removed[, dbs <app>_*<suffix>]`
- `<name>: would remove[ (port N)][, server running][, dbs …]` with `--dry-run`
- `<name>: error — …` means a database drop or worktree removal failed. That worktree is kept
  so it can be retried, and the script exits 1.

## Rules

- Local and remote branches are never deleted, so committed work survives on its branch and a
  removed worktree can be recreated.
- Only the user starts a sweep. Never run it automatically from another skill, because even
  default mode removes worktrees other sessions may be about to use.
- If `gh` is unavailable, rule 3 can't fire and every branch counts as having no PR. Recent
  worktrees are still kept by rule 5, and anything with real work by rules 1–2.
