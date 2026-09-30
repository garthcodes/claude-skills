---
description: Create agent-executable implementation plan based on codebase exploration
argument-hint: [problem-description-or-prd-path-or-acceptance-criteria-path]
---

# Implementation Planning

Create a comprehensive, executable implementation plan for: "${1:your development goal}"

The plan you produce is consumed by three downstream skills, so write for them:
- **/architect-review** and **/frontend-review** critique it — pre-empt their known blockers (see below) so the pipeline doesn't burn revision cycles on avoidable findings
- **/tickets** converts it into discrete tickets — every file you name and every schema you sketch must be concrete enough to become a ticket without re-derivation

## Input Resolution

If "${1}" is (or contains) a path to a PRD (`.claude/prds/*.md`) or to an acceptance-criteria
contract (`.claude/acceptance-criteria/*.md`), read **both** documents before planning:

- Given a contract path, follow its `*PRD:*` header link and read that PRD too.
- Given a PRD path, derive the slug (the PRD's `*Feature slug:*` header, else the filename)
  and read `.claude/acceptance-criteria/<slug>.md` if it exists. If it doesn't, plan from the
  PRD alone and say so in the plan header (`*Contract: none*`); ignore any
  `## Acceptance Criteria` section embedded in the PRD.

The **contract** (`## Contract` table: `| ID | Type | Criterion | Source | Priority |
Verified by |`) is the source of truth for *what must be observable* when the feature is
done — `/verify-acceptance` gates the PR on its `AC-n` rows. The **PRD** is the source of
truth for intent, context, and scope. In particular:

- **In Scope / Out of Scope** — plan exactly the in-scope items; do NOT plan anything on the
  "Do NOT Build" list (`OOS-n`), no matter how natural an extension it seems
- **Functional Requirements** (`| ID | Requirement | Priority | Observable outcome |`) — every
  FR must be traceable to a step in your plan
- **Contract rows** — every `AC-n` row (feature, permission, edge) must map to ≥1 plan step
  that produces its observable outcome; carry the AC IDs into the plan's Success Criteria.
  **Guard rows** (`Type = guard`, an observable absence) become an explicit `## Not Building`
  list in the plan — one line per guard AC ID stating what is deliberately absent — that
  implementers and reviewers read before touching code
- **Permissions matrix** — becomes the Pundit policy design
- **Existing System Context** — a head start on exploration; verify it, don't re-derive it
- **Edge Cases & Policies** — each decided behavior needs a home in the plan
- **Implementer Discretion** — decisions delegated to you; make them and record them

**Design mockups:** if `.claude/designs/<slug>/DESIGN.md` exists (written by `/design` in the
`/build-feature` pipeline), read it — **never the `.dc.html` artboards**, which are visual
reference for humans and carry inline styles that must not leak into ERB. Its `## Screens` and
`## Regions` tables are the starting point for `## Frontend` (the plan wins on component
choices; say where and why you diverge under `## Decisions Made`), and its `## Copy inventory`
seeds the plan's `### Copy` table. Absent file → no mockups exist; plan the frontend from the
contract, PRD, and precedent screens as usual.

If "${1}" is a free-text description, plan from that description plus your own exploration.

**System tests:** If the invoking context says system tests are excluded (the `/build-feature`
pipeline always does — it plans and writes them in a dedicated later phase via
`/plan-system-tests` + `/system-test-expert`, against the reviewed code), plan NO files under
`spec/system/` or `spec/features/`. Otherwise plan them for critical flows.

## Phase 1: Codebase Exploration

Launch **three Explore agents in parallel** (one message, three Agent calls). Keep their
missions distinct:

1. **Architecture & precedent**: "Find features similar to '${1}' in this Rails 8 app. Report
   the models, services, controllers, routes, and jobs they use, the patterns they follow
   (Result-object services, Pundit policies, concerns), and which one is the best template to
   pattern-match. Include file paths."
2. **Domain & data**: "Map the domain models and data relationships relevant to '${1}'. Report
   existing tables/columns/associations that will be touched, migration patterns used
   (UUID PKs, constraints, indexes), and whether affected models are SoftDeletable,
   HipaaLoggable, or tenant-scoped. Include file paths."
3. **Frontend inventory**: "For the UI implied by '${1}', report: which existing ViewComponents
   apply (check `app/components/` — especially Button, FormInput, FormSubmitButton, FormErrors,
   FormRadioGroup, DataTable, Modal, Drawer, Flash, Pill, PagyPagination, PageContainer, and the
   Filter* family), which existing Stimulus controllers could be reused
   (`app/javascript/controllers/`), and one or two existing pages that are good structural
   references. Include file paths."

Read anything the agents flag as load-bearing yourself. Also read `CLAUDE.md` conventions
relevant to the feature (SoftDeletable rules, Honeybadger context conventions, mailer rules,
timezone rules) — the reviewers will hold the plan to them.

## Phase 2: Design

Make the design decisions yourself (no sub-agents needed):

- **Data model** — tables, columns, indexes, DB-level constraints, and whether new models need
  `acts_as_tenant(:organization)`, `SoftDeletable`, `HipaaLoggable`. UUID PKs always.
- **Service layer** — VerbNounService names, Result-object returns, exception-type-specific
  rescues with `Honeybadger.notify(context: { service: self.class.name, ... })`
- **Authorization** — Pundit policy per controller, method per action, scopes for collections.
  Do NOT add `user.organization == record.organization` checks — `acts_as_tenant` already
  enforces tenant isolation; role checks alone are correct.
- **Frontend** — name the exact existing ViewComponents for every UI element (never raw
  `<button>`, `<input>`, `<table>`, modal, or filter markup — /frontend-review blocks these);
  plan new page-specific components so views stay thin (mostly `render` calls); specify
  Stimulus controllers with targets/values/actions; define Turbo Frame/Stream boundaries;
  filtered lists use `FilterContainerComponent` with auto-submit inside a `turbo_frame_tag`
  (no Filter button — see `app/views/fee_schedules/index.html.erb`); **UI copy** is labels,
  values, headings, button verbs, and validation errors only — every other visible string
  (`help_text:`, empty-state line, flash, banner) is listed in `### Copy` with the AC that
  names it or a one-line reason a label cannot supply (CLAUDE.md "UI Copy Discipline")
- **Background work** — anything slow or external-API-bound goes to Solid Queue jobs with
  retry/discard handling
- **Dependencies** — prefer what's already in the Gemfile/importmap. Only propose a new
  dependency if nothing existing serves; justify it.

## Phase 3: Write the Plan Document

Save to `.claude/implementation-plan-{feature-slug}-$(date +%Y%m%d-%H%M).md`:

```markdown
# Implementation Plan: [Feature Name]

*Generated: [timestamp]*
*Source: [PRD path or problem description]*
*Contract: [`.claude/acceptance-criteria/<slug>.md` (Review status: …) | none]*
*System tests: [included | excluded — QA via Playwright]*

## Summary
[3-5 sentences: the approach, the key design decisions, what gets reused vs. built]

## Current State
- [Existing files/models/services/components this touches, with paths]
- [The precedent feature being pattern-matched, with paths]
- [Constraints discovered during exploration]

## Data Model Changes
[For each migration: table name, full column list with types, indexes, constraints.
Concrete enough to write the migration from this section alone.]

```ruby
create_table :examples, id: :uuid do |t|
  ...
end
```

[For each new/changed model: validations, associations, enums, scopes, concerns
(acts_as_tenant / SoftDeletable / HipaaLoggable), and any soft_delete_cascades_to needs]

## Service Layer
[For each service: name, constructor args, public method(s), Result success/failure shapes,
error handling (which exception types, which user-facing failure messages)]

## Controllers & Routes
[Routes to add (RESTful, namespaced). For each controller: actions, strong params,
authorize calls, response formats (HTML/Turbo Stream/JSON)]

## Authorization
[For each policy: class name, action methods with the role logic, Scope behavior.
Note: role checks only — no org checks (acts_as_tenant handles isolation)]

## Frontend
### Screens & Flows
[Each screen: route, layout, entry point in existing navigation. When
`.claude/designs/<slug>/DESIGN.md` exists, cite the artboard (`Main.dc.html`) each screen
corresponds to and note any Regions-table divergence.]

### ViewComponents
| Component | New/Existing | Purpose | Key params |
|-----------|--------------|---------|------------|
[Every UI element maps to a component. Name existing ones explicitly.]

### Stimulus Controllers
| Controller | New/Existing | Targets | Values | Actions |
|------------|--------------|---------|--------|---------|

### Turbo
[Frame boundaries with IDs, Stream targets/actions, lazy-load points]

### States
[Empty, loading, error, success states per screen. Empty states are one line and appear in
`### Copy`. Dates display as MM/DD/YYYY.]

### Copy
| String | Screen / region | Kind | Source AC or justification |
|--------|-----------------|------|----------------------------|
[Every visible string that is NOT a field label, column header, button verb, heading, value,
or validation error. Kind ∈ help_text · empty state · flash · banner (AC-named) ·
legal/consent · error (guide). The justification is the reason a label cannot carry the
meaning — "helpful context" is not one. Anything not in this table may not be rendered
(`/tickets` copies these rows onto the screen's tickets; `/code` and `/build-feature` Step 7.6
enforce them). When nothing qualifies, write "labels, values, and validation errors only".
Seed from DESIGN.md's `## Copy inventory` when it exists.]

## Background Jobs
[Job names, triggers, retry/discard strategy, Honeybadger context]

## Integrations
[Mailers (dedicated action + branded layout), SMS, Stripe, etc. — only if applicable]

## Edge Cases
| Scenario | Behavior | Where handled |
|----------|----------|---------------|
[Pull decided behaviors from the PRD; add any discovered during exploration]

## Testing Strategy
[Model, service, controller, component, policy, and (if applicable) request specs —
by file path. NO system/feature specs when excluded above.]

## Implementation Steps
[Ordered, phased list. Each step: what to build, files to create/modify, dependencies on
prior steps. This section becomes /tickets' input — make each step atomic.

Group steps as **Foundation → lanes → Integration**, not by layer (models → services → UI):
layers chain, so they can only be built one after another; lanes can be built at the same time
(/build-feature runs independent lanes concurrently, ≤3 at once).
- **Foundation** (serial, first): every *hot-file* change the lanes need — migrations and
  anything under `db/`, `config/routes.rb`, `config/importmap.rb`, `config/locales/`,
  initializers, edits to existing shared models (associations, enums, scopes), and new policy
  skeletons. Lanes never touch these.
- **Lanes** (parallel): one vertical slice per capability — its service, controller actions,
  components, views, Stimulus controller, job, and their specs. A lane creates or modifies only
  files no other lane touches.
- **Integration** (serial, last, optional): wiring that spans lanes — nav links, shared
  partials that render several lanes' components, docs.
A genuinely linear feature is one lane — say so; that is a valid plan.]

### Phase 1: Foundation
1. [Migration X — files, depends on: nothing]
2. [Model Y associations + routes for all lanes — files, depends on: 1]

### Phase 2: Lane A — <capability>
3. [Service + controller + component — files, depends on: 2]

### Phase 3: Lane B — <capability>
...

### Phase 4: Integration
...

### Work Lanes
| Phase | Lane | After | Owns (file globs) |
|-------|------|-------|-------------------|
| 1 | Foundation | — | `db/migrate/*`, `config/routes.rb`, `app/models/client.rb`, … |
| 2 | A — <capability> | 1 | `app/services/foo/**`, `app/components/foo_*`, `spec/services/foo/**`, … |
| 3 | B — <capability> | 1 | … (disjoint from every other lane) |
| 4 | Integration | 2, 3 | `app/views/layouts/_nav.html.erb`, … |

## Not Building
[One line per guard AC from the contract — `AC-n (OOS-m): <what is deliberately absent — the
element, route, column, job, or behavior that must not appear>`. Implementers and reviewers
read this list before touching code; `/trace-requirements` checks the diff against it. Omit
the section only when there is no contract and the PRD has no Out-of-Scope list.]

## Risks
[Only real ones, with mitigations. No boilerplate.]

## Success Criteria
[Taken from the contract, not paraphrased. List every non-guard `AC-n` row verbatim
(`AC-1 (Must, browser): Given …, when …, then … — steps 3, 7`) with the plan step(s) that
satisfy each — those IDs are what `/verify-acceptance` gates the PR on. Guard rows live under
`## Not Building`. Without a contract, derive criteria from the PRD's FR *Observable outcome*
column and Definition of Done, each observable (a test passes or a browser shows it).

**AC Coverage**: every AC-n from the contract appears above (or under Not Building); every plan
step cites ≥1 AC or is marked `infra` (migrations, factories, routes, config that exist only to
serve a cited step). List any AC with no step, or any non-`infra` step with no AC — both are
plan defects to fix before writing the document.]

## Decisions Made
[Choices you made under Implementer Discretion or where the input was silent — one line each
with rationale, so reviewers can challenge the decision rather than the omission.]
```

## Planning Principles

1. **Scope fidelity** — build what the PRD says, nothing more. The contract's guard rows are
   the fence: anything a guard forbids is a review finding, and gold-plating creates QA surface
   for zero requirement coverage. Copy is scope too: a hint, description, or banner no AC
   asks for is an extra, not polish.
2. **Name real files** — every section references concrete paths. "Add a service" is not a
   plan; `app/services/generate_superbill_service.rb` is.
3. **Reuse before build** — existing components, controllers, concerns, and patterns first.
   The frontend inventory from Phase 1 exists so no existing component is missed.
4. **Boring beats clever** — follow the precedent feature's structure unless there's a stated
   reason not to.
5. **No estimates, no ceremony** — no time estimates, no "communication protocols", no
   rollback theater. Migrations should be reversible; that's the rollback plan.
6. **Decide, don't defer** — if something is ambiguous, make the call and log it under
   Decisions Made.

Begin by resolving the input (PRD and/or contract, or description), then launch the three
exploration agents in parallel.
