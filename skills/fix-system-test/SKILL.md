---
name: fix-system-test
description: Fix System Test Command — debug failing/flaky system tests with Playwright and fix the test and/or application code
argument-hint: <spec-file-or-directory> [additional-failing-specs...]
---

# Fix System Test Command

You are an expert Rails system test debugger and fixer using Playwright with Capybara. Your goal is to analyze failing system tests, identify issues, and fix both the tests and underlying code to make tests pass while following established best practices for reliable, non-flaky tests.

**Reference Documentation:** This command follows the comprehensive guidance in `docs/SYSTEM_TEST_TROUBLESHOOTING.md`. Refer to this document for detailed troubleshooting patterns and examples.

## Input

You will receive one or more paths to system test files (or a directory). The user expects you to:
1. Run the test with Playwright and analyze failures
2. Debug the root causes using Playwright's superior debugging tools
3. Fix the tests and/or application code
4. Verify the fixes work consistently
5. Ensure all changes follow best practices for reliability

**Retry masking warning:** local runs retry system specs up to 2 times (`spec/support/rspec_retry.rb`),
so a flaky test can look green. Always diagnose and verify with retries disabled:
`CI=true USE_PLAYWRIGHT=true bundle exec rspec <file>`.

## Pipeline Mode (invoked from /build-feature or with multiple failing specs)

When given a batch of failing specs (e.g., from `system-test-expert`'s report or a suite run):

- **Read the test plan first** if one exists at `tmp/test-plans/*.md` — its "Handoff Notes for
  fix-system-test" predicts the likely root-cause categories per scenario, and its Async
  Boundaries Cheat Sheet names the waits the failing test probably lacks.
- **Fix serially, cheapest-diagnosis first**: group failures by error signature; one root cause
  (e.g., missing tenant setup in a shared `before`) often fixes several specs at once.
- **Budget: 3 fix attempts per test.** After 3 failed attempts, mark the test unfixable for now,
  record the failure output and your root-cause hypothesis, and move on. Report it — do NOT
  delete the test, do NOT skip/pend it silently, and do NOT loosen its assertions just to go
  green. The caller decides whether to ship with a known-failing test.
- **Distinguish test bugs from app bugs.** If the test is correct and the app is wrong, fix the
  app — and say so explicitly in the report (the caller may want a changelog entry). Never
  weaken a correct assertion to accommodate an app bug.
- **Verification scope in pipeline mode**: 3 consecutive clean runs per fixed test with
  `CI=true` (no retries), then one run of the feature's system-spec directory. Do not run the
  entire `spec/system/` suite mid-pipeline — that's the final CI gate's job.

## Process

### 1. Initial Analysis

First, examine the test file and run it with Playwright:

```bash
# Read the test file
# Run the specific test with Playwright enabled
USE_PLAYWRIGHT=true bundle exec rspec [test_file_path] --format documentation

# For visual debugging (non-headless):
HEADLESS=false USE_PLAYWRIGHT=true bundle exec rspec [test_file_path] --format documentation
```

Analyze the failure output for:
- Error messages and stack traces
- Specific assertions that are failing
- Timing issues (timeouts, race conditions)
- Element not found errors
- Stale element references
- JavaScript errors
- Network timing issues

### 2. Standards Compliance Check

Review the test against these standards from `docs/testing/system-testing-standards.md`:

#### Natural Browser Interactions
- ❌ **Avoid**: JavaScript event simulation (`page.execute_script`)
- ✅ **Use**: Natural Capybara methods (`fill_in`, `select`, `check`, `click_button`)
- ✅ **Use**: Semantic finders (`find_field`, `find_link`, `find_button`)

#### Proper Waiting Strategies
- ❌ **Avoid**: Fixed sleeps (`sleep(1)`)
- ✅ **Use**: Expectations with wait times (`expect(page).to have_css('.element', wait: 3)`)
- ✅ **Use**: Negative matchers for disappearance (`expect(page).to have_no_css('.loading')`)
- ❌ **Never**: Negate positive predicates (`!page.has_css?('.loading')`) - doesn't wait properly

#### Field Identification
- ✅ **Always**: Use `page` object with helper methods (`page.has_field?()`)
- ✅ **Verify**: Field names match current form implementation
- ✅ **Use**: Specific selectors to avoid ambiguity

#### Form Interactions Best Practices

**Text Fields:**
```ruby
# ✅ GOOD - Natural form filling
fill_in 'First Name', with: 'John'
fill_in 'field_name', with: 'value'

# ❌ BAD - JavaScript event simulation
page.execute_script("document.querySelector('input').value = 'value'")
```

**Checkboxes and Radio Buttons:**
```ruby
# ✅ PREFERRED - Direct Capybara methods (most natural)
check 'Accept Terms'
uncheck 'Subscribe'
choose 'Payment Method'

# ✅ ALTERNATIVE - Keyboard navigation for problematic elements
checkbox = find('input[type="checkbox"][name="field_name"]', visible: :all)
checkbox.send_keys(' ')  # Space to toggle
```

**Dropdowns:**
```ruby
# ✅ GOOD - Natural selection
select 'Option Text', from: 'field_name'
expect(page).to have_select('field_name', selected: 'Option Text')
```

**Auto-save Triggers:**
```ruby
# ✅ GOOD - Natural trigger with tab
fill_in 'field', with: 'content'
find('textarea[name="field"]').send_keys(:tab)
expect(page).to have_css('.auto-save-indicator.saved', wait: 3)

# ❌ BAD - JavaScript event simulation
page.execute_script("document.querySelector('textarea').dispatchEvent(new Event('change'))")
```

#### Element Finding Best Practices

**Semantic Finders:**
```ruby
# ✅ PREFERRED - Semantic finders with filters
find_field('Email').value
find_field('Email', with: 'user@example.com')
find_field(id: 'my_field').value
find_link('Home', visible: :all)
find_button('Submit').click

# ✅ GOOD - Using keyword filters
find_field('email', disabled: false)
find_button('Submit', disabled: true)
find_link('Profile', href: '/profile')

# ✅ GOOD - Filter blocks for complex conditions
find_field('First Name'){ |el| el['data-xyz'] == '123' }
find('#img_loading'){ |img| img['complete'] == true }
```

**Visibility Options:**
```ruby
# Find both visible and hidden elements
find('div', visible: :all)

# Only hidden elements
find_link('Profile', visible: false)

# Only visible (default)
find('.modal', visible: true)
```

**Checked/Unchecked Fields:**
```ruby
# ✅ GOOD - Finding by checked state
find_field('terms', checked: true)
find_field('newsletter', checked: false)  # same as unchecked: true

# ✅ GOOD - Conditional checks
if page.find_field('terms', checked: true, wait: 0)
  # checkbox is checked
end
```

#### Waiting for Dynamic Content

**Stimulus Controllers:**
```ruby
# ✅ GOOD - Wait for controller to connect
expect(page).to have_css("[data-controller='component-name']", wait: 2)
expect(page).to have_css("[data-component-target='element']", wait: 2)
```

**Content and Elements:**
```ruby
# ✅ GOOD - Wait for content
expect(page).to have_content('Expected Text', wait: 3)
expect(page).to have_css('.loaded-class', wait: 2)
expect(page).to have_selector('table tr', wait: 2)

# ✅ GOOD - Wait for elements to disappear (IMPORTANT!)
expect(page).to have_no_css('.loading-spinner', wait: 3)  # Waits properly
expect(page).not_to have_css('.loading-spinner')  # Also waits properly

# ❌ BAD - Doesn't wait for disappearance
!page.has_css?('.loading-spinner')  # Wrong - doesn't wait!
```

**Auto-save and AJAX:**
```ruby
# ✅ GOOD - Wait for auto-save completion
fill_in 'field', with: 'content'
find('textarea[name="field"]').send_keys(:tab)
expect(page).to have_css('.auto-save-indicator.saved', wait: 3)

# Verify persistence
visit current_path
expect(find('textarea[name="field"]').value).to eq('content')
```

#### XPath Best Practices

```ruby
# ✅ CORRECT - Relative XPath within scopes
within(:xpath, './/body') do
  find(:xpath, './/script')  # .// searches within current context
  within(:xpath, './/table/tbody') do
    find(:xpath, './/tr[1]')
  end
end

# ❌ WRONG - Absolute XPath breaks scoping
within(:xpath, './/table') do
  find(:xpath, '//tr')  # Searches entire document, not within table!
end
```

#### Scoping with within

```ruby
# ✅ GOOD - Scope interactions
within("#session") do
  fill_in 'Email', with: 'user@example.com'
  fill_in 'Password', with: 'password'
end

within_fieldset('User Information') do
  fill_in 'Name', with: 'John Doe'
end

within_table('Results') do
  expect(page).to have_content('Total')
end

# ✅ GOOD - Scope by tab
within("[data-tab-id='settings']") do
  fill_in 'field', with: 'value'
end
```

#### Current Path Assertions

```ruby
# ✅ GOOD - Use matcher (respects waiting)
expect(page).to have_current_path('/dashboard')
expect(page).to have_current_path(user_path(user))

# ❌ AVOID - Direct comparison (doesn't wait for page load)
expect(current_path).to eq('/dashboard')
```

### 3. Identify Root Cause Category

**IMPORTANT:** Before proceeding, categorize the failure into one of these 7 common root causes. Understanding the pattern helps you apply the right fix.

#### Category 1: Stale Element References
**Symptoms:** `Selenium::WebDriver::StaleElementReferenceError`, "element is not attached to the page document"

**Cause:** Turbo Streams replace DOM elements. Stored element references become stale after DOM updates.

**Quick Check:**
```ruby
# Anti-pattern: Storing references across actions
composer = find('textarea')
click_button "Send"  # Triggers Turbo Stream
expect(composer.value).to be_blank  # FAILS - stale!
```

**Fix Pattern:**
```ruby
# ✅ Re-find elements after DOM updates
find('textarea').fill_in with: "Test"
click_button "Send"
wait_for_turbo_complete
expect(find('textarea').value).to be_blank  # Re-find!
```

#### Category 2: Insufficient Turbo/Stimulus Wait Times
**Symptoms:** "expected to find content but found nothing", works with `sleep 2`

**Cause:** Not waiting for Turbo Streams, Stimulus controllers, or network requests to complete.

**Quick Check:**
```ruby
# Missing waits after async operations
click_button "Send"
expect(page).to have_content("Success")  # Default 2s too short!
```

**Fix Pattern:**
```ruby
# ✅ Explicit waits with longer timeouts
click_button "Send"
expect(page).to have_content("Success", wait: 10)
wait_for_turbo_complete
expect(page).to have_css("[data-controller*='composer']", wait: 10)
```

#### Category 3: Database State Race Conditions
**Symptoms:** Database checks fail intermittently, wrong counts, `reload` doesn't help

**Cause:** Checking database before Turbo submission completes and database commits.

**Quick Check:**
```ruby
# Checking database too early
click_button "Save"
expect(page).to have_content("Saved")
treatment_plan.reload
expect(treatment_plan.diagnoses.count).to eq(2)  # FAILS!
```

**Fix Pattern:**
```ruby
# ✅ Wait for UI confirmation, then database state
click_button "Save"
expect(page).to have_content("Saved", wait: 10)
wait_for_turbo_complete
wait_for_association(treatment_plan, :diagnoses, timeout: 10)
treatment_plan.reload
expect(treatment_plan.diagnoses.count).to eq(2)
```

#### Category 4: Dynamic Content / Prefilling Race Conditions
**Symptoms:** Field value checks fail, "expected 'John' but was blank"

**Cause:** Checking fields before Stimulus prefill controllers populate them.

**Quick Check:**
```ruby
# Checking before prefill completes
visit demographics_step_path
expect(page).to have_field('First Name', with: client.first_name)  # FAILS - empty!
```

**Fix Pattern:**
```ruby
# ✅ Wait for prefill controller and field population
visit demographics_step_path
wait_for_stimulus_controller('prefill')
wait_for_fields_prefilled(['first_name', 'last_name'])
expect(page).to have_field('first_name', with: client.first_name)
```

#### Category 5: Browser Back Button Navigation
**Symptoms:** Back button doesn't reload page, Turbo doesn't trigger

**Cause:** Capybara's `page.go_back` doesn't trigger Turbo navigation properly.

**Quick Check:**
```ruby
# Using Capybara back button
page.go_back  # Doesn't trigger Turbo!
expect(page).to have_current_path(previous_path)  # FAILS
```

**Fix Pattern:**
```ruby
# ✅ Use Playwright native navigation
page.driver.with_playwright_page do |pw_page|
  pw_page.go_back
  pw_page.wait_for_load_state(state: 'domcontentloaded', timeout: 10_000)
end
expect(page).to have_css('form', wait: 10)
expect(page).to have_current_path(previous_path)
```

#### Category 6: Complex UI Interactions (Grids, Dropdowns)
**Symptoms:** Data attribute checks fail, CSS classes don't update, wrong selection counts

**Cause:** Checking data attributes/classes before Stimulus JavaScript completes.

**Quick Check:**
```ruby
# Checking immediately after click
monday_9am = find("[data-day='1'][data-time='09:00']")
monday_9am.click
expect(monday_9am["data-selected"]).to eq("true")  # FAILS!
```

**Fix Pattern:**
```ruby
# ✅ Wait for Stimulus controller and data attribute changes
wait_for_stimulus_controller('availability-grid')
slot = "[data-day='1'][data-time='09:00']"
find(slot).click
wait_for_data_attribute(slot, 'selected', 'true')
expect(page).to have_css("#{slot}.bg-primary", wait: 5)
```

#### Category 7: Multi-User / Invitation Workflows
**Symptoms:** Lists don't show new items, sidebar doesn't update, background job results missing

**Cause:** Multi-step workflows with background jobs, emails, and Turbo Stream updates.

**Quick Check:**
```ruby
# Checking lists without waiting for full workflow
click_button "Send Invitation"
expect(page).to have_content("Invitation sent")
expect(page).to have_css("#pending-list", text: invitation.email)  # FAILS!
```

**Fix Pattern:**
```ruby
# ✅ Wait for all async operations
click_button "Send Invitation"
expect(page).to have_content("Invitation sent", wait: 10)
wait_for_turbo_complete
within('[data-testid="pending-invitations"]') do
  expect(page).to have_content(invitation.email, wait: 10)
end
wait_for_database_record(Invitation, { email: invitation.email })
```

#### Category 8: Organization/Tenant Context Issues
**Symptoms:** "Tenant required" errors, redirect to login, data not found, authorization failures

**Cause:** Missing or incorrect organization/tenant setup in multi-tenant application.

**Quick Check:**
```ruby
# Missing tenant context
let(:user) { create(:user, :therapist) }

before do
  sign_in user  # FAILS - no tenant context set!
  visit dashboard_path
end
```

**Fix Pattern:**
```ruby
# ✅ Proper organization/tenant setup (Standard Pattern - use for 95% of tests)
let(:organization) { $default_organization }  # Use global default
let(:user) { create(:user, :therapist, organization: organization) }
let(:client) { create(:client, organization: organization) }

before do
  # Set tenant context (REQUIRED!)
  ActsAsTenant.current_tenant = organization

  # Use helper that handles subdomain + auth
  fast_sign_in(user, organization)
end

# ✅ Unique organization (for multi-tenant isolation testing)
let(:organization) { create(:organization, subdomain: "test-#{SecureRandom.hex(4)}") }
let(:user) { create(:user, :therapist, organization: organization) }

before do
  ActsAsTenant.current_tenant = organization
  Capybara.app_host = "http://#{organization.subdomain}.localhost:#{Capybara.server_port}"
  Capybara.always_include_port = true
  login_as(user, scope: :user)
  visit root_path
end

after do
  Capybara.app_host = nil
  Capybara.always_include_port = false
end
```

**Common Organization Mistakes:**
```ruby
# ❌ Forgot to set tenant
before do
  sign_in user  # Missing ActsAsTenant.current_tenant
end

# ❌ Didn't pass organization to factories
let(:client) { create(:client) }  # Client has no organization!

# ❌ Forgot subdomain context for browser
ActsAsTenant.current_tenant = organization
visit dashboard_path  # May redirect or fail

# ✅ Correct - use fast_sign_in helper
fast_sign_in(user, organization)  # Handles everything!
```

### 4. Capybara Best Practices from Official Docs

Based on the latest Capybara documentation:

#### Automatic Element Reloading
Capybara automatically reloads stale elements:
```ruby
# ✅ This works even if sidebar content changes asynchronously
sidebar = find('#sidebar')
expect(sidebar.find('h1')).to have_content('New Title')
```

#### Proper Waiting Behavior for Negative Assertions
```ruby
# Given a page where an 'a' tag is removed via AJAX after 1s
visit(some_path)

# ❌ WRONG - Returns false immediately, doesn't wait
!page.has_xpath?('a')  # Returns false right away

# ✅ CORRECT - Waits for element to disappear
page.has_no_xpath?('a')  # Waits and returns true after element is gone

# ✅ CORRECT - RSpec matchers (both wait properly)
expect(page).not_to have_xpath('a')
expect(page).to have_no_xpath('a')
```

#### Finding Collections
```ruby
# ✅ GOOD - Proper waiting behavior
all('div')  # Waits for at least one element (default)
all('div', minimum: 2, wait: 5)  # Waits up to 5s for 2+ elements
all('div', wait: false)  # Returns immediately, may be empty

# ✅ GOOD - Using first properly
first('div')  # Waits for at least one, raises error if not found
first('div', minimum: 0)  # Returns nil immediately if not found
```

#### Multiple Windows
```ruby
# ✅ GOOD - Handle new windows
new_window = window_opened_by do
  click_button 'Open in New Window'
end

within_window new_window do
  expect(page).to have_content('New Window Content')
  fill_in 'field', with: 'value'
end
```

#### JavaScript Dialogs
```ruby
# ✅ GOOD - Handle confirms
accept_confirm do
  click_button 'Delete'
end

dismiss_confirm do
  click_button 'Cancel Action'
end

# ✅ GOOD - Handle prompts with input
accept_prompt(with: 'New Name') do
  click_link 'Rename'
end

# ✅ GOOD - Capture dialog messages
message = accept_confirm do
  click_button 'Submit'
end
expect(message).to eq('Are you sure?')
```

### 4. Helper Methods Reference

**Location:** `spec/support/browser_helpers.rb` and `spec/support/database_helpers.rb`

**IMPORTANT:** Always use these helpers instead of writing custom wait logic. They implement best practices with proper retry logic and error handling.

#### Turbo/Network Helpers

**`wait_for_turbo_complete(timeout: 10)`** - Waits for Turbo navigation and network idle
```ruby
click_button "Submit"
wait_for_turbo_complete
expect(page).to have_content("Success")
```

**`wait_for_turbo_stream_update(target_id, timeout: 10)`** - Waits for specific Turbo Stream target
```ruby
click_button "Add Item"
wait_for_turbo_stream_update('items-list')
expect(page).to have_css("#items-list .item", count: 5)
```

**`wait_for_turbo_frame_load(frame_id, timeout: 10)`** - Waits for Turbo Frame to load
```ruby
click_link "Load More"
wait_for_turbo_frame_load('messages-frame')
expect(page).to have_css("#messages-frame .message", minimum: 10)
```

#### Database State Helpers

**`wait_for_database_record(model, conditions, timeout: 10)`** - Waits for record to exist
```ruby
click_button "Send Message"
expect(page).to have_content("Message sent", wait: 10)
wait_for_database_record(Message, { content: "Test", user: current_user })
```

**`wait_for_record_count(relation, expected_count, timeout: 10)`** - Waits for specific count
```ruby
3.times { click_button "Add" }
wait_for_record_count(treatment_plan.diagnoses, 3)
expect(treatment_plan.diagnoses.count).to eq(3)
```

**`wait_for_record_state(record, attribute, value, timeout: 10)`** - Waits for attribute value
```ruby
click_button "Sign"
wait_for_record_state(document, :status, 'signed')
document.reload
expect(document.status).to eq('signed')
```

**`wait_for_association(record, association_name, timeout: 10)`** - Waits for association to exist
```ruby
click_button "Save"
expect(page).to have_current_path(next_path, wait: 10)
wait_for_association(treatment_plan, :diagnoses)
treatment_plan.reload
expect(treatment_plan.diagnoses).to be_present
```

#### Form/Field Helpers

**`wait_for_field_prefill(field_name, timeout: 10)`** - Waits for field to be prefilled
```ruby
visit demographics_step_path
wait_for_stimulus_controller('prefill')
wait_for_field_prefill('first_name')
expect(find_field('first_name').value).to eq(client.first_name)
```

**`wait_for_fields_prefilled(field_names, timeout: 10)`** - Waits for multiple fields
```ruby
visit health_info_step_path
wait_for_stimulus_controller('prefill')
wait_for_fields_prefilled(['medications', 'allergies', 'medical_history'])
```

**`wait_for_field_value(field_name, expected_value, timeout: 10)`** - Waits for specific value
```ruby
select 'Dr. Smith', from: 'Provider'
wait_for_field_value('provider_id', provider.id.to_s)
```

#### Stimulus Controller Helpers

**`wait_for_stimulus_controller(controller_name, timeout: 10)`** - Waits for controller connection
```ruby
visit availability_path
wait_for_stimulus_controller('availability-grid')
find('.time-slot[data-time="09:00"]').click
```

**`wait_for_stimulus_controllers(*controller_names, timeout: 10)`** - Waits for multiple controllers
```ruby
visit complex_page_path
wait_for_stimulus_controllers('dropdown', 'modal', 'tooltip')
```

**`expect_stimulus_action(selector, action_name)`** - Verifies action binding
```ruby
expect_stimulus_action('.toggle-button', 'dropdown#toggle')
```

#### Data Attribute Helpers

**`wait_for_data_attribute(selector, attribute, value, timeout: 10)`** - Waits for data attribute value
```ruby
find('.time-slot[data-time="09:00"]').click
wait_for_data_attribute('.time-slot[data-time="09:00"]', 'selected', 'true')
```

**`wait_for_data_attribute_present(selector, attribute, timeout: 10)`** - Waits for attribute to exist
```ruby
click_button "Load Item"
wait_for_data_attribute_present('.item', 'id')
item_id = find('.item')['data-id']
```

### 5. Error Message Interpretation Guide

When tests fail, these error patterns indicate specific root causes:

#### "Stale Element Reference"
```
Selenium::WebDriver::Error::StaleElementReferenceError:
  stale element reference: element is not attached to the page document
```
**Meaning:** Stored element reference, then Turbo replaced it
**Fix:** Don't store references. Re-find after actions.

#### "Element Not Found"
```
Capybara::ElementNotFound:
  Unable to find visible css ".selector"
```
**Possible Causes:**
- Turbo Stream hasn't updated DOM yet → Add `wait: 10`
- Stimulus controller hasn't rendered → Wait for controller
- Element is hidden by CSS → Use `visible: :all`
- Wrong selector → Verify selector
**Fix:** Add waits, check Turbo completion, verify selector

#### "Content Not Found"
```
Failure/Error: expect(page).to have_content("Success")
  expected to find text "Success" in "..."
```
**Possible Causes:**
- Turbo Stream response hasn't arrived → Wait for Turbo
- Flash message already dismissed → Check timing
- Wrong expectation → Verify content actually renders
**Fix:** Add `wait: 10`, check Turbo completion

#### "Ambiguous Match"
```
Capybara::Ambiguous:
  Ambiguous match, found 2 elements matching css ".button"
```
**Meaning:** Multiple elements match selector
**Fix:** Use more specific selector or scope with `within`:
```ruby
within('#modal') do
  click_button 'Submit'
end
```

#### "Wrong Count"
```
Failure/Error: expect(page).to have_css('.item', count: 3)
  expected to find visible css ".item" 3 times but found it 2 times
```
**Possible Causes:**
- Turbo Stream hasn't added item yet → Add `wait: 10`
- Database record not created yet → Use database helpers
- Wrong expectation → Verify expected count
**Fix:** Add waits, use database helpers

#### "Timeout Waiting"
```
Selenium::WebDriver::Error::TimeoutError:
  Timed out after 10 seconds
```
**Possible Causes:**
- Network request failed → Check browser console
- JavaScript error prevented update → Check console logs
- Wrong condition → Verify what you're waiting for
- Need longer timeout → Increase if legitimate
**Fix:** Check browser console, verify network requests, increase timeout

### 6. Common Issues and Playwright-Enhanced Fixes

#### Issue: Element Not Found
**Symptoms:** `Capybara::ElementNotFound` error

**Debug with Playwright:**
```ruby
# Check if element exists with different visibility
if page.has_css?('.element', visible: :all)
  puts "Element exists but may be hidden"
end

# Use Playwright trace to see exact DOM state
page.driver.trace(screenshots: true, snapshots: true, path: 'tmp/debug-trace.zip') do
  visit '/page'
  # Action that fails
end

# Check page HTML
puts page.html
save_screenshot('debug.png')

# Use Playwright's wait for selector with states
page.driver.with_playwright_page do |pw_page|
  pw_page.wait_for_selector('.element', state: 'visible', timeout: 5000)
end
```

**Fixes:**
- Verify field names match current implementation using browser dev tools
- Add appropriate wait times for dynamic content
- Use `visible: :all` if element might be hidden
- Check for correct scoping with `within`
- Use Playwright's `wait_for_load_state('networkidle')` for AJAX-heavy pages

#### Issue: Timing/Race Conditions
**Symptoms:** Intermittent failures, "element not visible" errors

**Playwright-Enhanced Fixes:**
```ruby
# ❌ BAD - Fixed sleeps
fill_in 'field', with: 'value'
sleep(1)

# ✅ GOOD - Wait for specific conditions
fill_in 'field', with: 'value'
expect(page).to have_css('.saved-indicator', wait: 3)

# ✅ GOOD - Wait for Stimulus controller
expect(page).to have_css("[data-controller='auto-save']", wait: 2)

# ✅ BETTER - Use Playwright's network idle for AJAX-heavy pages
fill_in 'field', with: 'value'
wait_for_network_idle  # Browser helper method
expect(page).to have_css('.saved-indicator')

# ✅ BEST - Combine Capybara waits with Playwright network idle
visit '/dashboard'
wait_for_network_idle
expect(page).to have_css('.data-loaded', wait: 2)
```

#### Issue: Stale Element Reference
**Symptoms:** `Selenium::WebDriver::Error::StaleElementReferenceError` or `Playwright::Error`

**Note:** Playwright handles stale elements better than Selenium, but you should still follow best practices.

**Fix:**
```ruby
# ❌ BAD - Storing element reference across page changes
button = find('button', text: 'Submit')
page.refresh
button.click  # Error!

# ✅ GOOD - Re-find elements after page changes
page.refresh
find('button', text: 'Submit').click

# ✅ GOOD - Let Capybara handle it automatically (works with Playwright)
expect(find('#sidebar').find('h1')).to have_content('New Title')

# ✅ PLAYWRIGHT ADVANTAGE - Auto-reload with waiting
# Playwright automatically handles most stale element scenarios
page.driver.with_playwright_page do |pw_page|
  pw_page.wait_for_load_state('domcontentloaded')
end
```

#### Issue: Click Interception
**Symptoms:** "element click intercepted" errors

**Fixes:**
```ruby
# ✅ Try keyboard navigation first
button = find('button', text: 'Submit')
button.send_keys(:return)

# ✅ Or scroll element into view
element = find('.element')
element.scroll_to(:center)
element.click

# ✅ Or wait for overlays to disappear
expect(page).to have_no_css('.modal-overlay', wait: 3)
click_button 'Submit'
```

#### Issue: Form Field Not Updating
**Symptoms:** Values not being set, auto-save not triggering

**Fixes:**
```ruby
# ✅ GOOD - Use tab to trigger blur/change events
fill_in 'field', with: 'value'
find('input[name="field"]').send_keys(:tab)

# ✅ GOOD - Wait for auto-save indicator
expect(page).to have_css('.auto-save-indicator.saved', wait: 3)
```

#### Issue: Incorrect Field Names
**Symptoms:** Field not found errors

**Debug:**
```bash
# Check actual form implementation in browser dev tools
# or examine the view file
```

**Fix:**
```ruby
# ❌ BAD - Outdated field name
fill_in 'old_field_name', with: 'value'

# ✅ GOOD - Correct field name matching form
fill_in 'clinical_document[completion_data][field_name]', with: 'value'
```

### 5. Playwright-Specific Debugging Tools

Playwright provides superior debugging capabilities. Use these tools when analyzing failures:

#### Playwright Traces (Most Powerful Debug Tool)
```ruby
# Use Playwright traces for comprehensive debugging
# Traces capture screenshots, network activity, console logs, and DOM snapshots

# Option 1: Programmatic trace control in test
it 'completes the workflow', :playwright do
  page.driver.trace(screenshots: true, snapshots: true, path: 'tmp/playwright-traces/test-trace.zip') do
    visit '/page'
    # ... test actions ...
  end
end

# Option 2: Using browser helpers
it 'completes the workflow', :playwright do
  start_playwright_trace(name: 'workflow')
  # ... test actions ...
  stop_playwright_trace(name: 'workflow')
end

# View trace with: npx playwright show-trace tmp/playwright-traces/[trace-file].zip
# Trace viewer shows: timeline, screenshots, network, console, DOM snapshots
```

#### Network Idle Waiting (Playwright Advantage)
```ruby
# Wait for all network activity to complete (more reliable than fixed waits)
def wait_for_network_idle(wait: 10)
  page.driver.with_playwright_page do |pw_page|
    pw_page.wait_for_load_state('networkidle', timeout: wait * 1000)
  end
end

# Use in tests for AJAX-heavy pages
visit '/dashboard'
wait_for_network_idle
expect(page).to have_content('Data loaded')
```

#### Visual Debugging
```ruby
# Standard Capybara debugging (works with Playwright)
save_and_open_page  # Opens HTML in browser
save_and_open_screenshot  # Opens screenshot

# Playwright-specific screenshot with custom name
save_test_screenshot('debug-point-1')  # Uses browser helper

# Full page screenshot (captures entire scrollable page)
page.save_screenshot('full-page.png', full_page: true)
```

#### Programmatic Debugging
```ruby
# Standard debugging
puts page.html  # Full page HTML
puts page.title  # Page title
puts current_url  # Current URL
page.save_screenshot('debug.png')

# Element inspection
element = find('#target')
puts element['class']  # Get attribute
puts element.text  # Visible text
puts element.value  # Form field value
puts element.disabled?  # Check if disabled
puts element.visible?  # Check if visible

# Check for elements without waiting
if page.has_css?('.element', wait: 0)
  puts "Element is present"
end

# Access Playwright page object for advanced debugging
page.driver.with_playwright_page do |pw_page|
  # Get console messages
  puts pw_page.evaluate('() => console.log("Debug message")')

  # Check network state
  pw_page.wait_for_load_state('domcontentloaded')

  # Evaluate JavaScript
  result = pw_page.evaluate('() => window.someGlobalVar')
  puts "Global var: #{result}"
end
```

#### Quick Debugging Commands Reference

Use these commands to quickly diagnose issues:

```ruby
# Screenshot debugging
save_screenshot('tmp/debug.png')                    # Save current state
save_screenshot('tmp/debug.png', full: true)        # Full page screenshot
save_and_open_screenshot                            # Save and open in browser

# HTML inspection
save_page('tmp/debug.html')                         # Save page HTML
puts page.html                                       # Print full HTML
puts page.text                                       # Print visible text

# Path and URL inspection
puts "Current path: #{page.current_path}"
puts "Current URL: #{current_url}"

# Element existence checks (no wait)
puts "Element exists: #{page.has_css?('.selector', wait: 0)}"
puts "Content exists: #{page.has_content?('Text', wait: 0)}"

# Print all matching elements
puts "All items: #{page.all('.item').map(&:text).inspect}"

# Element attribute inspection
element = find('.target')
puts "Element classes: #{element[:class]}"
puts "Data attribute: #{element['data-selected']}"

# Browser console messages (Playwright)
page.driver.with_playwright_page do |pw_page|
  console_messages = pw_page.console_messages
  puts "=== BROWSER CONSOLE ==="
  console_messages.each do |msg|
    puts "[#{msg.type}] #{msg.text}"
  end
end

# Network request tracking (Playwright)
page.driver.with_playwright_page do |pw_page|
  requests = []
  pw_page.on('request', ->(request) {
    requests << { method: request.method, url: request.url }
  })
  # Perform actions
  click_button "Submit"
  # Print requests
  puts "Network requests made:"
  requests.each { |r| puts "#{r[:method]} #{r[:url]}" }
end

# Stimulus controller connection check
def stimulus_controller_connected?(name)
  page.has_css?("[data-controller*='#{name}']", wait: 0)
end
puts "Prefill controller connected: #{stimulus_controller_connected?('prefill')}"

# Step-by-step debugging
binding.pry  # Pause execution
# In pry console:
#   page.html
#   page.save_screenshot('tmp/debug.png')
#   page.find('.selector').text
```

#### Automatic Failure Diagnostics

When tests fail, check these locations for automatic diagnostics:

- **Screenshots**: `/tmp/capybara/failures_<timestamp>/`
- **Page HTML**: Look for `.html` files alongside screenshots
- **Videos** (if enabled): `tmp/videos/`
- **Traces** (if enabled): `tmp/traces/` or `tmp/playwright-traces/`

**View Playwright traces:**
```bash
npx playwright show-trace tmp/traces/[trace-file].zip
# Shows: timeline, screenshots, network, console, DOM snapshots
```

#### Video Recording for Flaky Tests
```ruby
# Enable video recording in Playwright config (already configured)
# Videos saved to tmp/videos/ when RECORD_VIDEO=true

# Run test with video recording:
# RECORD_VIDEO=true USE_PLAYWRIGHT=true bundle exec rspec [test_file_path]

# Useful for debugging intermittent failures
```

#### Pause for Manual Inspection (Development Only)
```ruby
# Playwright pause (opens inspector)
page.driver.with_playwright_page do |pw_page|
  pw_page.pause  # Opens Playwright Inspector for manual debugging
end

# Or use the debug helper (defined in spec/support/browser_helpers.rb)
pause_for_inspection("Check the form state")  # Only works when DEBUG=true
```

### 6. Playwright-Specific Best Practices for Reliability

When fixing tests with Playwright, leverage these capabilities for maximum reliability:

#### Use Network Idle for AJAX-Heavy Pages
```ruby
# ✅ Best practice for pages with heavy AJAX/fetch activity
visit '/dashboard'
wait_for_network_idle  # Waits for all network requests to complete
expect(page).to have_content('Data loaded')

# Example: Auto-save form
fill_in 'notes', with: 'Important information'
find('textarea[name="notes"]').send_keys(:tab)
wait_for_network_idle  # Better than waiting for visual indicator alone
expect(page).to have_css('.auto-save-indicator.saved')
```

#### Use Turbo-Specific Waiting
```ruby
# For Turbo Drive navigation
click_link 'Dashboard'
wait_for_turbo  # Uses Playwright's network idle
expect(page).to have_current_path('/dashboard')

# For Turbo Frames
within('#user-details-frame') do
  click_button 'Edit'
  wait_for_network_idle
  expect(page).to have_field('Name')
end
```

#### Leverage Playwright Locators for Complex Selectors
```ruby
# When standard Capybara finders are insufficient
page.driver.with_playwright_page do |pw_page|
  # Use semantic locators
  pw_page.get_by_label('Email').fill('test@example.com')
  pw_page.get_by_role('button', name: 'Submit').click

  # Use text content
  pw_page.get_by_text('Welcome back').visible?

  # Use test IDs
  pw_page.get_by_test_id('submit-button').click
end
```

#### Use Traces for Debugging Flaky Tests
```ruby
# Wrap flaky test sections in traces
it 'performs complex workflow', :playwright do
  # Trace only the problematic section
  page.driver.trace(screenshots: true, snapshots: true, path: 'tmp/traces/workflow.zip') do
    visit '/complex-page'
    # Complex interactions that sometimes fail
    fill_in 'field', with: 'value'
    click_button 'Process'
    wait_for_network_idle
  end

  # Review trace: npx playwright show-trace tmp/traces/workflow.zip
  # Look for: network delays, element timing, console errors
end
```

#### Handle File Downloads with Playwright
```ruby
# Playwright handles downloads better than Selenium
page.driver.with_playwright_page do |pw_page|
  download = pw_page.expect_download do
    click_button 'Download Report'
  end

  # Save and verify file
  download.save_as('/tmp/report.pdf')
  expect(File.exist?('/tmp/report.pdf')).to be true
end
```

#### Intercept Network Requests for Testing
```ruby
# Mock API responses in system tests (use sparingly)
page.driver.with_playwright_page do |pw_page|
  pw_page.route('**/api/external-service', ->(route) {
    route.fulfill(
      status: 200,
      body: '{"status": "success"}'
    )
  })

  visit '/page-using-api'
  expect(page).to have_content('success')
end
```

### 7. Fix Application Code When Needed

Sometimes the test is correct but the application code has issues:

#### Check for:
1. **Missing HTML attributes:** data-controller, data-target, id, name attributes
2. **JavaScript errors:** Check browser console in test output
3. **Missing validations:** Check model validations match test expectations
4. **Incorrect routes:** Verify routes exist and point to correct actions
5. **Authorization issues:** Check Pundit policies allow the action
6. **Form field names:** Ensure form fields have correct name attributes
7. **Auto-save implementation:** Verify Stimulus controllers are working

#### Common Application Code Fixes:

**Missing Stimulus Controller:**
```erb
<%# ❌ BAD - Missing data-controller %>
<div>
  <input type="text" name="field">
</div>

<%# ✅ GOOD - With Stimulus controller %>
<div data-controller="auto-save">
  <input type="text" name="field" data-auto-save-target="input">
</div>
```

**Incorrect Form Field Names:**
```erb
<%# ❌ BAD - Incorrect or missing name attribute %>
<%= f.text_field :field_name %>  <%# Might not have right namespace %>

<%# ✅ GOOD - Correct nested field name %>
<%= f.fields_for :completion_data do |cd| %>
  <%= cd.text_field :field_name %>  <%# Generates: model[completion_data][field_name] %>
<% end %>
```

**Missing IDs or Classes:**
```erb
<%# ❌ BAD - No identifiers %>
<button>Submit</button>

<%# ✅ GOOD - With identifiers for testing %>
<button id="submit-button" class="btn-primary" data-testid="submit">Submit</button>
```

### 8. When to Use Playwright-Specific Features

**Use Standard Capybara when:**
- Simple page interactions (clicks, form fills)
- No complex AJAX or network activity
- Test is already reliable
- No timing issues

**Use Playwright Features when:**
- Heavy AJAX/fetch activity (use `wait_for_network_idle`)
- Flaky tests need debugging (use traces)
- Need to inspect network requests (use traces)
- File downloads involved (use Playwright download API)
- Need precise timing control (use Playwright waits)
- Turbo/Hotwire applications (use `wait_for_turbo`)

**General Rule:** Start with standard Capybara. Add Playwright features when needed for reliability or debugging.

### 9. Verification with Playwright

After making fixes, verify thoroughly using Playwright:

1. **Run the test multiple times with Playwright** to ensure reliability. Always include
`CI=true` so rspec-retry can't mask flakiness (local runs otherwise retry 2 times):
```bash
# Run 3-5 times to check for flakiness with Playwright (retries disabled)
for i in {1..5}; do
  echo "=== RUN $i ==="
  CI=true USE_PLAYWRIGHT=true bundle exec rspec [test_file_path] --format documentation
done

# For more comprehensive verification with tracing on failures:
for i in {1..5}; do
  echo "=== RUN $i ==="
  CI=true USE_PLAYWRIGHT=true RECORD_VIDEO=true bundle exec rspec [test_file_path] --format documentation
done
```

2. **Check test follows all standards:**
   - No JavaScript event simulation (use Capybara methods)
   - No fixed sleeps (use expectations with wait times or network idle)
   - Uses expectations with wait times
   - Uses semantic finders
   - Proper `page.` prefix on helper methods
   - Uses `have_no_*` matchers for disappearance
   - Uses `have_current_path` for path assertions
   - Uses Playwright-specific helpers when appropriate (network idle, traces)

3. **Verify related tests still pass with Playwright:**
```bash
# Run all tests in the same directory with Playwright
USE_PLAYWRIGHT=true bundle exec rspec spec/system/[feature_name]/ --format documentation

# Standalone use only (NOT in pipeline mode): full system suite as a comprehensive check
USE_PLAYWRIGHT=true bundle exec rspec spec/system/ --format documentation
```

4. **Test performance and reliability:**
   - Test should complete in reasonable time
   - No unnecessary waits or delays
   - Database queries optimized
   - Check Playwright traces for any timing issues
   - Verify network idle is used appropriately for AJAX-heavy pages

5. **Playwright-specific verification:**
   - Check that automatic screenshot on failure is working (screenshots in tmp/capybara/)
   - Verify traces are being generated when enabled
   - Ensure no browser console errors (check traces)
   - Validate network requests are completing properly (check traces)

### 9a. Quick Reference Checklist

Before considering a test fixed, verify ALL of the following:

#### When Test Fails Intermittently

**Check for stale elements:**
- [ ] No stored element references across actions
- [ ] Re-find elements after Turbo operations
- [ ] Let Capybara handle automatic refinding

**Check wait times:**
- [ ] Use `wait: 10` on expectations after async operations
- [ ] Wait for Turbo completion with `wait_for_turbo_complete`
- [ ] Wait for Stimulus controllers with `wait_for_stimulus_controller`
- [ ] Use helper methods instead of custom waits

**Check database timing:**
- [ ] Use database wait helpers (`wait_for_database_record`, etc.)
- [ ] Wait for UI confirmation before database checks
- [ ] Reload inside wait blocks, not before
- [ ] Check existence first, then specific values

**Check prefilling:**
- [ ] Wait for prefill controller connection
- [ ] Wait for fields to be populated before checking values
- [ ] Use `wait_for_fields_prefilled` helper
- [ ] Handle missing data gracefully

**Check data attributes:**
- [ ] Wait for attribute changes with `wait_for_data_attribute`
- [ ] Handle stale elements in wait blocks
- [ ] Verify both data attribute AND visual changes
- [ ] Check related UI updates (counters, labels)

**Check browser navigation:**
- [ ] Use Playwright native back/forward navigation
- [ ] Wait for DOM content loaded after navigation
- [ ] Verify page elements after navigation
- [ ] Consider Turbo cache effects

#### After Fixing a Test

**Stability verification:**
- [ ] Passes 10 consecutive times locally
- [ ] Passes 5 consecutive times in CI (if applicable)
- [ ] No stale element errors in logs
- [ ] No timing-related failures in screenshots
- [ ] Database assertions succeed consistently

**Run verification script** (10 runs standalone; 3 runs in pipeline mode — `CI=true` always,
so retries can't mask a flake):
```bash
for i in {1..10}; do
  echo "=== RUN $i ==="
  CI=true USE_PLAYWRIGHT=true bundle exec rspec path/to/spec.rb:42
  if [ $? -ne 0 ]; then
    echo "FAILED on run $i"
    exit 1
  fi
done
echo "All 10 runs passed!"
```

#### Common Wait Patterns to Apply

```ruby
# After Turbo action
click_button "Submit"
expect(page).to have_content("Success", wait: 10)
wait_for_turbo_complete

# Before checking fields
wait_for_stimulus_controller('prefill')
wait_for_fields_prefilled(['field1', 'field2'])

# Before checking database
expect(page).to have_current_path(next_path, wait: 10)
wait_for_database_record(Model, { attribute: value })

# Before checking data attributes
find('.element').click
wait_for_data_attribute('.element', 'selected', 'true')

# After browser navigation
page.driver.with_playwright_page { |pw| pw.go_back; pw.wait_for_load_state('domcontentloaded') }
expect(page).to have_css('form', wait: 10)
```

#### Root Cause Categories Checklist

Identify which category applies to your test failure:
- [ ] Category 1: Stale Element References
- [ ] Category 2: Insufficient Turbo/Stimulus Wait Times
- [ ] Category 3: Database State Race Conditions
- [ ] Category 4: Dynamic Content / Prefilling Race Conditions
- [ ] Category 5: Browser Back Button Navigation
- [ ] Category 6: Complex UI Interactions (Grids, Dropdowns)
- [ ] Category 7: Multi-User / Invitation Workflows
- [ ] Category 8: Organization/Tenant Context Issues

#### Helper Methods Usage Checklist

Verify you're using the right helpers:
- [ ] `wait_for_turbo_complete` after Turbo actions
- [ ] `wait_for_turbo_stream_update` for specific Turbo Stream targets
- [ ] `wait_for_database_record` before database assertions
- [ ] `wait_for_association` for association checks
- [ ] `wait_for_stimulus_controller` before Stimulus interactions
- [ ] `wait_for_fields_prefilled` for prefilled form fields
- [ ] `wait_for_data_attribute` for data attribute changes

#### Standards Compliance Checklist

- [ ] Uses natural browser interactions (no `page.execute_script` for forms)
- [ ] Uses semantic finders (`find_field`, `find_link`, `find_button`)
- [ ] Uses expectations with wait times (no fixed `sleep()`)
- [ ] Uses `have_no_*` matchers for element disappearance
- [ ] Uses `page.` prefix for all helper methods
- [ ] Uses `have_current_path` matcher for path assertions
- [ ] Uses `within` for scoping when appropriate
- [ ] Uses relative XPath (`.//`) within scopes
- [ ] Proper auto-save testing with indicators
- [ ] Clear, descriptive test names

#### Playwright-Specific Checklist

- [ ] Uses `wait_for_network_idle` for AJAX-heavy pages
- [ ] Uses `wait_for_turbo` for Turbo/Hotwire navigation
- [ ] Leverages traces for debugging flaky tests
- [ ] Automatic screenshots on failure working
- [ ] Checks browser console for errors (via traces)
- [ ] Uses browser helpers when appropriate
- [ ] Avoids fixed waits when network idle available

### 10. Documentation

After fixing, provide:

1. **Summary of issues found:**
   - What was failing and why
   - Root cause analysis

2. **Changes made:**
   - List of test changes with explanations
   - List of application code changes (if any)
   - Standards compliance improvements

3. **Verification results:**
   - Test run output showing passes
   - Any remaining concerns or follow-up needed

## Output Format

Provide your analysis and fixes in this format:

```markdown
## Test Analysis

**Test File:** [path]
**Initial Status:** [passing/failing]
**Issues Found:** [count]

### Issues Identified

1. **[Issue Type]** - [Description]
   - Location: [file:line]
   - Problem: [explanation]
   - Standard Violated: [standard]

[Repeat for each issue]

## Fixes Applied

### Test Changes

1. **[Description of change]**
   - File: [path]
   - Change: [what was changed]
   - Reason: [why this fix was needed]
   - Standard: [which standard this addresses]

### Application Code Changes (if any)

1. **[Description of change]**
   - File: [path]
   - Change: [what was changed]
   - Reason: [why this fix was needed]

## Verification

**Test Runs:** [X/5 passed]
**Performance:** [time taken]
**Related Tests:** [all passing/some failing]

## Recommendations

[Any follow-up items, refactoring suggestions, or additional improvements]
```

## Best Practices Checklist

Before completing, verify the test follows ALL these practices:

### Standard Capybara Practices
- [ ] Uses natural browser interactions (no `page.execute_script` for forms)
- [ ] Uses semantic finders (`find_field`, `find_link`, `find_button`)
- [ ] Uses expectations with wait times (no fixed `sleep()`)
- [ ] Uses `have_no_*` matchers for element disappearance (not `!has_*?`)
- [ ] Uses `page.` prefix for all helper methods
- [ ] Uses keyword filters (`disabled:`, `checked:`, `visible:`) appropriately
- [ ] Uses `within` for scoping when appropriate
- [ ] Uses relative XPath (`.//`) within scopes, not absolute (`//`)
- [ ] Uses `have_current_path` matcher for path assertions
- [ ] Verifies database state with `.reload`
- [ ] Tests real user interactions (tab, blur, etc.)
- [ ] Proper auto-save testing with indicators
- [ ] Clear, descriptive test names and contexts
- [ ] Reusable helper methods for common actions
- [ ] Minimal database hits (uses `build` when possible)
- [ ] Deterministic test data (sequences, not random)
- [ ] Tests both happy path and error scenarios
- [ ] Proper cleanup (uses transactional fixtures or DatabaseCleaner)
- [ ] Uses `:playwright` metadata for system tests

### Playwright-Specific Practices
- [ ] Uses `wait_for_network_idle` for AJAX-heavy pages
- [ ] Uses `wait_for_turbo` for Turbo/Hotwire navigation
- [ ] Leverages Playwright traces for debugging flaky tests
- [ ] Uses automatic screenshot on failure (configured by default)
- [ ] Considers video recording for intermittent failures
- [ ] Uses Playwright's `with_playwright_page` only when necessary
- [ ] Avoids fixed waits when network idle is available
- [ ] Checks traces for network delays and console errors
- [ ] Uses browser helpers (`wait_for_network_idle`, `wait_for_turbo`, etc.)
- [ ] Runs test with `USE_PLAYWRIGHT=true` for verification

## Examples of Good Fixes

### Playwright-Specific Examples

#### Example 1: Fixed Sleep to Network Idle (Playwright)

```ruby
# ❌ BEFORE
visit '/dashboard'
sleep(2)  # Wait for AJAX to complete
expect(page).to have_content('Data loaded')

# ✅ AFTER (Playwright)
visit '/dashboard'
wait_for_network_idle  # Waits for all network requests
expect(page).to have_content('Data loaded')
```

#### Example 2: Fixed Flaky Test with Traces (Playwright)

```ruby
# ❌ BEFORE - Flaky test without debugging info
it 'completes workflow' do
  visit '/complex-page'
  fill_in 'field', with: 'value'
  click_button 'Submit'  # Sometimes fails
  expect(page).to have_content('Success')
end

# ✅ AFTER - With Playwright traces for debugging
it 'completes workflow', :playwright do
  page.driver.trace(screenshots: true, snapshots: true, path: 'tmp/traces/workflow.zip') do
    visit '/complex-page'
    wait_for_network_idle
    fill_in 'field', with: 'value'
    click_button 'Submit'
    wait_for_network_idle
  end
  expect(page).to have_content('Success')

  # View trace: npx playwright show-trace tmp/traces/workflow.zip
end
```

#### Example 3: Fixed Turbo Navigation Timing (Playwright)

```ruby
# ❌ BEFORE - Unreliable Turbo navigation
click_link 'Dashboard'
expect(page).to have_content('Dashboard')

# ✅ AFTER - With proper Turbo waiting
click_link 'Dashboard'
wait_for_turbo  # Uses network idle
expect(page).to have_current_path('/dashboard')
expect(page).to have_content('Dashboard')
```

### Standard Capybara Examples

### Example 1: Fixed Sleep to Expectation

```ruby
# ❌ BEFORE
fill_in 'field', with: 'value'
sleep(1)
expect(page).to have_content('Saved')

# ✅ AFTER
fill_in 'field', with: 'value'
find('input[name="field"]').send_keys(:tab)
expect(page).to have_css('.auto-save-indicator.saved', wait: 3)
expect(page).to have_content('Saved')
```

### Example 2: Fixed JavaScript Event to Natural Interaction

```ruby
# ❌ BEFORE
page.execute_script("
  document.querySelector('input[name=\"date\"]').value = '2024-12-25';
  document.querySelector('input[name=\"date\"]').dispatchEvent(new Event('change'));
")

# ✅ AFTER
fill_in 'date', with: '2024-12-25'
find('input[name="date"]').send_keys(:tab)  # Trigger blur if needed
```

### Example 3: Fixed Incorrect Helper Method Usage

```ruby
# ❌ BEFORE
if has_field?('field_name')  # Error: method not found or doesn't wait
  fill_in 'field_name', with: 'value'
end

# ✅ AFTER
if page.has_field?('field_name')  # Correct: uses page object and waits
  fill_in 'field_name', with: 'value'
end
```

### Example 4: Fixed Negative Assertion Waiting

```ruby
# ❌ BEFORE
click_button 'Delete'
loop do
  break unless page.has_css?('.item')  # Doesn't wait properly
  sleep 0.1
end

# ✅ AFTER
click_button 'Delete'
expect(page).to have_no_css('.item', wait: 5)  # Waits properly for element to disappear
```

### Example 5: Fixed Click Interception

```ruby
# ❌ BEFORE
find('button', text: 'Submit').click  # Fails with click intercepted

# ✅ AFTER
button = find('button', text: 'Submit')
button.send_keys(:return)  # Use keyboard navigation instead
```

### Example 6: Fixed Semantic Finders

```ruby
# ❌ BEFORE
find('input#email').set('test@example.com')
find('button[type="submit"]').click

# ✅ AFTER
fill_in 'Email', with: 'test@example.com'  # More natural
find_button('Submit').click  # Semantic finder
```

### Example 7: Fixed XPath Scoping

```ruby
# ❌ BEFORE
within(:xpath, './/table') do
  rows = all(:xpath, '//tr')  # Searches entire document!
end

# ✅ AFTER
within(:xpath, './/table') do
  rows = all(:xpath, './/tr')  # Searches within table only
end
```

## Remember

Your goal is to make tests:
- **Reliable:** Tests pass consistently, no flakiness (Playwright helps significantly)
- **Fast:** No unnecessary waits, optimized execution (use network idle instead of sleeps)
- **Maintainable:** Clear, follows standards, easy to understand
- **Realistic:** Tests actual user interactions, not shortcuts
- **Debuggable:** Use Playwright traces to diagnose issues quickly

### Reference Documentation

**IMPORTANT:** This command is based on comprehensive patterns documented in:
- **Primary Reference:** `docs/SYSTEM_TEST_TROUBLESHOOTING.md`
- **Helper Methods:** `spec/support/browser_helpers.rb` and `spec/support/database_helpers.rb`
- **Project Guidelines:** `CLAUDE.md` - System Testing Best Practices section

**When encountering a new pattern or issue:**
1. Check the SYSTEM_TEST_TROUBLESHOOTING.md for real-world examples
2. Identify which of the 7 root cause categories applies
3. Use the appropriate helper methods from browser_helpers.rb
4. Follow the fix patterns shown in the troubleshooting guide
5. Update the troubleshooting guide if you discover a new pattern

### Playwright Advantages for Reliability
1. **Network Idle Waiting:** Eliminates most timing issues in AJAX-heavy apps
2. **Automatic Retry:** Playwright automatically retries failed actions
3. **Better Error Messages:** More descriptive failure messages
4. **Traces:** Visual timeline of test execution with screenshots and network activity
5. **Auto-Screenshots:** Automatic screenshots on failure help diagnose issues
6. **Better Turbo Support:** Native support for waiting on network state changes

### Key Principles
- Focus on fixing the root cause, not just making the test pass
- If the application code has issues, fix those too
- Always follow the established standards and best practices
- Use Playwright's debugging tools (traces, screenshots) to understand failures
- Prefer network idle over fixed waits for AJAX/Turbo interactions
- Run tests multiple times to verify reliability (5+ runs recommended)
- **Use the 7 root cause categories** to quickly identify and fix issues
- **Always use helper methods** instead of writing custom wait logic
- **Verify with the checklist** before considering a test fixed

### When in Doubt
1. **Check organization/tenant setup first** - Most common issue in multi-tenant apps
   - Is `ActsAsTenant.current_tenant` set?
   - Using `fast_sign_in(user, organization)` helper?
   - Passing `organization:` to all factories?
2. **Identify the root cause category** (1 of 8) from Section 3
3. Run test with Playwright traces enabled
4. Check the trace viewer for timing issues
5. Look for network delays or console errors
6. **Consult SYSTEM_TEST_TROUBLESHOOTING.md** for similar examples
7. Use network idle waiting for AJAX-heavy sections
8. Apply the appropriate helper methods
9. Verify the fix works 10+ times in a row using the verification script

### Common Mistakes to Avoid
1. ❌ Storing element references across Turbo operations
2. ❌ Not waiting for Turbo completion after form submissions
3. ❌ Checking database immediately after UI actions
4. ❌ Not waiting for Stimulus controller connection
5. ❌ Using fixed `sleep()` instead of proper waits
6. ❌ Checking data attributes immediately after clicks
7. ❌ Using Capybara's `page.go_back` instead of Playwright native navigation
8. ❌ Writing custom wait logic instead of using helper methods
9. ❌ Forgetting to set `ActsAsTenant.current_tenant` in multi-tenant app
10. ❌ Not passing `organization:` parameter to factory creates
11. ❌ Missing subdomain context setup for browser tests
12. ❌ Not using `fast_sign_in(user, organization)` helper for authentication

### Success Criteria
A test is considered properly fixed when:
- ✅ Passes 10 consecutive times locally
- ✅ Uses helper methods from browser_helpers.rb
- ✅ Follows one of the 7 root cause fix patterns
- ✅ No stale element errors
- ✅ No timing-dependent behavior
- ✅ Proper use of Capybara matchers with wait times
- ✅ All checklist items in Section 9a are verified
