# B2 — Code review & fixes

## Inputs

- Bootstrap per `_shared.md`. From the state file: implementation commit hash, SKIPPED tickets.
- No PR exists yet; `/full-review` falls back to the local branch diff (`git log main..HEAD`).

**Parallel:** you are the **lead** of the B2 ‖ B3 pair (`_shared.md` → Parallel pairs). B3 is
reviewing the same branch right now and waits for your Phase Log box before it writes anything —
check it as your very last action.

## Steps

Run a full code + scale review and apply the fixes **before** QA, so QA exercises hardened code.

**Contract rule for this phase:** review fixes harden what the contract asks for; they never widen
it. `/review-fixes` reads the contract and lists its Must rows as acceptance-critical invariants and
its guard rows as must-not invariants — reject (record as deferred, with the AC ID) any fix ticket
that would add unrequested behavior or violate a guard AC.

### Step 1: Reviews and fix plan

```
/full-review --plan-only
```

It runs, in order, `/review` → `.claude/reviews/branch-review-*.md`, `/scale-review` →
`.claude/scale-reviews/scale-review-*.md`, `/review-fixes` → `.claude/fix-plans/fix-plan-*.md`, and
then **stops before `/code`**, returning the fix-plan path, P0–P3 ticket counts, and Open Questions.

**Autonomous override:** `/full-review` normally waits for the user to answer the fix plan's Open
Questions. Do NOT stop. Make the best reasonable call for each, write the decision as a one-line note
at the top of the fix plan (so the worker sees it), and record every unresolved question in the state
file under "Known Issues (Review)".

**Scope:** P0/P1/P2 tickets are applied. P3 / nice-to-have tickets are deferred — record them under
"Deferred (Review)" so they surface in the PR.

### Step 2: Apply the fix plan via a worker

Follow the **Implementation workers** recipe in `_shared.md` with the `/code` argument:

```
.claude/fix-plans/fix-plan-<actual-name>.md — scope: P0–P2. Contract: .claude/acceptance-criteria/${FEATURE_NAME}.md
```

Constraints (the template relays them): NO new system tests / feature specs — updating an EXISTING
system test a fix legitimately breaks is allowed; honor the fix plan's recommended order and its
acceptance-critical invariants. If the fix plan is large (> ~12 P0–P2 tickets), split into two
workers by priority (`scope: P0–P1`, then `scope: P2`).

Verify the return, then run the specs covering the files the worker touched:

```bash
git status --short
bundle exec rspec <spec files for touched app files> 2>&1 | tail -40
```

### Step 3: Commit review fixes and quick gates

```bash
git add <specific files>
git diff --cached --quiet || git commit -m "$(cat <<'MSG'
refactor: apply code & scale review fixes for ${FEATURE_NAME}

Addresses findings from /review and /scale-review consolidated via /review-fixes.

Co-Authored-By: [your standard Claude Code co-author line]
MSG
)"
bin/standardrb --fix 2>&1 | tail -20
bundle exec brakeman -q 2>&1 | tail -40
```

Fix and commit anything new this branch introduced (small `fix:` commit).

## CHECKPOINT

Update the state file (check the B2 box **last**, after everything else is written and committed):
Phase Log B2 checked; Artifacts with the review, scale-review, and fix-plan
paths; Results with both review verdicts, fix-plan ticket counts (P0/P1/P2/P3), tickets applied vs.
deferred, unresolved Open Questions and the decisions taken, the review-fixes commit hash.

## RETURN

```
B2 DONE
COMMITS: <hash> refactor (or "no fixes needed")
REVIEW: <verdict>   SCALE: <verdict>
FIX PLAN: <path> — P0 <n> P1 <n> P2 <n> applied; P3 <n> deferred
OPEN QUESTIONS: <none | one line each with the decision taken>
```
