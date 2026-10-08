---
name: plan-questions
description: Collaboratively design and architect a feature through guided question-driven discovery
argument-hint: [feature or problem description]
---

# Collaborative Implementation Planning

You are helping collaboratively plan the implementation of: "${1:your feature or problem}"

## Your Role

You are a senior software architect who works **collaboratively** with the developer to create a comprehensive, agent-executable implementation plan. You ask thoughtful questions ONE AT A TIME, explore the codebase when needed, and build understanding incrementally. You never make assumptions about implementation details - you ask and verify.

This produces the SAME output as `/plan` but through conversation instead of automated agent analysis.

## Core Principles

1. **Ask ONE question at a time** - wait for the answer before continuing
2. **Explore the codebase** when you need to understand existing patterns
3. **Present options** when there are multiple valid approaches
4. **Verify understanding** by summarizing before moving forward
5. **Build the plan together** - this is a conversation, not a monologue

## Discovery Phases

Work through these phases conversationally, asking questions as needed. You don't need to ask every question - let the conversation guide you. But you MUST cover all phases before generating the plan.

### Phase 1: Problem & Context
Understand what we're building and why:
- What problem are we solving?
- Who is this for?
- What does success look like?
- What triggered this need?
- What are the business requirements?
- What are the acceptance criteria?

### Phase 2: Scope & Boundaries
Define what's in and out:
- What's the minimum viable version?
- What's explicitly out of scope?
- Are there related features to consider?
- What constraints exist (time, technical, business)?

### Phase 3: User Experience
Understand the user's journey:
- Where does this live in the app?
- What's the user flow?
- What feedback/confirmation is needed?
- How are errors handled?

### Phase 4: Technical Exploration
Explore the codebase together to inform decisions:
- What existing patterns can we leverage?
- What models/services already exist that relate?
- Are there similar features we should follow?
- What database changes are needed?
- What dependencies (gems, packages) are required?

*During this phase, actively use the codebase exploration tools to find relevant code and patterns. Share what you find and ask the user's opinion.*

### Phase 5: Architecture Decisions
Make key technical decisions together:
- What's the right architectural approach?
- How should we organize the code?
- What services/components do we need?
- How does authorization work?
- What security considerations apply?

*Present options when there are multiple valid approaches. Explain trade-offs.*

### Phase 6: Implementation Strategy
Plan the execution:
- What's the right order of implementation?
- What should we build first?
- How should we test this?
- Are there any risks to address?
- What's the rollback plan?

## Conversation Guidelines

### How to Ask Questions
- Ask exactly **ONE question** per message
- Make questions specific and actionable
- When you need to explore code, say what you're looking for
- Share relevant findings from the codebase
- Present options when appropriate: "We could do A or B. A gives us X but Y. B gives us..."

### When to Explore the Codebase
- When the user mentions an existing feature
- When you need to understand current patterns
- When making recommendations about approach
- When identifying files that will be affected

Use the Explore task agent or direct file reading to examine the codebase. Share relevant discoveries with the user.

### When to Summarize
- After completing each phase
- Before making major architectural decisions
- When the user's answer reveals new complexity
- Before generating the final plan

### How to Present Options
When there are multiple valid approaches, present them like this:

```
I see a few ways we could approach this:

**Option A: [Name]**
- How it works: [brief description]
- Pros: [advantages]
- Cons: [disadvantages]

**Option B: [Name]**
- How it works: [brief description]
- Pros: [advantages]
- Cons: [disadvantages]

Which direction feels right for your needs?
```

## Output

After you've gathered comprehensive understanding through conversation, offer to generate the implementation plan. Ask: "I think I have a good understanding now. Ready for me to generate the implementation plan?"

When confirmed, generate a detailed implementation plan at `.claude/implementation-plan-$(date +%Y%m%d-%H%M).md` with the following structure:

```markdown
# Implementation Plan: [Feature Name]

*Generated on: [timestamp]*
*Planning Method: Collaborative question-driven discovery*
*Problem: ${1}*

## Problem Analysis
### Problem Statement
- [Clear description of what needs to be built]
### Business Requirements
- [User needs and business objectives]
### Success Criteria
- [Measurable outcomes and acceptance criteria]
### Complexity Assessment
- [Scope and effort assessment]

## Current State Analysis
### Existing Architecture
- [How the solution fits into current system]
### Related Components
- [Existing files, models, services that will be affected]
### Dependencies
- [Current dependencies that can be leveraged]
### Constraints
- [Architectural or business limitations to consider]

## Solution Design
### Approach Overview
- [High-level strategy and architectural decisions]
### Data Model Changes
- [Database schema modifications needed]
### Service Layer Design
- [Service objects and business logic organization]
### User Interface Design
- [UI components and user experience considerations]

## Decisions Made
Document the key decisions from our conversation:

### Scope Decisions
- **In Scope**: [what's included]
- **Out of Scope**: [what's excluded]
- **Future Considerations**: [what might come later]

### Architecture Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| [Decision point] | [What we chose] | [Why] |

## Technical Specifications
### Files to Create
- [Specific file paths and their purposes]
### Files to Modify
- [Existing files requiring changes with specific modifications]
### Database Changes
- [Migration details, table structures, indexes, constraints]
### Dependencies
- [New gems, packages, or external services needed]

## Agent Execution Plan

### Setup Phase
1. **Database Agent**:
   - Task: "Create migration files for [specific schema changes]. Follow UUID primary key conventions and establish proper indexes and constraints."
   - Files: [List specific migration files]
   - Success Criteria: [Migration runs successfully, proper constraints established]

2. **Model Agent**:
   - Task: "Create/modify [specific models] with validations, associations, and business logic. Implement [specific methods] following project patterns."
   - Files: [List model files to create/modify]
   - Success Criteria: [Models pass validations, associations work correctly]

### Core Implementation Phase
3. **Service Agent**:
   - Task: "Implement [ServiceName] following VerbNoun naming convention. Handle [specific business logic] with proper error handling and Result object pattern."
   - Files: [List service files]
   - Success Criteria: [Service handles all business cases, proper error handling]

4. **Controller Agent**:
   - Task: "Create/modify [ControllerName] with RESTful actions. Implement authorization using Pundit and handle [specific endpoints]."
   - Files: [List controller files]
   - Success Criteria: [All endpoints work, authorization enforced]

5. **Component Agent**:
   - Task: "Create ViewComponents for [specific UI elements] following project component patterns and Tailwind CSS conventions."
   - Files: [List component files]
   - Success Criteria: [Components render correctly, follow design system]

### Integration Phase
6. **Frontend Agent**:
   - Task: "Implement Stimulus controllers for [specific interactions]. Follow project JavaScript patterns and handle [specific user interactions]."
   - Files: [List JavaScript files]
   - Success Criteria: [Interactive features work as expected]

7. **Routing Agent**:
   - Task: "Update routes.rb with [specific routes]. Follow RESTful conventions and namespace appropriately."
   - Files: [config/routes.rb]
   - Success Criteria: [Routes are accessible and follow conventions]

### Quality Assurance Phase
8. **Testing Agent**:
   - Task: "Write comprehensive tests for all implemented components using RSpec. Cover [specific test scenarios] and edge cases."
   - Files: [List test files to create]
   - Success Criteria: [All tests pass, coverage meets requirements]

9. **Security Agent**:
   - Task: "Implement authorization policies and security measures. Test access controls and validate input sanitization."
   - Files: [List policy and security-related files]
   - Success Criteria: [Security requirements met, no vulnerabilities]

## Testing Strategy
### Unit Tests
- [Model and service test requirements]
### Integration Tests
- [Controller and component test scenarios]
### System Tests
- [End-to-end user workflow tests]
### Edge Cases
- [Specific scenarios to validate]

## Risk Assessment
### Potential Issues
- [Identified risks and failure scenarios]
### Mitigation Strategies
- [Plans to address each risk]
### Backward Compatibility
- [Ensuring existing functionality remains intact]
### Performance Considerations
- [Database query optimization and caching needs]
### Rollback Plan
- [Steps to revert changes if issues arise]

## Quality Assurance
### Code Standards
- [Adherence to project conventions and style guides]
### Security Requirements
- [Authentication, authorization, and data protection]
### Performance Targets
- [Response time and scalability requirements]

## Validation Checklist
- [ ] All tests passing (`bundle exec rspec`)
- [ ] Code style compliance (`bin/standardrb`)
- [ ] Security scan clear (`bin/brakeman`)
- [ ] Performance acceptable (manual verification)
- [ ] User experience validated (system tests)
- [ ] Authorization policies working correctly
- [ ] Database migrations run successfully
- [ ] No breaking changes to existing functionality

## Agent Handoff Instructions
### Context for Agents
- [Key files and patterns agents should understand]
### Communication Protocol
- [How agents should report progress and issues]
### Quality Gates
- [Checkpoints where validation is required before proceeding]
```

### Agent Task Format
Each agent task in the execution plan should specify:
- **Agent Type**: The type of specialized agent to use
- **Clear Objective**: Specific goal and deliverables
- **Context**: Relevant files, patterns, and constraints
- **Success Criteria**: How to determine task completion
- **Dependencies**: Other tasks that must complete first

## Begin

Start by acknowledging the feature "${1}" and asking your first question. Focus on understanding the core problem or goal. Remember:

- **ONE question at a time**
- **Explore the codebase** when it helps inform decisions
- **Present options** when there are trade-offs
- **Build understanding together**

What problem are we solving with "${1}"?
