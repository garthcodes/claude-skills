---
name: service-test
description: Generate RSpec tests for a service object following the application's patterns
---

# Service Test Generator Command

You are an expert Rails service test developer. Write comprehensive, fast, and maintainable RSpec service tests for the application following established patterns and best practices.

## Core Principles

### 1. Comprehensive Coverage
- Test all public methods (both class and instance methods)
- Test success and failure scenarios for all operations
- Test Result object returns (success?, failure?, data, error)
- Test Callable concern integration (if included)
- Test service initialization with various parameter combinations
- Test business logic and validation rules
- Test interactions with models and other services
- Test error handling and recovery
- Test transaction safety and rollback behavior
- Test side effects (emails, jobs, external services)
- Test edge cases and boundary conditions

### 2. Write Fast, Efficient Tests
- Use `build` instead of `create` when database persistence is not required
- Use `let` for lazy evaluation, `let!` for immediate evaluation
- Avoid unnecessary database hits
- Minimize use of `before(:each)` hooks - prefer `let` or `let!`
- Mock external dependencies (email services, API calls)
- Use deterministic data with sequences, not random values
- Test database operations with appropriate data setup

### 3. Follow Established Patterns
Reference these service test files for patterns:
- `spec/services/clinical_document_signature_service_spec.rb` - Transaction safety, state changes, multiple roles
- `spec/services/diagnosis_prefill_service_spec.rb` - Business logic, private method testing
- `spec/services/treatment_plan_service_spec.rb` - Complex validation, error handling
- `spec/services/concerns/callable_spec.rb` - Callable concern testing

## Service Architecture Patterns in the Application

### 1. Standard Service Pattern
Services that accept domain object in constructor and provide business logic:
```ruby
class ExampleService
  def initialize(domain_object)
    @domain_object = domain_object
  end

  def perform_action
    # Returns boolean or Result object
  end
end
```

### 2. Callable Service Pattern
Services using the Callable concern that return Result objects:
```ruby
class ExampleService
  include Callable

  def initialize(param1:, param2:)
    @param1 = param1
    @param2 = param2
  end

  def call
    return failure("Error message") if invalid?
    success(data: result_data)
  end
end
```

### 3. Parent Class Services
Services that inherit from other services (e.g., `TreatmentPlanService < ClinicalDocumentService`):
- Test inherited behavior
- Test overridden methods
- Test parent-child interaction

## Test File Structure

### Standard Test Template
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceName, type: :service do
  # Setup with let/let! - minimal, deterministic data
  let(:organization) { create(:organization) }
  let(:user) { create(:user, :therapist, organization: organization) }
  let(:domain_object) { create(:model_name, organization: organization) }
  let(:service) { described_class.new(domain_object) }

  describe "#initialize" do
    # Test initialization scenarios
  end

  describe "#public_method_name" do
    # Test public method behavior
  end

  describe "business logic scenarios" do
    # Test complex workflows
  end

  describe "error handling" do
    # Test error conditions
  end

  describe "edge cases and boundary conditions" do
    # Test edge cases
  end

  describe "integration scenarios" do
    # Test real-world workflows
  end

  describe "private methods" do
    # Only when necessary to test through public interface
  end
end
```

### Test Naming Conventions
- Use descriptive describe blocks: `describe "#method_name"` for instance methods, `describe ".method_name"` for class methods
- Use contexts for different scenarios: `context "when user is admin"`, `context "with valid parameters"`
- Use clear it/scenario descriptions: `"returns success result"`, `"creates audit log entry"`
- Group related tests logically

## Initialization Testing

### Basic Initialization
```ruby
describe "#initialize" do
  context "with valid parameters" do
    let(:service) { described_class.new(valid_param) }

    it "creates a service object" do
      expect(service).to be_a(described_class)
    end

    it "sets instance variables correctly" do
      expect(service.instance_variable_get(:@param)).to eq(valid_param)
    end

    it "accepts provided parameters without error" do
      expect { described_class.new(valid_param) }.not_to raise_error
    end
  end

  context "with nil parameters" do
    it "accepts nil parameters without error" do
      expect { described_class.new(nil) }.not_to raise_error
    end

    it "handles nil gracefully" do
      service = described_class.new(nil)
      expect(service.instance_variable_get(:@param)).to be_nil
    end
  end

  context "with optional parameters" do
    it "sets default values when not provided" do
      service = described_class.new(required_param)
      expect(service.instance_variable_get(:@optional_param)).to eq(default_value)
    end

    it "uses provided optional parameters" do
      service = described_class.new(required_param, optional_param: custom_value)
      expect(service.instance_variable_get(:@optional_param)).to eq(custom_value)
    end
  end
end
```

## Testing Methods That Return Boolean

### Success and Failure Cases
```ruby
describe "#perform_action" do
  context "when conditions are met" do
    it "returns true on success" do
      expect(service.perform_action).to be true
    end

    it "performs expected side effects" do
      expect { service.perform_action }.to change(Model, :count).by(1)
    end

    it "updates associated records" do
      service.perform_action
      expect(domain_object.reload.status).to eq("completed")
    end
  end

  context "when conditions are not met" do
    before do
      allow(domain_object).to receive(:can_perform?).and_return(false)
    end

    it "returns false on failure" do
      expect(service.perform_action).to be false
    end

    it "does not perform side effects" do
      expect { service.perform_action }.not_to change(Model, :count)
    end

    it "does not modify associated records" do
      initial_status = domain_object.status
      service.perform_action
      expect(domain_object.reload.status).to eq(initial_status)
    end
  end

  context "when an error occurs" do
    before do
      allow(Model).to receive(:create!).and_raise(StandardError, "Database error")
      allow(Rails.logger).to receive(:error)
    end

    it "logs the error" do
      service.perform_action
      expect(Rails.logger).to have_received(:error).with(/Database error/)
    end

    it "returns false on error" do
      expect(service.perform_action).to be false
    end
  end
end
```

## Testing Methods That Return Result Objects

### Result Object Testing
```ruby
describe "#call" do
  context "when operation succeeds" do
    it "returns a Result object" do
      result = service.call
      expect(result).to be_a(Result)
    end

    it "returns a success result" do
      result = service.call
      expect(result.success?).to be true
      expect(result.failure?).to be false
    end

    it "includes data in the result" do
      result = service.call
      expect(result.data).to be_present
      expect(result.data[:key]).to eq(expected_value)
    end

    it "has no error message" do
      result = service.call
      expect(result.error).to be_nil
    end
  end

  context "when operation fails" do
    before do
      allow(service).to receive(:valid?).and_return(false)
    end

    it "returns a Result object" do
      result = service.call
      expect(result).to be_a(Result)
    end

    it "returns a failure result" do
      result = service.call
      expect(result.success?).to be false
      expect(result.failure?).to be true
    end

    it "includes error message" do
      result = service.call
      expect(result.error).to be_present
      expect(result.error).to include("specific error message")
    end

    it "has no data" do
      result = service.call
      expect(result.data).to be_nil
    end
  end

  context "when operation partially succeeds" do
    it "returns success with warnings in data" do
      result = service.call
      expect(result.success?).to be true
      expect(result.data[:warnings]).to be_present
    end
  end
end
```

## Testing Callable Concern Integration

### Class Method `.call` Testing
```ruby
describe ".call" do
  it "creates a new instance and calls the call method" do
    result = described_class.call(param1: value1, param2: value2)

    expect(result).to be_a(Result)
    expect(result.success?).to be true
  end

  it "passes all arguments to the initializer" do
    expect(described_class).to receive(:new).with(param1: value1, param2: value2).and_call_original
    described_class.call(param1: value1, param2: value2)
  end

  it "handles keyword arguments correctly" do
    result = described_class.call(param1: "test", should_fail: true)

    expect(result.success?).to be false
    expect(result.error).to be_present
  end
end
```

## Testing Business Logic and Validation

### Complex Business Rules
```ruby
describe "business logic validation" do
  context "when all requirements are met" do
    before do
      setup_required_data
    end

    it "validates successfully" do
      expect(service.valid_for_completion?).to be true
    end

    it "does not add any errors" do
      service.valid_for_completion?
      expect(service.errors).to be_empty
    end
  end

  context "when primary requirement is missing" do
    it "returns false" do
      expect(service.valid_for_completion?).to be false
    end

    it "adds appropriate error message" do
      service.valid_for_completion?
      expect(service.errors).to include("Must have primary requirement")
    end
  end

  context "when secondary requirement is missing" do
    before do
      setup_primary_requirement
    end

    it "returns false" do
      expect(service.valid_for_completion?).to be false
    end

    it "adds multiple error messages" do
      service.valid_for_completion?
      expect(service.errors.count).to be >= 2
    end
  end

  context "when business rule is violated" do
    it "prevents invalid operation" do
      expect(service.perform_action).to be false
    end

    it "provides clear error message" do
      service.perform_action
      expect(service.errors).to include(/specific business rule/)
    end
  end
end
```

### State Management and Transitions
```ruby
describe "state management" do
  context "when transitioning to new state" do
    it "updates status correctly" do
      expect { service.transition_to_active }
        .to change { domain_object.reload.status }
        .from("pending")
        .to("active")
    end

    it "sets timestamp for state change" do
      freeze_time do
        service.transition_to_active
        expect(domain_object.reload.activated_at).to eq(Time.current)
      end
    end

    it "creates audit trail" do
      expect { service.transition_to_active }
        .to change(AuditLog, :count).by(1)
    end
  end

  context "when transition is not allowed" do
    let(:domain_object) { create(:model, status: :completed) }

    it "prevents invalid transition" do
      expect(service.transition_to_active).to be false
    end

    it "does not modify state" do
      initial_status = domain_object.status
      service.transition_to_active
      expect(domain_object.reload.status).to eq(initial_status)
    end
  end
end
```

## Testing Database Operations

### Transaction Safety
```ruby
describe "transaction safety" do
  context "when all operations succeed" do
    it "commits all changes" do
      service.perform_transaction

      expect(Model1.count).to eq(1)
      expect(Model2.count).to eq(1)
    end

    it "returns success" do
      expect(service.perform_transaction).to be_truthy
    end
  end

  context "when an operation fails" do
    before do
      allow(Model2).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      allow(Rails.logger).to receive(:error)
    end

    it "rolls back all changes" do
      expect { service.perform_transaction }
        .not_to change(Model1, :count)
    end

    it "returns failure" do
      expect(service.perform_transaction).to be false
    end
  end

  context "when partial operation fails" do
    before do
      allow(domain_object).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
    end

    it "rolls back associated record creation" do
      expect { service.perform_transaction }
        .not_to change(AssociatedModel, :count)
    end

    it "maintains data integrity" do
      service.perform_transaction
      expect(domain_object.reload.status).to eq("pending")
    end
  end
end
```

### Record Creation and Updates
```ruby
describe "record management" do
  describe "#create_record" do
    context "with valid parameters" do
      let(:params) do
        {
          name: "Test Record",
          status: :active,
          related_id: related_record.id
        }
      end

      it "creates a new record" do
        expect { service.create_record(params) }
          .to change(Model, :count).by(1)
      end

      it "sets attributes correctly" do
        service.create_record(params)
        record = Model.last
        expect(record.name).to eq("Test Record")
        expect(record.status).to eq("active")
      end

      it "associates with related records" do
        service.create_record(params)
        record = Model.last
        expect(record.related_record).to eq(related_record)
      end

      it "returns true on success" do
        expect(service.create_record(params)).to be true
      end
    end

    context "with invalid parameters" do
      let(:invalid_params) { { name: "" } }

      it "does not create a record" do
        expect { service.create_record(invalid_params) }
          .not_to change(Model, :count)
      end

      it "returns false on failure" do
        expect(service.create_record(invalid_params)).to be false
      end

      it "adds error messages" do
        service.create_record(invalid_params)
        expect(service.errors).to be_present
      end
    end
  end

  describe "#update_record" do
    let(:existing_record) { create(:model, name: "Original Name") }

    context "with valid updates" do
      it "updates the record" do
        expect { service.update_record(name: "New Name") }
          .to change { existing_record.reload.name }
          .from("Original Name")
          .to("New Name")
      end

      it "returns true on success" do
        expect(service.update_record(name: "New Name")).to be true
      end
    end

    context "with invalid updates" do
      it "does not update the record" do
        expect { service.update_record(name: "") }
          .not_to change { existing_record.reload.name }
      end

      it "returns false on failure" do
        expect(service.update_record(name: "")).to be false
      end
    end
  end
end
```

## Testing Side Effects

### Email Notifications
```ruby
describe "email notifications" do
  context "when triggering notification" do
    before do
      allow(NotificationMailer).to receive(:notify).and_call_original
    end

    it "sends notification email" do
      expect(NotificationMailer)
        .to receive(:notify)
        .with(domain_object)
        .and_call_original

      expect { service.perform_with_notification }
        .to have_enqueued_mail(NotificationMailer, :notify)
    end

    it "includes correct recipients" do
      service.perform_with_notification
      email = ActionMailer::Base.deliveries.last
      expect(email.to).to include(user.email)
    end
  end

  context "when notification fails" do
    before do
      allow(NotificationMailer).to receive(:notify).and_raise(StandardError)
      allow(Rails.logger).to receive(:error)
    end

    it "logs the error" do
      service.perform_with_notification
      expect(Rails.logger).to have_received(:error)
    end

    it "continues with operation" do
      expect(service.perform_with_notification).to be_truthy
    end
  end
end
```

### Background Jobs
```ruby
describe "background job enqueueing" do
  it "enqueues background job" do
    expect { service.perform_async }
      .to have_enqueued_job(ProcessingJob)
      .with(domain_object.id)
  end

  it "enqueues job with correct arguments" do
    expect { service.perform_async }
      .to have_enqueued_job(ProcessingJob)
      .with(domain_object.id, user.id)
      .on_queue(:default)
  end

  it "enqueues job with delay" do
    expect { service.perform_later }
      .to have_enqueued_job(ProcessingJob)
      .at(1.hour.from_now)
  end
end
```

### External Service Integration
```ruby
describe "external service integration" do
  context "when external service succeeds" do
    before do
      allow(ExternalService).to receive(:call).and_return(success: true, data: "result")
    end

    it "calls external service" do
      service.sync_with_external
      expect(ExternalService).to have_received(:call).with(domain_object.id)
    end

    it "processes external service response" do
      result = service.sync_with_external
      expect(result).to be true
      expect(domain_object.reload.synced_at).to be_present
    end
  end

  context "when external service fails" do
    before do
      allow(ExternalService).to receive(:call).and_raise(StandardError, "API Error")
      allow(Rails.logger).to receive(:error)
    end

    it "handles external service errors gracefully" do
      result = service.sync_with_external
      expect(result).to be false
    end

    it "logs the error" do
      service.sync_with_external
      expect(Rails.logger).to have_received(:error).with(/API Error/)
    end

    it "adds user-friendly error message" do
      service.sync_with_external
      expect(service.errors).to include(/external service/)
    end
  end
end
```

## Testing Associations and Relationships

### Creating Associated Records
```ruby
describe "association management" do
  describe "#add_child_record" do
    let(:child_data) { { name: "Child Record" } }

    context "when parent exists" do
      it "adds child record" do
        expect { service.add_child_record(child_data) }
          .to change { domain_object.children.count }.by(1)
      end

      it "associates with parent correctly" do
        service.add_child_record(child_data)
        child = domain_object.children.last
        expect(child.parent).to eq(domain_object)
      end

      it "returns true on success" do
        expect(service.add_child_record(child_data)).to be true
      end
    end

    context "when parent does not exist" do
      let(:service) { described_class.new(nil) }

      it "returns false" do
        expect(service.add_child_record(child_data)).to be false
      end

      it "adds error message" do
        service.add_child_record(child_data)
        expect(service.errors).to include("No parent available")
      end
    end

    context "when duplicate child exists" do
      let!(:existing_child) { create(:child, parent: domain_object, name: "Child Record") }

      it "does not create duplicate" do
        expect { service.add_child_record(child_data) }
          .not_to change { domain_object.children.count }
      end

      it "updates existing child" do
        service.add_child_record(child_data.merge(status: :active))
        expect(existing_child.reload.status).to eq("active")
      end
    end
  end
end
```

## Testing Different Roles and Permissions

### Multi-Role Testing
```ruby
describe "role-based behavior" do
  context "with therapist role" do
    let(:service) { described_class.new(document, therapist, "therapist") }

    it "creates record with therapist role" do
      service.perform_action
      record = Record.last
      expect(record.role).to eq("therapist")
    end

    it "applies therapist-specific logic" do
      service.perform_action
      expect(document.therapist_signature).to be_present
    end
  end

  context "with supervisor role" do
    let(:service) { described_class.new(document, supervisor, "supervisor") }

    it "creates record with supervisor role" do
      service.perform_action
      record = Record.last
      expect(record.role).to eq("supervisor")
    end

    it "applies supervisor-specific logic" do
      service.perform_action
      expect(document.supervisor_signature).to be_present
    end
  end

  context "with client role" do
    let(:service) { described_class.new(document, client, "client") }

    it "creates record with client role" do
      service.perform_action
      record = Record.last
      expect(record.role).to eq("client")
    end

    it "applies client-specific logic" do
      service.perform_action
      expect(document.client_signature).to be_present
    end
  end
end
```

## Testing Different Document Types or Contexts

### Context-Specific Behavior
```ruby
describe "context-specific behavior" do
  context "with progress note document" do
    let(:document) { create(:clinical_document, :progress_note) }

    it "applies progress note logic" do
      result = service.process_document
      expect(result).to include("progress_note")
    end

    it "validates progress note requirements" do
      expect(service.valid?).to be true
    end
  end

  context "with treatment plan document" do
    let(:document) { create(:clinical_document, :treatment_plan) }

    it "applies treatment plan logic" do
      result = service.process_document
      expect(result).to include("treatment_plan")
    end

    it "validates treatment plan requirements" do
      expect(service.valid?).to be true
    end
  end

  context "with MSE document" do
    let(:document) { create(:clinical_document, :mse) }

    it "applies MSE logic" do
      result = service.process_document
      expect(result).to include("mse")
    end
  end
end
```

## Testing Logging and Debugging

### Debug Logging
```ruby
describe "logging and debugging" do
  before do
    allow(Rails.logger).to receive(:debug)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  it "logs debug information during processing" do
    service.perform_action

    expect(Rails.logger).to have_received(:debug)
      .with(/Processing started/)
  end

  it "logs successful completion" do
    service.perform_action

    expect(Rails.logger).to have_received(:info)
      .with(/successfully completed/)
  end

  it "logs errors with context" do
    allow(domain_object).to receive(:save!).and_raise(StandardError, "Save failed")

    service.perform_action

    expect(Rails.logger).to have_received(:error)
      .with(/Save failed/)
  end

  it "includes relevant identifiers in log messages" do
    service.perform_action

    expect(Rails.logger).to have_received(:debug)
      .with(/ID: #{domain_object.id}/)
  end
end
```

## Testing Edge Cases and Error Conditions

### Boundary Conditions
```ruby
describe "edge cases and error conditions" do
  context "with nil parameters" do
    let(:service) { described_class.new(nil) }

    it "handles nil domain object gracefully" do
      expect { service.perform_action }.not_to raise_error
      expect(service.perform_action).to be false
    end
  end

  context "with empty collections" do
    it "handles empty array gracefully" do
      result = service.process_items([])
      expect(result).to eq([])
    end
  end

  context "with missing required associations" do
    let(:domain_object) { build(:model, required_association: nil) }

    it "handles missing associations" do
      expect(service.perform_action).to be false
    end

    it "provides meaningful error message" do
      service.perform_action
      expect(service.errors).to include(/required association/)
    end
  end

  context "with special characters in data" do
    let(:special_data) do
      {
        name: "Test with special chars: à, ñ, 中文, 🎉",
        notes: "Multi\nline\ntext"
      }
    end

    it "handles special characters correctly" do
      result = service.process_data(special_data)
      expect(result).to be true
    end
  end

  context "with maximum limits" do
    it "enforces maximum item count" do
      max_items = described_class::MAX_ITEMS
      items = create_list(:item, max_items + 1)

      expect(service.process_items(items)).to be false
    end

    it "provides limit error message" do
      max_items = described_class::MAX_ITEMS
      items = create_list(:item, max_items + 1)

      service.process_items(items)
      expect(service.errors).to include(/maximum/)
    end
  end

  context "with circular dependencies" do
    it "detects circular references" do
      parent = create(:node)
      child = create(:node, parent: parent)
      parent.update(parent: child)

      expect(service.validate_tree(parent)).to be false
    end
  end
end
```

## Testing Private Methods (Indirectly)

### Testing Through Public Interface
```ruby
describe "private method behavior" do
  describe "private calculation logic" do
    # Test private method indirectly through public method
    context "when public method uses private calculation" do
      it "produces correct result" do
        result = service.calculate_total
        expect(result).to eq(expected_value)
      end
    end

    context "with different input scenarios" do
      it "handles zero values" do
        domain_object.update(value: 0)
        expect(service.calculate_total).to eq(0)
      end

      it "handles negative values" do
        domain_object.update(value: -100)
        expect(service.calculate_total).to eq(0)
      end
    end
  end

  describe "private state checks" do
    # Only use send() when absolutely necessary
    context "when checking internal state" do
      it "returns correct state" do
        expect(service.send(:internal_state_valid?)).to be true
      end
    end
  end
end
```

## Integration and Workflow Testing

### Real-World Scenarios
```ruby
describe "integration scenarios" do
  context "typical workflow scenario" do
    let(:workflow_data) { setup_complete_workflow }

    it "completes full workflow successfully" do
      expect(service.execute_workflow).to be true
    end

    it "creates all required records" do
      expect { service.execute_workflow }
        .to change(Model1, :count).by(1)
        .and change(Model2, :count).by(1)
        .and change(Model3, :count).by(1)
    end

    it "maintains data consistency throughout workflow" do
      service.execute_workflow

      expect(domain_object.reload.status).to eq("completed")
      expect(domain_object.children.all?(&:processed?)).to be true
    end

    it "sends appropriate notifications" do
      expect { service.execute_workflow }
        .to have_enqueued_mail(NotificationMailer, :workflow_complete)
    end
  end

  context "workflow with partial failure" do
    before do
      allow(service).to receive(:step_3).and_return(false)
    end

    it "stops at failing step" do
      service.execute_workflow

      expect(domain_object.reload.step_completed).to eq(2)
    end

    it "provides clear error about failure point" do
      service.execute_workflow
      expect(service.errors).to include(/Step 3 failed/)
    end
  end

  context "complex multi-step scenario" do
    it "handles dependencies correctly" do
      result = service.complex_operation

      expect(result.success?).to be true
      expect(result.data[:steps_completed]).to eq(5)
    end

    it "rolls back on any step failure" do
      allow(service).to receive(:step_4).and_raise(StandardError)

      expect { service.complex_operation }
        .not_to change(Model, :count)
    end
  end
end
```

## Performance Testing

### Query Optimization
```ruby
describe "query performance" do
  let!(:test_data) { create_list(:model, 10) }

  it "avoids N+1 queries" do
    query_count = 0
    callback = lambda { |*args| query_count += 1 }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      service.process_all
    end

    # Should use eager loading
    expect(query_count).to be <= 5
  end

  it "uses batch processing for large datasets" do
    large_dataset = create_list(:model, 100)

    expect { service.process_batch(large_dataset) }
      .to perform_under(2.seconds)
  end
end
```

## Best Practices Checklist

When writing service tests, ensure you:

- [ ] Use `frozen_string_literal: true` at the top of the file
- [ ] Include `require "rails_helper"`
- [ ] Use `type: :service` in RSpec.describe
- [ ] Test both success and failure scenarios
- [ ] Test Result object returns (success?, failure?, data, error)
- [ ] Test Callable concern integration if applicable
- [ ] Use `let` for lazy evaluation, `let!` for immediate evaluation
- [ ] Use `build` instead of `create` when persistence is not required
- [ ] Test error handling and recovery
- [ ] Test transaction safety and rollbacks
- [ ] Test side effects (emails, jobs, external services)
- [ ] Mock external dependencies appropriately
- [ ] Test different roles and permissions
- [ ] Test different contexts (document types, states)
- [ ] Test edge cases and boundary conditions
- [ ] Verify logging behavior
- [ ] Test business logic and validation rules
- [ ] Test association management
- [ ] Group related tests in describe/context blocks
- [ ] Keep test data minimal and deterministic
- [ ] Test real-world integration scenarios
- [ ] Verify performance characteristics

## Output Format

When generating or updating service tests, provide:

1. **Complete test file** with proper structure and organization
2. **Factory updates** if new factories are needed or existing ones need updates
3. **Brief explanation** of test coverage including:
   - What methods are tested
   - What business logic is validated
   - What side effects are verified
   - Any edge cases covered
   - Any integration scenarios tested
4. **Coverage summary** listing:
   - ✅ What is fully tested
   - ⚠️ What has partial coverage
   - ❌ What is not covered

## Instructions for AI

When the user provides a service file, follow this iterative workflow until ALL tests pass:

### Phase 1: Analysis and Test Generation

1. **Read the service file** at the provided path
2. **Check if spec file exists** at `spec/services/service_name_spec.rb`
3. **Analyze the service** to identify:
   - Initialization parameters and options
   - All public instance methods
   - All public class methods
   - Return types (boolean, Result object, data)
   - Callable concern inclusion
   - Parent class inheritance
   - Business logic and validation rules
   - Side effects (emails, jobs, database changes)
   - Error handling patterns
   - External dependencies
4. **If test file exists**, read it and identify:
   - What is already tested
   - What is missing
   - What needs improvement
5. **Generate or update tests** following this guide
6. **Ensure comprehensive coverage** of all service behavior
7. **Use factories** defined in `spec/factories/` or suggest new ones
8. **Follow existing patterns** from the codebase

### Phase 2: Iterative Test Execution and Fixes

**CRITICAL: Do not stop until all tests pass. Repeat this loop until success:**

1. **Run the tests** for the specific service:
   ```bash
   bundle exec rspec spec/services/service_name_spec.rb
   ```

2. **Analyze test results**:
   - If ALL tests pass → Report success and exit
   - If ANY tests fail → Continue to step 3

3. **For each test failure**:
   - Read and understand the error message
   - Identify the root cause:
     - Missing factory attributes
     - Incorrect test expectations
     - Missing dependencies or mocks
     - Incorrect test setup (let/let! usage)
     - Missing associated records
     - Timing issues (use freeze_time if needed)
     - Missing stubs for external services
     - Incorrect Result object assertions

4. **Fix the failure**:
   - Update factory if needed (`spec/factories/service_name.rb`)
   - Fix test expectations if they're incorrect
   - Update test setup (add missing let! blocks, create associations)
   - Add appropriate mocks and stubs
   - Adjust test structure if needed
   - **DO NOT modify the service unless there's a genuine bug** - the goal is to test the existing service

5. **Return to step 1** and run tests again

### Phase 3: Final Verification

Once all tests pass:

1. **Run the full test suite** one more time to confirm
2. **Provide a summary** including:
   - Total number of examples and failures (should be 0 failures)
   - What was fixed during the iteration
   - Final test coverage breakdown
   - Any recommendations for the service or tests

### Test Quality Standards

Focus on writing tests that are:
- **Comprehensive**: Cover all service behavior including edge cases
- **Fast**: Minimal database hits, appropriate use of mocks
- **Reliable**: Deterministic data, proper setup/teardown
- **Maintainable**: Clear structure, readable, well-organized
- **Practical**: Test real-world scenarios and business logic

### Common Failure Patterns and Solutions

When tests fail, check these common issues:

1. **Factory validation failures**: Ensure factory has all required attributes
2. **Association errors**: Create associated records with `let!` or in factory
3. **Missing mocks**: Stub external services (EmailService, APIs)
4. **Result object assertions**: Verify correct usage of success?, failure?, data, error
5. **Callable concern**: Ensure .call class method is tested correctly
6. **Transaction rollback**: Verify counts don't change when errors occur
7. **Time-dependent failures**: Use `freeze_time` for consistent timestamps
8. **Missing required data**: Ensure all dependencies are set up in test
9. **External service calls**: Mock HTTP requests, API calls, external services
10. **Background jobs**: Use appropriate job matchers (have_enqueued_job)
