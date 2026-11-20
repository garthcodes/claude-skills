---
name: settle-autofix-prs
description: Settle and merge every open autofix PR, then get main ready to deploy. Reads all open PRs labeled `autofix`, looks into each one's cold review and reviewer comments the way /settle-pr-review does, skips the complicated ones, asks the user only the questions that matter (all PRs' questions up front, one at a time), carries out the answers, merges the settled PRs into main one by one, then runs /ready-deploy — /green-ci and a fix commit on main if bin/ci is red — and ends with the deploy plan. Never runs bin/ci per PR and never opens VS Code. Use whenever the user says "/settle-autofix-prs", "settle all the autofix PRs", "merge the autofix PRs and get ready to deploy", "go through every autofix PR", "clear the autofix queue for a deploy", or asks to take the open autofix PRs to a deploy, even if they don't name the skill.
---

# Settle Autofix PRs

One run = every open `autofix` PR triaged → complicated ones skipped → the user's questions for all of them answered, one at a time → the answers carried out → the settled PRs merged into main → main green on `bin/ci` → the deploy plan.

This is `/settle-pr-review` (`.claude/skills/settle-pr-review/SKILL.md`) run over a batch, plus the merge and the deploy prep. Read that file first: its Step 1 (what counts as a review point), Step 3 (how to look into a point and the ask / handle-without-asking table), Step 4 (how to ask), Step 5 (how a chosen fix is built) and Step 7 (PR body, carry lines, decisions comment) apply here as written. The differences are below, and they win where the two disagree:

- **No `bin/ci` per PR.** Skip `/settle-pr-review` Step 6's `bin/ci` question entirely. A PR with fixes runs its targeted specs + `bin/standardrb` (Step 5.4); `bin/ci` runs once, on main, inside `/ready-deploy`. That one run is the safety net for the whole batch.
- **Never open VS Code** and never ask about it (skip Step 8's question).
- **This skill merges.** Invoking it is the user's go to merge every PR that ends **Ready to merge**, after the Step 4 plan below is approved.
- **Complicated PRs are skipped**, not settled (Step 2).

## Step 1: Collect the PRs

```bash
cd $MAIN_DIR && git fetch origin
gh pr list --state open --label autofix --limit 100 \
  --json number,title,headRefName,isDraft,labels,additions,deletions,changedFiles,mergeable,files
```

None → say so and go straight to Step 6. Resume: if `tmp/settle-autofix-prs/ledger.md` exists from an earlier run today, read it and continue from where it stopped (answered questions stay answered, merged PRs stay merged).

## Step 2: Triage every PR in parallel

Spawn one read-only research agent per PR (up to 5 at once), so the main thread keeps conclusions, not diffs. Each gets: the PR number, the path to `/settle-pr-review`'s SKILL.md with the instruction to do its Steps 1 and 3 only (read-only — no worktree, no edits, no comments; `bin/prod-read` / `bin/prod-sql` / `bin/prod-logs` allowed for counts), and the skip rules below. It returns:

```
PR #N — <title> · <files> files, +<add>/-<del> · labels
verdict: settle | skip: <reason>
points: <# · point · ask|auto · auto-handling or the question with options, recommendation first · one-line finding>
fix size if the recommendation is "fix in this PR": <files, lines>
```

**Skip the PR (complicated)** when any of these holds; the user can pull one back in Step 4:

| Signal | Why |
|---|---|
| A `stop` point: the PR does something other than its issue asked | Needs a rethink, not a merge |
| A recommended fix bigger than ~3 app files / ~50 lines, or that needs a new feature | That's a new build, not settling |
| A destructive migration (drop/rename, `NOT NULL` on an existing column, backfill) or a production data write | Needs its own deploy planning |
| Over ~300 changed lines outside `spec/` and no `small-fix` label | Too big to merge on a review alone |
| `mergeable: CONFLICTING` in app code (not just `db/schema.rb` or a lockfile) | A real conflict needs a human eye |
| A `## Prod data check` script that does anything but read and print counts | Settle-pr-review treats it as an ask; here it's a skip |

`needs-decision` and `not-reproduced` are not skips by themselves: they are the questions this skill exists to ask.

## Step 3: Ask, one question at a time

Print one overview: a table of every PR (settle / skip + reason), then the ask count across all of them, then the auto-handled points per PR (so the user can say "ask me about #1094 point 3").

Then ask every "ask" point across all PRs with AskUserQuestion, **one question per call**, waiting for each answer. Order: PR by PR (smallest first), and within a PR `/settle-pr-review` Step 4's order. Start each question's text with the PR number and title so it stands on its own. Same option set as Step 4 there; "Hold the PR" and "close the PR" turn the PR into a skip. Append each answer to `tmp/settle-autofix-prs/ledger.md` as it comes.

## Step 4: Show the plan, then wait

```
| PR | Title | Decisions | Fix? | Then |
|---|---|---|---|---|
| #1093 | Delete unused predicates … | 2 auto | — | merge |
| #1098 | Video calls: incoming audio … | 1 asked: fix in PR | 2 files, ~20 lines | fix → merge |
| #1090 | … | — | — | skip: destructive migration |

Merge order: #1093, #1092, #1098 …  then /ready-deploy
```

Merge order: no-fix PRs first, smallest first. Wait for "go" or adjustments; this is the only approval stop before the merges.

## Step 5: Carry out, then merge one PR at a time

For each PR in merge order:

1. **Fixes** (only if the user chose one): a worktree on the PR's branch exactly as `/settle-pr-review` Step 2 sets it up, then its Step 5 (plan → architect-review → code → specs → full-review → simplify), run in a sub-agent told the worktree path, branch, the chosen fixes and these overrides. If the fix grows past the skip threshold, stop that PR: it becomes a skip with the reason.
2. **Bring it up to main:** `gh pr view <N> --json mergeable,mergeStateStatus`. Behind or conflicting → `/merge-main` in its worktree (create one as above if needed). A conflict `/merge-main` can't resolve in tests, `db/schema.rb` (re-run the migrations) or lockfiles → skip the PR.
3. **Record and push:** `/settle-pr-review` Step 7 — PR body sections, carry lines, the `## Review decisions` comment. The Checks line reads `targeted specs green` (or `no code changes`) and `bin/ci: runs on main after the batch merge`.
4. **Merge:** `gh pr ready <N>` if draft, remove `needs-decision` if this run settled it, then `gh pr merge <N> --merge --delete-branch`. A failed merge (branch protection, new conflict) → that PR becomes a skip; never force anything.
5. Mark it merged in the ledger. Next PR.

A skip at any point only means "left open for the user" with one line on the PR (`gh pr comment`) saying why it was skipped. Never close a PR unless the user's answer said to.

## Step 6: Get main deployable

After the last merge:

```bash
cd $MAIN_DIR && git checkout main && git pull --ff-only
```

Run `/ready-deploy` from the main checkout. When its Step 3 `bin/ci` is red:

1. Run `/green-ci` on main (it leaves changes uncommitted).
2. If any change touches app code (not only specs/factories/support), ask one question first: show the behavior change `/green-ci` flagged, commit it or stop.
3. Run `bin/ci` again. Green → commit the fixes on main as `test: get bin/ci green after autofix merges` (specific paths, never `-A`, the session's attribution line) and `git push origin main`. Still red after one more `/green-ci` pass → stop and report the failures; no deploy plan for a red main.
4. Continue `/ready-deploy` from its Step 4. It ends by showing the deploy plan and waiting for "go"; walking the plan is `/ready-deploy`'s Step 6, not this skill's.

## Step 7: Report

Above the deploy plan, a few lines: PRs merged (numbers), PRs skipped with one-line reasons, issues commented on, the `bin/ci` result against which main SHA (and the green-ci commit if there was one), and every after-deploy task the merged PRs added (they're also in the plan).

## Guardrails

- Questions only for points that matter (`/settle-pr-review` Step 3's test), one per message, plain words, recommendation first.
- Merge only PRs with the `autofix` label that ended **Ready to merge**, only after Step 4's "go". Never merge a skip, never force-push, never push to a PR branch other than the one being settled.
- No new GitHub issues unless the user's answer asks for one.
- `bin/ci` runs only on main in Step 6, one at a time, nothing else running rspec alongside. Never trigger GitHub Actions.
- Production stays read-only; every deploy step is the user's, through `/ready-deploy`.
- No PHI in questions, comments or commits.
