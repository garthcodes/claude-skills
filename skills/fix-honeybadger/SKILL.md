---
description: Pull the latest Honeybadger fault, plan and implement a fix, review it, verify with Playwright, and create a PR
argument-hint: [fault-id-or-project-name]
---

# Fix Honeybadger Fault

Automated workflow to pull the latest unresolved fault from Honeybadger, fix it in an isolated git worktree, review the fix, verify it in-browser, and open a PR.

## Phase 1: Fetch the Latest Fault

### Step 1: Identify the Project and Fault

Use the Honeybadger MCP to find the target project and fault:

```
mcp__honeybadger__list_projects
```

**If `$ARGUMENTS` is a numeric fault ID** (e.g., `/fix-honeybadger 12345`):
- List projects to find the one containing this fault
- Skip Step 2 — go directly to Step 3 with this fault ID

**If `$ARGUMENTS` is a project name** (e.g., `/fix-honeybadger my-app`):
- Match the project by name
- Proceed to Step 2 to select a fault

**If no argument**:
- Use the project with the most recent `last_notice_at` that has unresolved faults
- Proceed to Step 2 to select a fault

If the selected project has no unresolved faults, inform the user and stop.

### Step 2: Get the Latest Unresolved Fault

Skip this step if a specific fault ID was provided in `$ARGUMENTS`.

```
mcp__honeybadger__list_faults(project_id: <id>, q: "-is:resolved -is:ignored", order: "recent")
```

Select the **most recent** unresolved fault.

### Step 3: Get Fault Details and Stack Trace

```
mcp__honeybadger__get_fault(project_id: <id>, fault_id: <fault_id>)
mcp__honeybadger__list_fault_notices(project_id: <id>, fault_id: <fault_id>)
```

Extract from the fault and its most recent notice:
- **Error class and message**
- **Full stack trace** (focus on application frames, not gem/framework frames)
- **Request URL and parameters** (if available)
- **User context** (user_id, email if available)
- **Environment** (production, staging)
- **Frequency** (how often it occurs)
- **Affected users count**

Present a summary to the user:

```
Honeybadger Fault #<id>: <error class>
Message: <error message>
URL: <request URL>
Occurrences: <count>
Affected Users: <count>
First seen: <date> | Last seen: <date>

Stack trace (app frames):
  app/controllers/foo_controller.rb:42 in `show`
  app/services/bar_service.rb:17 in `call`
  ...
```

## Phase 1.5: Create Isolated Worktree

### Step 3.5: Set Up Worktree

After fetching the fault details, create an isolated git worktree so the main working directory stays clean. All subsequent work (investigation, implementation, testing, verification) happens in this worktree.

**Variables** (use throughout all remaining phases):
- `MAIN_DIR` = the absolute path of the main repo checkout (the directory this skill is run from)
- `BRANCH_NAME` = `fix/honeybadger-<fault_id>-<short-description>` (kebab-case, derived from the error)
- `WORKTREE_DIR` = `../<repo-name>-hb-<fault_id>` (sibling directory)
- `WORKTREE_PORT` = `3002` (dev server port for Playwright verification)

```bash
# Create the worktree with its own branch off main
cd "$MAIN_DIR"
git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME" main

# Copy gitignored files needed for development (skip certs if your dev setup doesn't use local HTTPS)
cp -r "$MAIN_DIR/config/certs" "$WORKTREE_DIR/config/"
cp "$MAIN_DIR/.env" "$WORKTREE_DIR/.env"
```

**CRITICAL: From this point forward, ALL file reads, edits, searches, tests, linting, and git operations MUST use absolute paths based on `$WORKTREE_DIR`.** For example:
- Read files: `$WORKTREE_DIR/config/initializers/rack_attack.rb`
- Run tests: `cd $WORKTREE_DIR && bundle exec rspec spec/...`
- Run linting: `cd $WORKTREE_DIR && bin/standardrb`
- Git operations: `cd $WORKTREE_DIR && git add ...`

Inform the user which worktree was created and where.

## Phase 2: Investigate the Codebase

### Step 4: Trace the Error

Using the stack trace from Phase 1, **working in the worktree directory**:

1. **Read every application file** in the stack trace (skip gem/framework frames)
2. **Identify the exact line** where the error occurs
3. **Understand the data flow** - trace inputs from controller through services to the failure point
4. **Check for related code** - similar patterns, shared concerns, or recent changes
5. **Search git history** for recent changes to the affected files:
   ```bash
   cd $WORKTREE_DIR && git log --oneline -10 -- <file_path>
   ```
6. **Identify the root cause** - understand WHY the error happens, not just WHERE

### Step 5: Document the Investigation

Create a brief summary of findings:
- Root cause explanation
- Which files need changes
- Whether this is a backend-only fix, frontend-only, or both
- Any related areas that might be affected

## Phase 3: Plan the Fix

### Step 6: Create Implementation Plan

Use the `/plan` skill with the investigation context:

```
/plan Fix Honeybadger fault #<id>: <error class> - <root cause summary>
```

The plan should include:
- Root cause from investigation
- Specific files to modify
- The fix approach
- Testing strategy
- Risk assessment

### Step 7: Architect Review

Use the `/architect-review` skill to review the plan:

```
/architect-review
```

Address any concerns raised before proceeding.

### Step 8: Frontend Review (Conditional)

Check if any of the planned changes touch frontend files:
- Views (`app/views/`)
- ViewComponents (`app/components/`)
- Stimulus controllers (`app/javascript/controllers/`)
- Turbo Stream templates
- CSS/Tailwind changes

If YES, run:
```
/frontend-review
```

Address any concerns raised before proceeding.

## Phase 4: Execute the Fix

### Step 9: Implement

Use the `/code` skill to execute the implementation plan.

```
/code
```

**Reminder:** All file edits and new files must be created in the worktree (`$WORKTREE_DIR`), not the main repo.

This will create the fix following the plan, including tests.

## Phase 5: Rails Review

### Step 10: Review the Implementation

Use the `/review-rails` skill to review all changes:

```
/review-rails
```

### Step 11: Fix Review Issues

If the review finds P3 (Critical) or P2 (High) issues:
1. Read the review report
2. Fix each issue identified (in the worktree)
3. Run linting: `cd $WORKTREE_DIR && bin/standardrb --fix`
4. Run tests: `cd $WORKTREE_DIR && bundle exec rspec` (for affected spec files)
5. Re-run `/review-rails` to confirm issues are resolved

If only P1/P0 issues remain, proceed (these are optional improvements).

## Phase 6: Verify with Playwright

### Step 12: Start Dev Server in Worktree

Start a development server from the worktree on a separate port so Playwright can verify the fix.

```bash
# Create a Procfile with port 3002 for the worktree server
# (replace 3000 with whatever port your Procfile.dev normally uses)
cd $WORKTREE_DIR && sed 's/3000/3002/g' Procfile.dev > Procfile.dev.worktree

# Start the worktree dev server in the background
cd $WORKTREE_DIR && PORT=3002 foreman start -f Procfile.dev.worktree &
WORKTREE_SERVER_PID=$!
```

Wait for the server to be ready:

```bash
# Poll until the server responds (max 30 seconds)
for i in $(seq 1 30); do
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" http://localhost:3002 2>/dev/null)
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "302" ]; then
    echo "Worktree dev server ready on port 3002"
    break
  fi
  sleep 1
done
```

If the server fails to start after 30 seconds:
1. Check the foreman output for errors
2. Try `cd $WORKTREE_DIR && bundle install` then retry
3. If still failing, skip Playwright verification and note it in the PR

### Step 13: Authenticate

Determine the appropriate test user based on the fault context:
- If the error occurred in a staff route (`/staff/*`): use `admin@example.com` or `therapist@example.com`
- If the error occurred in admin route (`/admin/*`): use `admin@example.com`
- If the error occurred in client portal: use `user@example.com`
- Default to `admin@example.com` for broadest access

#### Authentication Flow:
1. Navigate to `http://localhost:3002`
2. Use `mcp__playwright__browser_snapshot` to see the login form
3. Enter the test email using `mcp__playwright__browser_type`
4. Click "Send Magic Link"
5. Get the magic link from logs:
   ```bash
   tail -100 $WORKTREE_DIR/log/development.log | grep -A5 "magic_link"
   ```
6. Navigate to the magic link URL (ensure it uses port 3002)
7. Confirm authentication succeeded with `mcp__playwright__browser_snapshot`

### Step 14: Set Viewport

Based on the fault's URL:
- **Staff/Admin routes** (`/staff/*`, `/admin/*`): Desktop viewport
  ```
  mcp__playwright__browser_resize(width: 1280, height: 800)
  ```
- **Client Portal**: Mobile-first viewport
  ```
  mcp__playwright__browser_resize(width: 375, height: 667)
  ```

### Step 15: Verify the Fix

Using the request URL and context from the Honeybadger fault:

1. **Navigate to the affected area** by clicking through the UI like a real user (sidebar, nav menus, buttons). Do NOT type URLs directly except for initial load and magic link.
2. **Take a snapshot** with `mcp__playwright__browser_snapshot`
3. **Reproduce the scenario** that triggered the error:
   - If the error was on a specific page, navigate to that type of page
   - If the error was triggered by a form submission, fill and submit the form
   - If the error was triggered by a specific action, perform that action
4. **Verify the error no longer occurs**:
   - Check console for errors: `mcp__playwright__browser_console_messages` (level: "error")
   - Check network for failures: `mcp__playwright__browser_network_requests`
   - Verify the page renders correctly with `mcp__playwright__browser_snapshot`
   - Verify expected behavior works (e.g., page loads, form submits successfully, data displays)
5. **Test edge cases** if relevant to the fix
6. **Take a final screenshot** confirming the fix works

### Step 16: Handle Verification Failure

If the fix doesn't work:
1. Document what happened
2. Check console and network errors
3. Return to Phase 4 (Step 9) with new insights
4. Re-implement, re-review, and re-verify
5. Maximum 2 retry cycles - if still failing, report to the user with findings

### Step 17: Clean Up Playwright and Dev Server

```bash
# Close Playwright browser
mcp__playwright__browser_close

# Stop the worktree dev server
kill $WORKTREE_SERVER_PID 2>/dev/null

# Also kill any remaining foreman/ruby processes on port 3002
lsof -ti:3002 | xargs kill -9 2>/dev/null

# Remove the temporary Procfile
rm -f $WORKTREE_DIR/Procfile.dev.worktree
```

Delete any screenshots created during verification (in `.playwright-mcp/` or elsewhere).

## Phase 7: Create Pull Request

### Step 18: Commit the Fix

The branch was already created when the worktree was set up, so just commit:

```bash
cd $WORKTREE_DIR

# Stage all changed files (be specific, don't use git add -A)
git add <specific files>

# Commit with descriptive message
git commit -m "$(cat <<'EOF'
Fix: <error class> in <location>

Resolves Honeybadger fault #<fault_id>.

Root cause: <brief root cause explanation>
Fix: <brief fix description>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

### Step 19: Create the PR

```bash
cd $WORKTREE_DIR

git push -u origin $BRANCH_NAME

gh pr create --title "Fix: <short error description>" --body "$(cat <<'EOF'
## Summary

Fixes Honeybadger fault #<fault_id>: `<ErrorClass>` in `<file:line>`

**Error:** <error message>
**Occurrences:** <count>
**Affected Users:** <count>

## Root Cause

<Explanation of why the error was occurring>

## Fix

<Description of what was changed and why>

## Changes

- `<file1>`: <what changed>
- `<file2>`: <what changed>

## Testing

- [ ] Unit/integration tests added
- [ ] Playwright verification passed (error no longer occurs)
- [ ] `bundle exec rspec` passes
- [ ] `bin/standardrb` passes
- [ ] No new console/network errors

## Verification

Verified in-browser using Playwright:
- Navigated to the affected area
- Performed the action that triggered the error
- Confirmed the error no longer occurs
- No console or network errors

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Step 20: Clean Up Worktree

After the PR is created, clean up the worktree:

```bash
cd "$MAIN_DIR"
git worktree remove $WORKTREE_DIR
```

If the remove fails (e.g., uncommitted changes), warn the user and provide the manual cleanup command.

### Step 21: Report to User

Present the final summary:

```
Honeybadger Fault #<id> Fixed

Error: <error class> - <message>
Root Cause: <brief explanation>
Fix: <brief description>

PR: <PR URL>
Branch: <branch_name>

Reviews:
- Architect Review: <passed/issues found>
- Frontend Review: <passed/skipped/issues found>
- Rails Review: <verdict>

Verification:
- Playwright: <passed/failed/skipped>
- Tests: <passed/failed>
- Linting: <passed/failed>

Worktree: cleaned up
```

## Important Guidelines

1. **Always investigate thoroughly** before planning a fix - understand the root cause
2. **Follow existing patterns** - maintain consistency with the codebase
3. **Make minimal, targeted changes** - fix the bug without over-engineering
4. **Use specialized skills for front-end changes** - defer to `/frontend-expert` for view/component/Stimulus work
5. **Navigate like a real user** during Playwright verification - click through the UI, don't type URLs
6. **Address all P3/P2 review issues** before creating the PR
7. **Never skip the Playwright verification** unless the worktree dev server fails to start - code review alone doesn't prove the fix works
8. **Clean up after yourself** - close browser, stop dev server, delete temp files, remove worktree
9. **Be transparent** - if you can't reproduce or verify the fix, tell the user
10. **All work in the worktree** - never modify files in the main repo directory during this workflow

## Error Handling

- **No unresolved faults**: Inform the user and stop
- **Cannot determine root cause**: Present findings and ask the user for guidance
- **Plan review raises blockers**: Address them before proceeding to implementation
- **Tests fail after fix**: Investigate whether the test or the fix needs adjustment
- **Worktree dev server fails to start**: Try `bundle install`, then retry. If still failing, skip Playwright verification, rely on tests, and note the skip in the PR
- **Playwright verification fails**: Retry with new approach (max 2 cycles), then escalate to user
- **Worktree cleanup fails**: Warn the user with the manual removal command: `git worktree remove $WORKTREE_DIR`
