# C4 — Simplify, CI, and ship

## Inputs

- Bootstrap per `_shared.md`. Read the `## Acceptance` verdict from the state file first — it
  changes what Steps 5 and 6 do.

## Steps

### Step 1: Simplification pass

The code has been patched by several hands (implementation, review fixes, system-test app fixes, QA
bug fixes, acceptance gap fixes). Run `/simplify` — it reviews the branch's changed code for reuse,
simplification, efficiency, and altitude cleanups and applies the fixes:

```
/simplify
```

Then run the specs for the files it touched (`bundle exec rspec <specs> 2>&1 | tail -40`) — fix or
revert anything it broke. Simplification must not remove or change behavior any AC asserts: if a
"simplification" deleted a contract-covered path, revert that hunk. Commit (skip if no changes):

```bash
git add <specific files>
git diff --cached --quiet || git commit -m "$(cat <<'MSG'
refactor: simplify ${FEATURE_NAME} after review and QA fixes

Co-Authored-By: [your standard Claude Code co-author line]
MSG
)"
```

If Step 2's CI failures trace back to this commit and can't be fixed within the cycles, `git revert`
it rather than shipping a broken simplification.

### Step 2: Final CI gate

Run `bin/ci` **detached and polled** exactly as the Context hygiene section of `_shared.md` shows
(`log/ci-run<N>.log`, `tmp/ci.pid`, poll loops of ≤ 9 minutes until `DONE`). Never return from this
agent while `bin/ci` is running. Read failures from the log with the grep given there.

If CI fails: fix, re-run (`log/ci-run2.log`, …). **Maximum 3 cycles.** Still failing → record the
remaining failures under "Known Issues (CI)"; the PR will be a **draft** (subject to the Acceptance
Gate — a FAIL verdict still means no PR). Pre-existing flakes (see B1's memory note on UTC
date-boundary specs) are confirmed in `${PRIMARY_DIR}`, classified as pre-existing, and do not force a
draft.

## CHECKPOINT (before the state file is deleted)

Update the state file now — Step 4 builds the PR body from it: Phase Log C4 in progress, the
simplify commit hash (or "no changes"), CI result and cycle count, "Known Issues (CI)" for anything
still failing, and the screenshots branch outcome once Step 3 runs.

### Step 3: Publish QA screenshots

Screenshots go to GitHub, which is outside any data-protection boundary: they must show **seed data only, never PHI or real client data**. If a screenshot came from anything but local seed data, skip this step.

```bash
if ls tmp/pr-screenshots/*.png >/dev/null 2>&1; then
  SHOT_BRANCH="screenshots/${FEATURE_NAME}"
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  git worktree add --detach ../pr-shots-tmp
  cd ../pr-shots-tmp
  git checkout --orphan "$SHOT_BRANCH"
  git rm -rf --quiet . 2>/dev/null || true
  cp "${OLDPWD}/tmp/pr-screenshots/"*.png .
  git add ./*.png
  git commit -m "QA screenshots for ${FEATURE_NAME}"
  git push -f origin "$SHOT_BRANCH"
  cd "$OLDPWD"
  git worktree remove --force ../pr-shots-tmp
fi
```

Image URLs for the PR body: `https://github.com/${REPO}/blob/screenshots/${FEATURE_NAME}/<name>.png?raw=true`.
If anything fails (no screenshots, push rejected), skip — the PR gets "Screenshots: not available".

### Step 4: Draft the PR body — BEFORE Step 5 deletes the state file

Read `.claude/pipeline-state.md` and write the complete PR body to `tmp/pr-body.md` with the Write tool (gitignored,
survives cleanup). Fill every placeholder with real values — the file must be final:

```markdown
## Summary

Implements ${FEATURE_NAME} as specified in the PRD (committed on this branch at
`.claude/prds/${FEATURE_NAME}.md`) and verified against its acceptance-criteria contract
(`.claude/acceptance-criteria/${FEATURE_NAME}.md`, review PASS [date]).

[2-3 bullet points describing what was built]

## Acceptance Criteria

**Verdict: PASS | PASS WITH SHOULD GAPS** — Must X/Y • Should X/Y • Guards X/Y (scorecard by `/verify-acceptance`)

| AC | Type | Priority | Status | Evidence |
|----|------|----------|--------|----------|
| AC-1 | feature | Must | VERIFIED | SC-003 PASS · `spec/system/…:12` |
[one row per AC from the scorecard; non-VERIFIED Should rows in bold with the reason]

### Scope guards
[One line per `guard` AC: `AC-n — <what is deliberately absent> — VERIFIED (SC-…)`. Then the
Scope Drift table from the state file, if any surfaces were kept without an AC — "none" otherwise.]

## Screenshots

[One image per screenshot with a one-line caption:
![caption](https://github.com/{owner/repo}/blob/screenshots/{feature}/{name}.png?raw=true)
The `screenshots/{feature}` branch can be deleted after merge. Or: "Screenshots: not available"]

## Reviews Completed

- Architect Review: [verdict]
- Frontend Review: [verdict]
- Code Review / Scale Review: [verdicts; fix tickets applied / deferred]
- Security Review: [Critical/High fixed: N; recorded findings: N or "None"; UNRESOLVED blockers listed prominently]

## Requirements Trace

- FRs implemented: X/Y (Must: X/Y, Should: X/Y)
- Definition of Done traced: X/Y
- Gaps: [FR IDs still PARTIAL/MISSING with one-line reasons, or "None"]

## System Tests

- Scenarios Implemented: X (spec/system/...)
- Passing: X | Pending (documented): Y
- App bugs caught and fixed by system tests: [list or "None"]

## QA Results

- Scenarios Passed: X/Y
- Bugs Found and Fixed: Z

## Known Issues

[Unverified Should ACs (with the scorecard reason), retry-limit escalations, unresolved review
feedback, failing CI checks, QA bugs not resolved. Pull these from `.claude/pipeline-state.md` NOW.
If none, write "None."]

## Changes

- `file1` - description
- `file2` - description

## Testing

- [ ] `bin/ci` passes (linting, security, tests)
- [ ] QA scenarios pass (Playwright verification)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

**Cold-review notes, from the same read.** Step 7's reviewer needs what the state file knows, and
Step 5 deletes it. Write `tmp/cold-review-notes.md` now, about 15 lines, honestly: the decisions agents
made that the PRD left open, retry-limit escalations, ACs verified only by a spec (not seen in QA),
Should ACs left unverified and why, roles or data QA didn't cover, places where the build moved from
the plan, and adjacent problems the reviews or QA noticed but left alone.

### Step 5: Remove pipeline artifacts

Delete the planning, review, ticket, trace, and QA documents generated **by this pipeline run**.
**Delete by feature-scoped filename pattern — NEVER by whole directory**, and check `git status`
before committing: the worktree is a full checkout and other features' committed artifacts may live
in the same directories (a past run had to restore 6 files).

```bash
SLUG="${FEATURE_NAME}"
rm -f .claude/implementation-plan-*"${SLUG}"*.md .claude/tickets-*"${SLUG}"*.md
rm -f .claude/architect-review-*"${SLUG}"*.md .claude/frontend-review-*"${SLUG}"*.md
rm -f .claude/reviews/branch-review-*"${SLUG}"*.md .claude/scale-reviews/scale-review-*"${SLUG}"*.md
rm -f .claude/fix-plans/fix-plan-*"${SLUG}"*.md
rm -f .claude/requirement-traces/trace-"${SLUG}"-*.md
rm -f .claude/acceptance-criteria-reviews/review-"${SLUG}"-*.md
rm -f .claude/acceptance-criteria/"${SLUG}"-[0-9]*.md      # timestamped drafts only — NEVER the contract
rm -f docs/qa-plans/"${SLUG}"-*.md; rm -rf docs/bug-reports/qa-"${SLUG}"-*/
rm -f tmp/test-plans/"${SLUG}"-*.md
rmdir .claude/reviews .claude/scale-reviews .claude/fix-plans .claude/requirement-traces \
      .claude/acceptance-scorecards .claude/acceptance-criteria-reviews \
      docs/qa-plans docs/bug-reports tmp/test-plans 2>/dev/null || true
```

Artifacts whose filenames don't carry the slug (skills name files by branch/date): list them with
`ls -t <dir> | head` and delete only the ones dated within this run.

- **PASS / PASS WITH SHOULD GAPS**: also `rm -f .claude/acceptance-scorecards/scorecard-${SLUG}-*.md .claude/pipeline-state.md`.
- **FAIL**: keep the scorecard and the state file (resume inputs for a relaunched C3/C4); copy the
  scorecard to `tmp/acceptance-scorecard.md` as well.

Preserve `.claude/skills/`, `.claude/prds/`, `.claude/acceptance-criteria/<slug>.md`, and every
other permanent file. Then:

```bash
git status --short      # deleted TRACKED files must all be this run's artifacts — restore anything else with git checkout
git add <the specific deleted artifact paths>
git diff --cached --quiet || git commit -m "$(cat <<'MSG'
chore: remove pipeline artifacts

Co-Authored-By: [your standard Claude Code co-author line]
MSG
)"
```

### Step 6: Rebase, push, and apply the Acceptance Gate

```bash
git fetch origin main
git rebase origin/main
```

- Clean rebase, nothing new on main → push.
- Clean rebase over new main commits → smoke-run this feature's spec files, then push (full `bin/ci`
  already ran; repeat it only if the smoke check fails).
- Conflicts → resolve preserving BOTH intents (prefer main's side in unrelated code); re-run the
  specs for every conflicted file. A messy rebase → `git rebase --abort`, push un-rebased, note
  "branch is behind main; rebase needed before merge" in Known Issues.

```bash
git push -u origin "feature/${FEATURE_NAME}"
```

Then the gate, from the `## Acceptance` verdict:

- **PASS** → `gh pr create --title "feat: ${FEATURE_NAME}" --body-file tmp/pr-body.md`
- **PASS WITH SHOULD GAPS** → `gh pr create --draft --title "feat: ${FEATURE_NAME}" --body-file tmp/pr-body.md`
- **FAIL** → **no PR.** The branch is pushed so nothing is lost; the state file, scorecard, and
  `tmp/pr-body.md` stay in place; return `GATE FAILED` with the unmet Must ACs. Do NOT open a draft
  "just to ship something", and do NOT edit the contract or PRD to make it pass.

After a PR is created: `rm -f tmp/pr-body.md; rm -rf tmp/pr-screenshots/`.

### Step 7: Cold review (PR or draft PR only; skip on GATE FAILED)

Nine agents built this, and each one handed assumptions to the next. Follow
`.claude/skills/resolve-issue/references/cold-review.md` with:

- `<WHAT>`: "built feature ${FEATURE_NAME} from its PRD through a multi-agent pipeline"; `<WT>`: `${WORKTREE_PATH}`; slug `${FEATURE_NAME}`, with the notes at `tmp/cold-review-notes.md`
- `<ASK>`: `1. The PRD: ${PRD}` and `2. The acceptance contract: ${AC_PATH}` (both under `<WT>`)
- `<FOCUS>`: "The diff is large: don't read it line by line. Start from the PR's Known Issues and any AC verified only by a spec, and look for a requirement the code meets in letter but not in intent, a guard AC with a gap, and a behavior of existing screens the feature changed."
- `<STOP>`: the default ("the PR does something other than what the PRD and contract asked")
- `<RECHECK>`: re-run the affected spec files and `bin/standardrb` on the changed files; re-run `bin/ci` (detached and polled, per `_shared.md`) when app code changed

Phase agents usually can't spawn agents. When the Agent tool isn't available, take the reviewer's
part yourself using the brief: C4 didn't build the feature, so it is the coldest reader the run has. Then
`rm -f tmp/cold-review-notes.md`.

### Step 8: Keep the worktree, databases, and server

Do NOT drop the databases or stop the server. The user runs `/worktree-sweep` by hand
when they want every pipeline worktree removed.

## RETURN

```
C4 DONE
PR: <url> | DRAFT PR: <url> | GATE FAILED — <AC-n (Must, status) — reason, one per line>; scorecard <path>
PORT: <n>   CI: <green after k cycles | failing: list>
SIMPLIFY: <commit hash | no changes>   SCREENSHOTS: <branch | not available>
KNOWN ISSUES: <count> (<sources>)
COLD REVIEW: <comment link — tag counts — verify results | skipped: GATE FAILED>
```
