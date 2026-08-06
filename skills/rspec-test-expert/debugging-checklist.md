# RSpec Test Debugging Checklist

When an RSpec test fails, work through this checklist systematically:

## 1. Read the Failure Message (2 minutes)

- [ ] Read the full error message carefully
- [ ] Identify which expectation failed
- [ ] Note the file and line number
- [ ] Check if it's a consistent failure or flaky (run 3-5 times)
- [ ] Look for clues in the diff output

## 2. Verify Test Setup (5 minutes)

- [ ] Is `require 'rails_helper'` at the top of the file?
- [ ] Is the correct test type specified (`:model`, `:service`, etc.)?
- [ ] Are all `let` variables being created correctly?
- [ ] Is `let!` needed instead of `let` for eager loading?
- [ ] Are factories building valid objects?
- [ ] Is multi-tenancy context set up (`ActsAsTenant.with_tenant`)?

## 3. Factory Issues (Most Common - 40% of failures)

- [ ] Does the factory create valid data?
  ```ruby
  # In rails console or test
  FactoryBot.create(:model)  # Does it work?
  ```
- [ ] Are all required associations present?
- [ ] Are all required fields being set?
- [ ] Is the factory using valid enum values?
- [ ] Do trait combinations create valid records?
- [ ] Check factory definition:
  ```ruby
  # Read the factory file
  cat spec/factories/models.rb
  ```

## 4. Database State Issues

- [ ] Is the test polluting the database?
- [ ] Are transactions being rolled back properly?
- [ ] Is data from previous tests interfering?
- [ ] Check record counts:
  ```ruby
  puts "Model count: #{Model.count}"
  puts "Last record: #{Model.last.inspect}"
  ```
- [ ] Are you testing in the correct tenant context?
- [ ] Do records have correct organization_id?

## 5. Validation Failures

- [ ] Print validation errors:
  ```ruby
  model = build(:model, field: value)
  model.valid?
  puts model.errors.full_messages
  ```
- [ ] Are all required fields present?
- [ ] Are values in the correct format?
- [ ] Are enum values valid?
- [ ] Are associated records valid?
- [ ] Check custom validations

## 6. Association Issues

- [ ] Do associated records exist in database?
- [ ] Are associations loaded correctly?
  ```ruby
  puts model.association(:items).loaded?
  puts model.items.to_sql
  ```
- [ ] Are foreign keys set correctly?
- [ ] Is polymorphic type set correctly?
- [ ] Are dependent destroys working as expected?

## 7. Callback Issues

- [ ] Are callbacks running when expected?
- [ ] Are callbacks in the correct order?
- [ ] Are callbacks modifying data unexpectedly?
- [ ] Are callbacks being skipped (`.save(validate: false)`)?
- [ ] Add debug output:
  ```ruby
  before_save do
    puts "Before save callback running"
    puts "Current state: #{inspect}"
  end
  ```

## 8. Scope and Query Issues

- [ ] Print the generated SQL:
  ```ruby
  puts Model.active.to_sql
  ```
- [ ] Are scopes returning expected records?
- [ ] Are WHERE clauses correct?
- [ ] Are JOINs working correctly?
- [ ] Check for N+1 queries
- [ ] Test scope in isolation:
  ```ruby
  puts Model.scope_name.count
  puts Model.scope_name.pluck(:id)
  ```

## 9. Mocking/Stubbing Issues

- [ ] Are mocks set up before the code runs?
- [ ] Are you stubbing the right method?
- [ ] Are you stubbing on the right object?
- [ ] Is the mock return value correct type?
- [ ] Are argument matchers too strict?
- [ ] Remove mocks temporarily to see real behavior

## 10. Time-Related Issues

- [ ] Is time being frozen when needed?
  ```ruby
  freeze_time do
    # Test code
  end
  ```
- [ ] Are date calculations correct?
- [ ] Are timezones handled correctly?
- [ ] Are you comparing Time vs DateTime vs Date correctly?
- [ ] Check time zone:
  ```ruby
  puts Time.zone
  puts Time.current
  ```

## 11. Expectation Issues

- [ ] Is the matcher correct for the data type?
  ```ruby
  # String vs Symbol
  expect(model.status).to eq('active')  # String
  expect(model.status).to eq(:active)   # Symbol

  # Array equality
  expect(array).to match_array([1, 2, 3])  # Order doesn't matter
  expect(array).to eq([1, 2, 3])            # Order matters
  ```
- [ ] Are you testing the right thing?
- [ ] Is the actual value what you think it is?
  ```ruby
  puts "Expected: #{expected.inspect}"
  puts "Actual: #{actual.inspect}"
  ```

## 12. Service Object Issues

- [ ] Is the service initialized correctly?
- [ ] Are errors being populated correctly?
- [ ] Is the service returning the correct value (true/false)?
- [ ] Are side effects happening?
  ```ruby
  service.call(params)
  puts "Errors: #{service.errors.inspect}"
  puts "Result: #{service.object.inspect}"
  ```

## 13. Deep Dive (If still failing)

Add debug output:

```ruby
describe '#method_name' do
  it 'does something' do
    model = create(:model)

    puts "Model: #{model.inspect}"
    puts "Model valid?: #{model.valid?}"
    puts "Model errors: #{model.errors.full_messages}"
    puts "Model attributes: #{model.attributes}"

    result = model.method_name

    puts "Result: #{result.inspect}"

    expect(result).to eq(expected)
  end
end
```

Use binding.pry for interactive debugging:

```ruby
require 'pry'

it 'does something' do
  model = create(:model)
  binding.pry  # Pauses execution here
  expect(model.method_name).to eq(expected)
end
```

## 14. Common Solutions

| Problem | Solution |
|---------|----------|
| Factory invalid | Add required fields/associations to factory |
| Validation error | Check model validations, fix factory data |
| Association not found | Use `let!` or `create` instead of `let`/`build` |
| Wrong tenant | Wrap test in `ActsAsTenant.with_tenant(org) do` |
| Callback not running | Ensure you're using `create` not `build` |
| Scope returns wrong data | Check SQL output, verify data setup |
| Time comparison fails | Use `freeze_time` or match time ranges |
| Enum comparison fails | Check if comparing string vs symbol |
| Mock not working | Verify mock is set before method call |
| Stale data | Use `reload` to get fresh data from DB |

## 15. Test-Specific Issues

### Model Tests
- [ ] Are validations being tested correctly?
- [ ] Are associations using correct matchers?
- [ ] Are callbacks tested in isolation?
- [ ] Are instance methods receiving correct data?

### Service Tests
- [ ] Is service object initialized correctly?
- [ ] Are error messages being populated?
- [ ] Are database changes happening?
- [ ] Are external services mocked?

### Request/Controller Tests
- [ ] Is user authenticated?
- [ ] Does user have correct permissions?
- [ ] Are params formatted correctly?
- [ ] Is correct HTTP method used?

## 16. Check Test Environment

```bash
# Rails version
rails --version

# Database state
RAILS_ENV=test rails db:version

# Reset test database
RAILS_ENV=test rails db:drop db:create db:migrate

# Check for pending migrations
RAILS_ENV=test rails db:migrate:status
```

## 17. Isolation Test

Run the failing test alone:

```bash
# Run single test
bundle exec rspec spec/models/model_spec.rb:42

# Run single describe block
bundle exec rspec spec/models/model_spec.rb -e "validations"
```

If it passes alone but fails in suite:
- [ ] Test is dependent on previous test state
- [ ] Database cleanup issue
- [ ] Shared state in `before(:all)` block
- [ ] Race condition with parallel execution

## 18. Nuclear Option

If all else fails:

1. Delete the test
2. Manually test the behavior in `rails console`
3. Document what actually happens
4. Rewrite test to match actual behavior
5. If behavior is wrong, fix the code first
6. Then write test for correct behavior

## Success Criteria

Test is ready when:
- [ ] Passes 10 times in a row locally
- [ ] Clear, descriptive test name
- [ ] Tests one specific behavior
- [ ] Uses appropriate matchers
- [ ] Minimal test data setup
- [ ] No debug output (`puts`, `binding.pry`)
- [ ] Fast execution (< 0.1s per test ideal)
- [ ] Independent of other tests

## Prevention Checklist

To avoid future test failures:

- [ ] Use factories for all test data
- [ ] Always wrap in tenant context if multi-tenant
- [ ] Use `freeze_time` for time-dependent tests
- [ ] Mock external services
- [ ] Test one behavior per test
- [ ] Use descriptive test names
- [ ] Keep tests simple and readable
- [ ] Validate factories regularly
- [ ] Run tests frequently during development
