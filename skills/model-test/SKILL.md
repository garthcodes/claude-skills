---
name: model-test
description: Generate RSpec model tests (validations, associations, scopes) following the application's patterns
---

# Model Test Generator Command

You are an expert Rails model test developer. Write comprehensive, fast, and maintainable RSpec model tests for the application following established patterns and best practices.

## Core Principles

### 1. Comprehensive Coverage
- Test all validations (presence, uniqueness, format, conditional)
- Test all associations (belongs_to, has_many, has_one, polymorphic)
- Test all scopes with various data scenarios
- Test all instance methods (public methods only)
- Test all class methods
- Test callbacks and their side effects
- Test enums and state transitions
- Test database constraints
- Test edge cases and error conditions

### 2. Write Fast, Efficient Tests
- Use `build` instead of `create` when database persistence is not required
- Use `let` for lazy evaluation, `let!` for immediate evaluation
- Avoid unnecessary database hits
- Use shoulda-matchers for one-liner tests where appropriate
- Minimize use of `before(:each)` hooks - prefer `let` or `let!`
- Test N+1 queries with proper eager loading verification
- Use deterministic data with sequences, not random values

### 3. Follow Established Patterns
Reference these model test files for patterns:
- `spec/models/user_spec.rb` - Complex associations, scopes, callbacks
- `spec/models/clinical_document_spec.rb` - Enums, state machines, polymorphic associations
- `docs/testing/RSPEC_MODEL_TESTING_GUIDE.md` - Comprehensive testing guide

## Test File Structure

### Standard Test Template
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModelName, type: :model do
  # Setup with let/let! - minimal, deterministic data
  let(:organization) { create(:organization) }
  let(:model) { build(:model_name, organization: organization) }

  describe "validations" do
    # Validation tests here
  end

  describe "associations" do
    # Association tests here

    describe "association behavior" do
      # Test dependent: :destroy, ordering, etc.
    end
  end

  describe "nested attributes" do
    # Test accepts_nested_attributes_for if present
  end

  describe "enums" do
    # Enum tests here
  end

  describe "scopes" do
    # Scope tests here
  end

  describe "callbacks" do
    # Callback tests here
  end

  describe "instance methods" do
    # Instance method tests here
  end

  describe "class methods" do
    # Class method tests here
  end

  describe "database constraints" do
    # Test database-level constraints
  end

  describe "factory data validation" do
    # Verify factories work correctly
  end

  describe "error handling" do
    # Test validation errors, custom exceptions
  end
end
```

### Test Naming Conventions
- Use descriptive describe blocks: `describe "#method_name"` for instance methods, `describe ".method_name"` for class methods
- Use contexts for different scenarios: `context "when user is admin"`, `context "with existing data"`
- Use clear it/scenario descriptions: `"returns only active records"`, `"raises error when invalid"`
- Group related tests logically

## Validation Testing

### Basic Validation Tests (Use Shoulda Matchers)
```ruby
describe "validations" do
  # Presence validations
  it { should validate_presence_of(:name) }
  it { should validate_presence_of(:email) }

  # Uniqueness validations
  it { should validate_uniqueness_of(:email).case_insensitive }
  it { should validate_uniqueness_of(:slug).scoped_to(:organization_id) }

  # Length validations
  it { should validate_length_of(:password).is_at_least(8) }
  it { should validate_length_of(:title).is_at_most(255) }

  # Inclusion/Exclusion validations
  it { should validate_inclusion_of(:status).in_array(%w[active inactive]) }
  it { should validate_exclusion_of(:role).in_array(%w[restricted banned]) }

  # Numericality validations
  it { should validate_numericality_of(:age).is_greater_than(0) }
  it { should validate_numericality_of(:price).is_greater_than_or_equal_to(0) }

  # Format validations
  it { should allow_value('test@example.com').for(:email) }
  it { should_not allow_value('invalid-email').for(:email) }
end
```

### Complex Validation Testing
```ruby
describe "email validation" do
  let(:user) { build(:user, email: email) }

  context "with valid email" do
    let(:email) { "test@example.com" }

    it "is valid" do
      expect(user).to be_valid
    end
  end

  context "with invalid email" do
    let(:email) { "invalid-email" }

    it "is invalid" do
      expect(user).to be_invalid
      expect(user.errors[:email]).to include("is invalid")
    end
  end
end
```

### Conditional Validations
```ruby
describe "conditional validations" do
  context "when model is in active state" do
    let(:model) { build(:model_name, status: :active) }

    it { expect(model).to validate_presence_of(:required_field) }
  end

  context "when model is in pending state" do
    let(:model) { build(:model_name, status: :pending) }

    it { expect(model).not_to validate_presence_of(:required_field) }
  end
end
```

### Custom Validation Methods
```ruby
describe "custom validations" do
  context "when custom validation fails" do
    let(:model) { build(:model_name, invalid_attribute: "bad_value") }

    it "adds custom error message" do
      expect(model).to be_invalid
      expect(model.errors[:base]).to include("Custom error message")
    end
  end
end
```

## Association Testing

### Basic Association Tests (Use Shoulda Matchers)
```ruby
describe "associations" do
  # belongs_to
  it { should belong_to(:organization) }
  it { should belong_to(:user).optional }
  it { should belong_to(:author).class_name('User').with_foreign_key('author_id') }

  # has_many
  it { should have_many(:posts).dependent(:destroy) }
  it { should have_many(:comments).through(:posts) }
  it { should have_many(:active_posts).class_name('Post').conditions(active: true) }

  # has_one
  it { should have_one(:profile).dependent(:destroy) }
  it { should have_one(:avatar).through(:profile) }

  # has_and_belongs_to_many
  it { should have_and_belong_to_many(:roles) }

  # Polymorphic
  it { should belong_to(:taggable).optional }
  it { should have_many(:tags).as(:taggable) }
end
```

### Association Behavior Testing
```ruby
describe "association behavior" do
  let!(:parent) { create(:parent) }

  describe "ordering" do
    it "orders children by created_at desc" do
      old_child = create(:child, parent: parent, created_at: 2.days.ago)
      new_child = create(:child, parent: parent, created_at: 1.hour.ago)

      expect(parent.reload.children).to eq([new_child, old_child])
    end
  end

  describe "dependent destroy" do
    it "destroys associated children when parent is deleted" do
      create_list(:child, 3, parent: parent)

      expect { parent.destroy }.to change(Child, :count).by(-3)
    end
  end

  describe "through associations" do
    it "returns correct records through intermediate association" do
      child = create(:child, parent: parent)
      grandchild = create(:grandchild, child: child)

      expect(parent.grandchildren).to include(grandchild)
    end
  end
end
```

### Polymorphic Association Testing
```ruby
describe "polymorphic associations" do
  let(:user) { create(:user) }
  let(:comment) { create(:comment, commentable: user) }

  it "can be associated with users" do
    expect(comment.commentable).to eq(user)
    expect(comment.commentable_type).to eq('User')
  end

  it "returns comments for the polymorphic parent" do
    expect(user.comments).to include(comment)
  end
end
```

### Nested Attributes Testing
```ruby
describe "nested attributes" do
  it { should accept_nested_attributes_for(:addresses).allow_destroy(true) }

  describe "address creation via nested attributes" do
    let(:user) { create(:user) }
    let(:address_params) do
      { addresses_attributes: [{ street: '123 Main St', city: 'Boston' }] }
    end

    it "creates associated addresses" do
      expect { user.update(address_params) }.to change(Address, :count).by(1)
    end
  end

  describe "nested attribute rejection" do
    it "rejects invalid nested records" do
      user = create(:user)
      user.update(addresses_attributes: [{ street: '' }])

      expect(user.addresses.count).to eq(0)
    end
  end
end
```

## Scope Testing

### Basic Scope Tests
```ruby
describe "scopes" do
  let!(:active_record) { create(:model_name, status: :active, created_at: 1.hour.ago) }
  let!(:inactive_record) { create(:model_name, status: :inactive, created_at: 2.days.ago) }

  describe ".active" do
    it "returns only active records" do
      expect(ModelName.active).to include(active_record)
      expect(ModelName.active).not_to include(inactive_record)
    end
  end

  describe ".recent" do
    it "orders records by creation date descending" do
      results = ModelName.recent

      expect(results.first).to eq(active_record)
      expect(results.last).to eq(inactive_record)
    end
  end

  describe ".created_after" do
    it "returns records created after specified date" do
      results = ModelName.created_after(1.day.ago)

      expect(results).to include(active_record)
      expect(results).not_to include(inactive_record)
    end
  end
end
```

### Scope Chaining Tests
```ruby
describe "scope chaining" do
  let!(:active_recent) { create(:model_name, status: :active, created_at: 1.hour.ago) }
  let!(:active_old) { create(:model_name, status: :active, created_at: 10.days.ago) }
  let!(:inactive_recent) { create(:model_name, status: :inactive, created_at: 2.hours.ago) }

  it "chains multiple scopes correctly" do
    results = ModelName.active.recent

    expect(results).to include(active_recent, active_old)
    expect(results).not_to include(inactive_recent)
    expect(results.first).to eq(active_recent)
  end
end
```

### Complex Scope Tests with Joins
```ruby
describe ".with_approved_comments" do
  let(:model_with_approved) { create(:model_name) }
  let(:model_without_approved) { create(:model_name) }

  before do
    create(:comment, commentable: model_with_approved, status: :approved)
    create(:comment, commentable: model_without_approved, status: :pending)
  end

  it "returns only models with approved comments" do
    results = ModelName.with_approved_comments

    expect(results).to include(model_with_approved)
    expect(results).not_to include(model_without_approved)
  end
end
```

## Enum Testing

### Basic Enum Tests
```ruby
describe "enums" do
  it { should define_enum_for(:status).with_values(
    active: 0,
    inactive: 1,
    pending: 2
  ).with_prefix(:status) }

  describe "status enum behavior" do
    let(:model) { create(:model_name, status: :pending) }

    it "provides status check methods" do
      expect(model).to be_status_pending
      expect(model).not_to be_status_active
      expect(model).not_to be_status_inactive
    end

    it "allows status transitions" do
      model.status_active!
      expect(model).to be_status_active
      expect(model.reload.status).to eq('active')
    end

    it "provides status scopes" do
      active = create(:model_name, status: :active)

      expect(ModelName.status_active).to include(active)
      expect(ModelName.status_active).not_to include(model)
    end
  end
end
```

## Callback Testing

### Testing Callbacks
```ruby
describe "callbacks" do
  describe "before_validation" do
    let(:model) { build(:model_name, email: '  TEST@EXAMPLE.COM  ') }

    it "normalizes email before validation" do
      model.valid?
      expect(model.email).to eq('test@example.com')
    end
  end

  describe "before_save" do
    let(:model) { build(:model_name) }

    it "sets default values" do
      expect { model.save }.to change { model.slug }.from(nil)
    end
  end

  describe "after_create" do
    let(:model) { build(:model_name) }

    it "sends notification email" do
      expect(ModelMailer).to receive(:notification).with(model).and_call_original
      expect { model.save }.to have_enqueued_mail(ModelMailer, :notification)
    end

    it "creates associated record" do
      expect { model.save }.to change(AssociatedModel, :count).by(1)
    end
  end

  describe "after_update" do
    let(:model) { create(:model_name, status: :pending) }

    it "triggers status change callback" do
      expect(model).to receive(:notify_status_change)
      model.update(status: :active)
    end
  end

  describe "before_destroy" do
    let(:model) { create(:model_name) }

    it "archives data before deletion" do
      expect(model).to receive(:archive_data)
      model.destroy
    end
  end

  describe "after_commit" do
    let(:model) { build(:model_name) }

    it "executes after transaction commits" do
      expect(ExternalService).to receive(:notify)
      model.save
    end
  end
end
```

## Instance Method Testing

### Basic Instance Methods
```ruby
describe "instance methods" do
  let(:model) { build(:model_name, first_name: "John", last_name: "Doe") }

  describe "#full_name" do
    it "returns concatenated first and last name" do
      expect(model.full_name).to eq("John Doe")
    end

    context "when first_name is missing" do
      let(:model) { build(:model_name, first_name: nil, last_name: "Doe") }

      it "returns only last name" do
        expect(model.full_name).to eq("Doe")
      end
    end

    context "when both names are missing" do
      let(:model) { build(:model_name, first_name: nil, last_name: nil, email: "test@example.com") }

      it "returns email" do
        expect(model.full_name).to eq("test@example.com")
      end
    end
  end

  describe "#active?" do
    context "when status is active" do
      let(:model) { build(:model_name, status: :active) }

      it { expect(model.active?).to be true }
    end

    context "when status is not active" do
      let(:model) { build(:model_name, status: :inactive) }

      it { expect(model.active?).to be false }
    end
  end

  describe "#deactivate!" do
    let(:model) { create(:model_name, status: :active, deactivated_at: nil) }

    it "changes status to inactive" do
      expect { model.deactivate! }.to change(model, :status).from('active').to('inactive')
    end

    it "sets deactivated_at timestamp" do
      freeze_time do
        expect { model.deactivate! }.to change(model, :deactivated_at).from(nil).to(Time.current)
      end
    end
  end
end
```

### Methods with Complex Logic
```ruby
describe "#calculate_total" do
  let(:model) { create(:model_name) }

  context "with no items" do
    it "returns zero" do
      expect(model.calculate_total).to eq(0)
    end
  end

  context "with items" do
    before do
      create_list(:item, 3, model: model, price: 10)
    end

    it "returns sum of item prices" do
      expect(model.calculate_total).to eq(30)
    end
  end

  context "with discount" do
    before do
      create(:item, model: model, price: 100)
      model.update(discount_percentage: 20)
    end

    it "applies discount to total" do
      expect(model.calculate_total).to eq(80)
    end
  end
end
```

### Methods that Change State
```ruby
describe "#process!" do
  let(:model) { create(:model_name, status: :pending) }

  it "transitions status to processing" do
    expect { model.process! }.to change(model, :status).from('pending').to('processing')
  end

  it "sets processed_at timestamp" do
    freeze_time do
      model.process!
      expect(model.processed_at).to eq(Time.current)
    end
  end

  it "creates audit log entry" do
    expect { model.process! }.to change(AuditLog, :count).by(1)
  end

  context "when already processed" do
    let(:model) { create(:model_name, status: :completed) }

    it "raises error" do
      expect { model.process! }.to raise_error(ModelName::AlreadyProcessedError)
    end
  end
end
```

## Class Method Testing

### Basic Class Methods
```ruby
describe "class methods" do
  describe ".find_by_identifier" do
    let!(:model) { create(:model_name, identifier: "ABC-123") }

    it "finds record by identifier" do
      result = ModelName.find_by_identifier("ABC-123")
      expect(result).to eq(model)
    end

    it "returns nil when not found" do
      result = ModelName.find_by_identifier("NONEXISTENT")
      expect(result).to be_nil
    end

    it "is case insensitive" do
      result = ModelName.find_by_identifier("abc-123")
      expect(result).to eq(model)
    end
  end

  describe ".search" do
    let!(:match1) { create(:model_name, name: "Ruby on Rails") }
    let!(:match2) { create(:model_name, name: "Rails API") }
    let!(:no_match) { create(:model_name, name: "Python Django") }

    it "returns records matching search term" do
      results = ModelName.search("Rails")

      expect(results).to include(match1, match2)
      expect(results).not_to include(no_match)
    end

    it "handles empty search term" do
      results = ModelName.search("")
      expect(results).to include(match1, match2, no_match)
    end
  end

  describe ".generate_identifier" do
    it "generates unique identifier" do
      id1 = ModelName.generate_identifier
      id2 = ModelName.generate_identifier

      expect(id1).to be_present
      expect(id2).to be_present
      expect(id1).not_to eq(id2)
    end

    it "generates identifier with correct format" do
      identifier = ModelName.generate_identifier
      expect(identifier).to match(/\A[A-Z]{3}-\d{4}\z/)
    end
  end
end
```

## Database Constraint Testing

### Testing Database-Level Constraints
```ruby
describe "database constraints" do
  describe "unique constraint on email" do
    it "enforces uniqueness at database level" do
      create(:model_name, email: "test@example.com")

      expect do
        create(:model_name, email: "test@example.com")
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "not null constraint" do
    it "enforces not null on required_field" do
      expect do
        # Bypass validation and attempt to save with null value
        model = ModelName.new
        model.save(validate: false)
      end.to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  describe "foreign key constraint" do
    it "prevents deletion of referenced record" do
      parent = create(:parent)
      create(:child, parent: parent)

      expect { parent.delete }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe "check constraint" do
    it "enforces check constraint" do
      expect do
        # Bypass validation and attempt invalid value
        create(:model_name, price: -10, skip_validation: true)
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end
```

## Performance Testing

### Testing N+1 Queries
```ruby
describe "query performance" do
  let!(:parents) { create_list(:parent, 3) }

  before do
    parents.each { |parent| create_list(:child, 2, parent: parent) }
  end

  describe ".with_children" do
    it "avoids N+1 queries when loading children" do
      # Warm up
      Parent.with_children.first

      # Count queries
      query_count = 0
      callback = lambda { |*args| query_count += 1 }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        Parent.with_children.each { |parent| parent.children.to_a }
      end

      # Should be 2 queries: 1 for parents, 1 for children
      expect(query_count).to be <= 3
    end
  end

  describe "#children_names" do
    it "uses includes to avoid N+1" do
      parent = parents.first

      expect do
        parent.children_names
      end.not_to exceed_query_limit(1)
    end
  end
end
```

### Testing Preloading
```ruby
describe "eager loading" do
  let!(:users) { create_list(:user, 3) }

  before do
    users.each { |user| create_list(:post, 2, user: user) }
  end

  it "preloads associations correctly" do
    loaded_users = User.includes(:posts).all

    # Verify associations are loaded
    expect(loaded_users.first.association(:posts).loaded?).to be true

    # No additional queries should be made
    expect do
      loaded_users.each { |user| user.posts.map(&:title) }
    end.not_to make_database_queries
  end
end
```

## Edge Cases and Error Handling

### Testing Edge Cases
```ruby
describe "edge cases" do
  describe "#calculate_percentage" do
    it "handles zero denominator" do
      model = build(:model_name, total: 0)
      expect(model.calculate_percentage).to eq(0)
    end

    it "handles nil values" do
      model = build(:model_name, total: nil)
      expect(model.calculate_percentage).to eq(0)
    end

    it "handles negative values" do
      model = build(:model_name, total: -100)
      expect { model.calculate_percentage }.to raise_error(ArgumentError, "Total must be positive")
    end
  end

  describe "#truncate_text" do
    it "handles empty string" do
      expect(ModelName.truncate_text("", 10)).to eq("")
    end

    it "handles nil" do
      expect(ModelName.truncate_text(nil, 10)).to be_nil
    end

    it "handles text shorter than limit" do
      expect(ModelName.truncate_text("short", 10)).to eq("short")
    end
  end
end
```

### Testing Error Handling
```ruby
describe "error handling" do
  describe "validation errors" do
    let(:invalid_model) { build(:model_name, email: nil, name: nil) }

    it "provides meaningful error messages" do
      invalid_model.valid?

      expect(invalid_model.errors[:email]).to include("can't be blank")
      expect(invalid_model.errors[:name]).to include("can't be blank")
    end

    it "accumulates multiple errors" do
      invalid_model.valid?
      expect(invalid_model.errors.count).to be >= 2
    end
  end

  describe "custom exceptions" do
    let(:model) { create(:model_name, status: :inactive) }

    it "raises custom error for invalid operation" do
      expect do
        model.activate_premium_features!
      end.to raise_error(ModelName::InactiveModelError, /cannot activate/i)
    end
  end

  describe "rescue from errors" do
    let(:model) { create(:model_name) }

    before do
      allow(ExternalService).to receive(:call).and_raise(StandardError, "Service unavailable")
    end

    it "handles external service errors gracefully" do
      result = model.sync_with_external_service

      expect(result).to be false
      expect(model.errors[:base]).to include("External service error")
    end
  end
end
```

## Factory Validation

### Testing Factory Data
```ruby
describe "factory data validation" do
  it "creates valid model with factory" do
    model = create(:model_name)

    expect(model).to be_valid
    expect(model).to be_persisted
  end

  it "creates valid model with all traits" do
    [:active, :with_children, :premium].each do |trait|
      model = create(:model_name, trait)
      expect(model).to be_valid
    end
  end

  describe "factory traits" do
    it "creates active model" do
      model = create(:model_name, :active)
      expect(model.status).to eq('active')
    end

    it "creates model with associations" do
      model = create(:model_name, :with_children)
      expect(model.children.count).to be > 0
    end
  end

  describe "build vs create" do
    it "builds valid model without saving" do
      model = build(:model_name)
      expect(model).to be_valid
      expect(model).not_to be_persisted
    end

    it "creates and persists valid model" do
      model = create(:model_name)
      expect(model).to be_persisted
    end
  end
end
```

## Best Practices Checklist

When writing model tests, ensure you:

- [ ] Use `frozen_string_literal: true` at the top of the file
- [ ] Include `require "rails_helper"`
- [ ] Use `type: :model` in RSpec.describe
- [ ] Use shoulda-matchers for one-liner tests (validations, associations)
- [ ] Test both positive and negative cases
- [ ] Use `let` for lazy evaluation, `let!` for immediate evaluation
- [ ] Use `build` instead of `create` when persistence is not required
- [ ] Test conditional validations in separate contexts
- [ ] Test enum state transitions and query methods
- [ ] Test callback side effects (emails, jobs, associated record creation)
- [ ] Test association ordering and dependent destroy behavior
- [ ] Test scopes with realistic data scenarios
- [ ] Test edge cases (nil, empty, zero, negative values)
- [ ] Test error messages and custom exceptions
- [ ] Verify N+1 queries are prevented with proper eager loading
- [ ] Use `freeze_time` for testing time-sensitive logic
- [ ] Group related tests in describe/context blocks
- [ ] Keep test data minimal and deterministic
- [ ] Test database constraints separately from model validations
- [ ] Verify factory data is valid
- [ ] Test both public instance and class methods (not private methods)

## Multi-Tenant Testing Pattern

For multi-tenant applications using ActsAsTenant:

```ruby
describe "multi-tenant behavior" do
  let(:organization1) { create(:organization) }
  let(:organization2) { create(:organization) }
  let!(:model1) { create(:model_name, organization: organization1) }
  let!(:model2) { create(:model_name, organization: organization2) }

  it "scopes records to current tenant" do
    ActsAsTenant.with_tenant(organization1) do
      expect(ModelName.all).to include(model1)
      expect(ModelName.all).not_to include(model2)
    end
  end

  it "validates uniqueness scoped to organization" do
    ActsAsTenant.with_tenant(organization1) do
      duplicate = build(:model_name, email: model1.email, organization: organization1)
      expect(duplicate).to be_invalid
    end
  end
end
```

## Time-Sensitive Testing

```ruby
describe "time-sensitive methods" do
  describe "#expired?" do
    around do |example|
      freeze_time do
        example.run
      end
    end

    context "when expiration date is in the future" do
      let(:model) { build(:model_name, expires_at: 1.day.from_now) }

      it { expect(model.expired?).to be false }
    end

    context "when expiration date is in the past" do
      let(:model) { build(:model_name, expires_at: 1.day.ago) }

      it { expect(model.expired?).to be true }
    end
  end

  describe "#set_expiration" do
    it "sets expiration 30 days from now by default" do
      freeze_time do
        model = create(:model_name)
        model.set_expiration

        expect(model.expires_at).to eq(30.days.from_now)
      end
    end
  end
end
```

## Testing Private Methods (Indirectly)

Do not test private methods directly. Test them through public methods:

```ruby
describe "#public_method_that_uses_private" do
  let(:model) { create(:model_name) }

  # This tests the private method indirectly through the public interface
  it "produces correct result" do
    result = model.public_method_that_uses_private
    expect(result).to eq(expected_value)
  end
end
```

## Output Format

When generating or updating model tests, provide:

1. **Complete test file** with proper structure and organization
2. **Factory definitions** if new factories are needed or existing ones need updates
3. **Brief explanation** of test coverage including:
   - What validations are tested
   - What associations are tested
   - What methods are tested
   - Any edge cases covered
   - Any performance considerations
4. **Coverage summary** listing:
   - ✅ What is fully tested
   - ⚠️ What has partial coverage
   - ❌ What is not covered

## Instructions for AI

When the user provides a model file, follow this iterative workflow until ALL tests pass:

### Phase 1: Analysis and Test Generation

1. **Read the model file** at the provided path
2. **Check if spec file exists** at `spec/models/model_name_spec.rb`
3. **Analyze the model** to identify:
   - All validations (including conditional ones)
   - All associations (with options like dependent, through, etc.)
   - All scopes
   - All enums
   - All callbacks
   - All public instance methods
   - All public class methods
   - Database columns and constraints
4. **If test file exists**, read it and identify:
   - What is already tested
   - What is missing
   - What needs improvement
5. **Generate or update tests** following this guide
6. **Ensure comprehensive coverage** of all model behavior
7. **Use factories** defined in `spec/factories/` or suggest new ones
8. **Follow existing patterns** from the codebase

### Phase 2: Iterative Test Execution and Fixes

**CRITICAL: Do not stop until all tests pass. Repeat this loop until success:**

1. **Run the tests** for the specific model:
   ```bash
   bundle exec rspec spec/models/model_name_spec.rb
   ```

2. **Analyze test results**:
   - If ALL tests pass → Report success and exit
   - If ANY tests fail → Continue to step 3

3. **For each test failure**:
   - Read and understand the error message
   - Identify the root cause:
     - Missing factory attributes
     - Incorrect test expectations
     - Missing validations or associations in the model
     - Incorrect test setup (let/let! usage)
     - Database constraint issues
     - Missing dependent records
     - Timing issues (use freeze_time if needed)
     - N+1 query issues

4. **Fix the failure**:
   - Update factory if needed (`spec/factories/model_name.rb`)
   - Fix test expectations if they're incorrect
   - Update test setup (add missing let! blocks, create associations)
   - Adjust test structure if needed
   - **DO NOT modify the model unless there's a genuine bug** - the goal is to test the existing model

5. **Return to step 1** and run tests again

### Phase 3: Final Verification

Once all tests pass:

1. **Run the full test suite** one more time to confirm
2. **Provide a summary** including:
   - Total number of examples and failures (should be 0 failures)
   - What was fixed during the iteration
   - Final test coverage breakdown
   - Any recommendations for the model or tests

### Test Quality Standards

Focus on writing tests that are:
- **Comprehensive**: Cover all model behavior
- **Fast**: Minimal database hits, use `build` when possible
- **Reliable**: Deterministic data, proper setup/teardown
- **Maintainable**: Clear structure, readable, well-organized
- **Practical**: Test real-world scenarios and edge cases

### Common Failure Patterns and Solutions

When tests fail, check these common issues:

1. **Factory validation failures**: Ensure factory has all required attributes
2. **Association errors**: Create associated records with `let!` or in factory
3. **Uniqueness validation failures**: Use sequences in factories
4. **Shoulda matcher failures**: Verify the matcher matches the actual validation
5. **Enum failures**: Ensure enum values in tests match model definition
6. **Callback failures**: Mock external dependencies (mailers, services)
7. **Time-dependent failures**: Use `freeze_time` for consistent timestamps
8. **Database constraint violations**: Ensure test data satisfies all constraints
