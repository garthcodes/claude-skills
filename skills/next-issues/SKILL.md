---
name: next-issues
description: Pick the open GitHub issues to run /issue-ready on next, so they can be queued for autofix and ship in the next deploy. Read-only. Lists every open issue, drops the ones autofix would skip or already owns, checks each one against what merged since the live production revision (and the last two weeks), and sorts the rest into ready for /issue-ready, already done by a merged PR (close it), unblocked by a recent merge, blocked, or not autofix work. Ends with a ranked table and the /issue-ready commands to run. Use whenever the user says "/next-issues", "what should I get ready next", "which issues can autofix take", "find issues for the next deploy", "what's ready for issue-ready", or asks which open issues are worth queueing, even if they don't say "issue-ready".
argument-hint: "[label:<name>] [since:<days>]"
---

# Next Issues

One run = a short ranked list of open issues worth taking through `/issue-ready` now, so autofix can build them before the next deploy. This skill changes nothing: no labels, no comments, no closing. The user runs `/issue-ready <N>` on the ones they pick.

## Input

`$ARGUMENTS` (all optional):
- `label:<name>`: only issues with that label.
- `since:<days>`: how far back to read merged PRs besides the deploy range (default 14).

## Step 1: Load

```bash
gh issue list --state open --limit 300 --json number,title,labels,createdAt,updatedAt,body,url
gh pr list --state open --limit 100 --json number,title,headRefName,body
gh pr list --state merged --search "merged:>=$(date -v-14d +%F)" --limit 200 \
  --json number,title,mergedAt,body,mergeCommit,closingIssuesReferences
```

Production's revision, the same way `/ready-deploy` reads it (never `fly`):

```bash
DEPLOYED=$(curl -sL --max-time 20 "https://<app-host>/users/sign_in" \
  | grep -o '<meta name="honeybadger-revision" content="[a-f0-9]*"' | grep -o '[a-f0-9]\{40\}')
git fetch -q origin && git log --oneline "$DEPLOYED..origin/main" --merges
```

A merged PR whose merge commit is in `$DEPLOYED..origin/main` is **pending deploy**; older ones are **live**. No SHA → say so and treat every merged PR as "merged, deploy status unknown".

## Step 2: Drop what autofix won't take

Same rules as `Autofix::Dispatcher#issue_blocked_reason` (`app/services/autofix/dispatcher.rb`) plus the labels that mean someone already owns it. Drop and count, don't list one by one:

| Drop when | Why |
|---|---|
| Label `autofix-queue` or `autofix` | Already queued or a run has it. |
| Label `grouped` | Folded into a combined issue. |
| Label `rcm-audit` | Revenue-cycle findings are worked by `/rcm-resolve`, which ranks them by today's money at stake; they never go through autofix. |
| Open PR with head `issue_<N>`, or a body matching `close[sd]?|fix(e[sd])?|resolve[sd]? #<N>` | Already being built. |

Keep `needs-decision` and `fix-didnt-work` issues: `/issue-ready` is exactly how they get unstuck. Mark them.

**Spec-sweep continuation** (label `spec-sweep-next`): a leftover from before sweeps moved to the Spec sweep project board, which autofix no longer runs from an issue. Drop it and say once: "run `/project-new runner=spec-sweep` to move #<N> onto the board". Issues labeled `from-spec-sweep` are ordinary candidates (bugs and cleanups a sweep filed); one that is also `needs-decision` is a product question for `/issue-ready` to settle.

## Step 3: Check each issue against recent merges

Read each remaining issue's body (and comments for anything that looks related to a merge: `gh issue view <N> --comments`). For each, compare against the merged PRs' titles, bodies and `closingIssuesReferences`:

- **Already done.** A merged PR delivers what the issue asks, though it closed a different issue number (a split, a duplicate, a sibling filed the same day). Name the PR and whether it's live or pending deploy. These go to the user to close, not to `/issue-ready`. Only say "already done" when the PR's body or diff covers the issue's ask; when it covers part of it, say which part is left and keep the issue as a candidate.
- **Unblocked.** The issue says it depends on, follows, or backfills after another issue/PR, and that one has merged. Note whether it needs the parent **live** first (a backfill rake task or anything that reads data the parent writes in prod) or just **merged** (code built on top). Unblocked-by-merged is a top candidate: it can ship in the same deploy as its parent.
- **Blocked.** It depends on an issue or PR that is still open. Name the blocker.
- **Not autofix work.** Autofix is one unattended code change in this repo. Skip and give a one-line reason for: external enrollments or vendor paperwork, infra/ops chores, trackers and epics, new skills or tooling outside the app, anything `/prd`-sized (new pages, new workflows, permission model changes). Ongoing work that will take several PRs (a feature to improve over time, a tracker or epic of code changes) is **"make it a project"**: point at `/project-new <N>`. `/issue-ready` can split a big issue, so mark "big, needs a split" instead of skipping when the issue is a few separable code fixes.
- **Candidate.** Everything else.

Use `git log --oneline -5 -- <file>` on a file the issue names when you need to tell whether a recent change already touched it. Don't do `/issue-ready`'s research here; one look per issue is enough to classify it.

## Step 4: Rank the candidates

Order, top first:
1. Unblocked by a merge (ships with its parent).
2. `impact: blocking`, then `impact: important`.
3. `user-reported`, `fix-didnt-work`, `needs-decision` (someone is waiting).
4. `bug` before `enhancement`.
5. Smaller first: a clear cause in the body, few files named, no migration or backfill. Mark the likely size `small` / `full` / `split`, the way `/issue-ready` Step 2 sizes it.
6. Oldest first.

## Final report

Print in the terminal, nothing else:

```
Live: <short DEPLOYED>  ·  pending deploy: <K> PRs  ·  open issues: <total>, dropped <D> (queued/owned/has PR)

Ready for /issue-ready
| # | Issue | Size | Why now |
|---|-------|------|---------|
| 1 | #964 Backfill imported_diagnoses … | full | unblocked: #965/#966 merged, pending deploy, needs them live |

Already done (close them)
- #961 … ← PR #965 (pending deploy)

Blocked
- #NNN … waits on #MMM

Not autofix work
- #879 Medicare enrollment: vendor paperwork
```

Then one line with the candidates in rank order and the command that takes them, e.g. `Order: 964, 969, 1023 → /issues-ready (top 10 at once) or /issue-ready <N> for one`. `/issues-ready` reads this line, so keep every number on it. Leave out empty sections. Say plainly when nothing is ready.
