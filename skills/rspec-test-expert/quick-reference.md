# RSpec Quick Reference

## Common Test Patterns

### Basic Test Structure

```ruby
require 'rails_helper'

RSpec.describe Model, type: :model do
  let(:organization) { create(:organization) }

  describe '#method_name' do
    context 'when condition' do
      it 'does something' do
        # Arrange
        model = build(:model, organization: organization)

        # Act
        result = model.method_name

        # Assert
        expect(result).to eq(expected_value)
      end
    end
  end
end
```

### Shoulda Matchers (Most Common)

```ruby
# Validations
it { should validate_presence_of(:field) }
it { should validate_uniqueness_of(:email) }
it { should validate_inclusion_of(:status).in_array(['active', 'inactive']) }
it { should validate_numericality_of(:age).is_greater_than(0) }
it { should validate_length_of(:name).is_at_least(3).is_at_most(50) }

# Associations
it { should belong_to(:organization) }
it { should belong_to(:user).optional }
it { should have_many(:items).dependent(:destroy) }
it { should have_many(:users).through(:memberships) }
it { should have_one(:profile).dependent(:destroy) }

# Enums
it { should define_enum_for(:status).with_values(draft: 0, active: 1) }

# Database
it { should have_db_column(:name).of_type(:string) }
it { should have_db_index(:email) }

# Nested attributes
it { should accept_nested_attributes_for(:items).allow_destroy(true) }
```

### Multi-Tenancy Pattern

```ruby
describe 'with multi-tenancy' do
  let(:organization) { create(:organization) }

  before do
    ActsAsTenant.with_tenant(organization) {}
  end

  it 'scopes to tenant' do
    ActsAsTenant.with_tenant(organization) do
      model = create(:model, organization: organization)
      expect(model.organization_id).to eq(organization.id)
    end
  end
end
```

### Service Object Pattern

```ruby
RSpec.describe MyService, type: :service do
  let(:service) { described_class.new(object) }
  let(:object) { build_stubbed(:object) }

  describe '#call' do
    context 'with valid params' do
      it 'returns true' do
        expect(service.call(params)).to be true
      end

      it 'performs action' do
        expect { service.call(params) }.to change(Model, :count).by(1)
      end
    end

    context 'with invalid params' do
      it 'returns false' do
        expect(service.call(invalid_params)).to be false
      end

      it 'populates errors' do
        service.call(invalid_params)
        expect(service.errors).not_to be_empty
      end
    end
  end
end
```

## Common Matchers

```ruby
# Truthiness
expect(value).to be true
expect(value).to be false
expect(value).to be_nil
expect(value).to be_present

# Equality
expect(result).to eq(expected)           # ==
expect(result).to eql(expected)          # eql?
expect(result).to be(expected)           # same object
expect(string).to match(/pattern/)

# Comparison
expect(value).to be > 10
expect(value).to be_between(1, 10).inclusive

# Collections
expect(array).to include(item)
expect(array).to match_array([1, 2, 3])
expect(hash).to include(key: value)
expect(array).to be_empty

# Change
expect { action }.to change(Model, :count).by(1)
expect { action }.to change { object.status }.from('draft').to('active')

# Errors
expect { action }.to raise_error(StandardError)
expect { action }.to raise_error(StandardError, 'message')

# ActiveRecord
expect(model).to be_valid
expect(model).to be_invalid
expect(model).to be_persisted
expect(model.errors[:field]).to include('message')
```

## Data Setup

```ruby
# let - Lazy evaluated
let(:user) { create(:user) }

# let! - Eager evaluated (runs before each test)
let!(:user) { create(:user) }

# build - Not saved to database (faster)
let(:user) { build(:user) }

# build_stubbed - Not saved, read-only (fastest)
let(:user) { build_stubbed(:user) }

# create - Saved to database
let!(:user) { create(:user) }

# create_list - Multiple records
let!(:users) { create_list(:user, 3) }
```

## Time Testing

```ruby
# Freeze time
freeze_time do
  model = create(:model)
  expect(model.created_at).to eq(Time.current)
end

# Travel to specific time
travel_to Time.zone.local(2024, 1, 1) do
  # Test code
end

# Travel relative
travel 2.days do
  # 2 days in the future
end

# Time zone
Time.use_zone('Pacific Time (US & Canada)') do
  # Test code
end
```

## Mocking and Stubbing

```ruby
# Stub method
allow(object).to receive(:method).and_return(value)
allow(object).to receive(:method).and_raise(StandardError)

# Expect method call
expect(object).to receive(:method).with(args)
expect(object).to receive(:method).once
expect(object).to receive(:method).exactly(3).times
expect(object).not_to receive(:method)

# Stub with block
allow(object).to receive(:method) do |arg|
  # Custom behavior
end

# Any instance
allow_any_instance_of(Class).to receive(:method).and_return(value)

# Class method
allow(Class).to receive(:method).and_return(value)
```

## Common Test Scenarios

### Testing Callbacks

```ruby
describe 'callbacks' do
  describe 'before_save' do
    it 'normalizes phone number' do
      model = build(:model, phone: '(123) 456-7890')
      model.save
      expect(model.phone).to eq('1234567890')
    end
  end

  describe 'after_create' do
    it 'sends email' do
      expect {
        create(:model)
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end
  end
end
```

### Testing Scopes

```ruby
describe 'scopes' do
  describe '.active' do
    it 'returns only active records' do
      active = create(:model, status: :active)
      inactive = create(:model, status: :inactive)

      expect(Model.active).to include(active)
      expect(Model.active).not_to include(inactive)
    end
  end
end
```

### Testing Validations

```ruby
describe 'validations' do
  it 'requires field' do
    model = build(:model, field: nil)
    expect(model).to be_invalid
    expect(model.errors[:field]).to include("can't be blank")
  end

  it 'validates format' do
    model = build(:model, email: 'invalid')
    expect(model).to be_invalid
    expect(model.errors[:email]).to include('is invalid')
  end
end
```

### Testing Associations

```ruby
describe 'associations' do
  it 'destroys dependents' do
    parent = create(:parent)
    create_list(:child, 3, parent: parent)

    expect { parent.destroy }.to change(Child, :count).by(-3)
  end

  it 'loads through association' do
    parent = create(:parent)
    child = create(:child)
    create(:join, parent: parent, child: child)

    expect(parent.children).to include(child)
  end
end
```

### Testing Instance Methods

```ruby
describe '#full_name' do
  it 'combines first and last name' do
    user = build(:user, first_name: 'John', last_name: 'Doe')
    expect(user.full_name).to eq('John Doe')
  end
end

describe '#active?' do
  context 'when status is active' do
    it 'returns true' do
      model = build(:model, status: :active)
      expect(model.active?).to be true
    end
  end

  context 'when status is inactive' do
    it 'returns false' do
      model = build(:model, status: :inactive)
      expect(model.active?).to be false
    end
  end
end
```

## Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific file
bundle exec rspec spec/models/user_spec.rb

# Run specific line
bundle exec rspec spec/models/user_spec.rb:42

# Run with documentation format
bundle exec rspec --format documentation

# Run only failures from last run
bundle exec rspec --only-failures

# Run tests matching description
bundle exec rspec --example "calculates age"
```

## Test Organization

```ruby
describe 'validations' do
  describe 'presence validations' do
    # Presence tests
  end

  describe 'format validations' do
    # Format tests
  end
end

describe 'associations' do
  # Association tests
end

describe 'callbacks' do
  # Callback tests
end

describe 'scopes' do
  # Scope tests
end

describe 'class methods' do
  describe '.method_name' do
    # Class method tests
  end
end

describe 'instance methods' do
  describe '#method_name' do
    context 'when condition' do
      # Tests
    end
  end
end

describe 'edge cases' do
  # Edge case tests
end

describe 'factory validation' do
  # Factory tests
end
```
