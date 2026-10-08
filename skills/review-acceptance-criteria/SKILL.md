---
name: review-acceptance-criteria
description: Audit an Acceptance Criteria contract against its PRD — completeness (nothing left out), fidelity (nothing extra or invented), verifiability, priorities — fix the contract in place, and stamp it PASS so /build-feature can gate on it
argument-hint: [acceptance-criteria-path-or-blank]
---

# Acceptance Criteria Review

Audit the Acceptance Criteria contract at "${1:blank}" against the PRD it was derived from, fix
what's wrong **in the contract**, and decide whether it is fit to gate a build. This is the
only skill allowed to edit an acceptance-criteria file, and only before `/plan` has run against
it. It never edits the PRD, code, specs, or QA documents.

The question this review answers: *if every row in this file were VERIFIED, would the PRD be
built exactly to spec — nothing missing, nothing extra?* A contract that lets a requirement
slip through, or that would bless an unrequested feature, fails.

## Phase 1: Resolve inputs

- If "${1}" is a path, read that contract.
- If blank, resolve from the branch: `git branch --show-current`, strip `feature/`, look for
  `.claude/acceptance-criteria/<slug>.md`. Fall back to
  `ls -t .claude/acceptance-criteria/*.md | head -1` only if its `*Feature slug:*` line
  plausibly matches the branch (or there is no feature branch).
- If none is found, **stop**: "No acceptance-criteria file — run `/acceptance-criteria <prd>`."

Read the contract's `*PRD:*` link and read that PRD in full. Extract from the PRD the same
inventory `/acceptance-criteria` uses — FRs (with priority and observable outcome), Out-of-Scope
bullets (`OOS-n`), Edge Cases (`EC-n`), Permissions cells (`PERM-<role>-<action>`), UX states,
Definition of Done items, Resolved Decisions, Implementer Discretion, `## Addendum` items
(`ADD-n`), In Scope items with no FR (`SCOPE-n`). Ignore any `## Acceptance Criteria` section
embedded in the PRD. **Addenda win**: an addendum supersedes whatever earlier PRD text it
contradicts, so a row sourced from `ADD-n` is not an invention and not a Do-NOT-Build
violation even if it contradicts an earlier FR, OOS bullet, or Resolved Decision — the
contradiction itself is a **PRD defect** (report-only; it does not fail the contract unless
it leaves a Must FR unverifiable).

Parse the contract: the `## Contract` table (`| ID | Type | Criterion | Source | Priority |
Verified by |`), `## Coverage Map`, `## Definition of Done`, `*Review status:*`.

## Phase 2: Audit

Produce findings with an ID (`RAC-1`, …), a severity, the AC/PRD item concerned, and the
**exact fix** (a rewritten row, a new row, a priority change, or "PRD defect — cannot fix
here"). Severity:

- **BLOCKER** — the contract would let the PRD be built wrong: a Must FR / OOS bullet with no
  covering AC, an AC that contradicts the PRD, an AC that positively requires a Do-NOT-Build
  item, an unverifiable Must row.
- **MAJOR** — a real gap that a Should item or a partial row leaves: Should FR uncovered, edge
  case or permission denial uncovered, compound row, vague *Then*, wrong layer, missing manual
  command, priority lower than its source FR.
- **MINOR** — hygiene: ordering, abridged text drift in the Coverage Map, a redundant row that
  duplicates another's outcome, wording that could be more concrete without changing meaning.

### 1. Completeness — nothing left out

For every PRD item in the inventory, find the ACs that prove it and judge whether they prove
**all** of it (an FR that says "sortable by name and date" with an AC that only sorts by name is
PARTIAL → MAJOR):

- every FR has ≥1 AC; every **Must** FR has ≥1 **Must** AC
- every Out-of-Scope bullet has ≥1 `guard` AC asserting a concrete absence
- every decided Edge Case row has an AC (or is cited as a Source on a feature row that actually
  exercises that edge)
- every ❌ permission cell for an in-scope action has a `permission` AC; every ✅ cell is
  proven by some row (usually the feature row) — the Coverage Map must say which
- every UX state the PRD names (empty / loading / error / success) has an AC
- every Definition of Done item maps to ≥1 AC
- any record-level scoping note in Permissions ("therapists see only their own …") has an AC
  with a *different-owner* Given

### 2. Fidelity — nothing extra, nothing invented

For every AC, confirm its Source(s) exist in the PRD and that the row asserts only what those
sources say:

- no AC asserts behavior the PRD does not specify (an invented sort order, an extra field, a
  notification the PRD never mentions) — this is how extras get *blessed*; remove or soften to
  the PRD's actual claim
- no AC contradicts a Resolved Decision
- no AC fixes an Implementer Discretion choice as a value (assert the outcome instead)
- no AC positively requires anything on the Do-NOT-Build list
- guard rows exist only for things the PRD excludes or preserves — a guard for something the
  PRD never mentioned is itself an invention

### 3. Verifiability

- Given / When / Then with concrete values (roles, routes, field values, visible text, counts)
- the *Then* is observable at the stated layer (`browser` needs something on screen; `spec`
  needs a callable behavior; `browser+spec` needs both; `manual` needs an exact command and
  the output that proves it)
- one outcome per row (a `manual` guard whose single command covers every path of one Out-of-Scope
  bullet counts as one outcome — do not split it; do flag per-file guard rows for the same bullet as
  a MINOR and merge them)
- nothing verifiable only by reading code
- guard rows name *what* would be absent (element text, route, column, enqueued job), not a
  feature name

### 4. Priority correctness

- Must FR ⇒ at least one Must AC; an AC may not be lower priority than the Must FR it is the
  sole cover for
- guards for Out-of-Scope items are Must
- Should is a downgrade with a reason visible in the PRD (a Should FR), never a default

### 5. Structure

- IDs unique (gaps allowed, duplicates not); ascending in reading order for the original
  draft — rows added by a review may sit out of order
- Coverage Map lists every PRD inventory item, and its AC lists agree with the table's Source
  column in both directions
- Definition of Done = the Must rows, verbatim, in ID order
- header lines present (`Feature slug`, `PRD`, `Generated`, `Review status`)

## Phase 3: Fix the contract (max 2 cycles)

If there are any BLOCKER or MAJOR findings, edit the contract file:

- **Add** rows at the end of their type group with the next unused ID — never renumber.
  Post-review appends break strict reading order; that is accepted (IDs must be unique and
  never reused, not sorted)
- **Rewrite** a row in place, keeping its ID
- **Drop** a row only when it is an invention or an exact duplicate; leave the ID gap and note
  the removal in the report
- Update the Coverage Map and Definition of Done to match
- Record the change in the file under a `## Review Log` section (`YYYY-MM-DD — RAC-3: added
  AC-14 (guard for OOS-2)`) so the history is visible to later phases

Then re-run the Phase 2 audit on the edited file. **Maximum 2 fix cycles.** MINOR findings are
fixed opportunistically in the same pass when the fix is mechanical; otherwise they are listed
and left.

**PRD defects** — things the contract cannot repair because the PRD itself is silent or
contradictory (an FR with no observable outcome, an edge case marked TBD, a permission row for
an action no FR describes, two Resolved Decisions in conflict) — are **not** fixed by guessing.
List them under `## PRD Defects` in the report with the PRD line and what decision is needed.
A PRD defect that leaves a **Must** FR unverifiable is a BLOCKER that stays open.

## Phase 4: Stamp and report

Set the contract's `*Review status:*` line:

- `PASS YYYY-MM-DD` — zero BLOCKER and zero MAJOR remaining
- `PASS YYYY-MM-DD (minors: n)` — same, with n MINORs *remaining* (not found) listed in the report
- `FAIL YYYY-MM-DD` — any BLOCKER or MAJOR remains after the fix cycles

Write the report to `.claude/acceptance-criteria-reviews/review-<slug>-<YYYYMMDD>.md`:

```markdown
# Acceptance Criteria Review: <feature-slug>
*Contract: <path> • PRD: <path> • Reviewed: YYYY-MM-DD*

**Verdict**: PASS | PASS WITH MINORS | FAIL
**Contract**: N rows (Must X / Should Y — feature a · permission b · edge c · guard d) — was N₀ before fixes
**Coverage**: FRs X/Y • Out-of-Scope guards X/Y • Edge cases X/Y • Permission denials X/Y • UX states X/Y • DoD X/Y • Addenda X/Y
(denominators = items the PRD lists; `n/a` items count as covered and are noted as "(n n/a)")

## Findings
| ID | Severity | Dimension | AC / PRD item | Finding | Fix applied |
|----|----------|-----------|---------------|---------|-------------|

## Remaining (not fixed)
- MINORs and any open BLOCKER/MAJOR, one line each with why

## PRD Defects
- <PRD section/line> — <what is missing or contradictory> — <the decision needed>
  (empty section if none)

## Changes made to the contract
- one line per add / rewrite / drop, with AC IDs
```

End the response with the verdict line, the counts line, the list of open BLOCKER/MAJOR IDs
(if any), the PRD Defects (if any), and the report path. On `FAIL`, say explicitly: "Do not
run `/build-feature` on this contract — resolve the PRD defects with `/prd`, re-run
`/acceptance-criteria`, then this review." On a `PASS` that still lists PRD Defects, add one
line: "The contract is buildable; the PRD contradictions above should be cleaned up in the
PRD (`/prd`) before its next revision."

## Principles

1. **Both directions** — a missing criterion and an invented criterion are equally defects;
   the first ships less than the PRD, the second blesses more.
2. **Fix the contract, report the PRD** — the contract is this skill's to repair; the PRD is
   the user's and is only ever annotated in the report.
3. **Concrete beats complete-sounding** — "handles errors gracefully" covers nothing; a row is
   only coverage if a browser, spec, or command can fail it.
4. **Stable IDs** — downstream artifacts cite `AC-n`; append, never renumber.
5. **PASS means gate-worthy** — `/build-feature` will refuse to build on anything else, so do
   not stamp PASS with a known MAJOR open.

Begin by resolving the contract and reading its PRD.
