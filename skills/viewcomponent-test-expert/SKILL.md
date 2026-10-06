---
name: viewcomponent-test-expert
description: Write, review, trim, and fix RSpec specs for ViewComponents so they assert what a user sees and can do (text, links, buttons, form fields, ARIA, data-* hooks Stimulus relies on, each conditional state), not Tailwind classes, HTML substrings, private-method sends, or "it renders". Use when the user asks for component tests, points at app/components or spec/components, says component specs are bloated or brittle, or a component spec is failing.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# ViewComponent Test Expert

First read `.claude/skills/rspec-test-expert/test-quality.md`: the fat catalogue, the proof
(coverage plus probes), concurrency-safe spec runs, and the review workflow. This file covers what
is particular to components. Component specs are where most of this suite's fat lives (about
12,500 of the ~20,000 static-smell points), mostly CSS-class assertions, `to_html` substrings,
private `send`s, and ivar peeks.

Map paths: `app/components/foo/bar_component.rb` (+ `bar_component.html.erb`) ↔
`spec/components/foo/bar_component_spec.rb`.

## What a component's behavior is

A component's contract is **the DOM it hands to the user and to Stimulus**, given its inputs. For
each input or state the template branches on, assert:

| Assert | How |
|---|---|
| Visible text and values (formatted dates `MM/DD/YYYY`, money, names, empty states) | `expect(page).to have_css("[data-testid='…']", text: "12/31/2026")` / `have_text` |
| What the user can do: links (with href), buttons, form fields (name, value, disabled) | `have_link("Edit", href: edit_client_path(client))`, `have_button("Save", disabled: true)`, `have_field("client[email]", with: …)` |
| What must **not** be there in this state (no delete button for a biller, no PHI in a portal preview) | `not_to have_link(...)`, `not_to have_text(client.date_of_birth...)` |
| Accessibility that the markup is responsible for: label/field association, `aria-expanded`/`aria-controls` on toggles, `role="alertdialog"`, `sr-only` text on icon buttons | `have_css("button[aria-label='Remove payment method']")` |
| Stimulus wiring the JS depends on: `data-controller`, `data-*-target`, `data-action`, `data-*-value` | `have_css("[data-controller='autosave'][data-autosave-url-value='#{path}']")`; it's a contract with a JS file |
| Slots: content lands in the right place, and the component's behavior when a slot is absent | Render with and without the slot |
| Raises on bad input, when the component validates its arguments | `expect { described_class.new(mode: :bogus) }.to raise_error(ArgumentError, /mode/)` |
| `render?` | `expect(render_inline(...).to_html).to be_empty` when it should not render, plus one rendering case |

Public non-template methods that hold real logic (a status→label mapping, a formatter) can be unit
tested directly. They are often a component's most testable decision table. Use table-driven
examples.

## When classes ARE behavior

Assert a class only when it is the observable effect of a decision:

- visibility toggles (`hidden`, `sr-only`, `invisible`) driven by state;
- a status badge whose entire job is mapping state → color: one example per state, asserting the
  mapping (ideally via a public method or a `data-` attribute, not five Tailwind tokens);
- a selected or active marker (`aria-current` is better when the markup has it).

Padding, spacing, typography, borders, and shadows are design, not behavior. Never assert them.

## Component-specific fat

- `superclass == ApplicationComponent`, `be_present` after `render_inline`, "renders without error".
- Tailwind class and `to_html).to include("px-4 py-2 …")` assertions for styling.
- `.send(:private_helper)` and `instance_variable_get` (often dozens per file). Assert the rendered
  outcome of that helper instead. Keep a `send` only when removing it lets a probe survive and the
  rendered path is impractical, and note it.
- One example per attribute of the same element in the same state; merge with `:aggregate_failures`.
- Cross-tenant examples in components (tenancy isn't the component's job).
- `create` where `build`/`build_stubbed` renders fine. Components rarely need persisted records
  unless the template queries associations.

## App specifics

- `render_inline` then the Capybara `page` matchers are available in component specs (`type:
  :component`, ViewComponent test helpers are included by `rails_helper`). Prefer them over
  `rendered.css(...)` plus manual checks; they give better failure messages.
- Avo-embedded components: `it_behaves_like "an Avo-safe component"`
  (`spec/support/shared_examples/avo_safe_component.rb`).
- Times and dates in staff UI go through `StaffTimeHelper`; specs without an office render in
  `America/Los_Angeles`. Pin time with `travel_to`.
- Copy changes per the UI Copy Discipline in CLAUDE.md are design decisions. Assert copy that is
  data or required (labels, values, error text), not decorative phrasing that will churn.
- `spec/components/benefits_review_row_component_spec.rb` is a good reference: `data-testid`
  hooks, exact text, the absent state alongside the present one.

## Shape

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentMethodCardComponent, type: :component do
  let(:client) { create(:client) }
  let(:card) { create(:payment_method, client:, brand: "visa", last4: "4242", status: :active) }

  it "shows the card and lets the user remove it when another active method exists", :aggregate_failures do
    create(:payment_method, client:, status: :active)
    render_inline(described_class.new(payment_method: card))

    expect(page).to have_text("Visa ending in 4242")
    expect(page).to have_css("a[data-turbo-method='delete'][href='#{client_payment_method_path(client, card)}']")
  end

  it "replaces Remove with an explanation when it is the only active method", :aggregate_failures do
    render_inline(described_class.new(payment_method: card))

    expect(page).not_to have_css("a[data-turbo-method='delete']")
    expect(page).to have_css("[title='Must have at least one active payment method']")
  end
end
```

(Illustrative: read the real component and template for names, paths, and copy.)

## Prove it, then report

Run coverage on **both** files: `line_coverage.rb app/components/x_component.rb,app/components/x_component.html.erb spec/...`
(template lines are tracked through `eval` coverage). No `lost_lines`. Probe the template's
conditionals: flip an `if`/`unless` in the `.html.erb` or in `render?`, swap a link target or
`data-` value, or return a different label from a mapping method. All must be KILLED. Then lint
with `bin/standardrb <spec>` and report per `test-quality.md` or the caller's format.

If a spec fails and the cause isn't obvious, the usual suspects are: a selector that doesn't match
the real markup (print `page.native.to_html` once, then delete the print), roles missing because
of `build(:user, :role)`, a missing `travel_to`, or helpers the template needs that aren't stubbed
because they rely on a request (`with_request_url`).
