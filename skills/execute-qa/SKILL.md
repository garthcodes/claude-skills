---
description: Execute a QA plan document and report bugs using Playwright browser automation
argument-hint: <path-to-qa-plan.md>
---

# Execute QA Command

You are tasked with executing a QA test plan document created by `/create-qa-document`. You will run each scenario using Playwright MCP tools and create bug reports compatible with `/bug-hunt-fix` for any issues found. **You do NOT fix bugs - you only execute scenarios and report failures.**

## QA Plan to Execute
$ARGUMENTS

## Phase 1: Preparation

### Step 1: Read and Parse the QA Plan

Read the QA plan document and extract:
- **Feature name** and branch
- **All scenarios** (SC-001, SC-002, etc.) with their steps, expected results, and priorities
- **Setup scripts** that need to run before testing
- **User roles** needed for each scenario
- **Viewport requirements** for each scenario
- **Preconditions** for each scenario

### Step 2: Resolve Base URL and Ensure the Server is Running

**Read the `**Base URL:**` line from the QA plan's Test Environment section** — that is the
`BASE_URL` for the entire run (server check, authentication, all navigation). Fall back to
`http://localhost:3000` (your app's dev URL) only if the plan doesn't specify one. `/build-feature`
runs QA against a worktree server on a different port — never assume the default.

```bash
curl -sk -o /dev/null -w "%{http_code}" $BASE_URL 2>/dev/null || echo "not running"
```

If the server is not running:
1. If `BASE_URL` is the default dev URL, start the development server with `bin/dev`. If it's a
   non-default URL, the caller owns that server — report it as down rather than starting a new
   one on the wrong port.
2. Wait for it to be ready (check with curl until you get a 200/302 response)
3. Wait 10-15 seconds for full startup

### Step 3: Run Setup Scripts

If the QA plan includes setup scripts:
1. Run them in order using `bin/rails runner` or Rails console
2. Verify the data was created correctly
3. Note any setup failures - these may block scenarios

**IMPORTANT — Multi-tenant organization:** This is a multi-tenant app. Always use the default tenant organization from seeds when running setup scripts or creating test data:
```ruby
org = Organization.find_by(subdomain: "your-org")
ActsAsTenant.with_tenant(org) do
  # all setup code here
end
```
Do NOT use `Organization.first` — it returns the Platform org, not the default tenant, and will cause data to be invisible in the app.

## Application Configuration

**Base URL:** the `BASE_URL` resolved in Step 2 (from the QA plan; default `http://localhost:3000`)
**Organization:** Default tenant (multi-tenant app uses subdomains)

### Viewport Strategy

| Area | Target Device | Viewport | Notes |
|------|---------------|----------|-------|
| **Staff EHR** (all `/staff/*` routes) | Desktop | 1280x800 or larger | Desktop-only interface |
| **Admin** (all `/admin/*` routes) | Desktop | 1280x800 or larger | Desktop-only interface |
| **Client Portal** (`/clients/*` or root for clients) | Mobile | 375x667 (iPhone SE) | 90% of users are on mobile |

## Phase 2: Execute Scenarios

### Step 4: Authenticate

Use passwordless authentication:

#### Available Test Users:

Use the `User Role:` email specified in each scenario. If a scenario names a role without an
email, use these seeded users (**cross-check `db/seeds/users.rb` at runtime** — hardcoded lists
go stale):

| Role | Email |
|------|-------|
| Admin | `admin@example.com` (or `admin2@example.com`) |
| Therapist | `therapist@example.com` |
| Coordinator | `coordinator@example.com` (or `coordinator2@example.com`) |
| Supervisor + Therapist | `supervisor1@example.com`, `supervisor2@example.com` |
| Manager | `manager@example.com` |
| Client portal | `testclient@example.com` |

**Note:** Do not assume a role-named email exists just because the role does — verify against
`db/seeds/users.rb`. `clinical_supervisor` has no dedicated user; it's granted to a
supervisor via `db/seeds/supervision_relationships.rb` (typically `supervisor1@example.com`
— verify at runtime).

#### Authentication Flow:
1. Navigate to `$BASE_URL` - you'll be redirected to the sign-in page
2. Use `mcp__playwright__browser_snapshot` to see the login form
3. Enter the test email using `mcp__playwright__browser_type`
4. Click "Send Magic Link" button
5. **Get the magic link from Rails server logs:**
   - Use Bash to read recent log output: `tail -100 log/development.log | grep -A5 "magic_link"`
   - The magic link URL will look like: `$BASE_URL/passwordless/magic_links/...` (if the logged
     link shows a different port than `BASE_URL`, rewrite the port before navigating)
6. Navigate to the magic link URL using `mcp__playwright__browser_navigate`
7. Confirm authentication succeeded

**Re-authentication:** If a scenario requires a different user role than the current session, close the browser and re-authenticate with the new user.

### Step 5: Execute Each Scenario

**CRITICAL: Execute scenarios in priority order** (Critical first, then High, Medium, Low).

For each scenario (SC-XXX):

#### 5.1 Pre-Scenario Setup
- Set the correct viewport: `mcp__playwright__browser_resize(width: X, height: Y)`
- Authenticate as the required user (re-auth if role changed)
- Run any scenario-specific precondition scripts
- Navigate to the starting point **through the UI** (click sidebar, menus, buttons)

#### 5.2 Execute Steps
Follow the scenario steps exactly as written:
- **Navigate like a real user** - click links and buttons, don't type URLs directly
- Use `mcp__playwright__browser_snapshot` before each major interaction to understand the page
- Use `mcp__playwright__browser_click` for buttons and links
- Use `mcp__playwright__browser_type` for text input
- Use `mcp__playwright__browser_fill_form` for form fields
- Use `mcp__playwright__browser_select_option` for dropdowns
- Use `mcp__playwright__browser_navigate_back` for back button tests

#### 5.3 Verify Expected Results
For each expected result checkbox in the scenario:
- **Visual checks:** Use `mcp__playwright__browser_snapshot` and `mcp__playwright__browser_take_screenshot`
- **Console errors:** Use `mcp__playwright__browser_console_messages` with level "error"
- **Network errors:** Use `mcp__playwright__browser_network_requests` to check for 4xx/5xx
- **Data verification:** If the scenario checks data was saved, verify through the UI or with a Rails runner query
- **Turbo Stream checks:** If testing dynamic updates, verify the DOM updated correctly via snapshot

#### 5.X — MANDATORY snapshot/context discipline

A single full-page accessibility snapshot of a populated application page can run 50K–400K characters. If you take one full snapshot per interaction across a 40-scenario plan, you will exhaust the context budget long before the plan finishes and the run will fail mid-execution. Follow these rules without exception:

**Default to `depth: 5`** on every `mcp__playwright__browser_snapshot` call. The full tree is rarely needed. `depth: 4–6` returns enough structure to locate landmarks (nav, main, headings, buttons) and the targets near the top of the viewport. Only deepen when a specific subtree is the actual target of the next interaction.

**Always scope with `target: "<ref>"`** when you already know which subtree you care about (a form, a modal, a table row, a panel). For example, after navigating to a record, snapshot `target: <main-region-ref>` instead of the whole page. Element refs from the previous snapshot remain valid until the next navigation or Turbo Stream replacement.

**Dump to file with `filename:`** when you need to scan large content (long lists, tables with hundreds of rows, deep configuration panels). The snapshot is written to disk and a short reference is returned to you; you then `grep` or `Read` the file for what you actually need. This keeps the heavy content out of your context window entirely.

**Never use full-page screenshots routinely.** `mcp__playwright__browser_take_screenshot` with `fullPage: true` is for capturing visual evidence of a confirmed bug, not for "let me see what the page looks like." For passing scenarios, no screenshot is needed.

**Don't re-snapshot to "see what's there."** Re-snapshot only after an action you expect to change the DOM (click, form submit, Turbo Stream update). If you already have a recent snapshot and nothing has happened, reuse it.

**Console + network reads:** call `browser_console_messages` with `level: "error"` only (not "info"/"debug" unless debugging a specific issue). Call `browser_network_requests` with `static: false` to skip image/font/CSS noise; add a `filter` regex when you know the endpoint pattern.

**Cap big tool results.** If a tool result returns more than ~500 lines, write it to a file and grep it instead of letting it land in context. The Playwright snapshot tool's `filename:` option is the primary lever here.

**On scenario PASS, move on immediately.** Do not capture extra evidence. The PASS line in the execution report is sufficient.

**On scenario FAIL, capture exactly:** one targeted snapshot of the broken area (depth-limited), one screenshot for the bug report, the error-level console messages, the 4xx/5xx network requests. That's it.

Following these rules reduces per-scenario context use by 5–10×, which is what makes the sweep finish.

#### 5.4 Record Result
For each scenario, record:
- **PASS**: All expected results met, no console/network errors
- **FAIL**: One or more expected results not met - create a bug report
- **BLOCKED**: Could not execute due to a prerequisite failure or blocker
- **SKIP**: Not applicable (e.g., feature not deployed, data unavailable)

### Step 6: Navigate Like a Real User

**CRITICAL: Navigate by clicking through the UI, not by entering URLs directly.** You are simulating a real user who clicks links and buttons. Direct URL navigation should only be used for:
- The initial page load (`$BASE_URL`)
- Following the magic link for authentication

After authentication, **use the UI** (sidebar links, navigation menus, buttons, breadcrumbs) to reach each page.

**If you cannot reach a page through the UI:**
- If there is no link/button that a user would reasonably expect, **report as a Navigation bug**
- If a link/button exists but is broken, **report as a Navigation bug**

## Phase 3: Bug Reporting

### Step 7: Create Bug Reports for Failed Scenarios

For each FAIL result, create a bug report **in the same format as `/bug-hunt`** so that `/bug-hunt-fix` can consume them.

#### Directory Structure:
```
docs/bug-reports/
└── qa-{feature-name}-{YYYYMMDD-HHMMSS}/
    ├── INDEX.md                    # Summary linking to all bugs
    ├── BUG-001-short-title.md      # Individual bug report
    ├── BUG-002-short-title.md
    └── screenshots/
        ├── BUG-001.png
        └── BUG-002.png
```

**Important:** Use the `qa-` prefix in the directory name to distinguish QA execution bugs from ad-hoc bug hunts.

#### Individual Bug Report Template:
Create one file per bug at `docs/bug-reports/{session}/BUG-XXX-{short-title}.md`:

```markdown
# BUG-XXX: [Descriptive Title]

**Severity:** Critical | High | Medium | Low
**Type:** UI | Functional | Navigation | JS Error | Network | Accessibility | Visual
**URL:** [Full page URL where bug occurs]
**Date Found:** [Date/Time]
**Feature Area:** [Feature being tested]
**QA Scenario:** [SC-XXX from the QA plan]
**QA Plan:** [Path to the QA plan document]

---

## Description

[Clear, concise description of the bug]

---

## Steps to Reproduce

1. Navigate to [URL]
2. [Action taken]
3. [Action taken]
4. Observe: [What happens]

---

## Expected Behavior

[What should happen - copied/adapted from the QA scenario's expected results]

---

## Actual Behavior

[What actually happens]

---

## Screenshot

![BUG-XXX](screenshots/BUG-XXX.png)

---

## Console Errors

```
[Any JavaScript errors from browser console, or "None"]
```

---

## Network Errors

```
[Any failed network requests, or "None"]
```

---

## Environment

- **Browser:** Playwright Chromium
- **URL:** [Full URL]
- **User:** [Test user email used]
- **Viewport:** [Width x Height]

---

## Additional Context

[Reference to the QA scenario, any deviations from expected flow, related observations]
```

### Step 8: Take Screenshots Immediately

When a scenario fails:
1. **Take a screenshot immediately** - don't wait
2. Save to `docs/bug-reports/{session}/screenshots/BUG-XXX.png`
3. Capture console errors and network requests right away

## Severity Definitions

- **Critical**: Application crashes, data loss, security vulnerability, feature completely broken
- **High**: Major functionality broken, but workarounds exist
- **Medium**: Feature works but with issues that affect user experience
- **Low**: Minor visual issues, cosmetic problems, edge cases

## Phase 4: Execution Report

### Step 9: Create Execution Report

After all scenarios are executed, create the INDEX.md with an expanded format:

```markdown
# QA Execution Report: [Feature Name]

**QA Plan:** [Path to QA plan document]
**Date Executed:** [Date/Time]
**Executed By:** Claude Code (Automated)
**Branch:** [branch-name]
**Base URL:** [the BASE_URL used for this run]

---

## Execution Summary

| Status | Count |
|--------|-------|
| ✅ PASS | X |
| ❌ FAIL | X |
| ⚠️ BLOCKED | X |
| ⏭️ SKIP | X |
| **Total** | **X** |

---

## Bug Summary

| Severity | Count |
|----------|-------|
| Critical | X |
| High | X |
| Medium | X |
| Low | X |
| **Total** | **X** |

---

## Scenario Results

### Critical Priority

| Scenario | Title | Status | Bug |
|----------|-------|--------|-----|
| SC-001 | [Title] | ✅ PASS | - |
| SC-002 | [Title] | ❌ FAIL | [BUG-001](BUG-001-short-title.md) |

### High Priority

| Scenario | Title | Status | Bug |
|----------|-------|--------|-----|
| SC-003 | [Title] | ✅ PASS | - |

### Medium Priority
...

### Low Priority
...

---

## Bugs Found

### Critical
- [BUG-001: Title](BUG-001-short-title.md) (from SC-002)

### High
- [BUG-002: Title](BUG-002-short-title.md) (from SC-005)

### Medium
...

### Low
...

---

## Blocked Scenarios

| Scenario | Title | Reason |
|----------|-------|--------|
| SC-010 | [Title] | [Why it was blocked] |

---

## Test Coverage

### Pages Visited
- [x] /path/one - Tested
- [x] /path/two - Tested
- [ ] /path/three - Not tested (reason)

### Interactions Tested
- [x] Forms submitted
- [x] Buttons clicked
- [x] Navigation verified
- [x] Error states tested
- [x] Responsive layouts (if applicable)

---

## Recommendations

[High-level recommendations based on test results]

---

## How to Fix Bugs

Run `/bug-hunt-fix` with each individual bug file:
```
/bug-hunt-fix docs/bug-reports/qa-{feature-name}-{timestamp}/BUG-001-short-title.md
/bug-hunt-fix docs/bug-reports/qa-{feature-name}-{timestamp}/BUG-002-short-title.md
```
```

## Important Guidelines

1. **DO NOT FIX BUGS** - Your job is only to execute scenarios and report failures
2. **NAVIGATE LIKE A REAL USER** - Click links and buttons to move between pages. Never type a URL directly (except for initial load and magic link).
3. **Execute in priority order** - Critical scenarios first, Low priority last
4. **Take screenshots on failure** - Visual evidence is crucial
5. **Check console on every scenario** - Many bugs manifest as JS errors
6. **Re-authenticate when roles change** - Close browser and start fresh for each role switch
7. **Document everything** - Better to over-document than under-document
8. **Report BLOCKED scenarios** - If a prerequisite fails, mark the scenario as blocked and note why
9. **Stay focused on the plan** - Execute exactly what the QA plan says, don't improvise additional tests
10. **Bug reports must be bug-hunt-fix compatible** - Follow the exact template so `/bug-hunt-fix` can consume them
11. **Clean up** - Close the browser when done with `mcp__playwright__browser_close`

## Execution Flow

1. Read the QA plan document
2. Run any setup scripts from the plan
3. Group scenarios by user role to minimize re-authentication
4. Within each role group, execute in priority order (Critical → Low)
5. For each scenario:
   a. Set viewport
   b. Navigate to starting point via UI
   c. Execute steps exactly as written
   d. Verify all expected results
   e. Record PASS/FAIL/BLOCKED/SKIP
   f. If FAIL: create bug report immediately with screenshot
6. After all scenarios: create INDEX.md execution report
7. Run cleanup scripts from the QA plan
8. Close the browser
9. Announce results summary

Begin by reading the QA plan document.
