# Test Debugging Checklist

When a system test fails, work through this checklist systematically:

## 1. Gather Information (5 minutes)

- [ ] Read the failure message carefully - what exactly failed?
- [ ] Check screenshot in `tmp/capybara/failures_*/` folder
- [ ] Note the line number where test failed
- [ ] Check if failure is consistent or intermittent (run 3-5 times)

## 2. Timing Issues (Most Common - 70% of flaky tests)

- [ ] Is there a wait after the action that failed?
- [ ] Add `wait: 10` to the expectation that failed
- [ ] Check for Turbo navigation - did we wait for `current_path`?
- [ ] Check for Stimulus controller - did we wait for `[data-controller]`?
- [ ] Is JavaScript computing something? Add timeout loop
- [ ] Did we wait long enough? Try increasing wait time to verify

## 3. Selector Issues

- [ ] Does the element actually exist? Check screenshot
- [ ] Is the selector too specific? (Avoid nth-child, complex CSS)
- [ ] Is the selector too generic? (Multiple matches)
- [ ] Are we using Tailwind classes that might change?
- [ ] Print all matching elements: `puts page.all('.selector').count`
- [ ] Try finding by text instead: `find('button', text: 'Click Me')`

## 4. State Issues

- [ ] Did previous test leave dirty data?
- [ ] Are we signed in? (Check for redirect to login)
- [ ] Does the factory create valid data?
- [ ] Do associations exist? (client.organization present?)
- [ ] Is Pundit authorization blocking access?
- [ ] Check `rails_helper.rb` for `use_transactional_fixtures` setting

## 4a. Tenant/Organization Issues (CRITICAL - Multi-Tenant App)

- [ ] Is `ActsAsTenant.current_tenant` set in before block?
- [ ] Did we pass `organization:` to all factory creates?
- [ ] Is subdomain context set? (`Capybara.app_host` with `.localhost`)
- [ ] Are we using `fast_sign_in(user, organization)` for auth?
- [ ] Do user and resources belong to same organization?
- [ ] Check for "Tenant required" errors in logs
- [ ] Verify `$default_organization` is available
- [ ] Are we testing cross-org access? Need separate org setup
- [ ] Check if test needs unique subdomain vs default org

## 5. JavaScript/Stimulus Issues

- [ ] Open test in non-headless mode to see browser
- [ ] Check browser console for JavaScript errors
- [ ] Is Stimulus controller actually connected?
- [ ] Do we need to trigger events manually? (click + change)
- [ ] Are CSS transitions blocking interaction? Wait for animation
- [ ] Is element behind overlay/modal? Check z-index

## 6. Turbo-Specific Issues

- [ ] Did Turbo intercept the form submission?
- [ ] Are we waiting for Turbo to complete?
- [ ] Is this a Turbo Frame? Use `within 'turbo-frame#id'`
- [ ] Is this a Turbo Stream? Element updated in place, not navigation
- [ ] Check for `data-turbo="false"` - might bypass Turbo

## 7. Form Issues

- [ ] Did we fill ALL required fields?
- [ ] Are field names/labels correct? Check view file
- [ ] Are we selecting from correct dropdown?
- [ ] Did we click the right submit button?
- [ ] Are validations preventing submission?
- [ ] Check for JavaScript form validation

## 8. Deep Dive (If still failing)

- [ ] Add debug output:
  ```ruby
  puts "Current path: #{current_path}"
  puts "Page content: #{page.has_content?('Expected')}"
  puts "Element exists: #{page.has_css?('.selector')}"
  save_screenshot('tmp/debug.png')
  save_page('tmp/debug.html')
  ```

- [ ] Check Rails test log: `tail -f log/test.log`

- [ ] Verify database state:
  ```ruby
  puts "Record count: #{Model.count}"
  puts "Last record: #{Model.last.inspect}"
  ```

- [ ] Run test in non-headless to watch:
  ```ruby
  # In spec/rails_helper.rb temporarily change to:
  driven_by :selenium, using: :chrome, options: { browser_options: { args: [] } }
  ```

- [ ] Add sleep to pause and inspect:
  ```ruby
  sleep 10 # Remove after debugging!
  ```

## 9. Common Solutions

| Problem | Solution |
|---------|----------|
| Element not found | Add wait, check selector |
| Stale element | Re-find element before using |
| Form not submitting | Fill all required fields, wait after submit |
| Wrong page showing | Wait for navigation, check Turbo |
| Test passes alone, fails in suite | Database cleanup issue, check factories |
| Random failures | Race condition, add proper waits |
| Element not clickable | Wait for element, check if covered by overlay |
| Validation error | Check factory data validity |

## 10. Nuclear Option

If all else fails:

1. Delete the test
2. Manually perform the workflow in browser
3. Note every single step and what you see
4. Rewrite test matching exact workflow
5. Add waits after every interaction
6. Run 10 times to verify

## Success Criteria

Test is ready when:
- [ ] Passes 10 times in a row locally
- [ ] Clear expectations with explicit waits
- [ ] Uses semantic selectors (not brittle CSS)
- [ ] Tests user behavior, not implementation
- [ ] Has descriptive name and clear intent
- [ ] No `sleep` calls (use proper waits instead)
