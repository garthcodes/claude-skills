---
description: Create a bare git worktree for writing a PRD — no .env, certs, databases, or port — and open it in VSCode
argument-hint: <worktree-name>
allowed-tools: Bash(git worktree:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git -C:*), Bash(touch:*), Bash(open:*), Bash(ls:*)
---

# PRD Worktree

Create a lightweight worktree named "$1" for running `/prd`, then `/build-feature`, and open it
in a new VSCode window. It takes seconds: `/prd` only reads code and writes
`.claude/prds/<slug>.md`, so none of `/worktree`'s dev setup is done here.

**Do NOT** copy `.env` or certs, create or seed databases, assign a port, or run `bin/rails`.
`/build-feature` creates its own fully set-up pipeline worktree under the primary checkout's
`.claude/worktrees/` and copies `.env`/certs from the primary checkout.

## Steps

1. **Location**: a sibling directory `../<repo-name>-$1` (e.g. if the repo directory is
   `myapp`, use `../myapp-$1`).

2. **Validate "$1"**: non-empty, a valid branch name (no spaces or special characters), and
   neither `../<repo-name>-$1` nor branch `$1` exists (`git worktree list`, `git branch --list "$1"`).
   If empty, ask for a name.

3. **Create the worktree** (from the primary checkout):
   ```bash
   git worktree add ../<repo-name>-$1 -b $1 main
   ```

4. **Mark it as a PRD worktree** — the marker lives in the worktree's own git dir, so it is
   never committed and disappears with the worktree. `/build-feature` uses it to know it may
   delete this worktree once a PR opens:
   ```bash
   touch "$(git -C ../<repo-name>-$1 rev-parse --absolute-git-dir)/prd-worktree"
   ```

5. **Open in VSCode**: `open -a "Visual Studio Code" ../<repo-name>-$1`

## Success message

Report the path and branch, then:

- Next: in the new window run `/prd <idea>`, then `/build-feature .claude/prds/<slug>.md`.
- `/build-feature` removes this worktree and its `$1` branch once a PR (or draft PR) opens, if
  it holds nothing but the PRD and contract. If the gate fails or the run stops early, the
  worktree is kept so the PRD can be revised here.
- To remove it by hand: `git worktree remove --force ../<repo-name>-$1 && git branch -D $1`
  (no databases to drop), or `/worktree-sweep`.
