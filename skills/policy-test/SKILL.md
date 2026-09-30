---
name: policy-test
description: Generate RSpec tests for a Pundit policy following the application's patterns
---

# Pundit Policy Test Generator Command

You are an expert Rails Pundit policy test developer. Write comprehensive, fast, and maintainable RSpec policy tests for the application following established patterns and best practices for Rails 8 and Pundit authorization.

## Core Principles

### 1. Comprehensive Coverage
- Test all standard CRUD actions (index?, show?, create?, new?, update?, edit?, destroy?)
- Test all custom policy methods specific to the policy
- Test policy scopes (Scope#resolve)
- Test role-based authorization (admin, coordinator, therapist, supervisor, manager, biller)
- Test resource ownership and assignment-based access
- Test organization-level access (multi-tenancy)
- Test edge cases (nil user, users without roles, cross-organization access)
- Test inherited actions (new? delegates to create?, edit? delegates to update?)
- Test users with multiple roles
- Test special relationships (supervisor-supervisee, manager-managed users)

### 2. Write Fast, Efficient Tests
- Use `build` instead of `create` when database persistence is not required
- Use `let` for lazy evaluation, `let!` for immediate evaluation
- Avoid unnecessary database hits
- Use deterministic data with sequences, not random values
- Test authorization logic, not implementation details

### 3. Follow Established Patterns
Reference these policy test files for patterns:
- `spec/policies/` directory for existing policy tests
- `app/policies/application_policy.rb` for base policy structure
- Existing policy specs demonstrate comprehensive role and edge case testing

## Test File Structure

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PolicyName, type: :policy do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:record) { create(:model_name, organization: organization) }

  subject { described_class.new(user, record) }

  before do
    ActsAsTenant.current_tenant = organization
  end

  describe '#index?' do
    # Test each role with context blocks
  end

  describe '#show?' do
    # Test viewing permissions for each role
  end

  describe '#create?' do
    # Test creation permissions
  end

  describe '#new?' do
    # Test that it delegates to create?
  end

  describe '#update?' do
    # Test update permissions
  end

  describe '#edit?' do
    # Test that it delegates to update?
  end

  describe '#destroy?' do
    # Test deletion permissions
  end

  describe '#custom_action?' do
    # Test any custom policy methods
  end

  describe 'Scope' do
    describe '#resolve' do
      # Test scope filtering for each role
    end
  end

  describe 'inherited actions' do
    # Test delegated actions like new? and edit?
  end

  describe 'edge cases' do
    # Test nil user, users without roles, cross-org access, etc.
  end
end
```

## Key Testing Patterns

### Subject Declaration
```ruby
# For instance-level actions (show?, update?, destroy?)
subject { described_class.new(user, record) }

# For class-level actions (index?, create?)
subject { described_class.new(user, ModelClass) }
```

### Testing Authorization with Expectations
```ruby
context 'when user is an admin' do
  let(:user) { create(:user, :admin, organization: organization) }

  it 'allows access' do
    expect(subject.index?).to be true
  end
end

context 'when user is a biller' do
  let(:user) { create(:user, :biller, organization: organization) }

  it 'denies access' do
    expect(subject.index?).to be false
  end
end
```

### Testing Scopes
```ruby
describe 'Scope' do
  describe '#resolve' do
    let!(:record1) { create(:model, organization: organization) }
    let!(:record2) { create(:model, organization: organization) }
    let!(:other_org_record) do
      ActsAsTenant.without_tenant do
        create(:model, organization: other_organization)
      end
    end

    context 'when user is an admin' do
      let(:user) { create(:user, :admin, organization: organization) }

      it 'returns all records in the organization' do
        scope = Pundit.policy_scope(user, Model)
        expect(scope).to include(record1, record2)
        expect(scope).not_to include(other_org_record)
      end
    end

    context 'when user is a therapist' do
      let(:user) { create(:user, :therapist, organization: organization) }

      before do
        # Create assignment relationship
        create(:assignment, user: user, record: record1)
      end

      it 'returns only assigned records' do
        scope = Pundit.policy_scope(user, Model)
        expect(scope).to include(record1)
        expect(scope).not_to include(record2)
      end
    end
  end
end
```

### Testing Delegated Actions
```ruby
describe '#new?' do
  context 'when user is an admin' do
    let(:user) { create(:user, :admin, organization: organization) }

    it 'delegates to create? and allows access' do
      expect(subject.new?).to eq(subject.create?)
      expect(subject.new?).to be true
    end
  end

  context 'when user cannot create' do
    let(:user) { create(:user, :therapist, organization: organization) }

    it 'delegates to create? and denies access' do
      expect(subject.new?).to eq(subject.create?)
      expect(subject.new?).to be false
    end
  end
end
```

### Testing Multi-Tenancy and Cross-Organization Access
```ruby
context 'when user is from a different organization' do
  let(:user) do
    ActsAsTenant.without_tenant do
      create(:user, :admin, organization: other_organization)
    end
  end

  it 'denies access across organizations' do
    expect(subject.show?).to be false
  end
end
```

### Testing Assignment-Based Access
```ruby
context 'when user is a therapist' do
  let(:user) { create(:user, :therapist, organization: organization) }

  context 'when therapist is assigned to the record' do
    before do
      create(:assignment, user: user, record: record)
    end

    it 'allows access' do
      expect(subject.show?).to be true
    end
  end

  context 'when therapist is not assigned to the record' do
    it 'denies access' do
      expect(subject.show?).to be false
    end
  end
end
```

### Testing Edge Cases
```ruby
describe 'edge cases' do
  describe 'nil user' do
    let(:user) { nil }

    it 'raises NoMethodError or returns falsey when accessing policy methods' do
      expect { subject.index? }.to raise_error(NoMethodError)
      # Or for methods that handle nil gracefully:
      # expect(subject.create?).to be_falsey
    end
  end

  describe 'user with no roles' do
    let(:user) { create(:user, organization: organization, role_names: []) }

    it 'denies access' do
      expect(subject.show?).to be false
    end
  end

  describe 'user with multiple roles' do
    let(:user) { create(:user, organization: organization, role_names: [:admin, :therapist]) }

    it 'allows admin-level access' do
      expect(subject.destroy?).to be true
    end
  end

  describe 'soft-deleted records' do
    let(:deleted_record) { create(:model, organization: organization, deleted_at: Time.current) }

    context 'when user is admin' do
      let(:user) { create(:user, :admin, organization: organization) }

      it 'includes soft-deleted records in scope' do
        scope = Pundit.policy_scope(user, Model)
        expect(scope).to include(deleted_record)
      end
    end
  end
end
```

## Instructions for AI

When the user provides a policy file path as `$ARGUMENTS`, follow this iterative workflow until ALL tests pass:

### Phase 1: Analysis and Test Generation

1. **Read the policy file** at `$ARGUMENTS`
2. **Determine test file path**: Convert policy path to spec path
   - `app/policies/foo_policy.rb` → `spec/policies/foo_policy_spec.rb`
   - `app/policies/client_portal/foo_policy.rb` → `spec/policies/client_portal/foo_policy_spec.rb`
3. **Check if spec file exists** at the determined path
4. **Analyze the policy** to identify:
   - Policy class name and inheritance (should inherit from ApplicationPolicy)
   - All public policy methods (index?, show?, create?, update?, destroy?, custom methods)
   - Delegated methods (new?, edit?)
   - Role checks (has_role?, has_any_role?)
   - Organization checks (user.organization == record.organization)
   - Assignment/ownership checks (record.user == user, accessible_clients, etc.)
   - Scope implementation (Scope#resolve)
   - Special authorization logic (conditions, custom queries)
5. **If test file exists**, read it and identify:
   - What is already tested
   - What is missing
   - What needs improvement
6. **Generate or update tests** following the patterns in this document
7. **Ensure comprehensive coverage** of:
   - All policy methods
   - All roles in the application (admin, coordinator, therapist, supervisor, manager, biller)
   - Edge cases
   - Scope behavior
8. **Use factories** defined in `spec/factories/` or suggest new ones

### Phase 2: Iterative Test Execution and Fixes

**CRITICAL: Do not stop until all tests pass. Repeat this loop until success:**

1. **Run the tests** for the specific policy:
   ```bash
   bundle exec rspec spec/policies/policy_name_spec.rb
   ```

2. **Analyze test results**:
   - If ALL tests pass → Report success and exit
   - If ANY tests fail → Continue to step 3

3. **For each test failure**:
   - Read and understand the error message
   - Identify the root cause:
     - Missing factory attributes
     - Incorrect test expectations
     - Missing role assignments
     - Incorrect organization setup
     - Missing associated records (assignments, therapist relationships)
     - Multi-tenant issues (ActsAsTenant.without_tenant needed)
     - Incorrect use of Pundit.policy_scope vs PolicyClass::Scope.new

4. **Fix the failure**:
   - Update factory if needed
   - Fix test expectations if they're incorrect
   - Update test setup (add missing let! blocks, create associations)
   - Fix multi-tenancy issues
   - **DO NOT modify the policy unless there's a genuine bug**

5. **Return to step 1** and run tests again

### Phase 3: Final Verification

Once all tests pass:

1. **Run the full test suite** one more time to confirm
2. **Provide a summary** including:
   - Total number of examples and failures (should be 0 failures)
   - What was fixed during the iteration
   - Final test coverage breakdown
   - Any recommendations for the policy or tests

## Test Organization Checklist

For every policy test file, verify:

- [ ] `require 'rails_helper'` at top
- [ ] `type: :policy` metadata
- [ ] Multi-tenant setup with `ActsAsTenant.current_tenant`
- [ ] Subject declaration appropriate for each describe block
- [ ] Test all standard CRUD actions (index?, show?, create?, new?, update?, edit?, destroy?)
- [ ] Test all custom policy methods
- [ ] Test policy scope (Scope#resolve) for all relevant roles
- [ ] Test all application roles (admin, coordinator, therapist, supervisor, manager, biller)
- [ ] Test ownership and assignment-based access
- [ ] Test cross-organization access (should deny)
- [ ] Test inherited actions (new? → create?, edit? → update?)
- [ ] Test edge cases (nil user, no roles, multiple roles, soft-deleted records)
- [ ] Use `let` for lazy evaluation
- [ ] Use `build` instead of `create` when possible
- [ ] Use `ActsAsTenant.without_tenant` for cross-org scenarios
- [ ] Test both positive (allows) and negative (denies) cases

## Common Failure Patterns and Solutions

1. **Factory validation failures**: Ensure factory has all required attributes
2. **Role check failures**: Verify user has correct roles using `:admin`, `:therapist` traits
3. **Association errors**: Create assignments, client_therapist records, or other relationships
4. **Multi-tenant errors**: Always set `ActsAsTenant.current_tenant` in before block
5. **Scope errors**: Use correct scope syntax (`Pundit.policy_scope` vs `PolicyClass::Scope.new`)
6. **Organization mismatch**: Create cross-org records inside `ActsAsTenant.without_tenant` block
7. **Nil user handling**: Some policies may not handle nil users gracefully - test both NoMethodError and falsey returns
8. **Custom method coverage**: Don't forget to test all custom policy methods, not just CRUD actions

## Common Policy Roles in the Application

The application uses these roles (from lowest to highest privilege):

- **biller**: Billing-related access only
- **therapist**: Can view/manage assigned clients and appointments
- **supervisor**: Like therapist, plus can supervise other therapists
- **manager**: Can manage users and organizational resources
- **coordinator**: Full operational access to clients and appointments
- **admin**: Full system access including user management
- **platform_admin**: Platform-level access across organizations (rare)

## Authorization Patterns to Test

1. **Role-based**: `user.has_role?(:admin)`
2. **Multi-role**: `user.has_any_role?(:admin, :coordinator)`
3. **Ownership**: `record.user == user`
4. **Assignment**: `user.accessible_clients.include?(record)`
5. **Organization**: `user.organization == record.organization`
6. **Supervisor relationship**: `user.supervisees.include?(other_user)`
7. **Manager relationship**: `user.managed_users.include?(other_user)`
8. **Combined conditions**: Multiple checks with AND/OR logic

## Best Practices from Pundit Documentation

- **Use subject declaration**: Makes tests more readable and DRY
- **Test scopes separately**: Scopes are just Ruby classes, test them thoroughly
- **Avoid testing implementation**: Test authorization outcomes, not internal logic
- **Use pundit-matchers gem patterns**: While not installed, follow similar patterns
- **Test nil user behavior**: Document how policies handle missing authentication
- **Test Rails 8 compatibility**: Ensure policies work with Current.user pattern

## Sources

Based on best practices from:
- [Pundit GitHub](https://github.com/varvet/pundit)
- [Pundit Matchers](https://github.com/pundit-community/pundit-matchers)
- [Testing Pundit Policies with RSpec](https://www.thunderboltlabs.com/blog/2013/03/27/testing-pundit-policies-with-rspec/)
- Existing policy test patterns in the application
