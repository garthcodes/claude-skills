---
description: Fix a bug from bug-hunt and verify the fix using Playwright browser automation
argument-hint: <path-to-bug-file.md>
---

# Verify Bug Fix Command

You are tasked with fixing a bug that was found by bug-hunt and verifying the fix using Playwright browser automation.

## Bug File to Analyze
$ARGUMENTS

## Phase 1: Bug Analysis

### Step 1: Read and Understand the Bug
Read the bug file provided and extract:
- **Summary**: What is the bug?
- **Steps to Reproduce**: How to trigger it
- **Expected vs Actual Behavior**: What should happen vs what happens
- **Related Files**: Files mentioned in the bug report
- **Technical Notes**: Any hints about the cause

### Step 2: Investigate the Codebase
Perform systematic investigation:
- Read all related files mentioned in the bug report
- Search for the error location in the codebase
- Examine the stack trace if provided
- Check related models, controllers, views, and services
- Look for similar patterns or known issues in the codebase
- Check test files for expected behavior
- Review Turbo Stream templates if it's a UI update issue

### Step 3: Root Cause Analysis
Before proposing any fix:
- Identify the exact root cause
- Understand WHY the bug occurs, not just WHERE
- Consider multiple possible causes
- Document your findings

## Phase 2: Solution Planning

### Step 4: Best Practices Review
Ensure your solution follows:
- Rails 8 conventions and patterns from CLAUDE.md
- Service object patterns for complex business logic
- Proper error handling and user feedback
- Hotwire/Turbo best practices for dynamic updates
- ViewComponent patterns if UI components are involved
- Security considerations
- Performance implications

### Step 5: Create Fix Plan
Document your proposed fix:
- Root cause analysis summary
- Proposed solution steps
- Files that need to be modified
- Potential side effects or risks
- Testing strategy to verify the fix

## Phase 3: Implementation

### Step 6: Implement the Fix
When implementing:
- Make minimal, targeted changes
- Follow existing code patterns and conventions
- Add appropriate error handling
- Include necessary validations
- **For any front-end changes** (views, partials, ViewComponents, Stimulus controllers, Turbo Stream templates, CSS/Tailwind, JavaScript): **Use the `/frontend-expert` skill** to implement the changes. This ensures proper Hotwire patterns, accessibility, and Tailwind conventions are followed.
- Run linting after changes: `bin/standardrb --fix`

## Phase 4: Verification with Playwright

### Step 7: Resolve the Base URL
This checkout may be the main repo (default port) or a `/build-feature` worktree with its own
server and database (`PORT=` in `.env`). Resolve it before touching the browser:

```bash
BASE_URL="$(bin/dev-url)"   # $PORT > PORT= in .env > 3000
```

Use `$BASE_URL` for the server check and every `browser_navigate`. Never hardcode the port.

### Step 7b: Prerequisites Check
Ensure the development server is running:

```bash
curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL" 2>/dev/null || echo "not running"
```

If not running, start it with `bin/dev` (it reads `PORT=` from `.env`) and wait for it to be ready.

### Step 8: Authenticate
Use passwordless authentication:

#### Available Test Users:
| Role | Email |
|------|-------|
| Admin | `admin@example.com` |
| Therapist | `therapist@example.com` |
| Coordinator | `coordinator@example.com` |
| Standard User | `user@example.com` |

#### Authentication Flow:
1. Navigate to `$BASE_URL`
2. Use `mcp__playwright__browser_snapshot` to see the login form
3. Enter the appropriate test email
4. Click "Send Magic Link"
5. Get the magic link from logs: `tail -100 log/development.log | grep -A5 "magic_link"`
6. Navigate to the magic link URL
7. Confirm authentication succeeded

### Step 9: Set Viewport
Based on the bug's URL:
- **Staff/Admin routes** (`/staff/*`, `/admin/*`): Desktop viewport (1280x800)
  ```
  mcp__playwright__browser_resize(width: 1280, height: 800)
  ```
- **Client Portal**: Mobile-first viewport (375x667)
  ```
  mcp__playwright__browser_resize(width: 375, height: 667)
  ```

### Step 10: Reproduce and Verify Fix
Follow the exact steps to reproduce from the bug report, **navigating through the UI like a real user**:

1. **After authentication, use the UI to navigate** - click sidebar links, nav menus, and buttons to reach the page where the bug occurs. Do NOT navigate directly to URLs (except for initial load and magic link).
2. **Take initial snapshot** with `mcp__playwright__browser_snapshot`
3. **Execute each reproduction step** exactly as documented, clicking buttons and links as a user would
4. **Capture state at critical points**:
   - Use `mcp__playwright__browser_snapshot` for accessibility tree
   - Use `mcp__playwright__browser_take_screenshot` for visual state (save to `.playwright-mcp/`)
5. **Check for console errors**: `mcp__playwright__browser_console_messages` with level "error"
6. **Check network requests**: `mcp__playwright__browser_network_requests`

### Step 11: Verify Expected Behavior
After reproducing the steps:
- Confirm the **expected behavior** now occurs (not the actual/buggy behavior)
- Take a screenshot showing the fix works (save to `.playwright-mcp/` - will be deleted in cleanup)
- Verify no new console errors were introduced
- Verify no network errors occurred

### Step 12: Additional Verification
- Test edge cases related to the bug
- Test that related functionality still works
- If the bug was about Turbo Streams, verify the DOM updates correctly

## Phase 5: Documentation

### Step 13: Update Bug Report
Add a "Fix Verification" section to the bug file (this is the ONLY edit allowed to `/docs/bug-reports/`):

```markdown
---

## Fix Applied

**Date:** [Current Date]
**Status:** VERIFIED FIXED

### Changes Made
- [File 1]: [Brief description of change]
- [File 2]: [Brief description of change]

### Verification Results
- [x] Followed reproduction steps
- [x] Bug no longer occurs
- [x] Expected behavior confirmed
- [x] No console errors
- [x] No network errors
- [x] Edge cases tested
```

Note: Do NOT add screenshots to the bug-reports folder. Screenshots are for your verification during testing and should be deleted during cleanup.

### Step 14: Clean Up
- Close the browser: `mcp__playwright__browser_close`
- **Delete any screenshots** you created during verification (in `.playwright-mcp/` or elsewhere)
- Run the test suite if relevant tests exist
- Ensure linting passes

## Important Guidelines

1. **ALWAYS investigate thoroughly** before implementing any fix
2. **Understand the root cause** - don't just patch symptoms
3. **Make minimal changes** - fix the bug without over-engineering
4. **Follow existing patterns** - maintain consistency with the codebase
5. **Use `/frontend-expert` for front-end changes** - Any changes to views, partials, ViewComponents, Stimulus controllers, Turbo Stream templates, CSS/Tailwind, or JavaScript MUST use the `/frontend-expert` skill
6. **Navigate like a real user** - During verification, click through the UI (sidebar, menus, buttons) to reach pages. Do NOT type URLs directly (except initial load and magic link).
7. **Verify with Playwright** - actually reproduce and confirm the fix
8. **Document everything** - update the bug report with verification results
9. **Check for regressions** - ensure the fix doesn't break related functionality
10. **Bug reports folder policy** - The ONLY edit you should make to `/docs/bug-reports/` is updating the bug document itself to explain the fix. Do NOT create, modify, or add any other files in that folder (no screenshots, no new markdown files, no subfolders). Screenshots for verification should be saved elsewhere (e.g., `.playwright-mcp/`) and deleted during cleanup.

## Error Handling

If verification fails:
1. Document what happened in the bug report
2. Analyze why the fix didn't work
3. Return to Phase 2 with new insights
4. Iterate until the fix is verified

Begin by reading the bug file and understanding the issue thoroughly.
