---
description: Score every agreed PRD acceptance criterion against QA results, system tests, and spec evidence — report-only, produces the scorecard /build-feature gates the PR on
argument-hint: [prd-path-or-blank]
---

# Acceptance Criteria Verification

Score the current branch against the PRD's **agreed Acceptance Criteria** table at "${1:blank}":
for every `AC-n` row, find evidence that the criterion was actually *observed* to hold — a
passing Playwright QA scenario, a passing system spec, a passing unit/controller spec, or a
quoted manual check — and produce a scorecard with a verdict. This skill **analyzes and
reports only** — it never edits code, specs, QA plans, or the PRD. Callers (a human, or the
`/build-feature` pipeline) own remediation.

Where `/trace-requirements` asks "does code exist for this requirement?" (static), this skill
asks "was this outcome demonstrated?" (dynamic). Code that plausibly implements a criterion
is **not** evidence here.

## Phase 1: Resolve the PRD and the contract

- If "${1}" is a path, read that PRD.
- If blank, resolve from the branch: `git branch --show-current`, strip the `feature/` prefix,
  and look for `.claude/prds/<slug>.md`. Fall back to `ls -t .claude/prds/*.md | head -1` only
  if its `*Feature slug:*` header plausibly matches the branch.
- If no PRD can be found, **stop** and say so.

Extract the `## Acceptance Criteria` table (`| ID | Criterion | FR | Priority | Verified by |`).

- If the section is **missing**, stop: "This PRD has no Acceptance Criteria table — run `/prd`
  (or re-run it on this PRD) to draft and agree criteria." Do not fabricate criteria from the
  FR table or Definition of Done; an unagreed contract can't gate anything.
- If the `*Agreed with user: …*` stamp is **absent**, still score the table but mark the report
  **UNAGREED** in the header and in the verdict line — the caller must not treat the verdict
  as a ship signal.
- Tolerate drift: `Verified by` missing → treat as `browser`; priority missing → `Must`.

Record the slug (`FEATURE_SLUG`) for locating artifacts below.

## Phase 2: Gather evidence

Collect everything, then join. Do the analysis inline with Grep/Glob/Read/Bash — no sub-agents.

1. **QA plan** — newest `docs/qa-plans/${FEATURE_SLUG}-*.md`. Build the map
   `SC-NNN → [AC-n, …]` from each scenario's `**Verifies:**` line. Scenarios without one map
   to nothing.
2. **QA execution report** — newest `docs/bug-reports/qa-${FEATURE_SLUG}-*/INDEX.md`. Build
   `SC-NNN → PASS | FAIL | BLOCKED | SKIP` from its results table, and `SC → BUG-xxx` links.
   If the report is **older than the QA plan** it was run against, note it under Ambiguities.
3. **System tests** — `git diff main...HEAD --name-only -- spec/system/` (plus any
   `spec/system` files whose contents mention the feature). Grep them for `AC-\d+` in `it`/
   `scenario` descriptions and comments to build `spec file:example → [AC-n]`. Run them:
   `CI=true bundle exec rspec <files> --format documentation` (CI=true so rspec-retry can't
   mask a flake) and record pass/fail per example.
4. **Other specs** — for every AC whose `Verified by` includes `spec`, find the spec(s) in the
   diff that exercise it: first by `AC-n` mentions, then by reading the spec descriptions
   against the criterion text. Run those files (`bundle exec rspec <files>`).
5. **Manual criteria** — for every `manual` AC, run the exact command the criterion names
   (only if it is read-only or explicitly a dry run against the development database — never
   anything that mutates data outside a dry-run flag, and never anything targeting production)
   and capture the output. If the command isn't safe to run or isn't stated, the AC is
   UNVERIFIED with a note.
6. **Supporting** — newest `.claude/requirement-traces/trace-${FEATURE_SLUG}-*.md`, if any.
   Use it only for the Evidence column's "code:" pointer; it never upgrades a status.

Artifacts that are simply absent are not errors — they just mean less evidence. **Never treat
a missing QA report as PASS**; browser ACs without a report are UNVERIFIED.

## Phase 3: Score each criterion

For every AC row, in order, assign exactly one status:

| Status | Meaning |
|--------|---------|
| **VERIFIED** | Evidence exists at the layer the row requires (see below), and every piece of it passed |
| **FAILED** | At least one SC / spec / manual check that covers this AC failed (link the bug report or failing example) |
| **UNVERIFIED** | No SC or spec names the AC (coverage gap), or the only coverage was BLOCKED/SKIP, or the manual command couldn't be run |

Layer rules:
- `browser` — a **PASS** QA scenario naming the AC **or** a passing system-spec example naming
  it. (Either is sufficient; both is better. If one passed and the other failed → FAILED.)
- `spec` — a passing spec example that exercises the criterion (named by `AC-n`, or clearly
  matched by description — say which in Notes).
- `browser+spec` — both of the above.
- `manual` — the stated command was run and its output matches the criterion; **quote the
  proving output** in Evidence.

Rules of evidence:
- Never mark VERIFIED from reading application code, from the requirements trace, from a QA
  plan that was never executed, or from a spec you didn't run.
- A scenario/spec that covers the AC only *partially* (asserts one clause of the Then but not
  another) is UNVERIFIED with the missing clause named — precision here is the whole value.
- When a QA scenario is **FAIL** because of an unrelated expected-result checkbox (e.g. a
  console error on the page), the AC is still FAILED — the scenario is the unit of evidence —
  but say so in Notes so the fixer knows what to chase.

**Verdict** (agreed table only):
- **PASS** — every AC VERIFIED
- **PASS WITH SHOULD GAPS** — every **Must** AC VERIFIED; ≥1 Should is FAILED/UNVERIFIED
- **FAIL** — any **Must** AC is FAILED or UNVERIFIED

## Phase 4: Write the scorecard

Save to `.claude/acceptance-scorecards/scorecard-${FEATURE_SLUG}-${YYYYMMDD}.md` (create the
directory if needed):

```markdown
# Acceptance Scorecard: [Feature Name]

**PRD**: [path] — Acceptance Criteria agreed [date] | **UNAGREED**
**Branch**: [branch] (base: main)
**Evidence**: QA plan [path or "none"] · QA report [path or "none"] · system specs [N files, run
at HH:MM] · other specs [N files] · manual checks [N]

**Verdict**: PASS | PASS WITH SHOULD GAPS | FAIL
**Must**: X/Y verified • **Should**: X/Y verified

---

## Scorecard

| AC | Priority | Verified by | Status | Evidence | Notes |
|----|----------|-------------|--------|----------|-------|
| AC-1 | Must | browser | VERIFIED | SC-003 PASS; `spec/system/x_spec.rb:12` pass | |
| AC-2 | Must | spec | FAILED | `spec/services/y_spec.rb:40` FAIL | expected 0 results, got 2 |
| AC-3 | Must | browser | UNVERIFIED | — | no SC or system spec names AC-3 |
| AC-4 | Should | manual | VERIFIED | `bin/rails z:task DRY_RUN=1` → "Would delete 14 …" | |

---

## Gaps & Recommended Actions

[One entry per non-VERIFIED row, Must first, written as an executable ticket:]

1. **AC-2 (Must, FAILED)**: Fix — see `docs/bug-reports/qa-…/BUG-002-….md` / failing example
   `spec/services/y_spec.rb:40` ("…"). Then re-run SC-005 / the spec.
2. **AC-3 (Must, UNVERIFIED — coverage gap)**: Add a QA scenario to
   `docs/qa-plans/<plan>.md` with `**Verifies:** AC-3` covering "<criterion>", or a system
   spec example titled "… (AC-3)"; execute it.
3. **AC-6 (Should, UNVERIFIED — manual)**: Run `<command>` against the dev DB and confirm
   "<expected output>".

---

## Ambiguities & Recommended Defaults

[Every judgment call: an AC matched to a spec by description rather than by ID; a QA report
older than the plan; a `manual` command you declined to run and why; a scenario whose FAIL
was unrelated to the AC's clause.]
```

End your response with the verdict line, the Must/Should counts, the list of non-VERIFIED
**Must** IDs (if any), and the report path.

## Principles

1. **Report-only.** Never edit code, specs, QA plans, or the PRD — even to add a one-line
   `Verifies:` tag. The caller owns remediation.
2. **Observed, not inferred.** VERIFIED means something ran and showed the outcome. If you
   didn't see it pass, it isn't verified.
3. **Must gaps are the headline.** An unverified Should is a note; an unverified Must is the
   verdict — and, in `/build-feature`, no PR.
4. **The agreed table is the whole contract.** Don't invent criteria, don't drop rows, don't
   re-prioritize. If the table is wrong, say so under Ambiguities and let a human change it.
5. **Precise UNVERIFIEDs.** "No coverage" must name what would cover it; "partial" must name
   the missing clause.

Begin by resolving the PRD.
