# System Test Quick Reference

## Organization/Tenant Setup (REQUIRED!)

```ruby
# Standard pattern (use for 95% of tests)
let(:organization) { $default_organization }
let(:user) { create(:user, :therapist, organization: organization) }

before do
  ActsAsTenant.current_tenant = organization
  fast_sign_in(user, organization)  # Handles subdomain + auth
end

# Unique organization (for multi-tenant testing)
let(:organization) { create(:organization, subdomain: "test-#{SecureRandom.hex(4)}") }

before do
  ActsAsTenant.current_tenant = organization
  Capybara.app_host = "http://#{organization.subdomain}.localhost:#{Capybara.server_port}"
  Capybara.always_include_port = true
  login_as(user, scope: :user)
  visit root_path
end
```

## Most Common Wait Patterns

```ruby
# After navigation
expect(page).to have_current_path(path, wait: 10)

# After content change
expect(page).to have_content('Text', wait: 10)

# For Stimulus controller
expect(page).to have_css("[data-controller*='name']", wait: 10)

# For dynamic element
expect(page).to have_css("[data-testid='element']", wait: 10)

# Using Selenium WebDriverWait (most idiomatic)
wait = Selenium::WebDriver::Wait.new(timeout: 10)
wait.until { page.has_css?("[data-result]") }

# For element to disappear (CRITICAL!)
expect(page).to have_no_css('.loading-spinner', wait: 10)  # Correct
!page.has_css?('.loading-spinner')  # WRONG - doesn't wait!
```

## Form Submission Pattern

```ruby
# 1. Fill ALL fields
fill_in 'Name', with: 'Value'
select 'Option', from: 'Dropdown'

# 2. Submit
click_button 'Submit'

# 3. Wait for response (ALWAYS!)
expect(page).to have_content('Success', wait: 10)
```

## Modal Pattern

```ruby
# Open
click_button 'Open Modal'
expect(page).to have_css('#modal', visible: true, wait: 5)

# Interact
within '#modal' do
  # actions
end

# Close
expect(page).to have_no_css('#modal', wait: 5)
```

## Turbo Frame Pattern

```ruby
within 'turbo-frame#frame-id' do
  click_link 'Edit'
end

expect(page).to have_css('turbo-frame#frame-id', text: 'Updated', wait: 5)
```

## Stimulus Action Pattern

```ruby
# Wait for controller
expect(page).to have_css("[data-controller='name']", wait: 5)

# Trigger action
find("[data-action='click->name#method']").click

# Verify result
expect(page).to have_css("[data-name-target='result']", wait: 5)
```

## Debugging Shortcuts

```ruby
save_screenshot('tmp/debug.png')
save_page('tmp/debug.html')
puts page.html
puts current_path
puts page.has_css?('.selector')
```

## JavaScript Modals

```ruby
# Accept alert
accept_alert { click_button 'Show Alert' }

# Accept confirm
accept_confirm { click_link 'Delete' }

# Accept prompt with input
accept_prompt with: 'Value' { click_button 'Ask' }

# Dismiss
dismiss_confirm { click_link 'Cancel' }
```

## Stale Elements

```ruby
# WRONG
button = find('.btn')
button.click
button.click  # ERROR: Stale!

# CORRECT
find('.btn').click
find('.btn').click  # Works!
```

## Capybara 3.x

```ruby
# `all` waits by default
all('.item')  # Waits

# Get old behavior
all('.item', wait: false)  # No wait

# `first` raises if not found
first('.item')  # Raises error

# Get old behavior
first('.item', minimum: 0)  # Returns nil
```

## Multi-Session

```ruby
# Default session
sign_in user_a

# User B session
Capybara.using_session('user_b') do
  sign_in user_b
  visit dashboard_path
end

# Back to user_a automatically
```

## Selector Priority

1. `find('[data-testid="name"]')` - Best
2. `find('button[aria-label="Action"]')` - Great
3. `click_button 'Text'` - Good
4. `find('[role="navigation"]')` - Good
5. `find('.component-class')` - Last resort

## Text Matching

```ruby
click_button 'Save'  # Partial (default)
click_button 'Save', exact: true  # Exact only
```
