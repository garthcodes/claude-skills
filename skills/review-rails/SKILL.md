---
name: review-rails
description: Review the current branch for code quality, security, and Rails 8 conventions compliance
---

# review-rails

Review the current branch for code quality, security, and Rails 8 conventions compliance.

## Description

Comprehensive branch review that analyzes all code changes for security vulnerabilities, logic errors, data integrity risks, and compliance with the Rails 8 architectural patterns and conventions documented in CLAUDE.md. Generates a prioritized report with a merge verdict.

## Instructions

When invoked, you should:

1. **Get the current branch and changes**:

   ```bash
   # Get current branch name
   git branch --show-current

   # Get the base branch (default to main if not specified)
   BASE_BRANCH="${1:-main}"

   # Get list of changed files
   git diff --name-only $BASE_BRANCH...HEAD

   # Get full diff with context
   git diff $BASE_BRANCH...HEAD

   # Get commit history for context
   git log --oneline $BASE_BRANCH..HEAD
   ```

2. **Read and analyze changed files**:
   - Read each changed file in full (not just the diff)
   - Categorize by type (models, controllers, services, components, views, specs, migrations, etc.)

3. **Review for general code quality issues**:

   **Security (P3 - Critical)**:
   - SQL injection vulnerabilities
   - XSS vulnerabilities
   - Authentication/authorization bypasses
   - Sensitive data exposure
   - Command injection risks
   - Insecure dependencies

   **Data Integrity (P3 - Critical)**:
   - Missing database constraints
   - Dangerous migrations (data loss)
   - Missing validations for critical fields
   - Transaction safety issues

   **Logic & Correctness (P2 - High)**:
   - Incorrect conditionals or logic
   - Race conditions
   - Missing error handling
   - Edge cases not handled
   - N+1 query issues

   **Testing (P2/P1)**:
   - Missing tests for new functionality (P2)
   - Inadequate test coverage (P1)
   - Flaky test patterns (P1)

4. **Check against Rails 8 conventions**:

   **Service Objects** (`app/services/`):
   - Named with `VerbNounService` pattern
   - Uses `Result` object for success/failure handling
   - Accepts domain object in constructor
   - Handles errors within service, returns user-friendly messages
   - Has corresponding RSpec tests

   **ViewComponents** (`app/components/`):
   - Named with `*Component` suffix
   - Has paired `.rb` and `.html.erb` files
   - Inherits from `ApplicationComponent`
   - Has corresponding component tests
   - Uses Tailwind CSS only (no custom CSS except PDF templates)

   **Controllers** (`app/controllers/`):
   - RESTful and thin (logic delegated to services)
   - Uses `before_action :authenticate_user!`
   - Uses Pundit `authorize` calls and policy scopes
   - Uses strong parameters for all user input
   - Supports appropriate response formats (HTML/JSON/Turbo Stream)
   - Has controller specs or system tests

   **Models** (`app/models/`):
   - Uses UUID for primary keys (check migrations)
   - Has validations for all required fields
   - Uses ActiveRecord validations (not custom validation methods)
   - Uses scopes for complex queries
   - Uses enums for status/categorical fields
   - Has comprehensive model specs with FactoryBot

   **Migrations** (`db/migrate/`):
   - CLI-generated (not hand-written)
   - Uses UUID for primary keys (`id: :uuid`)
   - Has appropriate indexes for queried columns
   - Has database constraints in addition to model validations
   - Is reversible

   **JavaScript/Stimulus** (`app/javascript/controllers/`):
   - Stimulus controllers only (no jQuery)
   - ES6+ syntax
   - Uses data attributes for configuration
   - Follows 2-space indentation with semicolons
   - Uses `AbortController` for event listener cleanup (multiple listeners)

   **Tests** (`spec/`):
   - RSpec with FactoryBot
   - All ViewComponents have component tests
   - All services have service specs
   - Models have validation and relationship tests
   - Controllers have authorization tests
   - Request specs ONLY for JSON APIs and webhooks (not HTML actions)
   - System tests for HTML/Turbo Stream interactions
   - System tests follow non-flaky patterns (no stale elements, proper waits)

   **Code Style**:
   - Follows Standard Ruby style guide
   - 100 character line length maximum
   - 2-space indentation
   - Single quotes preferred
   - snake_case file naming

   **Performance**:
   - Proper indexing for queries
   - Eager loading to prevent N+1 queries
   - Background jobs for long-running tasks
   - Pagination for large collections (uses Pagy)

5. **Generate prioritized report**:

   Group issues by priority:

   **P3 - Critical** (must fix before merge):
   - Security vulnerabilities (SQL injection, XSS, command injection, auth bypasses)
   - Data loss risks
   - Breaking changes
   - Missing authorization checks
   - Dangerous migrations

   **P2 - High** (should fix before merge):
   - Logic errors and incorrect conditionals
   - Race conditions
   - Missing error handling
   - N+1 query problems
   - Missing tests for new functionality
   - Missing validations

   **P1 - Medium** (consider fixing):
   - Convention violations (naming, structure)
   - Missing indexes
   - Controllers too thick (not delegating to services)
   - Custom CSS (should use Tailwind)
   - Non-reversible migrations
   - Inadequate test coverage
   - Flaky test patterns (stale elements, missing waits)
   - Request specs for HTML actions (should be system tests)
   - Code duplication

   **P0 - Low** (optional improvements):
   - Code style improvements
   - Naming inconsistencies
   - Refactoring opportunities
   - Documentation suggestions
   - Minor performance optimizations

6. **Format the report**:

   ```markdown
   # Branch Review: [branch-name]

   **Base Branch:** main
   **Files Changed:** X
   **Commits:** Y
   **Review Date:** [date]

   ---

   ## P3 - Critical Issues (Must Fix)

   ### [Issue Title]
   **File:** `path/to/file.rb:LINE`
   **Category:** Security | Data Integrity | Breaking Change

   **Problem:**
   [Clear description of the issue]

   **Code:**
   ```ruby
   # Problematic code snippet
   ```

   **Recommendation:**
   ```ruby
   # Suggested fix
   ```

   ---

   ## P2 - High Priority Issues

   [Same format as P3]

   ---

   ## P1 - Medium Priority Issues

   [Same format as P3]

   ---

   ## P0 - Low Priority Issues

   [Same format as P3]

   ---

   ## Compliant Patterns

   [Highlight things done well to reinforce good patterns]

   ## Summary

   | Priority | Count | Status |
   |----------|-------|--------|
   | P3 Critical | X | Must fix before merge |
   | P2 High | X | Should fix before merge |
   | P1 Medium | X | Consider fixing |
   | P0 Low | X | Optional improvements |

   ### Verdict

   [READY FOR MERGE | NEEDS CHANGES | BLOCKED]

   [Brief explanation of overall assessment]

   ### Action Items

   1. [Prioritized list of fixes needed]
   2. ...
   ```

7. **Save the report**:

   Save the report to `.claude/reviews/` using the naming convention:
   ```
   .claude/reviews/branch-review-{branch-name}-{YYYYMMDD}.md
   ```
   - Create the `.claude/reviews/` directory if it doesn't exist
   - Sanitize branch name for filenames (replace `/` with `-`)
   - Overwrite if a review for the same branch and date already exists
   - Tell the user the file path after saving

## Known Patterns (Do NOT Flag as Issues)

These are intentional project patterns that should NOT be reported as bugs or security issues:

- **Pundit policies without organization checks**: `acts_as_tenant(:organization)` enforces tenant isolation at the database query layer. All queries are automatically scoped to the current tenant, making cross-tenant data access impossible. Pundit policies only need role-based checks (e.g., `user.has_any_role?(:admin, :coordinator)`). Do NOT flag missing `user.organization == record.organization` checks as a security issue — some older policies include this as a legacy pattern, but it is redundant and not required.

## Guidelines

- Focus on the conventions in CLAUDE.md as the source of truth
- Be specific with exact file paths and line numbers
- Provide actionable feedback with code examples for fixes
- Explain WHY each issue matters, not just what the issue is
- Reference CLAUDE.md sections and existing code when suggesting patterns
- Highlight patterns done well — be constructive, not just critical
- Consider the context — a small deviation might be intentional
- Check for common anti-patterns specific to this codebase
- Consider the bigger picture — how do changes fit with the rest of the codebase?

## Example Usage

```bash
/review-rails
/review-rails develop
```
