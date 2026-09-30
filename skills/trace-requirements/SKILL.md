---
description: Verify every PRD functional requirement is implemented in the branch diff — map each FR (and each row of the acceptance-criteria contract, guards included) to code/spec evidence or flag it MISSING/PARTIAL
argument-hint: [prd-or-contract-path-or-blank]
---

# Requirements Traceability

Verify that the current branch actually implements the PRD at "${1:blank}": map every
Functional Requirement and Definition of Done item to concrete code/spec evidence in the
branch diff, or flag it as a gap. This skill **analyzes and reports only** — it never edits
code. Callers (a human, or the `/build-feature` pipeline) decide what to do with the gaps.

This is the static gate between "the reviews liked the plan" and "QA exercised the behavior":
it catches requirements that were dropped between plan and code, which neither plan review nor
QA-scenario execution is guaranteed to notice.

## Phase 1: Resolve the PRD and the contract

"${1}" may be a PRD path or an acceptance-criteria contract path; the trace needs the PRD and
uses the contract when one exists.

- If "${1}" is a path under `.claude/acceptance-criteria/`, read that contract, follow its
  `*PRD:*` link, and read that PRD.
- If "${1}" is a PRD path, read it, then derive the slug (its `*Feature slug:*` header, else
  the filename) and look for `.claude/acceptance-criteria/<slug>.md`.
- If blank, resolve from the branch: `git branch --show-current`, strip the `feature/` prefix,
  and look for `.claude/prds/<slug>.md` and `.claude/acceptance-criteria/<slug>.md`. If the
  PRD misses, fall back to the newest PRD: `ls -t .claude/prds/*.md 2>/dev/null | head -1` —
  but verify its `*Feature slug: \`...\`*` header plausibly matches the branch before
  trusting it.
- If no PRD can be found, **stop** and say so — a trace without a PRD is meaningless. Suggest
  `/prd` to create one.
- If no contract file exists, continue: the `## Acceptance Criteria Trace (static)` section
  reads `N/A — no contract file; run /acceptance-criteria`, and the verdict is unaffected.

Extract from the PRD:
- **Functional Requirements** — the `| ID | Requirement | Priority | Observable outcome |`
  tables under `## Functional Requirements` (grouped under `###` category headings; IDs are
  `FR-1`, `FR-2`, … Priority is `Must` or `Should`; the *Observable outcome* is what the code
  must plausibly produce)
- **Definition of Done** — the checkbox list under `## Definition of Done` (lists the Must FRs)
- **Out of Scope** — the numbered bullets (`OOS-1`, `OOS-2`, …) under
  `### Out of Scope — Do NOT Build`
- **Edge Cases & Policies** — the decided-behavior table (rows carry an `ID` column, `EC-1`,
  `EC-2`, …; used as supporting evidence targets)

Ignore any `## Acceptance Criteria` section embedded in a PRD — the contract file is the only
source of ACs.

Extract from the contract (when present):
- **Acceptance Criteria** — the `## Contract` table
  (`| ID | Type | Criterion | Source | Priority | Verified by |`, rows `AC-1`, …). Type is
  `feature`, `permission`, `edge`, or `guard`; Source cites the PRD items (`FR-n`, `OOS-n`,
  `EC-n`, `PERM-…`, `UX-…`, `DOD-n`) the row proves. Note the `*Review status:*` line — an
  `UNREVIEWED` / `FAIL` contract is still traced, but say so under Ambiguities.
- **Guard rows** (`Type = guard`) assert an observable *absence*; they are traced in Phase 3
  as scope-drift checks, not as things to implement.

**Tolerate PRD format drift** — older or hand-written PRDs deviate from the `/prd` template.
Handle gracefully rather than failing:
- FR IDs may be non-sequential or suffixed (`FR-7a`) — trace whatever IDs exist
- The FR table's fourth column may be named `Acceptance Criteria` or `Notes` instead of
  `Observable outcome` — read it the same way; if it is empty, the Requirement text itself is
  the criterion
- Out-of-Scope bullets or Edge Case rows without IDs — number them in order (`OOS-n`, `EC-n`)
- The Out of Scope heading varies (`### Out of Scope (v1)` etc.) — match on "Out of Scope"
- If there is **no Definition of Done section**, report its trace as `N/A — PRD has no
  Definition of Done` and note the non-conformance under Ambiguities; do NOT invent items
  and do NOT let its absence affect the verdict (the verdict then rests on FRs alone)

## Phase 2: Scope the Diff

```bash
git branch --show-current
git diff main...HEAD --stat
git diff main...HEAD --name-only
git log main..HEAD --oneline
```

If the diff is empty (you're on `main`, or the branch has no commits), **stop** and say so —
there is nothing to trace against.

Read the full diff (`git diff main...HEAD`), keeping a map of changed files by layer
(migrations, models, services, controllers, policies, components, views, Stimulus, jobs,
mailers, specs).

## Phase 3: Trace Each Requirement

For **every FR**, **every non-guard contract row** (`feature` / `permission` / `edge`), and
**every Definition of Done checkbox**, in order:

1. Locate candidate evidence in the diff: the files, methods, routes, components, and specs
   that would satisfy it.
2. **Read the implementing code** — enough of it to confirm the acceptance criterion is
   plausibly satisfied at the code level. File names and method names alone are NOT evidence;
   a controller action that exists but ignores the required parameter is PARTIAL, not
   IMPLEMENTED. (Browser-level confirmation remains QA's job — this gate is static.)
3. Check spec coverage: which spec files in the diff exercise this requirement.
4. Assign a status:
   - **IMPLEMENTED** — code satisfies the acceptance criterion and has spec coverage
   - **PARTIAL** — some of the requirement exists but a stated part of the acceptance
     criterion is absent (name exactly what's missing); or code is complete but has zero spec
     coverage (note that as the missing part)
   - **MISSING** — no meaningful evidence in the diff

   **Client-side carve-out:** the zero-spec-coverage → PARTIAL rule applies to Ruby code.
   For behavior that lives in Stimulus controllers / JS (this repo has no JS unit-test
   framework), IMPLEMENTED requires the controller code to satisfy the criterion and the
   markup wiring (targets/actions/values in a component or view, ideally asserted by a
   component spec) to be present — browser-level proof is QA's job. Note such FRs under
   Ambiguities so the caller knows they rest on static evidence only.

Do the analysis inline with Grep/Glob/Read — no sub-agents needed.

Then check **scope drift**, in both directions:
- Diff changes not traceable to any in-scope FR (list them; small hardening/refactors that
  came from code review are normal — note them, don't inflate them into findings)
- Anything that implements an item on the **Out of Scope — Do NOT Build** list — this is
  always a finding (the PRD treats gold-plating as a defect)
- **Every guard AC** from the contract, as a static check: *does the diff introduce what this
  guard forbids?* Read the guard's *Then* (the element text, route, column, job, or unchanged
  behavior it says must be absent) and search the diff for it — a new route or link matching
  the text, a migration adding the column, a job enqueue, a change to the behavior it
  preserves. Record each guard as **HELD** (nothing in the diff introduces it) or **VIOLATED**
  (cite the file/line). A violated guard is **always a finding** under Scope Drift, regardless
  of whether the same item is also caught by the Out-of-Scope list above. Guards do not
  appear in the AC trace table as IMPLEMENTED/PARTIAL/MISSING — held/violated is their whole
  status here; whether the absence was *observed* is `/verify-acceptance`'s job.

Exclude pipeline/working artifacts from drift analysis entirely: anything under
`.claude/` (plans, tickets, reviews, bug-reports, prds), `docs/qa-plans/`,
`docs/bug-reports/`, `tmp/`, and screenshots. They are not product changes.

## Phase 4: Write the Report

Save to `.claude/requirement-traces/trace-{feature-slug}-{YYYYMMDD}.md` (create the directory
if it doesn't exist):

```markdown
# Requirements Trace: [Feature Name]

**PRD**: [path]
**Contract**: [`.claude/acceptance-criteria/<slug>.md` — Review status: … | "none"]
**Branch**: [branch] (base: main)
**Analyzed**: [date] — [N] commits, [N] files changed

---

## Executive Summary

[2-3 sentences: how complete the implementation is, where the gaps concentrate.]

**Verdict**: FULLY TRACED | GAPS FOUND | SIGNIFICANT GAPS

[FULLY TRACED = every FR and DoD item IMPLEMENTED. SIGNIFICANT GAPS = any Must-priority FR
is MISSING. Otherwise GAPS FOUND. If the PRD has no DoD section, the verdict rests on the
FRs alone.]

**FRs implemented**: X/Y (Must: X/Y, Should: X/Y) • **Acceptance Criteria (static)**: X/Y • **Guards held**: X/Y • **Definition of Done**: X/Y

---

## Functional Requirements Trace

### [Category from PRD]
| FR | Priority | Status | Evidence (files/specs) | Notes |
|----|----------|--------|------------------------|-------|
| FR-1 | Must | IMPLEMENTED | `app/services/x.rb` (`#call`), `spec/services/x_spec.rb` | |
| FR-2 | Must | PARTIAL | `app/controllers/y_controller.rb` | Sort param accepted but ignored — acceptance criterion "user can sort by date" unmet |
| FR-3 | Should | MISSING | — | No evidence in diff |

---

## Acceptance Criteria Trace (static)

| AC | Type | Source | Priority | Verified by | Status | Evidence | Notes |
|----|------|--------|----------|-------------|--------|----------|-------|
| AC-1 | feature | FR-1 | Must | browser | IMPLEMENTED | `app/...`, `spec/...` | |

[Static only: "code + spec that would satisfy this exists". Whether it was *observed* to hold
is `/verify-acceptance`'s job, later in the pipeline. Guard rows are reported under Scope
Drift, not here. `N/A — no contract file; run /acceptance-criteria` if there is no contract.]

## Definition of Done Trace

| Item | Status | Evidence |
|------|--------|----------|
| [checkbox text] | IMPLEMENTED / PARTIAL / MISSING | [files] |

---

## Scope Drift

- **Out-of-scope violations**: [changes implementing "Do NOT Build" items, or "None"]
- **Guard ACs**: [one line per guard row — `AC-n (OOS-m): HELD` or `AC-n (OOS-m): VIOLATED — file:line introduces …`; or "N/A — no contract file"]
- **Untraceable changes**: [diff work not mapping to any FR — one line each, or "None"]

---

## Gaps & Recommended Actions

[One entry per PARTIAL/MISSING item and per VIOLATED guard, written like a ticket an
implementer can execute without re-derivation: the FR/AC, what exactly is absent (or, for a
guard, what must be removed), which files to create/modify, and which precedent in the
diff/codebase to pattern-match. Must-priority gaps first.]

1. **FR-2 (Must, PARTIAL)**: Wire the `sort` param in `YController#index` into the query
   (see `XController#index` for the precedent); add a controller spec for both sort orders.

---

## Ambiguities & Recommended Defaults

[This report is often consumed by an autonomous pipeline where no one can answer questions.
For each judgment call you had to make (e.g., an FR whose acceptance criterion is only
verifiable in a browser), state the issue AND the default you applied.]
```

End your response with the verdict line, the X/Y counts, and the report path.

## Principles

1. **Report-only.** Never edit application code, specs, the PRD, or the contract — even for
   a one-line gap. The caller owns remediation.
2. **Evidence over inference.** Every IMPLEMENTED status cites files you actually read. If you
   didn't read it, it isn't evidence.
3. **Must gaps are the headline.** A MISSING Should is a note; a MISSING Must is the verdict.
4. **The PRD is the whole scope; the contract's guards are its fence.** Don't invent
   requirements the PRD doesn't state, and don't grade code quality — `/full-review` owns
   that.
5. **Honest PARTIALs.** The value of this gate is in the precise "what's absent" — vague
   PARTIALs are unactionable and worse than either clean status.

Begin by resolving the PRD and the contract.
