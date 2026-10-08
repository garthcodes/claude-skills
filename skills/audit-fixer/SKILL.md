---
name: audit-fixer
description: Walk a severity-ranked audit document and fix every finding one at a time by invoking /plan then /code per finding, until all are taken care of. Does not commit.
argument-hint: <path-to-audit-doc> [optional severity scope, e.g. "P0-P1 only"]
---

# Audit Fixer

You are tasked with walking a severity-ranked audit document (e.g. `docs/STEDI_CLAIMS_APPEALS_ERA_AUDIT.md`) and fixing every non-skipped finding, **one finding at a time**, by invoking `/plan` and then `/code` for each. After all findings are processed, write a short summary document. **Do NOT stage, commit, or push any changes** — leave the working tree dirty for the user to review.

## Audit to Process
$ARGUMENTS

If no path is given, take the newest audit-shaped document: `ls -t docs/*AUDIT*.md | head -1`. If the argument includes a severity scope (e.g. "P0-P1 only", "just the P0s"), process only findings in that scope and record the rest as OUT OF SCOPE in the summary.

## CRITICAL: You Are The Orchestrator

You will invoke `/plan` and `/code` via the Skill tool once **per finding**. Those child skills' instructions each read like a complete end-to-end task (exploration phases, validation phases, final reports) — **they are not the end of YOUR task**. One `/plan` + `/code` pair is one iteration of a loop.

When a child skill invocation finishes:
- **DO NOT stop, summarize, or report completion.**
- **DO NOT treat `/code`'s final report as the end of the batch.**
- Update the TaskList, then **immediately proceed** to the next step of the current finding (`/code` after `/plan`) or the next pending finding.
- Only after the TaskList shows every non-skipped finding completed do you proceed to Phase 3.

The single most common failure mode of this skill is stopping after the first finding. Guard against it by checking the TaskList every time control returns to you: if any finding task is `pending` or `in_progress`, the next thing you do is the next `/plan` or `/code` invocation — no exceptions, no asking the user.

## Phase 1: Parse the Audit

### Step 1: Read the Audit Document
Read the full audit file. Expected shape (as produced by billing/security/code audits in this repo):

- Severity sections: `## P0 — ...`, `## P1 — ...`, `## P2 — ...`, `## P3 — ...`
- Findings as numbered subheadings inside them: `### 3. Deductible, coinsurance, and copay claims are marked "denied"`
- Under each finding: one or more `file:line` location lines in backticks, a description/scenario, and usually an explicit **Fix:** paragraph
- Often a closing "Recommended fix order" line — if present, it overrides document order

If the document doesn't match this shape, adapt: any heading that identifies a discrete defect with a location counts as a finding. Do not treat "Verified clean", "Sources", or "Method" sections as findings.

### Step 2: Extract Findings
Build an ordered list. For each finding record:
- **Number and title** (e.g. `1. A clearinghouse-rejected appeal is recorded as successfully submitted`)
- **Severity** (from the enclosing section)
- **Locations** (every `file:line` reference)
- **Full body text** — scenario and Fix paragraph verbatim. This becomes `/plan`'s input; do not paraphrase it down.

Order: recommended fix order if the document states one; otherwise severity (P0 first), then document order.

### Step 3: Apply Skip Markers and Scope
Treat a finding as SKIPPED if any of the following appear on its heading line or anywhere in its body:
- The literal marker `[SKIP]` (case-insensitive)
- The HTML comment `<!-- skip -->` (case-insensitive)
- `~~strikethrough~~` on the heading title
- A `**Status:** fixed`-style annotation or a `Fix applied` section (already handled in a previous run — resumability)

Also treat findings outside the caller's severity scope (if given) as OUT OF SCOPE. Do not plan or fix skipped/out-of-scope findings.

### Step 4: Report the Plan and Create Tasks
Print a concise plan: total findings, count to fix, count skipped/out-of-scope with reasons. **Then immediately create a TaskList** with one task per non-skipped finding, in fix order, titled like `Fix finding 2 (P0): ERA reversals dropped, adjustments sign-stripped`. The TaskList is your loop state.

Do not ask the user to confirm. Proceed directly into Phase 2.

## Phase 2: Fix Loop (one finding at a time)

Work strictly serially — never plan or code two findings at once. Findings in the same audit frequently touch the same files (e.g. `process_era_service.rb`), and later findings must be planned against the tree as already modified by earlier fixes.

For the first `pending` task, mark it `in_progress` via TaskUpdate, then:

### Step 5: Invoke /plan
Invoke `/plan` via the Skill tool. The argument is a self-contained problem description assembled from the audit:

```
Fix audit finding <N> (<severity>) from <audit-doc-path>: <title>.

Locations: <file:line list>

<full finding body verbatim — scenario and Fix paragraph>

Constraints:
- This is a bug fix, not a feature: keep the plan minimal and scoped to this finding only. Do not fold in other audit findings — they are handled separately.
- Follow the fix direction given in the finding's "Fix:" paragraph unless exploration proves it wrong; if you deviate, record why under Decisions Made.
- Include regression specs that prove the failure scenario is fixed.
- If the finding touches Stedi request/response handling, verify field semantics against Stedi's live docs and the vendored OpenAPI schema (spec/fixtures/stedi/schema/) rather than memory, per the stedi-billing-expert skill.
```

### Step 6: Invoke /code
When `/plan` returns, locate the plan it wrote — `ls -t .claude/implementation-plan-*.md | head -1` — and invoke `/code` via the Skill tool with that **explicit path** (never "latest", which could pick up an unrelated document).

### Step 7: Record the Outcome — and Keep Going
When `/code` returns control, do the following **in the same response**:
- Record the outcome from `/code`'s report and `git status`:
  - **FIXED** — implemented and its specs pass
  - **ATTEMPTED** — changes made but validation incomplete (capture what's left)
  - **FAILED** — could not implement (capture the reason)
- Note files changed and the plan-file path for the summary.
- Mark the task `completed` via TaskUpdate (a FAILED outcome still completes the loop item).
- Check the TaskList. **If any task is still `pending`, immediately mark the next one `in_progress` and go back to Step 5.** Do not pause, do not summarize, do not hand back to the user.

### Step 8: Failure and Conflict Handling
- If `/plan` or `/code` fails on a finding, record it and continue with the next finding. Never abort the batch for one finding.
- If a later finding's fix conflicts with an earlier one's changes, the tree as it stands wins — plan against reality, and note the interaction in the summary.
- If `/code` leaves the suite broken for a finding after its own retry cycles, prefer reverting that finding's changes (its files only) over leaving the tree broken for subsequent findings; record it as FAILED.

### Step 9: Do Not Commit
No `git add`, `git commit`, `git stash`, `git reset` (except targeted reverts in Step 8), or `git push` at any point — in this skill or in instructions passed to child skills. The user reviews and commits manually.

## Phase 3: Write Summary

### Step 10: Create the Fix Summary
Write `<audit-doc-directory>/<audit-doc-basename>_FIX_SUMMARY.md` (e.g. `docs/STEDI_CLAIMS_APPEALS_ERA_AUDIT_FIX_SUMMARY.md`). Keep it short — one or two lines per finding:

```markdown
# Audit Fix Summary

**Source audit:** <audit-doc-path>
**Date:** [YYYY-MM-DD HH:MM local]
**Findings processed:** X of Y (Z skipped/out of scope)

## Fixed
- **Finding 1 (P0)** — <title>
  - Files: <paths>
  - Change: <one line>
  - Plan: <implementation-plan path>

## Attempted (not verified)
- **Finding N (P_)** — <title> — <what's left>

## Failed
- **Finding N (P_)** — <title> — <reason>

## Skipped / Out of scope
- **Finding N (P_)** — <title> — <marker or scope reason>

## Working tree
All changes are uncommitted. Review with `git status` / `git diff`, then run `bin/ci` and commit manually.
```

Do not edit the audit document itself — it is the source record. The summary file is also this skill's resumability marker: findings listed under **Fixed** there are skipped on a re-run (Step 3).

### Step 11: Final Message
Print a two-line recap: `Fixed: X | Attempted: Y | Failed: Z | Skipped: W`, then the summary path and a reminder that nothing is committed and `bin/ci` has not been run as a final gate.

## Important Guidelines

1. **Serial, one finding at a time.** Audit findings share files; parallel fixes conflict.
2. **Do not commit, stage, stash, or push.** Targeted revert of a failed finding's own files is the only allowed destructive git operation.
3. **Delegate, don't re-do.** `/plan` explores and designs; `/code` implements and tests. This skill only parses, sequences, invokes, tracks, and summarizes.
4. **Pass findings verbatim.** The audit body is the ground truth `/plan` needs — scenario, locations, and fix direction. Paraphrasing loses the failure scenario the regression spec must cover.
5. **Keep going on failures.** One broken finding never aborts the batch.
6. **Scope fidelity per finding.** Each plan/fix covers exactly one finding — no folding, no drive-by refactors.
7. **Do not edit the audit document.** Progress lives in the TaskList (during the run) and the fix summary (across runs).

## Execution Flow

1. Read the audit document
2. Parse findings with skip markers, prior-run summary, and severity scope applied
3. Print plan; create one task per finding via TaskCreate
4. **Loop**: next pending task → `in_progress` → invoke `/plan` with the finding verbatim → invoke `/code` with the resulting plan path → record outcome → `completed` → repeat until no tasks pending
5. Write the fix summary next to the audit document
6. Print recap — nothing is committed

**Anti-stop checklist every time a child skill returns:**
- [ ] Is the current finding mid-flight (planned but not coded)? → invoke `/code` now.
- [ ] Did I mark the current task `completed` after recording its outcome?
- [ ] Any `pending` tasks left? → invoke `/plan` for the next finding right now. No summary, no stopping, no asking.
- [ ] Zero pending → write the fix summary.

Begin by reading the audit document.
