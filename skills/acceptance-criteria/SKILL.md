---
name: acceptance-criteria
description: Derive the Acceptance Criteria contract from a PRD — one observable Given/When/Then row per requirement, edge case, permission denial, and Out-of-Scope guard — written to .claude/acceptance-criteria/<slug>.md for /review-acceptance-criteria to audit and /build-feature to gate on
argument-hint: [prd-path-or-blank]
---

# Acceptance Criteria Generation

Derive the **Acceptance Criteria contract** for the PRD at "${1:blank}". The contract is a
standalone document (`.claude/acceptance-criteria/<feature-slug>.md`) that every step of
`/build-feature` reads — `/plan`, the plan reviews, `/tickets`, `/code`, `/trace-requirements`,
`/plan-system-tests`, `/create-qa-document`, and finally `/verify-acceptance`, which decides
whether a PR is opened at all. Its job is to make "built to spec" mechanical: **nothing the PRD
asks for is left out, and nothing the PRD excludes gets added.**

This skill is deterministic and non-interactive: it reads the PRD and writes the file. It never
asks the user anything, never edits the PRD, and never invents product decisions — where the PRD
is silent, that is a finding for `/review-acceptance-criteria` to surface, not a gap to fill.

## Phase 1: Resolve and read the PRD

- If "${1}" is a path, read that PRD.
- If blank, resolve from the branch: `git branch --show-current`, strip the `feature/` prefix,
  and look for `.claude/prds/<slug>.md`. Fall back to `ls -t .claude/prds/*.md | head -1` only
  if its `*Feature slug:*` header plausibly matches the branch (or there is no feature branch).
- If no PRD can be found, **stop** and say so — suggest `/prd`.

Extract, in this order:

| PRD section | What to capture | Source ID scheme |
|-------------|-----------------|------------------|
| Header | `*Feature slug:*`, feature name | — |
| Executive Summary, In Scope | the capabilities being built | — |
| `### Out of Scope — Do NOT Build` | every bullet, in order | `OOS-1`, `OOS-2`, … (use the PRD's numbers if present, else number in order) |
| `## Functional Requirements` | every `FR-n` row, its priority, its *Observable outcome* column | `FR-n` |
| `## User Experience → States` | each named state (empty / loading / error / success) | `UX-empty`, `UX-loading`, `UX-error`, `UX-success` |
| `## Permissions` | every cell — ✅ and ❌ — plus any record-level scoping note | `PERM-<role>-<action-slug>` |
| `## Edge Cases & Policies` | every row's decided behavior | `EC-1`, `EC-2`, … (PRD numbers if present, else in order) |
| `## Definition of Done` | each checkbox | `DOD-n` |
| `## Resolved Decisions` | each choice (constraints ACs must not contradict) | — |
| `## Implementer Discretion` | each delegated item (ACs assert the outcome, never the choice) | — |
| `## Addendum …` sections (if any) | every requirement / exclusion / decision they add or change | `ADD-n` (per addendum item, in order) |
| In Scope items with no FR | capabilities the FR table doesn't restate (docs, spec updates) | `SCOPE-n` (the In Scope number) |

ID conventions:
- `UX-<slug>` for any state the PRD names (`UX-empty`, `UX-error`, `UX-removed-route`, …).
- `PERM-<role>-<action-slug>` with a short action slug (≤3 words, kebab-case,
  e.g. `PERM-therapist-edit-demographics`). `n/a` cells are not inventory.
- **Addenda win.** An `## Addendum` section supersedes whatever it contradicts earlier in the
  PRD (an FR, an Out-of-Scope bullet, a Permissions cell, a Resolved Decision). Derive from
  the addendum, cite `ADD-n`, and list each superseded item in the final report so the
  reviewer can record the contradiction as a PRD defect — do not write ACs for the superseded
  version.
- Definition of Done checkboxes that merely echo rows of an embedded (ignored) AC table are
  not inventory — skip them; DoD items that restate FRs map to those FRs.

**Ignore any `## Acceptance Criteria` section embedded in the PRD.** Older PRDs carried one;
the contract is always generated fresh from the sections above.

Tolerate format drift: FR tables whose fourth column is named `Acceptance Criteria` or `Notes`
are read the same way; a missing section yields zero rows of that type and is noted in the
final summary.

## Phase 2: Draft the criteria

### Drafting rules

- **One row per observable outcome**, written as **Given / When / Then** with concrete data
  ("Given the seeds are loaded, when a therapist searches `Z63` in the treatment-plan diagnosis
  search, then 0 results are shown and searching `F43` still returns results" — not "Z codes
  are hidden").
- **IDs** `AC-1`, `AC-2`, … in reading order: feature rows grouped by FR category in PRD order,
  then permission rows, then edge rows, then guard rows. IDs are stable once the file is
  reviewed — never renumber; dropped rows leave gaps.
- **Type** — one of:
  - `feature` — a capability the PRD asks for (sourced from an FR, UX state, or DoD item)
  - `permission` — a role can / cannot do something (sourced from the Permissions matrix)
  - `edge` — a decided edge-case behavior (sourced from Edge Cases & Policies)
  - `guard` — an observable **absence**: something the PRD says must NOT be built or must NOT
    change (sourced from Out of Scope, or from an FR / decision that explicitly preserves
    existing behavior)
- **Source** — the PRD item(s) the row proves, using the ID scheme above (`FR-2`,
  `FR-2 / EC-3`, `OOS-1`, `PERM-therapist-delete`, `UX-empty`). Every row has ≥1 source; a row
  with no PRD source is an invention and must not exist.
- **Coverage** — every FR has ≥1 AC; every **Must** FR has ≥1 **Must** AC; every Out-of-Scope
  bullet has ≥1 guard AC; every ❌ permission cell for an in-scope action has a permission AC
  (✅ cells are usually proven by the feature rows — say so in the Coverage Map); every
  Edge Case row has an AC (or is explicitly folded into a feature row that cites `EC-n`);
  every UX state the PRD names has an AC; every DoD item maps to ≥1 AC.
- **Priority** — `Must` (PR is blocked until verified) or `Should` (PR opens as draft if
  unverified). Inherit from the source FR; guard rows for Out-of-Scope items are `Must`;
  edge, UX, permission, and DoD rows inherit the priority of the FR they refine, else `Must`.
  `Should` only ever comes from a `Should` FR — never as a default.
- **Verified by** — the cheapest layer that can *observe* the outcome:
  - `browser` — Playwright QA scenario and/or Capybara system test (default for anything a user
    sees or does, including guard rows: "no `Export` button is rendered on `/clients/:id`")
  - `spec` — model/service/controller/component/policy spec (server-side rules a browser can't
    isolate, e.g. "a non-F code in the AI response is filtered before rendering"; policy
    denials are usually `spec` or `browser+spec`)
  - `browser+spec` — both required (typically validation that has a UI and a server rule)
  - `manual` — only for things neither can reach (a rake task's dry-run output, a mailer's
    rendered text). The criterion must then say **exactly** what command to run and what
    output proves it. For "file X / behavior Y is unchanged" guards, the command is
    `git diff origin/main...HEAD -- <path>` and the proof is empty output.
- **Group static guards per Out-of-Scope item.** When a guard is proven by a command over the diff
  (`git diff origin/main...HEAD -- <paths>` is empty, a `grep` finds nothing, no file added under a
  path), write **one** `manual` row per Out-of-Scope bullet that lists every path/pattern for that
  bullet in a single command — not one row per file. Keep separate rows only when the proofs need
  different layers (a browser absence and a diff check for the same bullet stay two rows) or when
  one path must stay changeable while its sibling must not.
- **Guard rows assert absence concretely.** "Given an `admin` on `/settings`, when the page
  renders, then there is no link or button whose text contains `Bulk export`" — not "bulk export
  is not built". Where the Out-of-Scope bullet is a *behavior* rather than a UI element, assert
  the unchanged behavior with the same concreteness ("… then the existing `client_messages`
  count is unchanged and no email is enqueued").
- **Negative and permission cases get their own rows** — "Given a `therapist`, when they visit
  `/x` directly, then they see 403 / are redirected to …". Empty state, error state, and every
  decided edge-case policy that a user can observe also gets a row.
- **One outcome per row.** Split "and also" criteria; compound rows hide partial failures.
- **Nothing that is only verifiable by reading code.** "The service uses a Result object" is a
  plan concern, not an AC. "Records are soft-deleted" becomes "… then the row is absent from
  the index and `Client.deleted.count` is 1" (`spec`).
- **Never fix a choice the PRD delegated.** For Implementer Discretion items, assert the
  required outcome ("an empty-state message is shown") not the choice ("the message reads …").
- **Never contradict a Resolved Decision**, and never write a *positive* AC for anything on
  the Do-NOT-Build list.

## Phase 3: Write the contract

Write to `.claude/acceptance-criteria/<feature-slug>.md` (create the directory if needed):

```markdown
# Acceptance Criteria — <Feature Name>

*Feature slug: `<feature-slug>`* · *PRD: `.claude/prds/<feature-slug>.md`* · *Generated: YYYY-MM-DD*
*Review status: UNREVIEWED*

This file is the contract `/build-feature` builds to and gates the PR on. It is derived from the
PRD — the PRD stays the source of product intent; this file is the checklist of observable
outcomes that prove the PRD was built to spec, with nothing missing and nothing extra. Only
`/review-acceptance-criteria` may edit it, and only before `/plan` runs.

## Contract

| ID | Type | Criterion | Source | Priority | Verified by |
|----|------|-----------|--------|----------|-------------|
| AC-1 | feature | Given <precondition>, when <action>, then <observable result with concrete values> | FR-1 | Must | browser |
| AC-2 | feature | Given …, when …, then … | FR-2 / UX-empty | Must | browser |
| AC-3 | permission | Given a `therapist`, when they visit `/…` directly, then … | PERM-therapist-manage | Must | browser+spec |
| AC-4 | edge | Given …, when …, then … | EC-1 / FR-2 | Should | spec |
| AC-5 | guard | Given an `admin` on `/…`, when the page renders, then no element with text `…` exists | OOS-1 | Must | browser |
| AC-6 | feature | Given …, when `bin/rails z:task DRY_RUN=1` is run, then it prints "Would delete N" and deletes nothing | FR-4 | Should | manual |

## Coverage Map

| PRD item | Text (abridged) | ACs |
|----------|-----------------|-----|
| FR-1 | … | AC-1 |
| FR-2 | … | AC-2, AC-4 |
| OOS-1 | … | AC-5 |
| PERM-therapist-manage | ❌ | AC-3 |
| PERM-admin-manage | ✅ | AC-1 (positive path) |
| EC-1 | … | AC-4 |
| UX-empty | … | AC-2 |
| DOD-1 | … | AC-1 |

## Definition of Done
- [ ] AC-1: <criterion verbatim>
- [ ] AC-3: <criterion verbatim>
- [ ] AC-5: <criterion verbatim>
```

- **Coverage Map** has one row for *every* extracted PRD item, grouped by section in the
  order of the Phase 1 table (all FRs, then OOS, then UX, then PERM, then EC, then DoD, then
  ADD / SCOPE). An item with `—` in the ACs column is a defect this skill must not leave behind —
  either write the row or (only when the PRD item is genuinely unobservable, e.g. a "design
  for later" note) put `n/a — <reason>` so the reviewer can judge it.
- **Definition of Done** lists the **Must** rows only, in ID order, criterion text verbatim.
  No new content.

**Existing file rule:** if `.claude/acceptance-criteria/<slug>.md` already exists and its
`*Review status:*` line is `UNREVIEWED` or `FAIL …`, overwrite it. If it is `PASS …`, the
contract is frozen — write to `.claude/acceptance-criteria/<slug>-<YYYYMMDD-HHMM>.md` instead
and say so prominently; the caller decides whether to replace the reviewed contract.

## Phase 4: Self-check, then report

Before finishing, run the same checklist `/review-acceptance-criteria` applies and fix what
fails (this is cheap now and expensive later):

1. Every FR / OOS / EC / PERM-❌ / UX / DoD item has ≥1 AC in the Coverage Map (or `n/a` with a reason)
2. Every Must FR has ≥1 Must AC; every OOS guard is Must
3. Every row: Given/When/Then, concrete values, exactly one outcome, ≥1 Source, a Type, a layer
4. Every `manual` row names the exact command and the proving output
5. No row is verifiable only by code reading; no row fixes an Implementer Discretion choice;
   no row contradicts a Resolved Decision; no positive row for a Do-NOT-Build item
6. IDs sequential in reading order; DoD = Must rows verbatim

Then report, in this order:

- The file path
- `N rows (Must X / Should Y — feature a · permission b · edge c · guard d)`
- PRD sections that were missing or empty (so the reader knows what could not be covered)
- Addendum items and the earlier PRD items each one supersedes (`ADD-1 supersedes FR-2, OOS-1`)
- Any PRD item you marked `n/a`, one line each
- "Next: `/review-acceptance-criteria <path>` — the contract is not binding until it passes."

## Principles

1. **Derive, don't decide** — every row traces to a PRD line. If you can't cite a source, the
   row doesn't belong; if the PRD is silent on something that clearly matters, say so in the
   report rather than guessing.
2. **Absence is a requirement** — guard rows are what stop an eager implementer from adding
   "helpful" extras. Write them as concretely as feature rows.
3. **Observable or nothing** — a criterion the browser, a spec, or a quoted command can't
   witness will never be verified and would silently weaken the gate.
4. **Stable IDs** — downstream artifacts (plan steps, tickets, QA scenarios, specs) cite
   `AC-n`; renumbering breaks the trace.
5. **The PRD is read-only here** — PRD defects are reported, never patched.

Begin by resolving and reading the PRD.
