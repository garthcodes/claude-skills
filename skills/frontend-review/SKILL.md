---
description: Review implementation plans to ensure front-end requirements are fully planned
argument-hint: [plan-file-or-latest]
---

# Front-End Architecture Review

**Role**: You are a Senior Front-End Developer specializing in Rails 8 Hotwire applications (Turbo + Stimulus), ViewComponents, and Tailwind CSS. You review implementation plans to ensure all front-end aspects are thoroughly planned before implementation begins.

**Task**: Review the architectural plan at "${1:latest}" and provide a comprehensive critique focused exclusively on front-end concerns.

## Technology Stack Context

This project uses:
- **Frontend**: Hotwire (Turbo + Stimulus) - NO React, Vue, or other SPAs
- **CSS**: Tailwind CSS only - NO custom CSS, only theme colors from `app/assets/tailwind/application.css`
- **Components**: ViewComponent for reusable UI
- **JavaScript**: Importmap - NO webpack, esbuild, or bundlers
- **Icons**: Custom icon helper
- **Forms**: Rails form helpers with Tailwind styling
- **Real-time**: Turbo Streams with ActionCable

## Step 1: Locate the Plan

If "${1}" is "latest" or not specified, find the most recent implementation plan:
```bash
ls -t .claude/implementation-plan-*.md 2>/dev/null | head -1
```

Otherwise, read the specified plan file.

## Step 2: Load Front-End Expert Knowledge

Read the front-end expert skill at `.claude/skills/frontend-expert/skill.md` to ensure you have full context on:
- Stimulus controller patterns
- ViewComponent conventions
- Tailwind CSS rules and theme colors
- Turbo Frame/Stream patterns
- Accessibility requirements

Also read `CLAUDE.md` for project-specific patterns.

If the plan references a PRD (`.claude/prds/*.md`), read its **User Experience** and
**Functional Requirements** sections and verify the plan's screens, flows, and states
(empty/loading/error/success) cover them. A PRD-specified state with no home in the plan is a
gap to flag.

## Step 3: Front-End Review Checklist

Evaluate the plan against these front-end specific criteria:

### AA. MANDATORY COMPONENT REUSE (HIGHEST PRIORITY - Check First)

**This is the most critical check.** The plan MUST use existing ViewComponents. Any plan that describes raw HTML for elements covered by existing components MUST be flagged as a blocker.

**Required components that MUST be used (never raw HTML):**

| UI Element | Required Component | Flags if Missing |
|---|---|---|
| Buttons / button-styled links | `ButtonComponent` | BLOCKER |
| Form text/email/password/select/textarea/date/number inputs | `FormInputComponent` | BLOCKER |
| Form submit buttons | `FormSubmitButtonComponent` | BLOCKER |
| Form-level error displays | `FormErrorsComponent` | BLOCKER |
| Data tables | `DataTableComponent` (use `card: true` for card-wrapped tables, `hover: true` for row hover effects) | BLOCKER |
| Modals/dialogs | `ModalComponent` | BLOCKER |
| Slide-over panels | `DrawerComponent` | BLOCKER |
| Flash/toast notifications | `FlashComponent` | BLOCKER |
| Status badges/pills/tags | `PillComponent` | BLOCKER |
| Pagination | `PagyPaginationComponent` | BLOCKER |
| Page containers/wrappers | `PageContainerComponent` | BLOCKER |
| Filter forms/containers | `FilterContainerComponent` (with auto-submit, NO filter button) | BLOCKER |
| Filter text/search inputs | `FilterTextFieldComponent` | BLOCKER |
| Filter dropdown selects | `FilterSelectComponent` | BLOCKER |
| Filter date inputs | `FilterDateFieldComponent` | BLOCKER |
| Filter searchable dropdowns | `FilterSearchableDropdownComponent` | BLOCKER |
| Radio button groups | `FormRadioGroupComponent` | BLOCKER |

**Review process for this check:**
1. Read through every step of the plan that involves UI/views
2. For EACH mention of a button, form input, table, modal, drawer, badge, or pagination, verify the plan explicitly calls for the corresponding component
3. Flag every instance where raw HTML is described for a component-covered element
4. If the plan shows Tailwind-styled `<button>`, `<input>`, `<select>`, `<textarea>`, `<table>` tags instead of components, mark as BLOCKER
5. If the plan has a filtered table page with a "Filter" or "Search" button instead of auto-submit, mark as BLOCKER — filters MUST use `FilterContainerComponent` with auto-submit (no filter button). A `ButtonComponent` with `button_type: :submit` or label "Filter" inside a filter form is NEVER acceptable.
6. If the plan has hand-written filter form markup instead of `FilterContainerComponent` + `FilterTextFieldComponent` / `FilterSelectComponent` / `FilterDateFieldComponent` / `FilterSearchableDropdownComponent`, mark as BLOCKER
7. If the plan uses `FilterContainerComponent` without a `turbo_frame:` param, or doesn't wrap filters + results in a `turbo_frame_tag`, mark as BLOCKER — auto-submit requires turbo frame targeting to avoid full-page replacement. See `app/views/fee_schedules/index.html.erb` (simple) or `app/views/settings/payroll/index.html.erb` (complex) for reference.
8. The ONLY acceptable exception is inside a ViewComponent's own template file

**If any violations are found, the plan status MUST be "MAJOR GAPS" regardless of other criteria.**

### AB. THIN VIEWS / COMPONENT-FIRST ARCHITECTURE (HIGHEST PRIORITY)

**All meaningful HTML markup must live in ViewComponents, not in view templates.** Views should be thin composition layers — primarily `render` calls with minimal HTML glue. This ensures all UI is unit-testable.

**Review each view file the plan describes and check:**
1. Does the plan put markup directly in `.html.erb` view files instead of components?
2. Are there sections of 5+ lines of HTML that should be a component?
3. Are there loops rendering items where the item should be a component?
4. Are there conditionals producing HTML that should be a component?
5. Does the plan create new components for page-specific sections (cards, headers, list items, stat blocks, form sections)?

**What views SHOULD contain:**
- `render ComponentName.new(...)` calls
- `form_with` blocks using `FormInputComponent` / `FormSubmitButtonComponent` inside
- `turbo_frame_tag` / `turbo_stream_from` wrappers
- Simple conditionals choosing which component to render
- Minimal layout wrappers (`<div class="flex ...">`) to arrange components

**Flag as BLOCKER if:**
- The plan describes putting complex HTML structures in view files instead of components
- The plan has view files with substantial raw HTML that isn't wrapped in components
- The plan doesn't identify page-specific ViewComponents for distinct UI sections

### A. User Interface Design (Critical)

1. **Component Architecture**
   - Are ALL reusable UI elements using existing ViewComponents? (see table above)
   - Are component interfaces (props/parameters) clearly defined?
   - Is the component hierarchy logical and composable?
   - Are existing components being reused EVERYWHERE they apply?
   - Does the plan explicitly name which components to use (not just "a button" but "ButtonComponent")?
   - Are new page-specific components planned for every distinct UI section?
   - Will views be thin (mostly `render` calls)?

2. **Page Layout Planning**
   - Is the layout structure (grid/flex) specified?
   - Are responsive breakpoints defined (mobile-first)?
   - Is the visual hierarchy clear?
   - Are loading states and empty states planned?

3. **Design System Consistency**
   - Are only approved theme colors used (`primary`, `secondary`, `text`, etc.)?
   - Is spacing consistent with project patterns?
   - Are button styles, form inputs, and other elements using the standard components (not raw HTML)?

### B. Hotwire Integration (Critical)

1. **Turbo Frames**
   - Are Turbo Frame boundaries clearly identified?
   - Is frame nesting appropriate (not over-nested)?
   - Are lazy-loading opportunities identified?
   - Are frame IDs unique and semantic?
   - Is `data-turbo-frame="_top"` used appropriately for navigation?

2. **Turbo Streams**
   - Are real-time update targets identified?
   - Are stream actions appropriate (append, prepend, replace, remove)?
   - Is the broadcast strategy defined for ActionCable?
   - Are optimistic UI updates considered?

3. **Turbo Drive Considerations**
   - Are any pages/forms that should disable Turbo identified?
   - Are confirmation dialogs planned (`data-turbo-confirm`)?
   - Is form submission feedback planned?

### C. Stimulus Controllers (High Priority)

1. **Controller Design**
   - Are all client-side interactions identified that need Stimulus?
   - Are controller responsibilities single and focused?
   - Are controllers named semantically (`modal`, `dropdown`, `autosave`)?
   - Is state management approach defined (DOM vs controller state)?

2. **Controller Specification**
   - Are targets clearly defined for each controller?
   - Are values (configurable data attributes) specified?
   - Are action handlers listed with their trigger events?
   - Are lifecycle methods (connect, disconnect) planned?

3. **Controller Reusability**
   - Can existing controllers be reused?
   - Are new controllers generic enough for reuse?
   - Is cross-controller communication planned if needed?

### D. ViewComponent Planning (High Priority)

1. **Component Identification**
   - Are all distinct UI elements identified as potential components?
   - Is the component boundary appropriate (not too large or granular)?
   - Are slot/content block needs identified?

2. **Component Interface**
   - Are all parameters documented with types and defaults?
   - Are required vs optional parameters clear?
   - Are HTML options/data attributes passthrough planned?

3. **Component Variants**
   - Are different sizes/types/states planned?
   - Is conditional rendering logic specified?
   - Are error states and loading states included?

### E. Accessibility (Critical)

1. **Semantic HTML**
   - Is heading hierarchy planned (h1 -> h2 -> h3)?
   - Are landmarks planned (`<nav>`, `<main>`, `<aside>`)?
   - Are lists, tables, and forms semantically correct?

2. **ARIA Requirements**
   - Are `role` attributes planned for custom widgets?
   - Are `aria-label` and `aria-labelledby` specified?
   - Are `aria-expanded`, `aria-controls`, `aria-hidden` planned for interactive elements?
   - Are `aria-live` regions identified for dynamic content?

3. **Keyboard Navigation**
   - Is tab order logical?
   - Are keyboard handlers planned (Escape, Enter, Arrow keys)?
   - Is focus management specified for modals/drawers?
   - Are focus traps planned for overlays?

4. **Visual Accessibility**
   - Are color contrast requirements considered?
   - Are focus indicators visible?
   - Are touch targets adequate (44x44px minimum)?

### F. Responsive Design (High Priority)

1. **Breakpoint Strategy**
   - Is mobile-first approach followed?
   - Are layout changes at each breakpoint specified?
   - Is the responsive sidebar pattern used appropriately?

2. **Mobile Considerations**
   - Are touch interactions planned?
   - Is content priority clear for small screens?
   - Are mobile-specific components needed (bottom sheets, drawers)?

3. **Desktop Considerations**
   - Are hover states defined?
   - Is available space used effectively?
   - Are multi-column layouts specified?

### G. Form Handling (Medium Priority)

1. **Form Structure**
   - Are form components used consistently?
   - Is validation feedback planned (inline errors, summaries)?
   - Are required field indicators specified?
   - Is form submission handling clear (Turbo vs standard)?

2. **Complex Inputs**
   - Are date pickers, file uploads, rich text editors identified?
   - Are multi-step forms planned with proper navigation?
   - Is autosave needed and planned?

### H. Date Display Format (High Priority)

1. **Date Format Standard**
   - Are ALL dates displayed to users in `MM/DD/YYYY` format?
   - Flag any date displayed in ISO format (`YYYY-MM-DD`), European format (`DD/MM/YYYY`), or other non-standard formats as a BLOCKER

### I. Performance (Medium Priority)

1. **Loading Strategy**
   - Are lazy-loaded frames identified?
   - Is progressive content loading planned?
   - Are skeleton screens/loading indicators specified?

2. **JavaScript Efficiency**
   - Is unnecessary JavaScript avoided (using Turbo instead)?
   - Are event listeners properly scoped?
   - Is DOM manipulation minimized?

## Step 4: Generate Review Report

Save the report to `.claude/frontend-review-$(date +%Y%m%d-%H%M).md` so the caller can re-read
it while editing the plan. Format:

```markdown
# Front-End Architecture Review: [Plan Title]

**Reviewed**: [timestamp]
**Plan File**: [file path]
**Reviewer**: Front-End Architecture Expert (Claude)

---

## Executive Summary

[2-3 sentences summarizing front-end readiness and key concerns]

**Front-End Readiness**:
- :large_green_circle: Ready for Implementation
- :yellow_circle: Needs Clarification
- :red_circle: Significant Gaps

---

## Mandatory Component Reuse Audit (HIGHEST PRIORITY)

### Existing Component Usage
For each UI element in the plan, verify the correct existing component is specified:

| UI Element in Plan | Required Component | Status |
|---|---|---|
| [Any button] | `ButtonComponent` | USED / VIOLATION |
| [Any form input] | `FormInputComponent` | USED / VIOLATION |
| [Any submit button] | `FormSubmitButtonComponent` | USED / VIOLATION |
| [Any form errors] | `FormErrorsComponent` | USED / VIOLATION |
| [Any data table] | `DataTableComponent` | USED / VIOLATION |
| [Any table row actions] | Icon-only buttons with hover bubble (`pencil-square`, `trash`, `eye`, `arrow-path`) | USED / VIOLATION |
| [Any modal] | `ModalComponent` | USED / VIOLATION |
| [Any drawer] | `DrawerComponent` | USED / VIOLATION |
| [Any pill/badge] | `PillComponent` | USED / VIOLATION |
| [Any pagination] | `PagyPaginationComponent` | USED / VIOLATION |
| [Any page container] | `PageContainerComponent` | USED / VIOLATION |
| [Any filter form] | `FilterContainerComponent` (auto-submit, no button) | USED / VIOLATION |
| [Any filter text input] | `FilterTextFieldComponent` | USED / VIOLATION |
| [Any filter select] | `FilterSelectComponent` | USED / VIOLATION |
| [Any filter date input] | `FilterDateFieldComponent` | USED / VIOLATION |
| [Any filter searchable dropdown] | `FilterSearchableDropdownComponent` | USED / VIOLATION |
| [Any radio button group] | `FormRadioGroupComponent` | USED / VIOLATION |

### Component Violations (BLOCKERS)
- [List every instance where the plan uses raw HTML instead of an existing component]
- [Include the specific plan step/section and what component should be used instead]

### Thin Views Audit
| View File | Raw HTML Lines | Components Used | Status |
|---|---|---|---|
| [view path] | [count] | [list] | THIN / TOO THICK |

### View Thickness Violations (BLOCKERS)
- [List every view that has substantial raw HTML instead of component composition]
- [Identify markup that should be extracted into new ViewComponents]
- [Suggest component names for each extraction]

**If ANY violations exist above, overall status MUST be "MAJOR GAPS".**

---

## Component Analysis

### ViewComponents Identified
| Component | Purpose | Priority | Status |
|-----------|---------|----------|--------|
| [Name] | [Purpose] | High/Med/Low | Planned/Missing/Incomplete |

### Missing Components
- [Components that should be created but aren't in the plan]

### Component Interface Gaps
- [Parameters, slots, or variants that need specification]

---

## Stimulus Controller Analysis

### Controllers Identified
| Controller | Interactions | Targets | Values | Status |
|------------|-------------|---------|--------|--------|
| [name]_controller | [actions] | [targets] | [values] | Planned/Missing/Incomplete |

### Missing Controllers
- [Interactions that need Stimulus but no controller is planned]

### Controller Specification Gaps
- [Controllers that need more detail]

---

## Turbo Integration Analysis

### Turbo Frames
| Frame ID | Purpose | Lazy Load? | Status |
|----------|---------|------------|--------|
| [id] | [purpose] | Yes/No | Planned/Missing |

### Turbo Streams
| Target | Actions | Trigger | Status |
|--------|---------|---------|--------|
| [target] | [append/replace/etc] | [when] | Planned/Missing |

### Turbo Gaps
- [Missing Turbo integration opportunities]

---

## Accessibility Assessment

### ARIA Requirements
- :white_check_mark:/:x: Roles specified for custom widgets
- :white_check_mark:/:x: Labels specified for interactive elements
- :white_check_mark:/:x: State attributes planned (expanded, hidden, etc.)
- :white_check_mark:/:x: Live regions identified

### Keyboard Navigation
- :white_check_mark:/:x: Focus management planned
- :white_check_mark:/:x: Keyboard handlers specified
- :white_check_mark:/:x: Focus traps for modals

### Missing Accessibility Requirements
- [Specific accessibility gaps that must be addressed]

---

## Responsive Design Assessment

### Mobile Strategy
- :white_check_mark:/:x: Mobile-first approach specified
- :white_check_mark:/:x: Layout breakpoints defined
- :white_check_mark:/:x: Touch interactions planned

### Responsive Gaps
- [Missing responsive considerations]

---

## Critical Front-End Issues (Must Address)

### Issue 1: [Title]
**Category**: Component | Stimulus | Turbo | Accessibility | Responsive

**Problem**:
[Description of what's missing or incorrect]

**Impact**:
[Why this matters for UX or implementation]

**Recommendation**:
[Specific fix with code examples if helpful]

```erb
<%# Example of recommended approach %>
```

---

## Front-End Recommendations (Should Address)

### Recommendation 1: [Title]
**Current Plan**:
[What the plan proposes]

**Better Approach**:
[Improved approach with rationale]

---

## Front-End Suggestions (Nice to Have)

- [Optional improvements]

---

## Checklist for Implementation

### Before Starting
- [ ] **MANDATORY: All buttons use ButtonComponent (no raw `<button>` tags)**
- [ ] **MANDATORY: All form inputs use FormInputComponent (no raw `<input>`/`<select>`/`<textarea>` tags)**
- [ ] **MANDATORY: All radio button groups use FormRadioGroupComponent (no hand-written radio groups)**
- [ ] **MANDATORY: All form submits use FormSubmitButtonComponent**
- [ ] **MANDATORY: All data tables use DataTableComponent (no raw `<table>` tags) — existing raw tables must be refactored to DataTableComponent**
- [ ] **MANDATORY: Table row actions use icon-only buttons with hover bubble effects (not text-label ButtonComponent)**
- [ ] **MANDATORY: All pills/badges use PillComponent**
- [ ] **MANDATORY: All modals use ModalComponent, all drawers use DrawerComponent**
- [ ] **MANDATORY: Views are thin — mostly `render` calls, no substantial raw HTML**
- [ ] **MANDATORY: Every distinct UI section has a ViewComponent (page-specific or reusable)**
- [ ] **MANDATORY: Loops rendering items use a component for each item**
- [ ] **MANDATORY: Filtered table pages use FilterContainerComponent with auto-submit (NO filter button)**
- [ ] **MANDATORY: Filter inputs use FilterTextFieldComponent / FilterSelectComponent / FilterDateFieldComponent / FilterSearchableDropdownComponent**
- [ ] **MANDATORY: All dates displayed in MM/DD/YYYY format**
- [ ] All ViewComponents specified with interfaces
- [ ] All Stimulus controllers specified with targets/values/actions
- [ ] Turbo Frame boundaries clearly defined
- [ ] Accessibility requirements documented
- [ ] Responsive breakpoints specified
- [ ] Loading and error states planned

### Component Checklist
- [ ] [Component 1] - interface defined, variants specified
- [ ] [Component 2] - interface defined, variants specified

### Stimulus Controller Checklist
- [ ] [controller_name] - targets, values, and actions specified
- [ ] [controller_name] - targets, values, and actions specified

### Accessibility Checklist
- [ ] Heading hierarchy planned
- [ ] ARIA attributes specified
- [ ] Keyboard navigation defined
- [ ] Focus management documented

---

## Ambiguities & Recommended Defaults

This review is often consumed by an autonomous pipeline where no one can answer questions.
For each ambiguity, state the issue AND the default the plan should adopt:

1. [Ambiguous UI requirement] → **Default**: [specific recommendation to write into the plan]
2. [Unspecified interaction behavior] → **Default**: [specific recommendation]

---

## Final Verdict

**Status**: FRONT-END READY | NEEDS SPECIFICATION | MAJOR GAPS

[Summary of what needs to happen before front-end implementation can begin]

### Next Steps
1. [First thing to address]
2. [Second thing to address]
3. [Third thing to address]
```

## Review Principles

1. **ENFORCE COMPONENT REUSE FIRST**: This is the #1 priority. Every button, form input, table, modal, drawer, pill, and pagination MUST use existing components. Flag violations as BLOCKERS.
2. **Be Specific**: Reference exact sections of the plan
3. **Be Practical**: Focus on what affects implementation
4. **Think Mobile-First**: Always consider mobile experience
5. **Prioritize Accessibility**: Never skip a11y requirements
6. **Leverage Hotwire**: Prefer Turbo over custom JavaScript
7. **Reuse Components**: Check for existing components before suggesting new ones
8. **Enforce Zero Custom CSS**: Flag any custom CSS in the plan

## Anti-Patterns to Flag

### BLOCKERS (Must fix before implementation)
- **Raw `<button>` tags** instead of `ButtonComponent` - this is NEVER acceptable in views
- **Raw `<input>`, `<textarea>`, `<select>` tags** instead of `FormInputComponent` - this is NEVER acceptable in form views
- **Raw `<input type="submit">` or submit `<button>`** instead of `FormSubmitButtonComponent`
- **Raw `<table>` markup** instead of `DataTableComponent` for data display — this includes existing raw tables that should be refactored. Use `card: true` for card-wrapped tables, `hover: true` for row hover effects. Never wrap `DataTableComponent` in a manual card div — use the `card:` option instead
- **Text-label buttons for table row actions** instead of icon-only buttons with hover bubble effects — table action columns MUST use icon-only links/buttons with the standard hover pattern: `p-2 rounded-lg text-text-light hover:text-primary hover:bg-primary/10` for primary actions (view, edit, restore) and `hover:text-secondary-accent hover:bg-secondary-accent/10` for danger actions (delete). Must include `title` tooltip and `aria-label`. Standard icons: `eye` (view), `pencil-square` (edit), `trash` (delete), `arrow-path` (restore). Reference: `app/components/clinical_document_row_component.html.erb`, `app/views/settings/offices/index.html.erb`
- **Hand-written modal/dialog HTML** instead of `ModalComponent`
- **Hand-written drawer/slide-over HTML** instead of `DrawerComponent`
- **Hand-written pill/badge/tag HTML** instead of `PillComponent`
- **Hand-written pagination HTML** instead of `PagyPaginationComponent`
- **Hand-written form error lists** instead of `FormErrorsComponent`
- **Hand-written page container divs** instead of `PageContainerComponent`
- **Hand-written filter forms** instead of `FilterContainerComponent` with auto-submit
- **Filter forms with a "Filter" or "Search" button** — MUST use auto-submit pattern (no button). A `ButtonComponent` with `button_type: :submit` inside a `FilterContainerComponent` is NEVER acceptable.
- **Filter forms without `turbo_frame:` param or missing `turbo_frame_tag` wrapper** — auto-submit REQUIRES turbo frame targeting. Both filters and results must be wrapped in a `turbo_frame_tag`, and `FilterContainerComponent` must receive the matching `turbo_frame:` param. Reference: `app/views/fee_schedules/index.html.erb`
- **Hand-written filter inputs** (text, select, date) instead of `FilterTextFieldComponent` / `FilterSelectComponent` / `FilterDateFieldComponent` / `FilterSearchableDropdownComponent`
- **Hand-written radio button groups** (`<input type="radio">` groups) instead of `FormRadioGroupComponent` — radio button groups in forms MUST use this component for consistent styling, fieldset/legend, and error handling
- **Select filters missing auto-submit action** — `FilterSelectComponent` MUST have `html_options: { data: { action: "change->auto-submit#submit" } }` for immediate submission on change
- **Thick views** — views with substantial raw HTML that should be in components
- **Unextracted UI sections** — distinct page sections (cards, list items, stat blocks, form sections) not planned as ViewComponents
- **Loops rendering raw HTML** — each item in a loop should be rendered via a component
- **Dates not in MM/DD/YYYY format** — ALL user-facing dates MUST be displayed as `MM/DD/YYYY`

### HIGH PRIORITY
- Custom JavaScript where Turbo would suffice
- Custom CSS instead of Tailwind utilities
- Non-theme colors (arbitrary values like `bg-[#ff0000]`)
- Missing ViewComponents for repeated UI patterns
- Stimulus controllers that are too large or do too much
- Missing accessibility attributes
- Desktop-first responsive design

### MEDIUM PRIORITY
- Over-nested Turbo Frames
- Missing loading/error states
- Interactive elements without keyboard support
- Modals/drawers without focus management

Begin by locating the plan file and reading it along with the front-end expert skill and CLAUDE.md for context.
