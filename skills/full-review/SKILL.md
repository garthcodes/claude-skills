---
description: Orchestrate /review → /scale-review → /review-fixes → /code end-to-end against a PR or the current branch
argument-hint: [pr-number]
---

# Full Review Pipeline

End-to-end orchestrator: runs the code review, the scale review, consolidates both into a prioritized fix plan, and then implements the fixes. Each phase's output is persisted to disk so the next phase can consume it and so the pipeline is resumable if a step fails.

```
/review           → .claude/reviews/branch-review-{slug}-{date}.md
/scale-review     → .claude/scale-reviews/scale-review-{slug}-{date}.md
/review-fixes     → .claude/fix-plans/fix-plan-{slug}-{date}.md
/code             → executes the tickets in the fix-plan
```

## Inputs

- **$1** (optional): PR number. If omitted, the pipeline auto-detects the PR for the current branch via `gh pr list --head $(git branch --show-current)`. If no PR exists yet, the pipeline still runs against the local branch diff.

## Autonomous Execution Policy

Run all four phases without stopping for user confirmation between them. If a phase produces unexpected output (e.g. an empty review), record it in the run-summary and proceed — do NOT pause to ask the user. The one sanctioned hard stop is if `git branch --show-current` returns `main` (or whatever the repo's base branch is) — in that case, abort with a clear message, because there is nothing to review.

## Step 1: Resolve Target

```bash
PR_NUM="${1:-}"
BRANCH=$(git branch --show-current)
SLUG=$(echo "$BRANCH" | tr '/' '-' | tr -cd '[:alnum:]-')
TODAY=$(date +%Y%m%d)

# Auto-detect PR for the current branch if not provided
if [ -z "$PR_NUM" ]; then
  PR_NUM=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null)
fi

# Hard stop guard
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|^origin/||' || echo main)
if [ "$BRANCH" = "$BASE_BRANCH" ]; then
  echo "Refusing to run: on base branch ($BASE_BRANCH). Check out a feature branch first." >&2
  exit 1
fi

mkdir -p .claude/reviews .claude/scale-reviews .claude/fix-plans
```

Record `PR_NUM`, `BRANCH`, `SLUG`, `TODAY` for use in subsequent phases. Announce the resolved target to the user in one line ("Reviewing PR #169 on `feature/superbill-pdf`…" or "Reviewing `feature/superbill-pdf` (no PR)").

## Step 2: Code Review → save to disk

Invoke the code review:

```
/review ${PR_NUM}
```

(If `PR_NUM` is empty, omit the argument — `/review` will fall back to the current branch.)

Capture the **full** review report it produces. Use the Write tool to persist it to:

```
.claude/reviews/branch-review-${SLUG}-${TODAY}.md
```

Prepend a small YAML header so `/review-fixes` can re-establish context:

```markdown
---
branch: ${BRANCH}
pr: ${PR_NUM}      # may be empty
generated: <ISO 8601 timestamp>
---

# Code Review — <PR title or branch name>

<the full review body verbatim>
```

If `/review` produced nothing useful (empty output, error), write a one-line stub file noting the failure so downstream steps know this input is absent, and continue.

## Step 3: Scale Review → save to disk

Derive a short feature description from the PR title and body (or, if no PR, from the first line of the most recent commit message and `git log --oneline ${BASE_BRANCH}..HEAD`). Pass it as the argument:

```
/scale-review <one-line feature description>
```

`/scale-review` produces a structured markdown report. Persist it to:

```
.claude/scale-reviews/scale-review-${SLUG}-${TODAY}.md
```

with the same YAML header as Step 2. Same fallback rule applies if the report is empty.

## Step 4: Consolidate into Fix Plan

Invoke:

```
/review-fixes .claude/reviews/branch-review-${SLUG}-${TODAY}.md .claude/scale-reviews/scale-review-${SLUG}-${TODAY}.md
```

This will produce `.claude/fix-plans/fix-plan-${SLUG}-${TODAY}.md` (the path naming is owned by `/review-fixes`; if it differs, capture the actual path it reports).

After this step, the orchestrator should print:

- The fix-plan file path
- The ticket count by priority (P0/P1/P2/P3)
- The top three tickets by priority+dependency
- Any "Dismissed Findings" or "Open Questions" section from the plan

If the fix plan contains **Open Questions** that block execution, surface them prominently before proceeding to Step 5 — the user may want to answer them rather than have the implementer guess.

## Step 5: Execute the Fix Plan

Invoke the implementer against the fix-plan:

```
/code .claude/fix-plans/fix-plan-${SLUG}-${TODAY}.md
```

`/code` will read the tickets and dispatch specialized agents to implement them. Constraints:

- **Honor the fix-plan's recommended order** (the plan orders tickets by dependency, then priority). If `/code` reorders for parallelism, that's fine as long as declared dependencies are respected.
- **No NEW system tests from fix plans** — if `/code` tries to create new files under `spec/system/`, skip those tickets (system tests are authored via `/plan-system-tests` + `/system-test-expert`, not review fixes). Updating an EXISTING system test that a fix legitimately breaks is allowed. Never create `spec/features/` files (project policy).
- **Stop after the fix-plan is implemented.** Do NOT chain into `/create-qa-document`, `/execute-qa`, or PR creation — those are separate workflows (`/build-feature` covers the full PRD-to-PR loop; this orchestrator is review-driven).

## Step 6: Run Summary

After all phases complete, print a compact summary (under 15 lines):

```
Full Review Pipeline Complete

Target:        ${BRANCH} (PR #${PR_NUM:-none})
Code review:   .claude/reviews/branch-review-${SLUG}-${TODAY}.md
Scale review:  .claude/scale-reviews/scale-review-${SLUG}-${TODAY}.md
Fix plan:      .claude/fix-plans/fix-plan-${SLUG}-${TODAY}.md
Tickets:       <P0 count> P0, <P1> P1, <P2> P2, <P3> P3 (<dismissed> dismissed)
Implemented:   <count of tickets /code completed>
Skipped:       <count and brief reason>
Next steps:    <e.g. "run bin/ci then commit"; or "answer open questions in fix-plan then re-run /code">
```

## Principles

1. **Persist between phases.** Each phase's output lands on disk before the next phase runs. This makes the pipeline resumable (re-run only the failing step) and lets `/review-fixes` reconcile both reviews against each other.
2. **One file per phase per day.** If re-run on the same day, overwrite — don't generate `-v2` files. Old runs are recoverable via git.
3. **Don't ask the user mid-pipeline.** Make a reasonable call and note the choice in the run summary. The only sanctioned stops are: on the base branch (Step 1), or after `/code` exhausts retries on a specific ticket (record it and continue).
4. **Stop at implementation.** This skill does not commit, push, open PRs, or run QA. Those are the user's call once they've reviewed the fix-plan outcome. (`/build-feature` is the skill that closes that full loop.)
5. **Surface Open Questions before /code.** A reviewer-flagged ambiguity should be answered by the user, not guessed by `/code`. If the fix-plan has unresolved questions, list them between Step 4 and Step 5 — the user can interrupt if they want to answer before implementation runs.
