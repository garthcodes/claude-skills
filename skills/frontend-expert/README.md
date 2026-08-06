# Frontend Expert Skill

This skill specializes in building front-end features using the Hotwire stack (Turbo + Stimulus), ViewComponents, and Tailwind CSS for a Rails 8 application.

## When to Use This Skill

Invoke this skill when you need to:

- Build new UI components or interactive features
- Create or modify Stimulus controllers
- Develop ViewComponents
- Implement responsive designs with Tailwind CSS
- Work with Turbo Frames or Turbo Streams
- Add client-side interactivity
- Create mobile-first responsive layouts
- Implement accessible interfaces

## CRITICAL: Mandatory Component Reuse

This skill STRICTLY enforces using existing ViewComponents. Writing raw HTML for elements covered by components is a **hard error**:

| UI Element | MUST Use | NEVER Write Raw HTML |
|---|---|---|
| Buttons | `ButtonComponent` | `<button>` tags in views |
| Form inputs | `FormInputComponent` | `<input>`, `<textarea>`, `<select>` in forms |
| Submit buttons | `FormSubmitButtonComponent` | Submit buttons in forms |
| Form errors | `FormErrorsComponent` | Error message lists |
| Data tables | `DataTableComponent` (with `card:`, `hover:`, `data:` options) | `<table>` elements — refactor existing raw tables too |
| Modals | `ModalComponent` | Modal/dialog markup |
| Drawers | `DrawerComponent` | Slide-over panels |
| Flash messages | `FlashComponent` | Toast notifications |
| Pills/badges | `PillComponent` | Status badges/tags |
| Pagination | `PagyPaginationComponent` | Pagination controls |
| Page containers | `PageContainerComponent` | Page wrappers |

## CRITICAL: Thin Views / Component-First Architecture

All meaningful HTML markup must live in ViewComponents, not in view templates. Views should be thin composition layers — primarily `render` calls with minimal HTML glue. This ensures all UI is unit-testable via ViewComponent tests.

**When to create a new component:**
- The markup has any logic (conditionals, loops, computed classes)
- The markup is more than ~5 lines of HTML in a view
- The markup represents a distinct UI concept (card, header, stat block, list item)
- The same pattern appears in 2+ places
- The markup would benefit from unit testing (almost always)

**Views should contain:** `render` calls, `form_with` blocks using form components, `turbo_frame_tag` wrappers, simple conditionals, minimal layout divs.

**Views should NOT contain:** Complex HTML structures, repeated patterns, conditional markup, raw form elements, raw buttons, raw tables.

## Skill Capabilities

### Stimulus Controllers

The skill knows how to:
- Create controllers with proper target, value, and action patterns
- Implement common patterns (modals, sidebars, autosave, form builders)
- Handle accessibility (focus management, keyboard navigation, ARIA)
- Manage lifecycle methods (connect/disconnect)
- Work with events and custom event dispatching

### ViewComponents

The skill knows how to:
- Structure components with `.rb` and `.html.erb` files
- Create reusable UI elements (buttons, modals, forms, cards)
- Implement dynamic class generation with Tailwind
- Handle component props and initialization
- Build complex components (multi-step wizards, form renderers)

### Tailwind CSS

The skill STRICTLY enforces:
- **ZERO custom CSS** - No CSS files, no `<style>` tags, no `style=""` attributes
- **ONLY theme colors** - Must use colors from `app/assets/tailwind/application.css` @theme section
- **NO arbitrary values** - No `bg-[#ff0000]` or similar
- **NO default Tailwind colors** - No `bg-blue-500`, `text-red-600`, etc.

The skill knows how to:
- Use the custom OKLCH color system from the theme
- Apply semantic color names (bg-primary, text-text, etc.)
- Build responsive layouts (mobile-first)
- Create consistent component styles
- Apply transitions and interactive states
- Follow accessibility guidelines (focus rings, contrast)

### Hotwire/Turbo

The skill knows how to:
- Implement Turbo Frames for partial page updates
- Create Turbo Stream responses for dynamic updates
- Set up real-time features with Turbo Streams and ActionCable
- Handle form submissions with Turbo
- Implement lazy loading with Turbo Frames

## Example Usage

```
User: "I need to create a filterable data table with sorting"

Skill will:
1. Create a ViewComponent for the table
2. Build a Stimulus controller for filtering/sorting
3. Use Tailwind for responsive table design
4. Implement Turbo Frames for dynamic updates
5. Add keyboard navigation and ARIA attributes
```

```
User: "Add a slide-over panel for notifications"

Skill will:
1. Create a DrawerComponent (ViewComponent)
2. Build a drawer_controller.js (Stimulus)
3. Implement slide-in/out animations with Tailwind
4. Add focus management and ESC key handling
5. Make it responsive (full-screen on mobile, slide-over on desktop)
```

## Patterns This Skill Uses

### From Your Codebase

The skill has analyzed and will follow patterns from:

- **Responsive Sidebar**: `app/javascript/controllers/responsive_sidebar_controller.js`
- **Modal System**: `app/javascript/controllers/modal_controller.js`
- **Autosave**: `app/javascript/controllers/bps_autosave_controller.js`
- **Form Builder**: `app/javascript/controllers/form_builder_controller.js`
- **Button Component**: `app/components/button_component.rb`
- **Form Components**: `app/components/form_input_component.rb`
- **Theme System**: `app/assets/tailwind/application.css`

### Architectural Principles

1. **Mobile-First Design** - Build for mobile, enhance for desktop
2. **Progressive Enhancement** - HTML works first, JavaScript enhances
3. **Component Composition** - Small, focused components that combine
4. **Accessibility First** - ARIA, keyboard nav, focus management
5. **Utility-First CSS** - Tailwind only, no custom CSS
6. **Stimulus Convention** - Targets, values, actions pattern

## File Organization

The skill will create files in the correct locations:

```
app/
├── components/
│   ├── {name}_component.rb
│   └── {name}_component.html.erb
├── javascript/
│   └── controllers/
│       └── {name}_controller.js
└── views/
    └── {resource}/
        └── {action}.turbo_stream.erb
```

## Testing Guidance

The skill knows how to test:

- **ViewComponents**: Unit tests with ViewComponent::TestCase
- **Stimulus Controllers**: System tests with JavaScript enabled
- **Turbo Streams**: Integration tests for dynamic updates
- **Accessibility**: Semantic HTML, ARIA attributes, keyboard navigation

## Accessibility Standards

Every feature built by this skill will include:

- Semantic HTML (proper heading hierarchy, landmarks)
- ARIA attributes (roles, labels, states)
- Keyboard navigation (Tab, Escape, Enter, Arrow keys)
- Focus management (visible indicators, logical order, focus trapping)
- Color contrast (WCAG AA compliance)
- Screen reader support

## Color System Reference

⚠️ **CRITICAL**: These are the ONLY colors allowed. Use nothing else.

The skill uses these semantic colors from your theme (`app/assets/tailwind/application.css`):

**Primary Colors** (Actions, Links)
- `bg-primary` / `text-primary` - Teal/blue (oklch(0.55 0.15 200))
- `bg-primary-light` / `text-primary-light` - Light teal/blue (oklch(0.75 0.15 200))
- `bg-primary-dark` / `text-primary-dark` - Dark teal/blue (oklch(0.45 0.15 200))

**Secondary Colors** (Borders, Subtle Backgrounds)
- `bg-secondary` / `text-secondary` - Light gray (oklch(0.98 0.02 100))

**Accent Colors** (Warnings, Errors)
- `bg-accent` / `text-accent` - Yellow/orange (oklch(0.85 0.18 80))
- `bg-secondary-accent` / `text-secondary-accent` - Red/danger (oklch(0.7 0.1183 27))
- `bg-secondary-dark` / `text-secondary-dark` - Dark red (oklch(0.4 0.1183 27))

**Text Colors**
- `text-text` - Dark gray for primary text (oklch(0.25 0.01 240))
- `text-text-light` - Medium gray for secondary text (oklch(0.65 0.01 240))
- `text-text-white` - White text on dark backgrounds (oklch(1 0 0))

**Background Colors**
- `bg-background` - White main background (oklch(1 0 0))
- `bg-background-alt` - Light blue-gray alternate background (oklch(0.98 0.02 240))

**FORBIDDEN:**
❌ Default Tailwind colors: `bg-blue-500`, `bg-red-600`, `bg-gray-100`, etc.
❌ Arbitrary values: `bg-[#3b82f6]`, `text-[rgb(255,0,0)]`, etc.
❌ Any color not listed above

## Common Tasks

### Create a Modal

```
"Create a confirmation modal for deleting clients"
```

Will generate:
- `ModalComponent` (if doesn't exist)
- `modal_controller.js` (if doesn't exist)
- Proper ARIA attributes and focus management
- ESC key and backdrop click handling

### Create a Dynamic Form

```
"Build a form that autosaves and shows validation errors inline"
```

Will generate:
- `autosave_controller.js`
- `FormInputComponent` with error states
- Turbo Stream responses for validation
- Debounced save with status indicator

### Create a Responsive Layout

```
"Create a responsive sidebar that's a drawer on mobile"
```

Will generate:
- `responsive_sidebar_controller.js`
- Breakpoint handling at 1024px
- Mobile overlay and toggle button
- Desktop always-visible sidebar

## Tips for Using This Skill

1. **Be Specific**: Describe the interaction you want, not just the visual
2. **Mention Responsiveness**: Specify if mobile behavior differs from desktop
3. **Describe State**: Explain what happens (loading, success, error states)
4. **Reference Existing**: Mention if it should be similar to another feature
5. **Accessibility Needs**: Call out any specific accessibility requirements

## Related Skills

- **rspec-test-expert**: Use for testing components and controllers
- **system-test-expert**: Use for full-stack feature testing with JavaScript

## Skill Maintenance

This skill is based on patterns found in:
- Rails 8.0.2 application structure
- Hotwire (Turbo 8, Stimulus 3)
- ViewComponent gem
- Tailwind CSS with OKLCH custom theme

If your patterns change significantly, update `skill.md` with new examples.
