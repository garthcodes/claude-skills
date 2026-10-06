#!/usr/bin/env bash
# Worktrees for /spec-sweep.
#
#   worktrees.sh setup <workers>   integration worktree on branch chore/spec-sweep (created from main
#                                  if missing) + worker worktrees w1..wN reset (detached) to its tip
#   worktrees.sh status            branch tips, dirty state
#   worktrees.sh teardown          remove worker worktrees (keeps the integration worktree + branch)
#
# Why worktrees: probe.rb mutates app/ files for a few seconds. Workers sharing one checkout would
# load each other's mutations and see phantom failures, so every worker gets its own tree.
# Each worker uses its own TEST_ENV_NUMBER database (worker k -> k+1), so DBs never collide either.
set -euo pipefail

MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
BASE="$MAIN_ROOT/.claude/worktrees"
INTEG="$BASE/spec-sweep"
BRANCH="chore/spec-sweep"

cmd="${1:-status}"

case "$cmd" in
  setup)
    n="${2:?usage: worktrees.sh setup <workers>}"
    mkdir -p "$BASE"
    if [ ! -d "$INTEG" ]; then
      if git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
        git -C "$MAIN_ROOT" worktree add -q "$INTEG" "$BRANCH"
      else
        git -C "$MAIN_ROOT" worktree add -q -b "$BRANCH" "$INTEG" main
      fi
    fi
    # Answers the user typed into a findings file are expected; step 0.4 commits them.
    dirty="$(git -C "$INTEG" status --porcelain | grep -v -E '^ M \.claude/audits/spec-sweep/findings-[0-9-]+\.md$' || true)"
    if [ -n "$dirty" ]; then
      echo "ABORT: integration worktree $INTEG has uncommitted changes:" >&2
      echo "$dirty" >&2
      exit 1
    fi
    tip="$(git -C "$INTEG" rev-parse HEAD)"
    for k in $(seq 1 "$n"); do
      wt="$BASE/spec-sweep-w$k"
      [ -d "$wt" ] || git -C "$MAIN_ROOT" worktree add -q --detach "$wt" "$tip"
      git -C "$wt" checkout -q --detach "$tip"
      git -C "$wt" reset -q --hard "$tip"
      git -C "$wt" clean -fdq -- spec app lib config
      echo "w$k  $wt  TEST_ENV_NUMBER=$((k + 1))"
    done
    echo "integration  $INTEG  ($BRANCH @ ${tip:0:9})"
    ;;
  status)
    for wt in "$INTEG" "$BASE"/spec-sweep-w*; do
      [ -d "$wt" ] || continue
      dirty="$(git -C "$wt" status --porcelain | wc -l | tr -d ' ')"
      echo "$(basename "$wt")  $(git -C "$wt" rev-parse --short HEAD)  dirty=$dirty"
    done
    ;;
  teardown)
    for wt in "$BASE"/spec-sweep-w*; do
      [ -d "$wt" ] && git -C "$MAIN_ROOT" worktree remove --force "$wt" && echo "removed $wt"
    done
    ;;
  *)
    echo "usage: worktrees.sh setup <workers> | status | teardown" >&2; exit 2 ;;
esac
