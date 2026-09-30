---
name: system-test
description: Generate reliable Capybara/Playwright system tests following the application's patterns
---

# System Test Generator Command

You are an expert Rails system test developer. Write high-quality, fast, and reliable system tests for the application using **Playwright** via Capybara following established patterns and best practices.

## Browser Automation: Playwright

The test suite uses **Playwright** as the browser automation driver through the `capybara-playwright-driver` gem. This provides:
- **Better reliability**: Auto-waiting reduces test flakiness
- **Faster execution**: 20-30% faster than Selenium
- **Enhanced debugging**: Video recording, traces, and inspector
- **Consistent API**: Full Capybara DSL compatibility

## Core Principles

### 1. Test Real User Interactions
- Use natural browser interactions (fill_in, select, click_button) instead of JavaScript execution
- Use semantic finders (`find_field`, `find_link`, `find_button`) for better readability
- Test actual form submissions and validation behavior
- Verify real database changes and state persistence
- Test error conditions and edge cases users might encounter

### 2. Write Fast, Reliable Tests
- Use expectations with wait times instead of fixed sleeps
- Use `have_no_*` matchers (not `!has_*?`) for waiting on element disappearance
- Leverage Capybara's automatic element reloading for dynamic content
- Minimize database hits by using `build` instead of `create` when possible
- Only create associations that are actually needed for the test
- Use deterministic data with sequences, not random values
- Prefer keyboard navigation (send_keys) for problematic elements

### 3. Use Capybara Features Properly
- Use keyword filters (`disabled: false`, `visible: :all`, `checked: true`)
- Scope interactions with `within`, `within_fieldset`, `within_table`
- Use `have_current_path` matcher instead of directly checking `current_path`
- Leverage specialized selectors (`:table_row`, `:field`, `:link`)
- Use relative XPath (`.//`) within scoped blocks, not absolute (`//`)

### 4. Follow Established Patterns
Reference these test files for patterns:
- `spec/system/users/availability_grid_spec.rb` - Complex JS interactions, tabs, data persistence
- `spec/system/mental_status_exams/wizard/e2e/complete_flow_improved_spec.rb` - Multi-step workflows, helper methods
- `spec/system/users/license_management_spec.rb` - Dynamic fields, form management

## Running Tests

### Basic Execution
```bash
# Run all system tests (uses Playwright headless by default)
bundle exec rspec spec/system/

# Run with visible browser (for debugging)
HEADLESS=false bundle exec rspec spec/system/

# Run with video recording (saves to tmp/videos/ on failure)
RECORD_VIDEO=true bundle exec rspec spec/system/

# Run specific test file
bundle exec rspec spec/system/feature_name/test_spec.rb

# Run specific test by line number
bundle exec rspec spec/system/feature_name/test_spec.rb:42
```

### Mobile Testing
```bash
# Tests tagged with :mobile metadata automatically use mobile viewport (390x844)
# No additional flags or setup needed - viewport set at driver registration time
bundle exec rspec spec/system/feature_name/mobile_spec.rb
```

### Driver Selection
The test driver is automatically selected based on RSpec metadata:
- **Desktop headless** (default): `playwright_headless` - 1920x1080 viewport
- **Desktop visible**: `playwright` - 1920x1080 viewport (when `HEADLESS=false`)
- **Mobile headless**: `playwright_mobile_headless` - 390x844 viewport (`:mobile` tag)
- **Mobile visible**: `playwright_mobile` - 390x844 viewport (`:mobile` tag + `HEADLESS=false`)

**No manual viewport management needed** - Viewport is configured at driver registration based on test metadata.

## Test Structure

### Standard Test Setup

**IMPORTANT:** This is a multi-tenant application. Every system test MUST set up organization/tenant context.

#### Recommended Pattern (95% of tests - use global default organization):

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "[Feature Name]", type: :system, js: true do
  # Use global default organization for better performance
  let(:organization) { $default_organization }
  let(:user) { create(:user, :therapist, organization: organization) }
  let(:client) { create(:client, organization: organization) }

  before do
    # Set tenant context (REQUIRED!)
    ActsAsTenant.current_tenant = organization

    # Use fast_sign_in helper - handles subdomain + authentication
    fast_sign_in(user, organization)
  end

  context "when [specific scenario]" do
    it "successfully [performs action]" do
      visit feature_path

      # Test implementation

      expect(page).to have_content("Success message", wait: 10)
    end
  end

  context "with error conditions" do
    it "handles validation errors" do
      # Test error scenarios
    end
  end
end
```

#### Alternative Pattern (for multi-tenant testing or unique subdomain needs):

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "[Multi-Tenant Feature]", type: :system, js: true do
  # Create unique organization for isolation testing
  let(:organization) { create(:organization, subdomain: "test-#{SecureRandom.hex(4)}") }
  let(:user) { create(:user, :therapist, organization: organization) }

  before do
    # Set up tenant context manually
    ActsAsTenant.current_tenant = organization
    Capybara.app_host = "http://#{organization.subdomain}.localhost:#{Capybara.server_port}"
    Capybara.always_include_port = true

    # Login manually when not using fast_sign_in
    login_as(user, scope: :user)
    visit root_path
  end

  after do
    # Clean up subdomain context
    Capybara.app_host = nil
    Capybara.always_include_port = false
  end

  it "tests organization-specific behavior" do
    # Test implementation
  end
end
```

**Key Points:**
- Use `$default_organization` for most tests (better performance, used in 20+ existing tests)
- Always set `ActsAsTenant.current_tenant` before interactions
- Use `fast_sign_in(user, organization)` helper - handles both auth and subdomain
- Explicitly pass `organization:` to all factory creates
- Only create unique organizations when testing multi-tenancy or requiring isolation

### Test Naming Conventions
- Use descriptive RSpec.describe blocks: `"Feature Name"`, not `"FeatureController"`
- Use contexts for different scenarios: `context "with existing data"`
- Use clear it/scenario descriptions: `"successfully completes workflow"`
- Tag JS tests explicitly: `js: true`
- Tag mobile tests with: `:mobile` (automatically uses mobile viewport)

### Mobile Testing Setup
```ruby
# Mobile tests automatically use 390x844 viewport (iPhone 12 Pro size)
RSpec.describe "Mobile Feature", type: :system do
  context "on mobile devices", :mobile do
    it "displays mobile navigation" do
      visit dashboard_path
      # Test runs with mobile viewport - no manual resizing needed
      expect(page).to have_css('[data-responsive-sidebar-target="toggle"]')
    end
  end
end
```

**Important**: Do NOT manually resize browser windows in tests. Viewport is set at driver registration time based on `:mobile` metadata.

## Form Interactions

### Date and Time Inputs ⚠️ CRITICAL

**IMPORTANT**: Playwright strictly enforces HTML5 input format requirements for date and time fields.

**Required Formats**:
- **Date inputs**: ISO format `"YYYY-MM-DD"` (e.g., `"2024-12-25"`)
- **Time inputs**: 24-hour format `"HH:MM"` (e.g., `"14:30"`)

**What FAILS** (will cause "Malformed value" errors):
- US date format: `"12/25/2024"`
- 12-hour time: `"2:30 PM"`
- `strftime('%m/%d/%Y')` output

**Recommended Solution - Use JavaScript Execution**:
```ruby
# ✅ BEST PRACTICE - JavaScript with ISO format (most reliable)
page.execute_script(<<~JS)
  var field = document.querySelector('input[name="clinical_document[completion_data][session_date]"]');
  if (field) {
    field.value = '2024-12-25';  // ISO format
    field.dispatchEvent(new Event('change', { bubbles: true }));
  }
JS

# ✅ ALTERNATIVE - Convert to ISO format before filling
date = Date.new(2024, 12, 25)
fill_in 'session_date', with: date.strftime('%Y-%m-%d')

# ✅ GOOD - For time inputs
time = Time.new(2024, 12, 25, 14, 30)
fill_in 'session_time', with: time.strftime('%H:%M')  # 24-hour format

# ❌ BAD - These will fail with Playwright
fill_in 'session_date', with: '12/25/2024'  # US format
fill_in 'session_time', with: '2:30 PM'     # 12-hour format
```

**Helper Method Pattern**:
```ruby
# Consider creating a helper for date/time inputs
def fill_in_date(field_name, date)
  iso_date = date.is_a?(Date) ? date.strftime('%Y-%m-%d') : date
  page.execute_script(<<~JS)
    var field = document.querySelector('[name="#{field_name}"]');
    if (field) {
      field.value = '#{iso_date}';
      field.dispatchEvent(new Event('change', { bubbles: true }));
    }
  JS
end

def fill_in_time(field_name, time)
  time_24h = time.is_a?(Time) ? time.strftime('%H:%M') : time
  page.execute_script(<<~JS)
    var field = document.querySelector('[name="#{field_name}"]');
    if (field) {
      field.value = '#{time_24h}';
      field.dispatchEvent(new Event('change', { bubbles: true }));
    }
  JS
end
```

### Filling Form Fields
```ruby
# ✅ GOOD - Natural form interactions with semantic finders
fill_in 'First Name', with: 'John'
fill_in 'field_name', with: 'value'
select 'Option Text', from: 'Select Box'
check 'checkbox_field'

# ✅ GOOD - Using specialized finders
find_field('Email').value  # Returns current value
find_field(id: 'my_field').value
find_button('Submit').click
find_link('Next', visible: :all).click

# ✅ GOOD - Wait for dynamic content with expectations
expect(page).to have_css('.loaded-content', wait: 2)
expect(page).to have_field('field_name', with: 'expected_value', wait: 3)

# ❌ BAD - JavaScript event simulation
page.execute_script("document.querySelector('input').value = 'value'")

# ❌ BAD - Fixed sleeps
fill_in 'field_name', with: 'value'
sleep(1)  # Use expectations instead
```

### Checkbox and Radio Button Interactions
```ruby
# ✅ PREFERRED - Direct Capybara methods (most natural)
check 'Accept Terms'
uncheck 'Subscribe to newsletter'
choose 'Payment Method'  # For radio buttons

# ✅ GOOD - Using find_field with filters
find_field('field_name', checked: false)
find_field('field_name', disabled: false)

# ✅ ALTERNATIVE - Keyboard navigation for problematic elements
checkbox = find('input[type="checkbox"][name="field_name"]', visible: :all)
checkbox.send_keys(' ')  # Space bar to toggle

# ✅ GOOD - Finding checked/unchecked fields
page.find_field(checked: true) == page.find_field(unchecked: false)
```

### Button and Link Clicks
```ruby
# ✅ PREFERRED - Standard click methods
click_button 'Submit'
click_link 'Next Step'
click_on 'Save'  # Clicks either link or button

# ✅ GOOD - Using specialized finders with filters
find_link('Home', visible: :all).click
find_link(href: '/dashboard').click
find_button(value: 'submit_action').click

# ✅ ALTERNATIVE - Keyboard for problematic buttons
button = find('button', text: 'Submit')
button.send_keys(:return)
```

## JavaScript and Dynamic Content

### Waiting for JavaScript
```ruby
# ✅ GOOD - Wait for Stimulus controllers
expect(page).to have_css("[data-controller='component-name']", wait: 2)
expect(page).to have_css("[data-component-target='element']", wait: 2)

# ✅ GOOD - Wait for dynamic content
expect(page).to have_content('Expected Text', wait: 3)
expect(page).to have_css('.loaded-class', wait: 2)
expect(page).to have_selector('table tr', wait: 2)
expect(page).to have_xpath('.//table/tr', wait: 2)

# ✅ GOOD - Wait for elements to disappear (IMPORTANT: use negative matchers)
expect(page).to have_no_css('.loading-spinner', wait: 3)  # Correct - waits
expect(page).not_to have_css('.loading-spinner')  # Also correct - waits

# ❌ BAD - Negating positive predicates doesn't wait properly
!page.has_css?('.loading-spinner')  # Wrong - doesn't wait for element to disappear

# ✅ GOOD - Wait for auto-save indicators
fill_in 'field', with: 'content'
find('textarea[name="field"]').send_keys(:tab)
expect(page).to have_css('.auto-save-indicator.saved', wait: 3)

# ❌ BAD - Fixed sleeps
sleep(2)
```

### Multi-tab and Complex UI
```ruby
# Wait for tab switching
find("button[data-tab-id='tab-name']").click
expect(page).to have_css("div[data-tab-id='tab-name']:not(.hidden)", wait: 2)

# Scope interactions within tabs using within
within("div[data-tab-id='tab-name']") do
  fill_in 'field', with: 'value'
  expect(page).to have_content('Expected')
end

# Scope by XPath when needed
within(:xpath, './/div[@data-tab-id="settings"]') do
  fill_in 'Email', with: 'test@example.com'
end

# Specialized scoping for forms
within_fieldset('User Information') do
  fill_in 'Name', with: 'John Doe'
end

within_table('Results') do
  expect(page).to have_content('Total')
end
```

## Data Verification

### Database State Verification
```ruby
# Always reload records before checking
model.reload
expect(model.attribute).to eq('expected_value')
expect(model.status).to eq('completed')
expect(model.associations.count).to eq(2)

# Verify specific associations
rules = user.availability_rules.where(office_id: office.id, active: true)
expect(rules.count).to be >= 1
expect(rules.first.start_time.hour).to eq(9)
```

### Cross-Page Data Persistence
```ruby
# Fill data
fill_in 'field', with: 'test data'
click_button 'Save'

# Navigate away and back
visit other_path
visit current_path

# Verify data persisted
field_value = find('input[name="field"]').value
expect(field_value).to eq('test data')
```

## FactoryBot Best Practices

### Creating Test Data
```ruby
# ✅ GOOD - Minimal factory with sequences
let(:user) { create(:user, :therapist, organization: organization) }
let(:client) { create(:client) }

# ✅ GOOD - Use traits for variations
let(:document) { create(:clinical_document, :mse, :completed) }

# ✅ GOOD - Build when database not needed
let(:validation_test) { build(:user, email: 'invalid') }

# ❌ BAD - Overriding associations unnecessarily
let(:appointment) { create(:appointment, client: client, user: user) }
```

### Deterministic Time Values
```ruby
# ✅ GOOD - Use Ruby time helpers for predictable times
scheduled_at: 1.day.from_now.beginning_of_day + 10.hours
created_at: 1.day.ago.beginning_of_day

# ✅ GOOD - Use traits for time scenarios
let(:appointment) { create(:appointment, :future) }

# ❌ BAD - Non-deterministic time
created_at: Time.current  # Can cause flaky tests
```

## Helper Methods

### Creating Reusable Helpers
```ruby
# spec/support/system_helpers/feature_helpers.rb
module FeatureHelpers
  def visit_feature_page(resource)
    visit feature_path(resource)
  end

  def fill_feature_form(attributes = {})
    fill_in 'field1', with: attributes[:field1] || 'default'
    select attributes[:field2] || 'Default', from: 'field2'
  end

  def expect_form_errors
    error_indicators = ['.bg-secondary', '.error', '.alert-danger', '.field_with_errors']
    has_errors = error_indicators.any? { |selector| page.has_css?(selector) }
    expect(has_errors).to be true
  end
end

# In spec_helper.rb or rails_helper.rb
RSpec.configure do |config|
  config.include FeatureHelpers, type: :system
end
```

### Wait Helper Pattern
```ruby
def wait_for_step_load(step_name)
  expect(page).to have_css("[data-step='#{step_name}']", wait: 3)
end

def wait_for_controller_ready(controller_name)
  expect(page).to have_css("[data-controller='#{controller_name}']", wait: 2)
end
```

## Validation Testing

### Non-Blocking Validation
```ruby
# Test that allows progression with warnings
navigate_to_next_step

# Check for validation but allow continued workflow
if page.has_css?('.bg-secondary, .error, .alert-danger, .field_with_errors')
  expect_form_errors
else
  # Form may use non-blocking validation
  expect(page).not_to have_current_path(original_path)
end
```

### Blocking Validation
```ruby
# Try to submit with missing required fields
click_button 'Submit'

# Should remain on current page
expect(page).to have_current_path(current_path)
expect(page).to have_content('required')

# Fill fields and retry
fill_required_fields
click_button 'Submit'
expect(page).to have_content('Success')
```

## Test Organization

### File Structure
```
spec/system/
├── feature_name/
│   ├── basic_functionality_spec.rb      # 200-400 lines
│   ├── advanced_features_spec.rb        # 200-400 lines
│   ├── validation_spec.rb               # 200-400 lines
│   └── e2e/
│       └── complete_workflow_spec.rb    # 500+ lines acceptable
```

### Context Organization
```ruby
RSpec.describe "Feature" do
  context "with basic setup" do
    it "performs basic action" do
      # Test basic functionality
    end
  end

  context "with existing data" do
    before do
      create(:existing_resource)
    end

    it "handles existing data correctly" do
      # Test with existing data
    end
  end

  context "with multiple resources" do
    it "manages multiple resources" do
      # Test complex scenarios
    end
  end
end
```

## Common Patterns

### Multi-Step Workflows
```ruby
scenario 'completes entire workflow' do
  # Step 1
  visit_step(:step1)
  wait_for_step_load(:step1)
  fill_step1_data
  navigate_to_next_step

  # Step 2
  wait_for_step_load(:step2)
  fill_step2_data
  navigate_to_next_step

  # Final verification
  wait_for_step_load(:review)
  verify_workflow_completion
end
```

### Dynamic Field Management
```ruby
it "adds and removes dynamic fields", js: true do
  # Add field
  click_button "Add Field"
  expect(page).to have_css('.dynamic-field', count: 1, wait: 2)

  within('.dynamic-field', match: :first) do
    fill_in 'Name', with: 'Value'
  end

  # Add another
  click_button "Add Field"
  sleep 0.3  # Brief wait for DOM update

  fields = page.all('.dynamic-field')
  expect(fields.count).to eq(2)

  # Remove field
  within(fields.first) do
    click_button "Remove"
  end

  sleep 0.3  # Brief wait for removal
  expect(page).to have_css('.dynamic-field', count: 1)
end
```

### Tabbed Interfaces
```ruby
it "manages data across tabs", js: true do
  # Tab 1
  within("[data-tab-id='tab1']") do
    fill_in 'field1', with: 'value1'
  end

  # Switch to Tab 2
  find("button[data-tab-id='tab2']").click
  expect(page).to have_css("div[data-tab-id='tab2']:not(.hidden)", wait: 2)

  within("[data-tab-id='tab2']") do
    fill_in 'field2', with: 'value2'
  end

  # Save and verify both tabs
  click_button "Save"

  resource.reload
  expect(resource.field1).to eq('value1')
  expect(resource.field2).to eq('value2')
end
```

## Advanced Capybara Features

### Element Filters and Options
```ruby
# ✅ GOOD - Using keyword filters
find_field('email', disabled: false)
find_button('Submit', disabled: true)
find(:element, 'data-role': 'admin')
find(id: 'notification', text: 'Success')

# ✅ GOOD - Visibility options
find('div', visible: :all)  # Find hidden and visible elements
find_link('Profile', visible: false)  # Only hidden links
find('.modal', visible: true)  # Only visible elements (default)

# ✅ GOOD - Filter blocks for complex conditions
find_field('First Name'){ |el| el['data-xyz'] == '123' }
find('#img_loading'){ |img| img['complete'] == true }
find_button('action'){ |btn| btn['data-confirm'].present? }

# ✅ GOOD - Finding by custom attributes
find(:css, '[data-test-id="user-profile"]')
find('[aria-label="Close dialog"]')
```

### XPath Best Practices
```ruby
# ✅ GOOD - Relative XPath within scopes
within(:xpath, './/body') do
  find(:xpath, './/script')  # .// searches within current context
  within(:xpath, './/table/tbody') do
    find(:xpath, './/tr[1]')
  end
end

# ❌ BAD - Absolute XPath breaks scoping
within(:xpath, './/table') do
  find(:xpath, '//tr')  # Searches entire document, not within table!
end

# ✅ GOOD - Using specialized selectors
find(:table_row, ['Cell 1', 'Cell 2'])
find(:table_row, 'Name' => 'John', 'Age' => '30')
```

### Handling Asynchronous Updates
```ruby
# ✅ GOOD - Capybara automatically reloads stale elements
sidebar = find('#sidebar')
# Even if sidebar content changes asynchronously:
expect(sidebar.find('h1')).to have_content('New Title')  # Works!

# ✅ GOOD - Finding all elements with proper waiting
all('div', wait: false)  # Returns immediately, may be empty
all('div')  # Default: waits for at least one element
all('div', minimum: 2, wait: 5)  # Waits up to 5s for 2+ elements

# ✅ GOOD - first with proper behavior
first('div')  # Waits for at least one, returns first or raises error
first('div', minimum: 0)  # Returns nil immediately if not found
```

### JavaScript Dialogs
```ruby
# ✅ GOOD - Accepting alerts
accept_alert 'Are you sure?' do
  click_link 'Delete Account'
end

# ✅ GOOD - Accepting confirms
accept_confirm do
  click_button 'Proceed'
end

# ✅ GOOD - Dismissing confirms
dismiss_confirm do
  click_button 'Dangerous Action'
end

# ✅ GOOD - Handling prompts with input
accept_prompt(with: 'New Name') do
  click_link 'Rename'
end

# ✅ GOOD - Capturing dialog messages
message = accept_confirm do
  click_button 'Submit'
end
expect(message).to eq('Confirm submission?')
```

### Multiple Windows and Sessions
```ruby
# ✅ GOOD - Handling new windows
new_window = window_opened_by do
  click_button 'Open in New Window'
end

within_window new_window do
  expect(page).to have_content('New Window Content')
  fill_in 'field', with: 'value'
end

# ✅ GOOD - Testing multi-user scenarios
Capybara.using_session("Admin") do
  login_as(admin_user)
  visit admin_dashboard_path
  expect(page).to have_content('Admin Panel')
end

Capybara.using_session("User") do
  login_as(regular_user)
  visit dashboard_path
  expect(page).to have_content('User Dashboard')
end
```

### Debugging Helpers (Playwright-Enhanced)
```ruby
# ✅ GOOD - Visual debugging
save_and_open_page  # Opens current HTML in browser
save_and_open_screenshot  # Opens screenshot in viewer
page.save_screenshot('debug.png')  # Save screenshot for later

# ✅ GOOD - Programmatic debugging
puts page.html  # Print page HTML
puts page.title  # Print page title
puts page.current_url  # Print current URL

# ✅ GOOD - Element inspection
element = find('#target')
puts element['class']  # Get attribute value
puts element.text  # Get visible text
puts element.value  # Get form field value
puts element.disabled?  # Check if disabled

# ✅ PLAYWRIGHT SPECIFIC - Video recording
# Videos automatically saved to tmp/videos/ when test fails (if RECORD_VIDEO=true)
# No manual code needed - configured at driver level

# ✅ PLAYWRIGHT SPECIFIC - Playwright Inspector (interactive debugging)
# Add to test where you want to pause:
page.driver.with_playwright_page do |pw_page|
  pw_page.pause  # Opens Playwright Inspector - step through actions
end

# ✅ PLAYWRIGHT SPECIFIC - Tracing (detailed execution timeline)
# Start trace at beginning of test
start_playwright_trace(screenshots: true, snapshots: true)

# ... your test code ...

# Stop trace and save
stop_playwright_trace(path: 'tmp/traces/test-trace.zip')
# View with: npx playwright show-trace tmp/traces/test-trace.zip

# ✅ PLAYWRIGHT SPECIFIC - LocalStorage access
# Clear local storage using helper
clear_local_storage

# Or access directly
page.driver.with_playwright_page do |pw_page|
  pw_page.evaluate('window.localStorage.getItem("key")')
  pw_page.evaluate('window.localStorage.setItem("key", "value")')
end
```

## Error Handling

### Testing Error Scenarios
```ruby
it "handles network interruption gracefully" do
  fill_in 'field', with: 'data'

  # Simulate interruption
  page.refresh

  # Verify form remains functional
  expect(page).to have_field('field')
  expect(page).to have_css('form')
end

it "handles large data gracefully" do
  large_text = 'Large content. ' * 100
  fill_in 'field', with: large_text

  click_button 'Submit'

  expect(page).not_to have_content('error', 'timeout', '500')
  expect(page).to have_content('Success')
end
```

## Browser Helpers (Playwright-Specific)

The test suite includes browser helpers in `spec/support/browser_helpers.rb`:

```ruby
# Check which driver is being used
if playwright?
  # Use Playwright-specific features
end

# Clear browser local storage (driver-agnostic)
clear_local_storage

# Save a screenshot with custom name (use this, not take_screenshot)
# Note: Method named save_test_screenshot to avoid conflict with RSpec's take_screenshot
save_test_screenshot('debug_state')

# Access native Playwright page for advanced operations
with_playwright_page do |pw_page|
  pw_page.evaluate('console.log("test")')
  pw_page.goto('https://example.com')
  pw_page.wait_for_selector('.element')
end

# Enable tracing for debugging
start_playwright_trace(screenshots: true, snapshots: true)
# ... test code ...
stop_playwright_trace(path: 'tmp/traces/trace.zip')
```

**IMPORTANT**: Do NOT create a helper method named `take_screenshot` - this conflicts with RSpec's built-in method. Use `save_test_screenshot` instead.

## Debugging

### Debug Helpers
```ruby
# Add to spec_helper or use inline
def debug_page_state
  puts "Current URL: #{current_url}"
  puts "Page title: #{page.title}"
  puts "Visible text: #{page.text[0..200]}..."
  save_screenshot("debug_#{Time.current.to_i}.png")
end

# Use in failing tests
begin
  expect(page).to have_content('Expected')
rescue RSpec::Expectations::ExpectationNotMetError => e
  debug_page_state
  raise e
end
```

### Playwright-Specific Debugging

```ruby
# 1. Interactive debugging with Playwright Inspector
it "debugs issue interactively" do
  visit some_path

  # Pause execution - opens Playwright Inspector
  page.driver.with_playwright_page { |p| p.pause }

  # Continue with test actions in inspector
end

# 2. Video recording (automatic on failure when RECORD_VIDEO=true)
# Run test with: RECORD_VIDEO=true bundle exec rspec spec/system/test_spec.rb
# Videos saved to: tmp/videos/

# 3. Tracing for detailed timeline
it "captures detailed trace" do
  start_playwright_trace(screenshots: true, snapshots: true)

  # Your test actions
  visit dashboard_path
  click_button 'Submit'

  stop_playwright_trace(path: 'tmp/traces/my-test.zip')
  # View with: npx playwright show-trace tmp/traces/my-test.zip
end

# 4. Screenshot on specific action
page.driver.with_playwright_page do |pw_page|
  pw_page.screenshot(path: 'tmp/debug-screenshot.png')
end
```

## Performance Guidelines

### Keep Tests Fast
- Avoid unnecessary database creation
- Use expectations instead of sleeps (saves 50%+ execution time)
- Only test JavaScript when necessary (non-js: true by default)
- Use traits to compose complex scenarios efficiently
- Run tests in parallel when possible

### Playwright Performance Benefits
Playwright provides significant performance improvements over Selenium:
- **20-30% faster execution**: More efficient browser communication
- **Better auto-waiting**: Reduces unnecessary wait times
- **Smarter element finding**: Faster selector resolution
- **Parallel execution**: More stable when running tests in parallel
- **Faster browser startup**: Chromium instances start more quickly

### When to Use `js: true`
- Testing JavaScript-driven interactions (Stimulus controllers)
- Testing dynamic content updates (auto-save, live validation)
- Testing async operations (AJAX, WebSocket)
- Testing complex UI components (tabs, modals, dropdowns)

## Capybara Matchers Reference

### Common RSpec Matchers
```ruby
# Content matchers
expect(page).to have_content('text')
expect(page).to have_text('text', exact: true)
expect(page).not_to have_content('text')
expect(page).to have_no_content('text')  # Better for waiting

# Selector matchers
expect(page).to have_css('div.class')
expect(page).to have_selector('table tr')
expect(page).to have_xpath('.//table/tr')
expect(page).to have_no_css('.loading')  # Wait for element to disappear

# Form matchers
expect(page).to have_field('Email')
expect(page).to have_field('Email', with: 'user@example.com')
expect(page).to have_checked_field('Accept Terms')
expect(page).to have_unchecked_field('Newsletter')
expect(page).to have_select('Country', selected: 'USA')
expect(page).to have_select('Colors', selected: ['Red', 'Blue'])

# Link and button matchers
expect(page).to have_link('Home')
expect(page).to have_link('Profile', href: '/profile')
expect(page).to have_button('Submit')
expect(page).to have_button('action', disabled: true)

# Path matcher (recommended over checking current_path directly)
expect(page).to have_current_path('/dashboard')
expect(page).to have_current_path(user_path(user))
```

### Predicate Methods (for conditionals)
```ruby
# Use these when you need boolean checks (not assertions)
if page.has_css?('.alert')
  # Handle alert
end

unless page.has_no_css?('.loading')
  # Wait for loading to finish
end

# Available predicates (all have negative has_no_* versions)
page.has_selector?('div')
page.has_css?('.class')
page.has_xpath?('.//div')
page.has_content?('text')
page.has_field?('Email')
page.has_checked_field?('Terms')
page.has_link?('Home')
page.has_button?('Submit')
```

## Patterns to Avoid (Selenium-Specific)

These patterns were required with Selenium but are **not needed** with Playwright:

```ruby
# ❌ BAD - Manual viewport resizing (Selenium pattern)
page.driver.browser.manage.window.resize_to(375, 667)
page.driver.browser.manage.window.maximize

# ✅ GOOD - Use :mobile metadata instead
context "on mobile", :mobile do
  # Viewport automatically set to 390x844
end

# ❌ BAD - Direct browser access (Selenium pattern)
page.driver.browser.switch_to.alert.accept
page.driver.browser.manage.delete_all_cookies

# ✅ GOOD - Use Capybara methods or Playwright helpers
accept_alert { click_button 'Delete' }
clear_local_storage  # Uses browser helper

# ❌ BAD - Selenium-specific waits
Selenium::WebDriver::Wait.new(timeout: 10).until { ... }

# ✅ GOOD - Use Capybara expectations
expect(page).to have_content('Expected', wait: 10)
```

## Playwright-Specific Considerations

### Auto-Waiting Behavior
Playwright has **better auto-waiting** than Selenium:
- Automatically waits for elements to be actionable (visible, enabled, stable)
- Waits for navigation to complete after clicks
- Waits for network idle in many scenarios
- Still use explicit expectations for dynamic content

### Event Timing
Playwright may dispatch events differently:
```ruby
# For Stimulus controllers, ensure controller is connected
expect(page).to have_css("[data-controller*='controller-name']", wait: 10)

# For AJAX operations, wait for completion
select "Option", from: "field"
expect(page).to have_css("[data-result]", wait: 5)
```

## Checklist for New Tests

- [ ] Use natural browser interactions (no JavaScript execution)
- [ ] Use semantic finders (`find_field`, `find_link`, `find_button`)
- [ ] Use expectations with wait times (no fixed sleeps)
- [ ] Use `have_no_*` matchers for waiting on disappearance
- [ ] Use keyword filters (`disabled:`, `checked:`, `visible:`) when appropriate
- [ ] Create minimal test data with factories
- [ ] Use deterministic data (sequences, not random)
- [ ] Verify database state after actions
- [ ] Test both happy path and error scenarios
- [ ] Include clear, descriptive test names
- [ ] Organize into logical contexts
- [ ] Use `within` for scoping interactions
- [ ] Create reusable helper methods for common actions
- [ ] Test data persistence across page reloads
- [ ] Handle JavaScript timing properly
- [ ] Use `js: true` only when necessary
- [ ] Keep test files under 400 lines (except e2e)
- [ ] Use `have_current_path` matcher instead of checking `current_path` directly
- [ ] **NEW**: Use `:mobile` metadata for mobile tests (no manual viewport resizing)
- [ ] **NEW**: Avoid Selenium-specific patterns (browser.manage, switch_to, etc.)
- [ ] **NEW**: Leverage Playwright debugging tools when needed (traces, inspector)

## Output Format

When generating tests, provide:
1. Complete test file with proper require statements
2. Factory definitions if new factories needed
3. Helper method definitions if creating new helpers
4. Brief explanation of test coverage

Focus on writing tests that are:
- **Fast**: Minimal database hits, smart waiting, leverages Playwright's speed
- **Reliable**: Deterministic data, proper timing, uses Playwright auto-waiting
- **Maintainable**: Clear structure, reusable helpers, driver-agnostic patterns
- **Realistic**: Tests real user interactions through Capybara DSL
- **Debuggable**: Uses Playwright debugging features when needed

## Migration Notes

The test suite has migrated from Selenium to Playwright. When writing new tests:
- **Do not** include any Selenium-specific code (browser.manage, switch_to, etc.)
- **Do** use the `:mobile` metadata for mobile viewport tests
- **Do** leverage Playwright debugging tools (traces, inspector, video recording)
- **Do** follow Capybara best practices (all patterns remain valid)
- **Do** use browser helpers from `spec/support/browser_helpers.rb`

For more details on the migration, see:
- Implementation plan: `.claude/implementation-plan-20251026-playwright.md`
- Playwright configuration: `spec/support/playwright_config.rb`
- Browser helpers: `spec/support/browser_helpers.rb`
