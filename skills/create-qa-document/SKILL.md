---
description: Generate a QA plan document from branch changes, a feature description, or a feature-and-role pair for deep per-role QA (used by /full-qa)
argument-hint: [feature-description-or-blank-for-current-branch] [--role=ROLE] [--full-feature]
---

# Create QA Document Command

You are tasked with analyzing code changes and creating a comprehensive QA test plan document. This document will be consumed by the `/execute-qa` command which will run each scenario with Playwright and produce bug reports compatible with `/bug-hunt-fix`.

## Input

$ARGUMENTS

**Three input modes:**

1. **Branch-diff mode (default, EXISTING behavior, unchanged)** — no argument provided. Analyze the current branch's changes compared to `main`.

2. **Feature-description mode (EXISTING behavior, unchanged)** — free-text feature description provided. Treat as a feature description and search the codebase for relevant code.

3. **Full-feature mode (EXT-1, NEW)** — argument matches the pattern `<feature-name> --role=ROLE` or `<feature-name> --full-feature [--role=ROLE]`. The feature name should map to a section title in `docs/APP_FEATURES.md`. This mode is intended for the `/full-qa` orchestrator. When in this mode:
   - **Skip Phase 1 (Step 1 git diff)** — there's no diff to analyze. Jump straight to feature-driven discovery.
   - **Run Phase 1b (Deep Source Code Reading)** below — mandatory.
   - **If `--role=ROLE` is present**, scope all scenarios to that single role and include both positive (with-permission) and negative (without-permission, where someone else holds permission) variants per action.
   - **If `--role=ROLE` is absent**, enumerate all roles with access (derive from Pundit policies — see Phase 1b).
   - Valid roles: `admin`, `therapist`, `supervisor`, `clinical_supervisor`, `coordinator`, `client` (client portal).

**Optional flag (any mode): `--base-url=URL`** — overrides the default test base URL
(`http://localhost:3000`, your app's dev URL). Used by `/build-feature`, which runs QA against
a worktree server on the worktree's own port (`PORT=` in its `.env`). Write the given URL into the document's `**Base URL:**` field —
`/execute-qa` reads it from there. Do not reference any other port anywhere in the document.

**Parse `--role=`, `--full-feature`, and `--base-url=` from `$ARGUMENTS` first**, then treat the remaining text as the feature description / name.

**PRD awareness (all modes):** If a PRD exists for the feature under `.claude/prds/` (check for
one matching the branch/feature name, or referenced in commit messages), read it. Its
**Acceptance Criteria** table (`| ID | Criterion | FR | Priority | Verified by |`, rows
`AC-1`, `AC-2`, …) is the agreed contract the PR is gated on:

- **Every AC whose `Verified by` is `browser` or `browser+spec` MUST map to at least one
  scenario.** Design the scenario's steps and expected results so that the AC's *Then* clause
  is asserted literally (same values, same visible text).
- Tag each scenario with the ACs it proves via a `**Verifies:**` line (see the template). A
  scenario may verify several ACs; an AC may need several scenarios (e.g. one per role).
- Finish the document with an **AC Coverage** table (see the template) listing every browser
  AC and the scenarios that cover it. If any browser AC has no scenario, list it under
  **Uncovered** with a reason — never silently omit it; `/verify-acceptance` will mark it
  UNVERIFIED and `/build-feature` will not open a PR on an unverified Must AC.
- `spec`-only and `manual` ACs are not yours to cover; leave them out of the coverage table.

If the PRD predates the AC table (no `## Acceptance Criteria` section), fall back to its
**Definition of Done** and per-FR **acceptance criteria** column as before — ensure every
Definition of Done item and every Must-Have FR's acceptance criteria map to at least one
scenario — and omit the AC Coverage table. In all cases use its **Edge Cases & Policies**
table as a source of edge-case scenarios with pre-decided expected behavior.

## Phase 1: Understand What Changed

### Step 1: Identify Changes

**If analyzing a branch:**
```bash
# Get branch name
git branch --show-current

# Get all changed files vs main
git diff main...HEAD --name-only

# Get full diff for understanding changes
git diff main...HEAD --stat

# Get commit messages for context
git log main..HEAD --oneline
```

Read the full diff to understand what changed:
```bash
git diff main...HEAD
```

**If analyzing a feature description:**
- Search routes, controllers, views, models, and services related to the described feature
- Use `Grep` and `Glob` to find all relevant files
- Read each file to understand the feature's implementation

### Step 2: Categorize Changes

Organize what you found into categories:
- **New routes/endpoints** added
- **Modified controllers** and their actions
- **New or changed views/partials**
- **Model changes** (new fields, validations, associations)
- **Service objects** (new or modified business logic)
- **Stimulus controllers** (new or modified JavaScript behavior)
- **ViewComponents** (new or modified UI components)
- **Database migrations** (schema changes)
- **Background jobs** (new or modified)
- **Configuration changes**

### Step 3: Identify User-Facing Flows

From the code changes, determine:
1. Which user roles are affected (Admin, Therapist, Coordinator, Client, etc.)
2. Which pages/screens are affected
3. What actions users can take on those pages
4. What data is displayed and how it's sourced
5. What validations and error states exist
6. How Turbo Frames/Streams update the page dynamically

## Phase 1b: Deep Source Code Reading (EXT-6, MANDATORY in full-feature mode)

When in full-feature mode (argument matches a feature section + `--role=` or `--full-feature`), perform exhaustive source-code reading **before** scenario design. The goal is to derive every interactive element and every authorization boundary directly from the code, not just from the markdown description.

### Step 1b.1: Locate the feature section in `docs/APP_FEATURES.md`

Read the matching section verbatim. Treat it as a **starting point**, not the source of truth — `APP_FEATURES.md` may be incomplete or stale.

### Step 1b.2: Derive the feature's route surface

```bash
# Find route blocks for the feature's primary resources
grep -nE "resources :<resource>|namespace :<namespace>" config/routes.rb
```

For each route, identify:
- HTTP verb + path + controller#action
- Whether it's in a namespace (`/admin/...`, `/staff/...`, `/client-portal/...`)
- Whether it's a member action (`/clients/:id/foo`) or collection action (`/clients/foo`)

### Step 1b.3: Read every controller in the feature's surface

For each controller action:
- Read the action body — what params does it require? What service does it call? What does it render or redirect to?
- Read `before_action :authorize_xxx` / `authorize @record` calls — which policy method is checked?
- Read strong params — which fields are user-editable?

### Step 1b.4: Read the corresponding Pundit policies

For each policy file (`app/policies/*_policy.rb`):
- Extract role checks via grep: `has_role?(:foo)`, `has_any_role?(:a, :b)`, `user.has_role?(:bar)`
- List each action method (`index?`, `show?`, `create?`, `update?`, `destroy?`, custom methods) and the set of roles each grants
- Union across actions = **the set of roles with feature access** (use this for role enumeration when `--role=` is not given)
- Note `Scope` class behavior — different roles often see different subsets

### Step 1b.5: Read views and ViewComponents

For each view file (`app/views/<controller_path>/*.html.erb`) and ViewComponent (`app/components/**/*.rb` + matching `.html.erb`):
- Enumerate every `link_to`, `button_to`, `<button>`, `<a>`, form submission, Turbo Frame target (`turbo_frame_tag`), Turbo Stream action, modal trigger, dropdown action — **each is a candidate scenario**
- Note empty states, loading states, error states — **each is a candidate scenario**
- Note inline role checks (`<% if current_user.has_role?(:admin) %>`) — these gate UI elements and need their own permission-negative scenarios

### Step 1b.6: Read models touched by the feature

- Validations — drive validation-negative scenarios
- Scopes — drive listing/filtering scenarios
- `SoftDeletable` inclusion — drive soft-delete safety scenarios (record absent from listings after delete, present in DB)
- HIPAA-loggable inclusion (`HipaaLoggable`) — drive audit-log verification scenarios

### Step 1b.7: Read seeds for accurate test users (CRITICAL — do not trust the table below)

**Read `db/seeds/users.rb` directly** to determine which seeded users exist for the feature's required roles. Hardcoded user lists in this skill or elsewhere may be stale. The current accurate seeds are documented in Phase 2 Step 4 below, but **always cross-check with `db/seeds/users.rb` at runtime**.

For client-portal scenarios, also read `db/seeds/form_assignments_with_receipts.rb` to find the seeded `TEST_CLIENT_EMAIL` constant and the seeded client's DOB (typically `30.years.ago`).

## Phase 2: Map Seed Data

### Step 4: Identify Available Seed Data

Check which seed data is relevant to the feature being tested. **Always cross-check this table against `db/seeds/users.rb` and `db/seeds/form_assignments_with_receipts.rb` at runtime — these are the source of truth.**

**Test Users (from `db/seeds/users.rb`):**
| Role | Email | Notes |
|------|-------|-------|
| Admin | `admin@example.com` | Simple test user |
| Therapist | `therapist@example.com` | Simple test user |
| Coordinator | `coordinator@example.com` | Simple test user |

**Named Staff (default organization, from `db/seeds/users.rb`):**
| Name | Email | Role(s) |
|------|-------|---------|
| Admin Two | `admin2@example.com` | admin |
| Coordinator Two | `coordinator2@example.com` | coordinator |
| Coordinator Three | `coordinator3@example.com` | coordinator |
| Supervisor One | `supervisor1@example.com` | supervisor, therapist |
| Supervisor Two | `supervisor2@example.com` | supervisor, therapist |
| Manager One | `manager@example.com` | manager |

**Role gotchas:**
- `clinical_supervisor` has **no dedicated seed user** — the role is granted to one of the supervisor users via `db/seeds/supervision_relationships.rb`. For QA needing this role, use `supervisor1@example.com` and verify the role assignment at runtime.
- Do not assume a role-named email exists just because the role does — some role-named emails may be absent from the current seeds despite older guidance to the contrary. Verify against `db/seeds/users.rb` before writing an email into a scenario.

**Client portal test client (from `db/seeds/form_assignments_with_receipts.rb`):**
| Identifier | Value |
|------------|-------|
| Email | `testclient@example.com` |
| DOB | `30.years.ago` from the time seeds were run |
| Portal token | Discover at runtime via `FormAssignment.with_valid_token.first.access_token` |

**Seed Data Available:**
- 625 clients across AZ and CO
- ~3,750 appointments (4 weeks past, 2 weeks future)
- Clinical documents (progress notes, treatment plans, MSE, BPS)
- Insurance policies and payers
- Invoices and payment methods
- Insurance claims (submitted, paid, denied, pending)
- 80+ DSM-5-TR diagnoses
- Form templates and assignments
- Supervision relationships
- Payroll data (Bruna Casper test scenario)
- Stedi test clients (John Doe, Jordan Doe, Bernie Prohas)

### Step 5: Determine Data Gaps

For each test scenario, determine if:
1. **Seed data is sufficient** - note which specific records to use
2. **Rails console scripts are needed** - write scripts to create missing test data
3. **UI setup is needed** - note manual steps to set up preconditions through the app

## Phase 3: Create Test Scenarios

### Step 6: Design Scenarios

For each user-facing flow identified, create test scenarios covering:

1. **Happy Path** - The primary expected workflow with valid data
2. **Validation/Error Cases** - Invalid inputs, missing required fields
3. **Authorization** - Correct role has access, wrong roles are blocked
4. **Edge Cases** - Empty states, maximum data, special characters
5. **Navigation** - Links, breadcrumbs, back button behavior
6. **Turbo/Dynamic Updates** - Turbo Frames load correctly, Turbo Streams update properly
7. **Visual/Responsive** - Layout is correct at the target viewport
8. **Data Integrity** - Saved data is correct, displayed data matches database

### Step 6.1: Exhaustive Button/Journey Coverage (EXT-2, MANDATORY in full-feature mode)

When in full-feature mode, surface-level scenarios are not enough. Use the enumeration from Phase 1b Step 1b.5 (every `link_to`, `button_to`, form submission, Turbo Frame target, modal trigger, dropdown action, empty/loading/error state). **Every one of these is a candidate scenario**. Group them logically (one Scenario Group per page/flow), but do not skip any interactive element.

Practical rule: if a user can click it, tap it, type in it, or wait for it to render, it gets at least one scenario.

### Step 6.2: Role-Aware Scenarios (EXT-3, MANDATORY in full-feature mode)

**If `--role=ROLE` was provided** in `$ARGUMENTS`:
- Emit scenarios only for that role (label `User Role:` accordingly).
- For each user-facing action, generate **two** scenarios:
  - **Positive**: user with the required permission performs the action and succeeds.
  - **Permission-Negative**: a different role (one that lacks permission, but exists in seeds) attempts the same action via direct URL — expect 403 or redirect with flash. (This catches authorization regressions where a UI hides a button but the endpoint is still callable.)

**If `--role=` was not provided** in full-feature mode:
- Enumerate the role set derived from Phase 1b Step 1b.4. For each role, generate that role's scenarios. Clearly label `User Role:` per scenario so `/execute-qa` logs in as the right user.

### Step 6.3: Negative Tests (EXT-4, MANDATORY in full-feature mode)

For each Scenario Group, include the three negative-test types as named, dedicated scenarios:

**Permission Negative**
```
#### SC-NNN: [Action] — Permission Denied

**Priority:** High
**User Role:** [role without permission, e.g., therapist@example.com when action is admin-only]
**Viewport:** [match feature's viewport]
**Preconditions:**
- Target record exists (reference the seeded record)

**Steps:**
1. Authenticate as `[role without permission]`
2. Navigate directly to the action URL (do not rely on the UI)
3. Attempt the action

**Expected Results:**
- [ ] HTTP 403 OR redirect to root/dashboard with flash alert
- [ ] No data modified
- [ ] Honeybadger / audit log records the attempt if applicable
```

**Validation Negative**
For each form, generate scenarios that submit:
- Required field empty
- Invalid format (bad email, bad date, bad phone)
- Max-length exceeded (text fields)
- Numeric out of range (rates, amounts)
- For each: expect the form to re-render with the error message visible.

**Edge Case Negative**
- Access a deleted (soft-deleted) record — expect "not found" or graceful handling.
- Resume an expired session — expect redirect to sign-in.
- Trigger a Turbo Stream update on a record another user just deleted — expect graceful degradation.

### Step 6.4: HIPAA & Compliance Scenarios (EXT-5, MANDATORY in full-feature mode for any feature that touches PHI)

If the feature touches PHI (clients, charts, clinical documents, billing tied to a client, messages, video meetings, treatment plans, etc.), include a dedicated `## HIPAA & Compliance` Scenario Group with **at minimum** the five scenarios below. **Scenario IDs continue the SC-NNN sequence — the `HIPAA & Compliance` group heading is what conveys the HIPAA categorization; `/execute-qa` parses SC-NNN as the scenario identifier.**

**SC-NNN: Audit Log Verify**
```
**Priority:** Critical
**User Role:** [appropriate role]
**Steps:**
1. Authenticate as `[appropriate role]`
2. Perform an action that touches PHI (view chart, edit demographics, sign a document)
3. Note the timestamp of the action

**Expected Results:**
- [ ] A `HipaaAuditLog` row exists for the actor, action_type, and target within the timestamp window
  (verify via `bin/rails runner "puts HipaaAuditLog.order(created_at: :desc).first.attributes"` if needed)
- [ ] The audit row records the correct user, organization, target resource, and action
```

**SC-NNN: PHI Exposure Scan**
```
**Priority:** Critical
**User Role:** [appropriate role]
**Steps:**
1. Authenticate as `[appropriate role]`
2. Navigate through the feature's primary pages
3. For each page, inspect: URL path, document.title, any visible error message, browser console output (Playwright `console_messages`)

**Expected Results:**
- [ ] No client first/last name, DOB, SSN, diagnosis code, or clinical note content appears in any URL
- [ ] No PHI in document titles
- [ ] No PHI in error messages or flash alerts (e.g., "Client #abc123 not found" is OK; "Client Jane Doe DOB 01/02/1990 not found" is a bug)
- [ ] No PHI in console logs or `console.error` output
```

**SC-NNN: Soft-Delete Safety**
```
**Priority:** High
**User Role:** [role with delete permission]
**Steps:**
1. Authenticate as `[role with delete permission]`
2. Soft-delete a record (use the feature's UI delete action)
3. Verify the record disappears from listings/search
4. Verify the record is still present in DB via `Model.including_deleted.find(id)`

**Expected Results:**
- [ ] Record absent from default listing
- [ ] Record absent from search
- [ ] Record absent from count metrics
- [ ] Record present in `Model.including_deleted` and `Model.deleted` scopes
- [ ] Record data unchanged in DB (only `deleted_at` set)
```

**SC-NNN: Role-Permission Negative (Direct URL)**
```
**Priority:** Critical
**User Role:** [lower-privilege role, e.g., therapist when feature is admin-only]
**Steps:**
1. Authenticate as `[lower-privilege role]`
2. Attempt to access the feature's URL directly (do not use UI)

**Expected Results:**
- [ ] HTTP 403 OR redirect with denial flash
- [ ] No PHI exposed in the denial response
```

**SC-NNN: Log-Filter Verify**
```
**Priority:** High
**User Role:** [any role that submits PHI]
**Steps:**
1. Tail `log/development.log` in a terminal: `tail -F log/development.log`
2. Authenticate and perform a typical action involving PHI submission (e.g., update client demographics)
3. Inspect the log output

**Expected Results:**
- [ ] PHI parameters (SSN, date_of_birth, phone, clinical notes) appear as `[FILTERED]` in the request log
- [ ] No raw PHI values in the log line
```

**Numbering note:** When emitting these scenarios into the final document, assign sequential SC-NNN values continuing from the last scenario in the prior group (e.g., if the previous group ended at SC-014, these become SC-015 through SC-019).

### Step 7: Determine Viewport per Scenario

| Area | Target Viewport | Notes |
|------|----------------|-------|
| Staff EHR (`/staff/*`) | 1280x800 | Desktop only |
| Admin (`/admin/*`) | 1280x800 | Desktop only |
| Client Portal | 375x667 (primary), 768x1024 (secondary) | Mobile-first |

## Phase 4: Write the QA Document

### Step 8: Generate the Document

Create the QA document at:

- **Default / feature-description modes:** `docs/qa-plans/{feature-name}-{YYYYMMDD}.md`
- **Full-feature mode with `--role=<role>`:** `docs/qa-plans/{feature-name}-{role}-{YYYYMMDD}.md`
  (Role is inserted before the date so that multiple per-role plans for the same feature on the same day do not overwrite each other. This is critical when the `/full-qa` orchestrator generates one plan per accessible role.)
- **Full-feature mode without `--role=`:** `docs/qa-plans/{feature-name}-{YYYYMMDD}.md` (single plan covers all roles, same as default).

Use the following template structure:

```markdown
# QA Plan: [Feature Name]

**Branch:** [branch-name or "N/A"]
**Date Created:** [YYYY-MM-DD]
**Created By:** Claude Code (Automated)
**Status:** PENDING

---

## Overview

[2-3 sentence summary of what this feature does and what the code changes include]

### Files Changed
- `path/to/file1.rb` - [Brief description of change]
- `path/to/file2.html.erb` - [Brief description of change]

### Key Routes
| Method | Path | Controller#Action | Description |
|--------|------|-------------------|-------------|
| GET | /staff/example | staff/examples#index | List page |
| POST | /staff/example | staff/examples#create | Create action |

---

## Test Environment

**Base URL:** [http://localhost:3000, or the --base-url value if provided]
**Organization:** Default tenant (subdomain: your-org)

### Setup Scripts

> Run these in Rails console (`bin/rails console`) before testing if seed data is insufficient.

```ruby
# Script 1: [Description of what this creates]
# [Ruby code to create necessary test data]

# Script 2: [Description]
# [Ruby code]
```

### Seed Data Reference

[List specific seed records relevant to this feature with identifiers]

---

## Test Scenarios

### Scenario Group: [Group Name, e.g., "Client List Page"]

#### SC-001: [Descriptive scenario title]

**Priority:** Critical | High | Medium | Low
**Verifies:** AC-1, AC-3 | — (no PRD acceptance criterion; e.g. HIPAA group scenarios)
**User Role:** [admin@example.com / therapist@example.com / etc.]
**Viewport:** [1280x800 / 375x667]
**Preconditions:**
- [Any required setup or state]
- [Seed data reference if applicable]

**Steps:**
1. Authenticate as `[email]`
2. Navigate to [area] via [specific UI path: sidebar > link > button]
3. [Specific action to take]
4. [Next action]

**Expected Results:**
- [ ] [Specific expected outcome 1]
- [ ] [Specific expected outcome 2]
- [ ] No console errors
- [ ] No network errors

**Setup Script (if needed):**
```ruby
# Run in rails console before this scenario
```

---

#### SC-002: [Next scenario]
...

---

## AC Coverage

[Only when the PRD has an Acceptance Criteria table. One row per AC with `Verified by`
`browser` or `browser+spec`.]

| AC | Priority | Scenarios |
|----|----------|-----------|
| AC-1 | Must | SC-001, SC-004 |
| AC-3 | Must | SC-002 |

**Uncovered:** [AC IDs with a one-line reason each, or "None"]

---

### Scenario Group: [Next Group]
...

---

## Authorization Matrix

| Action | Admin | Therapist | Coordinator | Manager | Client |
|--------|-------|-----------|-------------|---------|--------|
| [Action 1] | ✅ | ✅ | ❌ | ✅ | ❌ |
| [Action 2] | ✅ | ❌ | ❌ | ❌ | ❌ |

---

## Edge Cases & Negative Tests

### EC-001: [Edge case title]
**Steps:** [How to trigger]
**Expected:** [What should happen]

---

## Cleanup Scripts

> Run these after testing to reset any changes made during QA.

```ruby
# Cleanup script
```

---

## Notes

[Any additional context, known limitations, or areas of concern]
```

## Important Guidelines

1. **Be specific in steps** - Write steps that can be executed by Playwright automation. Include exact UI paths (e.g., "Click 'Clients' in the left sidebar, then click on client 'John Smith'").
2. **Reference real seed data** - Use actual client names, email addresses, and records from the seeds when possible.
3. **Include setup scripts** - If a scenario needs data that doesn't exist in seeds, provide a Rails console script to create it.
4. **Cover authorization** - Always include scenarios testing that unauthorized roles are properly blocked.
5. **Think about Turbo** - If the feature uses Turbo Frames/Streams, include scenarios that specifically test dynamic updates.
6. **Number every scenario** - Use SC-001, SC-002, etc. for easy reference by execute-qa.
7. **Mark priorities** - Critical scenarios test core functionality, Low priority tests cover edge cases.
8. **Navigation paths must be explicit** - Don't say "go to the clients page." Say "Click 'Clients' in the left sidebar navigation."
9. **Include cleanup** - If scenarios modify data, provide cleanup scripts.
10. **One scenario per behavior** - Each SC-XXX should test one specific thing, making bug reports clear when they fail.
11. **Tag acceptance criteria** - Every scenario carries a `**Verifies:**` line (`AC-n, …` or `—`). `/verify-acceptance` joins `/execute-qa`'s PASS/FAIL results to the PRD contract through these tags; an untagged scenario proves nothing to the gate.

## Output

When complete:
1. Announce the QA document location
2. Summarize the number of scenarios by priority
3. When the PRD has an Acceptance Criteria table: `Acceptance criteria covered: X/Y browser
   ACs` and the uncovered IDs, if any
4. List any data gaps that require setup scripts
5. Note any areas that could not be fully covered and why

Begin by analyzing the changes and understanding the feature scope.

---

## EXT-7: Backwards Compatibility Statement

All extensions in this file (EXT-1 through EXT-6, plus EXT-7 itself) are **additive**. They do not change the existing output format or break existing consumers:

- **Output path — default / feature-description / full-feature without `--role=`**: `docs/qa-plans/{feature-name}-{YYYYMMDD}.md` (unchanged).
- **Output path — full-feature with `--role=<role>` (added in EXT-1)**: `docs/qa-plans/{feature-name}-{role}-{YYYYMMDD}.md`. The role segment is required to keep per-role plans from clobbering each other when `/full-qa` invokes this skill once per accessible role on the same day. This is a deliberate change from the original "path unchanged" guarantee, scoped narrowly to the `--role=` case.
- **`**Verifies:**` line and `## AC Coverage` table (added for `/verify-acceptance`)**: additive metadata. `/execute-qa` ignores both; plans for PRDs without an Acceptance Criteria table omit the coverage table and may use `—` on every scenario.
- **Scenario IDs unchanged**: `SC-001`, `SC-002`, etc. HIPAA scenarios from Step 6.4 also use SC-NNN — they are categorized by being placed in the `## HIPAA & Compliance` Scenario Group, NOT by a different ID prefix. `/execute-qa` parses SC-NNN as the scenario identifier and would not recognize a `HIPAA-NNN` prefix.
- **Setup Scripts section heading unchanged**: `### Setup Scripts`
- **Authorization Matrix retained**: still required, now derived from Phase 1b Step 1b.4 policy reading
- **`/execute-qa` input contract unmodified**: any plan produced by this skill — branch-diff mode, feature-description mode, or full-feature mode — is consumable by `/execute-qa` without changes.
- **Default mode behavior unchanged**: invoking with no arguments still produces a branch-diff QA plan exactly as before. New phases (Phase 1b) and new steps (Step 6.1 through Step 6.4) are MANDATORY only in full-feature mode; in default mode they are advisory.
