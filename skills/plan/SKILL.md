---
description: Create agent-executable implementation plan based on codebase exploration
argument-hint: [problem-description-or-prd-path]
---

# Implementation Planning

Create a comprehensive, executable implementation plan for: "${1:your development goal}"

The plan you produce is consumed by three downstream skills, so write for them:
- **/architect-review** and **/frontend-review** critique it — pre-empt their known blockers (see below) so the pipeline doesn't burn revision cycles on avoidable findings
- **/tickets** converts it into discrete tickets — every file you name and every schema you sketch must be concrete enough to become a ticket without re-derivation

## Input Resolution

If "${1}" is (or contains) a path to a PRD (`.claude/prds/*.md`), read the PRD first. It is the
source of truth for scope. In particular:

- **In Scope / Out of Scope** — plan exactly the in-scope items; do NOT plan anything on the
  "Do NOT Build" list, no matter how natural an extension it seems
- **Functional Requirements + acceptance criteria** — every FR must be traceable to a step in
  your plan; carry the acceptance criteria into the plan's Success Criteria
- **Permissions matrix** — becomes the Pundit policy design
- **Existing System Context** — a head start on exploration; verify it, don't re-derive it
- **Edge Cases & Policies** — each decided behavior needs a home in the plan
- **Implementer Discretion** — decisions delegated to you; make them and record them

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
  (no Filter button — see `app/views/fee_schedules/index.html.erb`)
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
[Each screen: route, layout, entry point in existing navigation]

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
[Empty, loading, error, success states per screen. Dates display as MM/DD/YYYY.]

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
prior steps. This section becomes /tickets' input — make each step atomic.]

### Phase 1: Foundation
1. [Migration X — files, depends on: nothing]
2. [Model Y — files, depends on: 1]

### Phase 2: Core
...

### Phase 3: UI
...

## Risks
[Only real ones, with mitigations. No boilerplate.]

## Success Criteria
[Copied/adapted from the PRD's acceptance criteria and Definition of Done. When the PRD has an
Acceptance Criteria table, list its rows by ID (`AC-1: …`) verbatim and name the plan step(s)
that satisfy each — those IDs are what `/verify-acceptance` gates the PR on. Every FR maps to
at least one criterion. Each criterion is observable (a test passes or a browser shows it).]

## Decisions Made
[Choices you made under Implementer Discretion or where the input was silent — one line each
with rationale, so reviewers can challenge the decision rather than the omission.]
```

## Planning Principles

1. **Scope fidelity** — build what the PRD says, nothing more. Gold-plating creates review
   findings and QA surface for zero requirement coverage.
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

Begin by resolving the input (PRD or description), then launch the three exploration agents
in parallel.
