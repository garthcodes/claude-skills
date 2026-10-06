#!/usr/bin/env bash
# Worktree for a /spec-sweep follow-up PR (bugs or findings), stacked on chore/spec-sweep.
#
#   followup_worktree.sh <name> <branch> [base]   e.g. spec-sweep-bugs fix/spec-sweep-bugs-20261003
#
# Creates (or reuses) .claude/worktrees/<name> on <branch>, cut from <base> (default
# chore/spec-sweep), with its own DATABASE_SUFFIX databases (dev: mini seed; test: self-seeds when
# rspec runs without TEST_ENV_NUMBER) and its own dev-server port. Prints the path, branch, port,
# and database name. A reused worktree is never reset: existing work is kept.
#
# Why a suffix and not the sweep's <app>_test2..9: the follow-ups run /code, /full-review and bin/ci,
# which would wipe or race the sweep's worker databases and the user's own <app>_development.
set -euo pipefail

name="${1:?usage: followup_worktree.sh <name> <branch> [base]}"
branch="${2:?usage: followup_worktree.sh <name> <branch> [base]}"
base="${3:-chore/spec-sweep}"

MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
WT="$MAIN_ROOT/.claude/worktrees/$name"
SUFFIX="_$(echo "$name" | tr '-' '_' | tr -cd 'a-z0-9_' | cut -c1-30)"

if [ -d "$WT" ]; then
  current="$(git -C "$WT" branch --show-current)"
  if [ "$current" != "$branch" ]; then
    echo "ABORT: $WT exists on branch '$current', not '$branch'. It may hold earlier work; resolve by hand." >&2
    exit 1
  fi
  echo "reused   $WT  ($(git -C "$WT" log --oneline "$base"..HEAD | wc -l | tr -d ' ') commits ahead of $base)"
else
  if git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$MAIN_ROOT" worktree add -q "$WT" "$branch"
  else
    git -C "$MAIN_ROOT" worktree add -q -b "$branch" "$WT" "$base"
  fi
  [ -d "$MAIN_ROOT/config/certs" ] && cp -r "$MAIN_ROOT/config/certs" "$WT/config/"   # local HTTPS certs, if you use them
  cp "$MAIN_ROOT/.env" "$WT/.env"   # never .env.prod-read: bin/prod-read finds it in the main checkout
  sed -i '' '/^DATABASE_SUFFIX=/d;/^PORT=/d' "$WT/.env"
  # printf's leading newline matters: .env may not end in one, and a glued-on line is ignored
  printf '\nDATABASE_SUFFIX=%s\n' "$SUFFIX" >> "$WT/.env"
  (cd "$WT" && bin/worktree-port --assign .env >/dev/null)
  echo "created  $WT  ($branch from $base)"
fi

cd "$WT"
db="$(bin/rails runner 'puts ActiveRecord::Base.connection_db_config.database' 2>/dev/null | tail -1)"
# schema:load against an unsuffixed name would wipe the user's <app>_development.
case "$db" in
  *"$SUFFIX") ;;
  *) echo "ABORT: worktree resolves to database '$db', expected suffix $SUFFIX. Fix $WT/.env." >&2; exit 1 ;;
esac

if ! bin/rails runner 'exit(Organization.exists? ? 0 : 1)' >/dev/null 2>&1; then
  bin/rails db:create 2>&1 | tail -2
  bin/rails db:schema:load 2>&1 | tail -2   # loads both <app>_development$SUFFIX and <app>_test$SUFFIX
  bin/rails db:seed:mini 2>&1 | tail -1
fi

echo "path=$WT branch=$branch port=$(grep -E '^PORT=' .env | cut -d= -f2) db=$db"
