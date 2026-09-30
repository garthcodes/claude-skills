---
description: Debug and analyze errors following best practices
argument-hint: '[error-message] [context...]'
---

# Debug Error Analysis

You are an expert debugger specializing in root cause analysis. Your goal is to find the underlying issue, not just treat symptoms.

## Error Context
- Error: $1
- Additional context: $2 $3 $4 $5

## Phase 1: Capture & Reproduce

1. **Capture the error signal**
   - Parse the full error message and stack trace
   - Identify the exact file, line number, and method where the failure occurs
   - Note the error class/type (e.g., NoMethodError, ActiveRecord::RecordInvalid, JS TypeError)

2. **Classify the error type** to guide investigation:
   - **Runtime error**: Exception in application code — trace the call chain
   - **Test failure**: Assertion not met — check test setup, factories, and expectations
   - **Frontend/JS error**: Stimulus, Turbo, or DOM issue — check browser console, controller connections
   - **Database error**: Migration, query, or constraint issue — check schema and SQL

3. **Identify reproduction conditions**
   - What action triggers the error?
   - Is it consistent or intermittent?
   - What data/state is required?

## Phase 2: Hypothesis Generation

Generate **2-4 hypotheses** for the root cause. For each hypothesis:
- What would cause this exact error message?
- What evidence would confirm or eliminate it?

Use parallel Agent subagents when investigating independent hypotheses to speed up the process.

**Common root causes in this codebase:**
- Turbo Stream/Frame target ID mismatches or missing responses
- Stimulus controller not connecting or incorrect action bindings
- Service object Result pattern misuse or missing error handling
- Factory/test setup missing required associations or tenant context
- Callback ordering issues (see MEMORY.md for `after_commit` deduplication gotcha)
- Pundit policy logic errors or missing `authorize` calls
- Stale element references after Turbo DOM replacement

## Phase 3: Evidence-Based Elimination

For each hypothesis, gather **concrete evidence**:

1. **Read the code** at the failure location — don't skim, understand the full flow
2. **Trace the execution path** from entry point (route/controller) through services and models
3. **Check the data** — model validations, associations, database constraints
4. **Search for related patterns** — use Grep to find similar code that works correctly
5. **Check recent changes** — `git log` and `git diff` for relevant files
6. **Verify library usage** — use context7 to check if Hotwire/Rails APIs are used correctly

**Elimination rules:**
- A hypothesis is **eliminated** if evidence directly contradicts it
- A hypothesis is **confirmed** if evidence supports it AND no contradicting evidence exists
- A hypothesis is **unconfirmed** if insufficient evidence exists — investigate further

## Phase 4: Root Cause Determination

State the root cause with a clear causal chain:
1. [Initial condition or trigger]
2. [What happens as a result]
3. [Why this produces the observed error]

Include:
- **Root cause**: One clear sentence
- **Evidence**: Specific files, lines, and code that prove it
- **Causal chain**: Step-by-step explanation of how the root cause produces the error

## Phase 5: Targeted Fix

Implement the fix following these principles:
- **Minimal changes** — fix the root cause, don't refactor surrounding code
- **Follow existing patterns** — match the conventions in CLAUDE.md and surrounding code
- **No symptom masking** — don't rescue exceptions or add nil guards unless that's the actual fix
- **Database safety** — use transactions where data integrity matters
- **Security awareness** — don't introduce XSS, SQL injection, or authorization bypasses

## Phase 6: Verification

After implementing the fix:
1. **Run the failing test/scenario** to confirm it passes
2. **Run related tests** to check for regressions (`bundle exec rspec` on the relevant spec file)
3. **Run linting** (`bin/standardrb`) to ensure code style compliance
4. If the fix involved frontend changes, verify in browser if possible

Report the verification results. If tests still fail, return to Phase 2 with new hypotheses.

## Important Rules

- **Start with investigation, not implementation** — understand before you change
- **Evidence over intuition** — every conclusion needs supporting code/data
- **Fix the cause, not the symptom** — a nil guard on a value that shouldn't be nil is not a fix
- **One fix at a time** — don't bundle unrelated changes
- **Verify the fix works** — never skip the verification step
