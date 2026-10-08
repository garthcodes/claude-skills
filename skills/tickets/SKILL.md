---
name: tickets
description: Convert implementation plan into discrete, executable tickets for Claude Code
argument-hint: <plan-file-path>
---

# Implementation Plan to Tickets Converter

Converting the implementation plan "${1}" into discrete, executable tickets.

## Phase 1: Plan Analysis

**Read and Parse the Implementation Plan:**

1. Read the entire implementation plan file at "${1}"
2. Extract the following sections:
   - **Implementation Steps / Phases** (the primary source — each step maps to one ticket)
   - **Technical Specifications** (Files to Create, Files to Modify)
   - **Dependencies between components**
   - **Success Criteria**
   - **Testing Requirements**
3. Check the plan header for a **system tests** flag. If the plan says system tests are
   excluded (all /build-feature plans do), emit NO tickets that create files under
   `spec/system/` or `spec/features/`, and omit those paths from mixed tickets.
4. If the plan's Success Criteria list contract IDs (`AC-n`, from
   `.claude/acceptance-criteria/<slug>.md`), distribute them:
   - every AC appears verbatim (ID + criterion) as an acceptance criterion on ≥1 ticket — the
     ticket(s) implementing the plan step(s) the plan names for it — so nothing is verified
     only "at the end"
   - every ticket cites ≥1 AC in its Acceptance Criteria, or is tagged `infra` with a one-line
     justification in its Description (e.g. "infra — migration serving TICKET-1-03 / AC-2")
   - guard ACs from the plan's `## Not Building` list are copied onto every ticket they
     constrain as **Must NOT** lines (`- [ ] Must NOT (AC-9): add an Export button to …`), so
     the implementer sees the fence in the ticket they are working from
   If the plan has no contract IDs, distribute its Success Criteria as before.
5. If the plan has a `## Frontend → ### Copy` table, carry it onto the tickets — `/code` reads
   tickets, not the plan, so copy that lives only in the plan is unenforced:
   - every row goes onto the ticket(s) that render that screen/region as
     `- [ ] Copy (allowed): "<string>" — <Kind>; <source AC or reason>` under Acceptance Criteria
   - every `view` / `component` ticket that renders a screen also gets
     `- [ ] Must NOT: render any other non-label/value/heading/button/validation-error text on
     this screen (CLAUDE.md "UI Copy Discipline")` — including when the table is empty or says
     "labels, values, and validation errors only"
   - never invent copy while writing tickets; a ticket may not add `help_text:`,
     `description:`, tooltip, or banner text the plan did not list

## Phase 2: Ticket Generation

Generate tickets following these rules:

### Ticket Structure

Each ticket MUST follow this exact format:

```markdown
---

### TICKET-{PHASE}-{NUMBER}: {Title}

**Phase:** {Phase Name}
**Type:** {migration|model|service|controller|component|view|stimulus|job|policy|test|configuration}
**Priority:** {P0-Critical|P1-High|P2-Medium|P3-Low}
**Complexity:** {S|M|L|XL}
**Dependencies:** {List of ticket IDs that must complete first, or "None"}

#### Description
{2-3 sentences explaining what needs to be built and why}

#### Files to Create
- `{file_path}` - {brief description}

#### Files to Modify
- `{file_path}` - {what changes}

#### Implementation Details
{Specific technical guidance from the plan - schemas, patterns, code examples}

#### Acceptance Criteria
- [ ] {Specific, testable criterion}
- [ ] {Another criterion}
- [ ] Tests pass: `bundle exec rspec {relevant_spec_files}`

#### Testing Requirements
- Unit test: `spec/{path}_spec.rb`
- {Additional test files if needed}

---
```

### Ticket Grouping Rules

1. **Database Migrations** - One ticket per migration file, always P0-Critical
2. **Models** - One ticket per model, include factory and model spec
3. **Services** - One ticket per service, include service spec
4. **Controllers** - Group by resource (e.g., all CRUD actions for one controller)
5. **Components** - One ticket per ViewComponent, include preview and spec
6. **Views** - Group related views (e.g., all views for one controller)
7. **Stimulus Controllers** - One ticket per controller
8. **Jobs** - One ticket per job with spec
9. **Policies** - Group policies by phase
10. **Configuration** - Group related config changes (routes, initializers)

### Phase Size Cap

Each `## Phase N` is executed by one fresh implementation agent (`/build-feature` runs one worker per
phase), so a phase must fit comfortably in one context. Keep every phase to **at most 5 tickets and
about 10 app files touched**, with no more than one L/XL ticket (a phase made only of S tickets — e.g.
migrations — may hold up to 8). When a plan step is bigger (e.g. one
seam that every caller must adopt), split it into consecutive phases along a dependency line — the
seam and its direct specs first, then its callers in groups of ≤ 5 tickets. Splitting adds phases;
it never reorders dependencies. (Measured 2026-09-22: an 8-ticket "core resolution & claims" phase ran 32 min at a
399k-token peak; the other phases — 2 to 7 smaller tickets — ran 8–22 min at ~200k.)

### Lanes and the Phase Schedule

`/build-feature` runs independent phases **concurrently** (≤3 per wave) in one working tree, so
every phase declares what it waits for and which files it owns. If the plan has a
`### Work Lanes` table, map each row to one `## Phase N` (split a lane over the size cap into
consecutive phases of the same lane). Without the table, derive lanes yourself the same way.

- Under each `## Phase N` heading, before its tickets, add:
  ```markdown
  **After:** Phase 1, Phase 2        (or "None")
  **Owns:** `app/services/foo/**`, `app/components/foo_*`, `spec/services/foo/**`, …
  ```
  `Owns:` covers every file in the phase's tickets' Files to Create / Files to Modify,
  specs and factories included.
- **Hot files** go only in phases that run **serial**: migrations and anything under `db/`,
  `config/routes.rb`, `config/importmap.rb`, `config/locales/**`, `config/initializers/**`,
  existing shared models, `spec/factories/` files for existing models, and `Gemfile*`. Put
  them in the Foundation phase (first); cross-lane wiring (nav, shared partials, docs) goes in an
  Integration phase (last).
- Group phases into waves: a wave is the phases whose `After:` phases are all in earlier waves.
  A wave runs **parallel** only if its phases' `Owns:` sets are disjoint and none holds a hot
  file; otherwise split it into consecutive serial waves. Max 3 phases per wave.
- A linear feature is one lane: every wave is serial. That is correct, not a failure.

### Dependency Resolution

Order tickets so that:
1. Migrations come first within each phase
2. Models before services that use them
3. Services before controllers that use them
4. Controllers before views
5. Components can be parallel with controllers
6. Tests can be included with implementation or as separate tickets

### Complexity Estimation

- **S (Small)**: Single file, < 50 lines, straightforward implementation
- **M (Medium)**: 2-3 files, 50-150 lines, some complexity
- **L (Large)**: 4-6 files, 150-300 lines, significant logic
- **XL (Extra Large)**: 7+ files, 300+ lines, complex integrations

## Phase 3: Output Document Generation

Generate the tickets document at: `.claude/tickets-{plan-name}.md`

The document should have this structure:

```markdown
# Implementation Tickets: {Project Name}

*Generated from: {plan_file_path}*
*Generated on: {timestamp}*
*Total Tickets: {count}*

## Summary

| Phase | Tickets | P0 | P1 | P2 | P3 |
|-------|---------|----|----|----|----|
| {Phase 1 Name} | {count} | {count} | {count} | {count} | {count} |
| {Phase 2 Name} | {count} | {count} | {count} | {count} | {count} |
| ... | ... | ... | ... | ... | ... |
| **Total** | **{total}** | **{total}** | **{total}** | **{total}** | **{total}** |

**Contract check**: ACs without a ticket: {list or None} • Tickets without an AC: {list or None} • `infra` tickets: {list or None}

## Dependency Graph

{ASCII diagram showing ticket dependencies}

## Execution Order

{Recommended order to execute tickets, grouped by what can be parallelized}

## Phase Schedule

| Wave | Phases | Mode | Why |
|------|--------|------|-----|
| 1 | Phase 1 | serial | Foundation — migrations, routes, shared models |
| 2 | Phase 2, Phase 3 | parallel | disjoint Owns, no hot files |
| 3 | Phase 4 | serial | Integration — nav + docs |

---

## Phase 1: {Phase Name}

**After:** None
**Owns:** `{glob}`, `{glob}`

{All tickets for Phase 1}

---

## Phase 2: {Phase Name}

**After:** Phase 1
**Owns:** `{glob}`, `{glob}`

{All tickets for Phase 2}

---

{Continue for all phases}

---

## Appendix: Quick Reference

### All Tickets by Type

**Migrations:**
- TICKET-1-01: {title}
- ...

**Models:**
- TICKET-1-02: {title}
- ...

{Continue for all types}

### Execution Checklist

- [ ] TICKET-1-01: {title}
- [ ] TICKET-1-02: {title}
- ...
```

## Phase 4: Validation

Before finalizing, validate:

1. **Completeness**: Every file in the plan is covered by a ticket
2. **Dependencies**: No circular dependencies exist
3. **Testability**: Every ticket has clear acceptance criteria
4. **Executability**: Each ticket can be independently completed by Claude Code
5. **Contract check** (when the plan carries `AC-n` IDs): build two lists —
   - **ACs with no ticket** — add each to the ticket that implements its plan step (create a
     ticket if no step covers it and say so)
   - **tickets with no AC** — tag `infra` with a justification, or drop the ticket if nothing
     in the plan needs it
   Print both lists (after fixing, ideally both "None") in the tickets document's Summary
   under `**Contract check**: ACs without a ticket: … • Tickets without an AC: …`, and repeat
   them in your closing message.
6. **Schedule check** — for every wave in `## Phase Schedule`:
   - every file in a phase's tickets is covered by that phase's `Owns:`
   - in a `parallel` wave, no file matches two phases' `Owns:`, and no phase owns a hot file
   - every `After:` phase sits in an earlier wave, and every ticket dependency points to the
     same phase or to a phase in an earlier wave
   On a violation, move the offending ticket to the Foundation or Integration phase, or make the
   wave serial — never leave it. Correctness beats width. State the result in one line in your
   closing message: `Schedule: <n> waves, max width <k>`.

## Important Instructions

- **Read the entire plan carefully** - don't miss any files or specifications
- **Preserve technical details** - include schemas, code examples, and patterns from the plan
- **Make tickets atomic** - each should be completable in one session
- **Include context** - each ticket should be understandable without reading other tickets
- **Prioritize correctly** - migrations and foundational work is P0, features are P1-P2
- **Estimate realistically** - consider Rails conventions and project patterns

## Example Ticket

```markdown
---

### TICKET-1-03: InsurancePolicy Model

**Phase:** Phase 1 - Foundation
**Type:** model
**Priority:** P0-Critical
**Complexity:** M
**Dependencies:** TICKET-1-01 (create_insurance_policies migration)

#### Description
Create the InsurancePolicy model to store client insurance card information. This model represents the core data structure for tracking client insurance coverage, including payer relationships, subscriber info, and card images.

#### Files to Create
- `app/models/insurance_policy.rb` - Main model with validations and associations
- `spec/models/insurance_policy_spec.rb` - Model specs
- `spec/factories/insurance_policies.rb` - FactoryBot factory

#### Files to Modify
- `app/models/client.rb` - Add `has_many :insurance_policies` association

#### Implementation Details
- Use UUID primary key (matches project convention)
- Include `acts_as_tenant(:organization)` for multi-tenancy
- Include `SoftDeletable` concern for soft delete
- Encrypt `subscriber_id` and `group_number` using Rails 7+ encryption
- Status enum: `active`, `inactive`, `terminated`
- Relationship order enum: `primary`, `secondary`, `tertiary`

Schema from migration:
```ruby
create_table :insurance_policies, id: :uuid do |t|
  t.references :organization, null: false, foreign_key: true, type: :uuid
  t.references :client, null: false, foreign_key: true, type: :uuid
  t.references :payer, null: false, foreign_key: true, type: :uuid
  t.string :subscriber_id, null: false
  t.string :group_number
  t.string :subscriber_name
  t.date :subscriber_dob
  t.string :relationship_to_subscriber
  t.integer :relationship_order, default: 0, null: false
  t.date :effective_date
  t.date :termination_date
  t.integer :status, default: 0, null: false
  t.datetime :deleted_at
  t.timestamps
end
```

#### Acceptance Criteria
- [ ] Model has all validations (subscriber_id presence, payer presence)
- [ ] Multi-tenancy works correctly with `acts_as_tenant`
- [ ] Encrypted fields are not readable in plain text
- [ ] `client.primary_insurance` returns the primary active policy
- [ ] Soft delete works correctly
- [ ] Factory creates valid records
- [ ] Tests pass: `bundle exec rspec spec/models/insurance_policy_spec.rb`

#### Testing Requirements
- Unit test: `spec/models/insurance_policy_spec.rb`
- Factory: `spec/factories/insurance_policies.rb`

---
```

Begin by reading and analyzing the implementation plan file.
