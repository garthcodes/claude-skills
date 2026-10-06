---
name: model-test
description: Write or review the RSpec spec for one ActiveRecord model (or model concern) so it tests the model's real business behavior (custom validations, scopes, callbacks, state changes, domain methods) and drops declaration-mirroring fat. Use when the user asks for model tests, points at a file in app/models or spec/models, or wants a model spec cleaned up, trimmed, or checked for whether it catches bugs.
argument-hint: '<app/models/... or spec/models/... path> [review|write]'
---

# Model Test

Write or review the spec for the model at `$ARGUMENTS`. First read
`.claude/skills/rspec-test-expert/test-quality.md`: the fat catalogue, the proof (coverage plus
probes), concurrency-safe spec runs, and the review workflow all live there. This file covers what
is particular to models.

Map paths: `app/models/foo/bar.rb` ↔ `spec/models/foo/bar_spec.rb`;
`app/models/concerns/x.rb` ↔ `spec/models/concerns/x_spec.rb`. If the spec exists, you are in
**review** mode (the workflow in `test-quality.md`); otherwise **write** mode.

## What a model's behavior is

Read the model and list these. They are what the spec must guard:

| In the model | Test it by |
|---|---|
| Custom `validate :method`, conditional validations (`if:`/`unless:`), cross-field rules | The valid and invalid case for each rule, asserting the specific `errors[:field]` message. Conditional: both sides of the condition. |
| Uniqueness with a scope, numeric bounds, format rules | A shoulda one-liner is fine here; it is short and asserts the rule's parameters. |
| Scopes and class query methods | Records that **should** and **should not** match, in one example. For ordering scopes, assert `eq([...])` order. Include the edge that the `where` clause draws (date boundary, status set). |
| Callbacks (`before_save`, `after_commit`, normalizers) | The observable effect: normalized value, enqueued job with args, created record. For `after_commit`, data must actually commit (default transactional tests do; check `have_enqueued_job`). |
| Enums | One example asserting the persisted integer values when they are stored or exported (`define_enum_for(...).with_values(...)`). Not the generated `?`/`!` methods; that's Rails. |
| State transitions and domain methods (`finalize!`, `billable_amount`, `display_name`) | Each branch, with exact values. Bang methods: the success path changes state; the guarded path raises or returns false and changes nothing. |
| `soft_delete_cascades_to`, SoftDeletable | `it_behaves_like "a soft-deletable model"` (`spec/support/shared_examples/soft_deletable_model.rb`) plus one example that the declared cascade targets get soft-deleted. The concern itself is tested in `spec/models/concerns/`. |
| Associations | Only those whose options carry behavior: `dependent:` (but remember that soft-delete doesn't cascade through `dependent:`), `optional: true` where nil is a real state, a non-obvious `class_name`/`foreign_key`/`inverse_of`, ordered `has_many`. Plain `belong_to(:organization)` is a mirror: drop it. |
| DB constraints the model relies on (check constraint, unique index, `null: false`, foreign key) | One example that the DB rejects the bad row (`save(validate: false)` / `update_column` → `NotNullViolation`/`RecordNotUnique`/`InvalidForeignKey`/`StatementInvalid`) when no validation covers it, **or when the constraint is new on this branch**, so the migration is proven to hold. |

## Model-specific fat to remove

- One-liners for every association and every presence validation, copied from the class body.
- "Factory creates a valid record", trait loops, `build vs create` demos.
- Re-testing concern behavior (HipaaLoggable, SoftDeletable, Normalizes…) in every includer. Test
  the concern once in `spec/models/concerns/`; in the includer, test only its configuration.
- `respond_to(:soft_delete)`, `included_modules`, `column_names` checks.
- N+1 or "query count" tests on plain associations. Keep a query-count example only when the model
  has a method whose point is preloading.
- `create`-heavy setup where `build` validates fine. Only scopes, callbacks, and uniqueness need
  persisted rows.

## Shape

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceAdjustment, type: :model do
  describe "validations" do
    it { is_expected.to validate_numericality_of(:amount_cents).other_than(0) }

    it "rejects a write-off larger than the invoice balance" do
      invoice = create(:invoice, balance_cents: 5_000)
      adjustment = build(:invoice_adjustment, invoice:, kind: :write_off, amount_cents: -6_000)

      expect(adjustment).not_to be_valid
      expect(adjustment.errors[:amount_cents]).to include("cannot exceed the remaining balance")
    end
  end

  describe ".posted_between" do
    it "includes both boundary days and excludes the day after", :aggregate_failures do
      travel_to Time.zone.local(2026, 9, 1, 12) do
        first = create(:invoice_adjustment, posted_on: Date.new(2026, 8, 1))
        last = create(:invoice_adjustment, posted_on: Date.new(2026, 8, 31))
        after = create(:invoice_adjustment, posted_on: Date.new(2026, 9, 1))

        result = described_class.posted_between(Date.new(2026, 8, 1), Date.new(2026, 8, 31))
        expect(result).to contain_exactly(first, last)
        expect(result).not_to include(after)
      end
    end
  end
end
```

(Illustrative: check the real model for names, messages, and columns. Never copy expectations
from this example.)

## Prove it, then report

Follow `test-quality.md`: the spec is green, coverage `--baseline` shows no `lost_lines`, and 2–5
probes are aimed at custom validations, scope conditions, callback effects, and transition guards,
all KILLED. Then lint with `bin/standardrb <spec>` and report as `test-quality.md` describes (or in
the caller's format).
