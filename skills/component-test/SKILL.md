# ViewComponent Test Generator Command

You are an expert Rails ViewComponent test developer. Write comprehensive, fast, and maintainable RSpec component tests for the application following established patterns and best practices.

## Reference Skill

For detailed patterns, examples, and testing conventions, consult the skill file at:
`.claude/skills/viewcomponent-test-expert/SKILL.md`

## Core Principles

### 1. Comprehensive Coverage
- Test component inheritance from ApplicationComponent
- Test initialization with required/optional parameters
- Test parameter validation and error cases
- Test basic rendering with render_inline
- Test all slot configurations (renders_one, renders_many)
- Test conditional rendering (states, modes, visibility)
- Test theme colors and styling (using theme colors from `app/assets/tailwind/application.css`)
- Test accessibility attributes (ARIA, semantic HTML)
- Test interactive elements (links, buttons, forms)
- Test empty states and edge cases
- Test helper methods (public and private through public interface)
- Test nested/child components

### 2. Write Fast, Efficient Tests
- Use `build` instead of `create` when database persistence is not required
- Use `let` for lazy evaluation, `let!` for immediate evaluation
- Avoid unnecessary database hits
- Use deterministic data with sequences, not random values
- Test rendered output, not implementation details

### 3. Follow Established Patterns
Reference these component test files for patterns:
- `spec/components/` directory for existing component tests
- `.claude/skills/viewcomponent-test-expert/SKILL.md` for comprehensive testing guide

## Test File Structure

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ComponentName, type: :component do
  let(:organization) { create(:organization) }
  let(:model) { create(:model_name, organization: organization) }

  before do
    ActsAsTenant.current_tenant = organization
  end

  describe 'inheritance' do
    it 'inherits from ApplicationComponent' do
      expect(described_class.superclass).to eq(ApplicationComponent)
    end
  end

  describe 'initialization' do
    # Test required and optional parameters
  end

  describe 'rendering' do
    # Test basic rendering with render_inline
  end

  describe 'content rendering' do
    # Test specific content sections
  end

  describe 'slots' do
    # Test renders_one and renders_many slots
  end

  describe 'styling' do
    # Test theme colors and CSS classes
  end

  describe 'accessibility' do
    # Test ARIA attributes and semantic HTML
  end

  describe 'helper methods' do
    # Test public helper methods
  end

  describe 'edge cases' do
    # Test nil, empty, special characters
  end
end
```

## Key Testing Patterns

### Rendering with render_inline
```ruby
rendered = render_inline(described_class.new(model: model))
expect(rendered.text).to include('Expected Text')
expect(rendered.css('.class-name')).to be_present
expect(rendered.to_html).to include('data-attribute')
```

### Testing Slots
```ruby
rendered = render_inline(described_class.new) do |component|
  component.with_header { 'Header Content' }
  component.with_body { 'Body Content' }
end
expect(rendered.css('.header').text).to eq('Header Content')
```

### Testing Conditional Rendering
```ruby
context 'when condition is true' do
  it 'shows element' do
    rendered = render_inline(described_class.new(show: true))
    expect(rendered.css('.element')).to be_present
  end
end

context 'when condition is false' do
  it 'hides element' do
    rendered = render_inline(described_class.new(show: false))
    expect(rendered.css('.element')).not_to be_present
  end
end
```

### Testing Accessibility
```ruby
describe 'accessibility' do
  it 'includes aria-label on interactive elements' do
    rendered = render_inline(described_class.new(model: model))
    button = rendered.css('button').first
    expect(button['aria-label']).to be_present
  end

  it 'marks decorative elements as aria-hidden' do
    rendered = render_inline(described_class.new(model: model))
    expect(rendered.css('[aria-hidden="true"]')).to be_present
  end
end
```

## Instructions for AI

When the user provides a component file path as `$ARGUMENTS`, follow this iterative workflow until ALL tests pass:

### Phase 1: Analysis and Test Generation

1. **Read the component file** at `$ARGUMENTS`
2. **Determine test file path**: Convert component path to spec path
   - `app/components/foo_component.rb` → `spec/components/foo_component_spec.rb`
   - `app/components/foo/bar_component.rb` → `spec/components/foo/bar_component_spec.rb`
3. **Check if spec file exists** at the determined path
4. **Analyze the component** to identify:
   - Class inheritance (should be ApplicationComponent)
   - Initialize parameters (required, optional, defaults)
   - Slots (renders_one, renders_many)
   - Helper methods (public and private)
   - Conditional rendering logic
   - Theme colors and styling
   - Accessibility attributes
   - Nested/child components
5. **If test file exists**, read it and identify:
   - What is already tested
   - What is missing
   - What needs improvement
6. **Generate or update tests** following the skill guide at `.claude/skills/viewcomponent-test-expert/SKILL.md`
7. **Ensure comprehensive coverage** of all component behavior
8. **Use factories** defined in `spec/factories/` or suggest new ones

### Phase 2: Iterative Test Execution and Fixes

**CRITICAL: Do not stop until all tests pass. Repeat this loop until success:**

1. **Run the tests** for the specific component:
   ```bash
   bundle exec rspec spec/components/component_name_spec.rb
   ```

2. **Analyze test results**:
   - If ALL tests pass → Report success and exit
   - If ANY tests fail → Continue to step 3

3. **For each test failure**:
   - Read and understand the error message
   - Identify the root cause:
     - Missing factory attributes
     - Incorrect test expectations
     - Missing slot configurations
     - Incorrect CSS selectors
     - Missing multi-tenant setup
     - Missing associated records
     - Incorrect render_inline usage

4. **Fix the failure**:
   - Update factory if needed
   - Fix test expectations if they're incorrect
   - Update test setup (add missing let! blocks, create associations)
   - Adjust CSS selectors to match actual component output
   - **DO NOT modify the component unless there's a genuine bug**

5. **Return to step 1** and run tests again

### Phase 3: Final Verification

Once all tests pass:

1. **Run the full test suite** one more time to confirm
2. **Provide a summary** including:
   - Total number of examples and failures (should be 0 failures)
   - What was fixed during the iteration
   - Final test coverage breakdown
   - Any recommendations for the component or tests

## Test Organization Checklist

For every component test file, verify:

- [ ] `require 'rails_helper'` at top
- [ ] `type: :component` metadata
- [ ] Multi-tenant setup with `ActsAsTenant.current_tenant`
- [ ] Test inheritance from ApplicationComponent
- [ ] Test initialization with required/optional parameters
- [ ] Test parameter validation and error cases
- [ ] Test basic rendering
- [ ] Test all slot configurations
- [ ] Test conditional rendering (states, modes)
- [ ] Test theme colors and styling
- [ ] Test accessibility attributes
- [ ] Test interactive elements (links, buttons)
- [ ] Test empty states
- [ ] Test edge cases (nil, empty, special chars)
- [ ] Test helper methods
- [ ] Test nested components if applicable

## Common Failure Patterns and Solutions

1. **Factory validation failures**: Ensure factory has all required attributes
2. **Association errors**: Create associated records with `let!` or in factory
3. **CSS selector mismatches**: Verify selectors match actual rendered HTML
4. **Missing slots**: Test all slot configurations including when empty
5. **Multi-tenant errors**: Always set `ActsAsTenant.current_tenant`
6. **Conditional rendering**: Test all branches of conditional logic
7. **Accessibility assertions**: Verify ARIA attributes exist and have correct values
8. **Theme color assertions**: Use exact class names from theme (bg-primary, text-text-light, etc.)
