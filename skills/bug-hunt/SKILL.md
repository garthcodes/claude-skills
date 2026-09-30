---
description: Hunt for bugs in a feature using Playwright browser automation
argument-hint: <feature-description>
---

# Bug Hunt Command

You are tasked with testing a feature in the application to find bugs. You will use Playwright MCP tools to interact with the browser and document any issues found. **You do NOT fix bugs - you only find and report them.**

## Feature to Test
$ARGUMENTS

## Scope Determination

Before doing anything else, determine what to test based on whether `$ARGUMENTS` above is empty.

### Mode A: Feature description provided (`$ARGUMENTS` is non-empty)

Use the provided feature description as the scope. Search the codebase for relevant controllers, views, and routes that match the feature. Proceed with the standard protocol below.

### Mode B: No arguments provided (test current branch only)

If `$ARGUMENTS` is empty, scope testing to **only the changes on the current git branch**. Do NOT test features that exist on `main` but were not modified on this branch.

1. Determine the merge base and list changed files:
   ```bash
   git merge-base HEAD main
   git diff --name-only $(git merge-base HEAD main)..HEAD
   git log --oneline $(git merge-base HEAD main)..HEAD
   ```

2. Read the changed files to understand what the branch actually does. Pay attention to:
   - **Controllers and routes**: identify the URLs and actions that were added or modified
   - **Views and components**: identify the UI surfaces that were added or modified
   - **Models, services, jobs**: understand the behavior changes, but only test them via their UI entry points
   - **Migrations**: note any schema changes that might affect existing flows
   - **Tests, configs, and docs**: ignore for testing purposes (no UI to exercise)

3. Build an explicit "in scope" list of pages/flows to test, derived from the diff. Write this list into the INDEX.md under a "Branch Scope" section so the report makes the boundary clear.

4. **Hard rule**: do not test a page or flow unless its code appears in the diff, OR it is a direct navigation step required to reach a page that IS in the diff (e.g. you must log in and navigate the sidebar to reach a modified page — that's fine, but don't start bug-hunting unrelated sidebar destinations along the way).

5. If the diff is empty (branch matches main), report that and stop.

## Prerequisites Check

### Step 0: Resolve the Base URL

**Do this first — before any Bash or Playwright call.** This checkout may be the main
repo (the default port) or a `/build-feature` worktree with its own server and its own database
(`PORT=` in `.env`, assigned by `bin/worktree-port` in the 3010–3099 range). Hunting the
wrong port means hunting the wrong branch.

```bash
BASE_URL="$(bin/dev-url)"   # $PORT > PORT= in .env > 3000
echo "$BASE_URL"
```

**Override**: if `$ARGUMENTS` contains a line of the form `Base URL: <url>` (for example,
when this skill is invoked by `/bug-hunt-all`), use exactly that URL instead and skip
`bin/dev-url`. That line is scope metadata, not part of the feature description — strip it
before using the rest of `$ARGUMENTS` as the feature scope.

Use `$BASE_URL` for every server check, every `browser_navigate`, and the
`**Base URL:**` field of the report. Never hardcode 3000.

### Step 1: Ensure Development Server is Running

First, check if the Rails server is running:

```bash
curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL" 2>/dev/null || echo "not running"
```

If the server is not running (response is not 200 or "not running"):
1. Start the development server in the background using `bin/dev` (it reads `PORT=` from `.env`, so it comes up on `$BASE_URL`)
2. Wait for it to be ready (check with curl until you get a 200 response)
3. Note: You may need to wait 10-15 seconds for the server to fully start

### Step 2: Understand the Feature

Before testing, gather context about the feature:
1. Search the codebase for relevant controllers, views, and routes
2. Identify the main entry points (URLs) for this feature
3. Understand the expected behavior from the code

Use tools like:
- `Grep` to find routes related to the feature
- `Read` to examine controller actions and views
- Check `config/routes.rb` for relevant paths

**In Mode B (branch-scoped)**: skip the open-ended grep — you already have the file list from `git diff`. Just read those files plus any routes/views/components they reference. Don't go searching the wider codebase for "related features" that weren't touched on this branch.

## Application Configuration

**Base URL:** `$BASE_URL` — resolved in Step 0 via `bin/dev-url`
**Organization:** Default tenant (multi-tenant app uses subdomains)
**Port:** 3000 in the main checkout; the worktree's own `PORT=` from `.env` otherwise

### Viewport Strategy

This application has different target devices for different areas:

| Area | Target Device | Viewport | Notes |
|------|---------------|----------|-------|
| **Staff EHR** (all `/staff/*` routes) | Desktop | 1280x800 or larger | Desktop-only interface |
| **Admin** (all `/admin/*` routes) | Desktop | 1280x800 or larger | Desktop-only interface |
| **Client Portal** (`/clients/*` or root for clients) | Mobile | 375x667 (iPhone SE) | 90% of users are on mobile |

**Before testing, determine which area you're testing and set the appropriate viewport:**

```
# For Staff/Admin (desktop):
mcp__playwright__browser_resize(width: 1280, height: 800)

# For Client Portal (mobile-first):
mcp__playwright__browser_resize(width: 375, height: 667)
```

For the Client Portal, also test at tablet (768x1024) and desktop (1280x800) as secondary viewports.

## Testing Protocol

### Step 3: Navigate to the Feature (Like a Real User)

**CRITICAL: Navigate by clicking through the UI, not by entering URLs directly.** You are simulating a real user who clicks links and buttons to get around the application. Direct URL navigation should only be used for:
- The initial page load (`$BASE_URL`)
- Following the magic link for authentication

After authentication, you will land on a dashboard/home page. From there, **use the UI** (sidebar links, navigation menus, buttons, breadcrumbs) to reach the feature you need to test.

**If you cannot reach a page through the UI:**
- If there is no link/button to navigate to a page that a user would reasonably expect to find from the current page, **report that as a bug** (Type: Navigation, Severity: Medium or High depending on importance)
- Only report missing navigation if it makes sense that a link/button SHOULD exist on that page. Don't report a missing link to an admin page from the client portal, for example.
- If a link/button exists but is broken (404, error, wrong destination), **report that as a bug**

### Step 4: Authenticate with Passwordless Magic Link

This application uses **passwordless authentication** with magic links (Devise-Passwordless). No passwords exist. This is one example of a test-login flow — if your app authenticates differently, substitute your own sign-in steps here.

#### Available Test Users:
| Role | Email |
|------|-------|
| Admin | `admin@example.com` |
| Therapist | `therapist@example.com` |
| Coordinator | `coordinator@example.com` |
| Biller | `billing@example.com` |
| Supervisor / clinical supervisor (co-signs for `therapist@example.com`) | `supervisor@example.com` |
| Manager | `manager@example.com` |

#### Authentication Flow:
1. Navigate to `$BASE_URL` - you'll be redirected to the sign-in page
2. Use `mcp__playwright__browser_snapshot` to see the login form
3. Enter a test email (e.g., `admin@example.com`) using `mcp__playwright__browser_type`
4. Click "Send Magic Link" button
5. **Get the magic link from Rails server logs:**
   - Use Bash to read recent log output: `tail -100 log/development.log | grep -A5 "magic_link"`
   - Or check the terminal where `bin/dev` is running
   - The magic link URL will look like: `$BASE_URL/passwordless/magic_links/...` (if the logged link shows a different port than `$BASE_URL`, rewrite the port before navigating)
6. Navigate to the magic link URL using `mcp__playwright__browser_navigate`
7. You should now be authenticated and redirected to the dashboard

**Tip:** Use `admin@example.com` for full access to all features

### Step 5: Systematic Testing

For each page/screen in the feature, perform these tests:

#### 5.1 Visual Inspection
- **First, set the correct viewport** based on the area being tested (see Viewport Strategy above)
- Use `mcp__playwright__browser_snapshot` to get the accessibility tree
- Use `mcp__playwright__browser_take_screenshot` to capture visual state
- Look for:
  - Layout issues (overlapping elements, misalignment)
  - Missing content or broken images
  - Incorrect styling
  - Responsive design issues:
    - **Staff/Admin areas**: Desktop-only, no mobile testing needed
    - **Client Portal**: Test mobile viewport FIRST (375x667), then tablet (768x1024), then desktop (1280x800)

#### 5.2 Console Errors
- Use `mcp__playwright__browser_console_messages` with level "error" to check for JavaScript errors
- Document any errors with their context

#### 5.3 Network Issues
- Use `mcp__playwright__browser_network_requests` to check for failed requests
- Look for 4xx and 5xx responses

#### 5.4 Interactive Element Testing
For each interactive element found in the snapshot:

**Buttons:**
- Click using `mcp__playwright__browser_click`
- Verify expected action occurs
- Check for error states

**Forms:**
- Fill with valid data using `mcp__playwright__browser_type` or `mcp__playwright__browser_fill_form`
- Submit and verify success
- Fill with invalid data and verify error handling
- Test required field validation
- Test edge cases (empty, very long input, special characters)

**Links:**
- Click and verify navigation
- Check for 404s or broken links

**Dropdowns/Selects:**
- Use `mcp__playwright__browser_select_option` to test all options
- Verify selections persist correctly

#### 5.5 Navigation Testing
- **Click every navigation link and button** on the page to verify they go to the correct destination
- Test browser back button using `mcp__playwright__browser_navigate_back`
- Verify breadcrumbs and navigation links work
- Verify that all expected navigation paths exist (e.g., if you're on a list page, each item should link to its detail page)
- Report any missing navigation that a user would reasonably expect to find on the page

#### 5.6 Accessibility Checks
From the snapshot accessibility tree, verify:
- All interactive elements are keyboard accessible
- Images have alt text
- Forms have proper labels
- ARIA attributes are correct

#### 5.7 Edge Cases
- Test with empty data states
- Test with maximum data limits
- Test rapid clicking/double submissions
- Test with special characters in inputs

### Step 6: Document Each Bug Found

**Each bug gets its own file.** As you find bugs:

1. **Create the session directory** (first bug only):
   - Default: `docs/bug-reports/{feature-name}-{YYYYMMDD-HHMMSS}/`
   - With screenshots subdir: `docs/bug-reports/{feature-name}-{YYYYMMDD-HHMMSS}/screenshots/`
   - **Override**: If `$ARGUMENTS` contains a line of the form `Output dir: <path>` (for example, when this skill is invoked by `/bug-hunt-all`), use exactly that path as the session directory instead of generating a new timestamped one. Still create a `screenshots/` subdirectory inside it. Do NOT create a sibling timestamped directory.

2. **For each bug, immediately create a file** with:
   - **Bug ID**: Sequential number (BUG-001, BUG-002, etc.)
   - **Filename**: `BUG-XXX-{short-kebab-title}.md` (e.g., `BUG-001-form-submit-fails.md`)
   - **Severity**: Critical / High / Medium / Low
   - **Type**: UI | Functional | Navigation | JS Error | Network | Accessibility | Visual
   - **Page/URL**: Where the bug occurs
   - **Steps to Reproduce**: Exact steps taken
   - **Expected Behavior**: What should happen
   - **Actual Behavior**: What actually happens
   - **Screenshot**: Save as `screenshots/BUG-XXX.png`
   - **Console Errors**: Capture with `mcp__playwright__browser_console_messages`
   - **Network Errors**: Capture with `mcp__playwright__browser_network_requests`
   - **Additional Context**: Any relevant details

3. **Take a screenshot immediately** when you find a bug - don't wait until the end

## Severity Definitions

- **Critical**: Application crashes, data loss, security vulnerability, feature completely broken
- **High**: Major functionality broken, but workarounds exist
- **Medium**: Feature works but with issues that affect user experience
- **Low**: Minor visual issues, cosmetic problems, edge cases

## Report Generation

### Step 7: Create Bug Reports

Each bug gets its own report file. Create a session directory and individual bug files.

#### Directory Structure:
```
docs/bug-reports/
└── {feature-name}-{YYYYMMDD-HHMMSS}/   # or the path from `Output dir:` in $ARGUMENTS
    ├── INDEX.md                    # Summary linking to all bugs
    ├── BUG-001-short-title.md      # Individual bug report
    ├── BUG-002-short-title.md
    └── screenshots/
        ├── BUG-001.png
        └── BUG-002.png
```

#### Individual Bug Report Template:
Create one file per bug at `docs/bug-reports/{session}/BUG-XXX-{short-title}.md`:

```markdown
# BUG-XXX: [Descriptive Title]

**Severity:** Critical | High | Medium | Low
**Type:** UI | Functional | Navigation | JS Error | Network | Accessibility | Visual
**URL:** [Full page URL where bug occurs]
**Date Found:** [Date/Time]
**Feature Area:** [Feature being tested]

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

[What should happen]

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
- **Viewport:** [Width x Height if relevant]

---

## Additional Context

[Any other relevant information, related bugs, or observations]
```

#### Index/Summary File Template:
Create `docs/bug-reports/{session}/INDEX.md`:

```markdown
# Bug Hunt Summary: [Feature Name]

**Date:** [Date/Time]
**Tester:** Claude Code (Automated)
**Feature:** [Feature Description]
**Base URL:** [the $BASE_URL used for this run]

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | X |
| High | X |
| Medium | X |
| Low | X |
| **Total** | **X** |

---

## All Bugs Found

### Critical
- [BUG-001: Title](BUG-001-short-title.md)

### High
- [BUG-002: Title](BUG-002-short-title.md)

### Medium
- [BUG-003: Title](BUG-003-short-title.md)

### Low
- [BUG-004: Title](BUG-004-short-title.md)

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
- [ ] Responsive layouts

### Out of Scope
- [List any areas intentionally not covered]

---

## Recommendations

[High-level recommendations for addressing the bugs found]
```

## Important Guidelines

1. **DO NOT FIX BUGS** - Your job is only to find and document them
2. **NAVIGATE LIKE A REAL USER** - Click links and buttons to move between pages. Never type a URL directly into the browser (except for initial load and magic link). If you can't reach a page through the UI, that itself may be a bug.
3. **Be thorough** - Test happy paths and edge cases
4. **Take screenshots** - Visual evidence is crucial
5. **Check console** - Many bugs manifest as JS errors
6. **Test responsively** - Try different viewport sizes
7. **Document everything** - Better to over-document than under-document
8. **Stay focused** - Only test the specified feature area. In Mode B (no arguments), this means only test pages/flows whose code appears in the branch diff — do not wander into other features that exist on `main`.
9. **Clean up** - Close the browser when done with `mcp__playwright__browser_close`

## Starting the Hunt

Begin by:
1. **Resolving `BASE_URL`** with `bin/dev-url` (Step 0) — do not assume 3000
1. **Determining scope** — check `$ARGUMENTS`. If non-empty, use Mode A (feature description). If empty, use Mode B (run `git diff` against `main` and scope strictly to changed files).
2. Checking if the server is running (start with `bin/dev` if not)
3. Understanding the feature from the codebase (routes, controllers, views) — in Mode B, restrict reads to files in the diff
4. **Determining the target viewport** (Staff/Admin = desktop, Client Portal = mobile-first)
5. Creating the session directory: `docs/bug-reports/{feature-or-branch-name}-{timestamp}/`
6. **Setting the appropriate viewport size** before navigating
7. Navigating to `$BASE_URL` and authenticating
8. **Clicking through the UI** (sidebar, nav menus, buttons) to reach the feature - do NOT type URLs directly
9. Systematically testing each component by interacting as a user would
10. Creating individual bug reports as you find issues (don't wait!)
11. Taking screenshots immediately when bugs are found
12. Creating the INDEX.md summary at the end (in Mode B, include the "Branch Scope" section listing the diff files and pages tested)

Good hunting!
