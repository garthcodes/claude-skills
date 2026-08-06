---
description: Execute implementation plans efficiently using specialized agents for rapid development
argument-hint: [tickets-fixplan-or-plan-file, or latest]
---

# Implementation Execution

Execute the work document "${1:latest}" to completion: implement every item, keep tests green
as you go, and report honestly what was done, skipped, and failed. This skill implements — it
does NOT commit, push, open PRs, or run QA. Callers own those steps.

## Phase 1: Resolve the Work Document

If "${1}" is a path, read that file. If it's empty or "latest", take the newest of:

```bash
ls -t .claude/tickets-*.md .claude/fix-plans/fix-plan-*.md .claude/implementation-plan-*.md 2>/dev/null | head -1
```

Three document shapes, one execution model:

- **Tickets doc** (`.claude/tickets-*.md` from /tickets): work items are `TICKET-N-NN` entries
  with Type, Priority, Dependencies, Files, Implementation Details, Acceptance Criteria.
- **Fix plan** (`.claude/fix-plans/fix-plan-*.md` from /review-fixes): work items are
  `TICKET-NN` entries grouped P0–P3, each with Root Cause, Fix Approach, Test Plan, Blast
  Radius, Dependencies. Also read **Feature Context** and **acceptance-critical invariants**
  at the top — fixes must not break those. Honor any priority scope the caller set (e.g.
  "P0–P2 only; defer P3").
- **Implementation plan** (`.claude/implementation-plan-*.md` from /plan): work items are the
  numbered entries under **Implementation Steps**; the rest of the plan is their context.

Extract every work item with its dependencies and priority. Announce the doc and item count in
one line.

**Constraint check:** if the doc or the invoking context excludes system tests (the
`/build-feature` pipeline always does), do NOT create files under `spec/system/` or
`spec/features/` — skip any item that only creates those, and strip system-test files from
mixed items.

## Phase 2: Execute

### Ordering

Topologically sort by declared dependencies, then priority (P0 first), then document order.
Never start an item before its dependencies are complete.

### Direct vs. delegated

- **Execute directly** (yourself, in sequence): migrations, small items (S complexity or
  single-file), items on shared hot files (`config/routes.rb`, `db/`, existing models), and
  any chain of dependent items.
- **Delegate to parallel agents** only when 2+ items are genuinely independent — disjoint
  files, no dependency edges between them. Cap at 3 concurrent. Each agent's prompt must
  contain the **full ticket text verbatim** plus: the feature summary, the precedent files to
  pattern-match, and the no-system-tests constraint. Agents implement and run their item's
  specs; you verify their report before marking the item done.

When in doubt, execute directly — coordination overhead and merge conflicts on shared files
cost more than parallelism saves.

### Per-item loop

1. Read the item's context (Implementation Details / Fix Approach, referenced files)
2. Implement, following CLAUDE.md conventions:
   - Existing ViewComponents for every UI element (Button, FormInput, DataTable, Modal,
     Filter* family, etc.) — never raw HTML for component-covered elements; thin views
   - Services: VerbNounService, Result objects, exception-specific rescues with
     `Honeybadger.notify` context
   - Pundit policy per controller; role checks only (no org checks — acts_as_tenant)
   - Migrations: `bin/rails generate migration`, then `bin/rails db:migrate` immediately;
     never touch `db/schema.rb` by hand
   - SoftDeletable models: `#soft_delete`, never `destroy`/`delete_all` expecting hard-delete
3. Write the item's specs (model/service/controller/component/policy — per its Testing
   Requirements)
4. Run **that item's specs only**: `bundle exec rspec <spec files>` — not the whole suite
5. Mark the item's checkbox/status in the work document so progress survives compaction

### Failure handling

An item that fails (specs won't pass, approach doesn't work) gets **2 attempts**. After that:
revert its broken changes if they'd break other items, mark it SKIPPED in the work document
with a one-line reason, and continue. Never let one item stall the run, and never leave the
codebase in a state where other items' specs fail because of a half-done item.

## Phase 3: Validate

After all items:

```bash
bin/standardrb --fix          # then fix anything it can't auto-fix
bundle exec rspec              # full suite
```

Fix failures you introduced (max 3 cycles). Pre-existing failures on files you didn't touch:
note them, don't chase them. (`bin/ci` is the caller's final gate — don't run it here.)

## Phase 4: Report

End with a compact summary:

```
Implementation complete: <doc path>

Completed: X/Y items
Skipped:   [item: reason, ...]  (or "none")
Failed:    [item: reason, ...]  (or "none")
Tests:     <rspec result>  Lint: <standardrb result>
Files:     <count> created, <count> modified
Notes:     <deviations from the doc, decisions made, anything the caller must know>
```

## Principles

1. **The document is the contract.** Implement what it says. If an item is wrong or impossible
   as written, do the closest correct thing and record the deviation in the report — don't
   silently redesign.
2. **Small verified steps.** Run each item's specs when it's done, not everything at the end.
   A failure found immediately is cheap; the same failure found 20 items later is not.
3. **Reuse over invention.** The plan/tickets already chose components and patterns; don't
   substitute your own.
4. **No scope creep.** No refactoring beyond the items, no extra features, no documentation
   files nobody asked for.
5. **Report faithfully.** Skipped is skipped, failed is failed. A false "complete" costs more
   downstream (review, QA) than an honest gap.

Begin by resolving the work document.
