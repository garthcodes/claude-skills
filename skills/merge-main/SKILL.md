---
name: merge-main
description: Merge origin/main into the current branch, resolve every conflict correctly (keeping both sides' intent), verify, then commit and push
argument-hint: [optional: --no-push to stop after the merge commit]
allowed-tools: Bash(git:*), Bash(bin/standardrb:*), Bash(bin/rails:*), Bash(bundle:*), Read, Edit, Grep, Glob
---

# Merge Main

Bring the current branch up to date with `origin/main` in one pass: fetch, merge, resolve
every conflict the way the authors of *both* sides would want, confirm the tree is sane,
commit, and push. Ask nothing unless a conflict is genuinely undecidable (see "When to stop").

## Preconditions (check all before touching anything)

```bash
git rev-parse --abbrev-ref HEAD      # must NOT be main/master
git status --porcelain               # must be empty
git fetch origin main
git merge-base --is-ancestor origin/main HEAD && echo "already up to date"
```

- On `main`? Stop — this skill only merges *into* feature branches.
- Dirty tree? Stop and say so. Never stash (the stash stack is shared across worktrees —
  see CLAUDE.md); ask the user to commit or discard first.
- `origin/main` already an ancestor? Report "already up to date" and finish — nothing to push.

## Step 1 — Merge

```bash
git merge --no-ff --no-edit origin/main
```

Clean merge → skip to Step 4. Otherwise list the conflicted files:

```bash
git diff --name-only --diff-filter=U
```

## Step 2 — Resolve each conflict correctly

"Correctly" means the result preserves **the intent of both sides**, not whichever side is
easier. For every conflicted file:

1. Understand *why* each side changed the region:
   ```bash
   git log --oneline HEAD...origin/main -- <file>       # commits on each side touching it
   git diff $(git merge-base HEAD origin/main) HEAD -- <file>          # ours
   git diff $(git merge-base HEAD origin/main) origin/main -- <file>   # theirs
   ```
2. Read the full conflicted file (not just the hunk) so imports, method order, and
   surrounding call sites are consistent after the edit.
3. Write the merged content. Both changes almost always belong together — a new method from
   main next to a new method from the branch, both new routes, both new spec examples.
   Take one side wholesale only when the other side's change is provably superseded
   (e.g. main deleted the method the branch was editing — then the branch's edit is dead
   and you must also fix the branch's callers).
4. Remove every `<<<<<<<`, `=======`, `>>>>>>>` marker, then `git add <file>`.

### File-type rules

- **`db/schema.rb`** — never hand-merge it. Resolve every migration conflict first, then
  regenerate:
  ```bash
  git checkout origin/main -- db/schema.rb
  bin/rails db:migrate
  ```
  The `version:` at the top must equal the newest migration timestamp across both sides.
  If `db:migrate` fails, the migrations themselves conflict (same table/column twice, a
  rename against a drop) — fix the *branch's* migration, never main's, and re-run.
- **Migrations** — two migrations touching the same table are both kept; rename the branch's
  file if its timestamp is now older than a main migration it depends on.
- **`Gemfile.lock` / `package.json` / `yarn.lock`** — take `origin/main`'s version, then
  re-add the branch's additions with the tool: `bundle install` / `bin/importmap pin …`.
  Never hand-edit lockfiles.
- **`config/routes.rb`, `config/locales/*.yml`, factories, `spec/support`** — union: keep
  both sides' entries, deduplicate identical lines, keep main's ordering.
- **Rename-vs-edit** — apply the branch's edit inside the file at main's new path; delete the
  stale copy.
- **Delete-vs-modify** — if main deleted a file the branch modified, the branch's change is
  usually dead; confirm by grepping for its callers before dropping it. If the branch deleted
  a file main modified, keep it deleted only if nothing on main now references it.
- **Generated/vendored files** (`app/assets/builds/*`, `public/assets/*`) — take main's and
  rebuild if a build step exists.

## Step 3 — Verify the resolution

Run the cheap checks before committing; the goal is a merge that would pass `bin/ci`, not
merely one with no markers.

```bash
git diff --check                                   # leftover markers / whitespace
grep -rn '^\(<<<<<<<\|=======\|>>>>>>>\)' --include='*' $(git diff --name-only --cached) || true
bin/standardrb $(git diff --name-only --cached -- '*.rb' | tr '\n' ' ')
bin/rails runner 'puts :ok'                        # app boots (catches bad constants/routes)
```

If schema or migrations were involved, also `bin/rails db:migrate:status | grep -v up`.

Then run the specs most likely affected — every spec file among the conflicted files, plus the
spec for each conflicted `app/` file (`app/models/foo.rb` → `spec/models/foo_spec.rb`):

```bash
bundle exec rspec <those files>
```

A failure here means the resolution is wrong, not the test. Go back to Step 2 for that file.
Never `pending`/`skip` a test to get past this step. Run `bin/ci` only when the user asked
for it or the conflicts touched more than ~10 files; note it runs one at a time in worktrees.

## Step 4 — Commit and push

Complete the merge commit (git supplies the "Merge remote-tracking branch 'origin/main'"
message; keep it). If conflicts were resolved, append a short body listing them:

```bash
git commit --no-edit            # clean merge, or
git commit -F- <<'MSG'
Merge remote-tracking branch 'origin/main' into <branch>

Conflicts resolved:
- app/models/client.rb — kept both new scopes
- db/schema.rb — regenerated via db:migrate

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
MSG
git push origin HEAD
```

`--no-push` in the arguments → stop before `git push` and say so.

Never `--force`. If push is rejected because the remote branch moved, `git pull --rebase` is
**wrong** for a merge commit — instead `git fetch` and merge `origin/<branch>` the same way,
then push again.

## When to stop and ask

Only these — everything else you decide yourself and explain in the report:

- The two sides implement **the same feature differently** (duplicate migration adding the
  same column with different types, two competing service objects for one job). Pick nothing;
  show both and ask.
- A conflict is inside a **migration that has already been applied in production** (check
  `git log origin/main -- db/migrate/<file>` — if it was on main before the last deploy tag,
  it is frozen).
- Resolving requires **changing behavior on main's side**.

On stop: `git merge --abort` is *not* automatic — leave the merge in progress so the user can
inspect, and tell them `git merge --abort` returns to the pre-merge state.

## Report

End with, in this order:

1. Result line: `Merged origin/main (<n> commits) into <branch> — <clean | k conflicts resolved> — pushed <sha>`.
2. One line per resolved conflict: file, what each side did, what you kept and why.
3. Verification run and outcome (lint, boot, which specs, pass/fail).
4. Anything the user should double-check (behavioral judgment calls, dropped dead code,
   renamed migrations).
