---
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
4. If the plan lists Success Criteria traced from a PRD, distribute them: each criterion
   should appear as an acceptance criterion on the ticket that implements it, so nothing is
   verified only "at the end".

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

## Dependency Graph

{ASCII diagram showing ticket dependencies}

## Execution Order

{Recommended order to execute tickets, grouped by what can be parallelized}

---

## Phase 1: {Phase Name}

{All tickets for Phase 1}

---

## Phase 2: {Phase Name}

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
