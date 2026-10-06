---
name: service-test
description: Write or review the RSpec spec for one service object (app/services) so every business decision, side effect, external-API contract, and error path is guarded by an assertion that would actually fail, with no padding (constructor echoes, be_a(Result), one-assertion-per-example re-runs, private-method sends). Use when the user asks for service tests, points at a file in app/services or spec/services, or wants a service spec trimmed, sped up, or checked for whether it catches bugs.
argument-hint: '<app/services/... or spec/services/... path> [review|write]'
---

# Service Test

Write or review the spec for the service at `$ARGUMENTS`. First read
`.claude/skills/rspec-test-expert/test-quality.md` (the fat catalogue, the proof via coverage plus
probes, concurrency-safe spec runs, and the review workflow). This file covers what is particular
to services.

Map paths: `app/services/billing/charge_service.rb` ↔ `spec/services/billing/charge_service_spec.rb`.
If the spec exists you are in **review** mode; otherwise **write** mode.

## Service shapes

- **Callable** (`include Callable`): `described_class.call(**kwargs)` returns a `Result`, built by
  `success(**data)` or `failure(message, **data)`. Assert `be_success` / `be_failure`,
  `result.data[:key]` with exact values, and `result.error` with the exact message when a user
  will see it. `Callable` and `Result` have their own specs, so don't re-test `.call` delegating
  to `new`.
- **Domain-object services** (`FooService.new(record).do_thing`): test each public method the
  controllers or jobs call. Find the call sites (`grep -rn "FooService" app`) to know which
  methods are the real interface and what the callers do with the return value.
- **Class-method facades** (`.validate_step`): if a class method only does `new(...).same_method`,
  one example through it is enough. Test the logic once, not through both doors.

## What to guard

1. **Each decision in `call`.** Guards and early returns (each produces its own failure), branches
   on state/role/payer/type, loops that skip items. One scenario per branch; for comparisons,
   the boundary value and one past it.
2. **Side effects, with their content.** Records created or updated (`reload` and assert the fields
   that matter), jobs enqueued *with arguments*, mail enqueued to the right recipient, broadcasts.
   Also the negative: on failure, nothing was written (`not_to change`) or the transaction rolled
   back.
3. **External-API contract.** Stub at the boundary (Stripe, Stedi, Vertex AI, RingRx, Google,
   mediasoup, HTTP via WebMock/VCR) and assert the **arguments sent** (`hash_including(amount:
   15_000, payment_intent: "pi_…")`, idempotency key present). Then assert how each response
   shape (success, declined, rate-limited, timeout) maps to the Result.
4. **The rescue ladder.** The app's services rescue specific exceptions, then a catch-all, and call
   `Honeybadger.notify(e, context: {service: …, external_service: …})` (CLAUDE.md). Each rescue
   branch gets an example asserting the user-facing `failure` message and the notify with its
   context. Ops relies on both. This is the branch the suite most often leaves unexecuted.
5. **PHI safety where it applies.** Notify context, log payloads, and push payloads carry no PHI.
   Assert the absence when the service builds such a payload.

## Service-specific fat

- `#initialize` blocks: "sets the document", `instance_variable_get`, "accepts nil without error".
- `be_a(Result)`, `be_a(Hash)`, `have_key(:errors)`, `be_a(Integer)`, `be(true).or be(false)`.
- **Re-run padding.** Six examples that each call the service again to check one more field:
  `returns success` / `returns payment` / `returns refund_id` / `marks payment refunded` /
  `creates Stripe refund`. Make it one example per scenario, `:aggregate_failures`, asserting all
  facets. It's faster too, because every example rebuilds the client, invoice, and payment graph.
- `.send(:private_step)` tests. Drive the branch through `call`. Keep a `send` test only when
  deleting it would let a probe survive and the public path needs absurd setup; then note the
  design smell in findings.
- `allow(service).to receive(:valid?)`-style stubs of the subject's own methods, and stubs of cheap
  in-app models or services.
- `Rails.logger` expectations (keep the Honeybadger ones).
- "Integration scenario" blocks that repeat the happy path already covered above.
- Constants re-listed (`ASSESSMENT_FIELD_OPTIONS.keys.size == 15`, `to be_frozen`).

## Shape

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe StripeRefundService, type: :service do
  let(:payment) { create(:payment, :completed, amount_cents: 15_000, stripe_payment_intent_id: "pi_123") }
  let(:user) { create(:user, :admin) }

  def refund(**overrides) = described_class.call(payment:, reason: :requested_by_customer, refunded_by: user, **overrides)

  context "when Stripe accepts the full refund" do
    before { allow(Stripe::Refund).to receive(:create).and_return(double(id: "re_1", status: "succeeded")) }

    it "refunds the whole amount and records it", :aggregate_failures do
      result = refund

      expect(Stripe::Refund).to have_received(:create)
        .with(hash_including(payment_intent: "pi_123", amount: 15_000, reason: "requested_by_customer"), hash_including(:idempotency_key))
      expect(result).to be_success
      expect(result.data).to include(refund_id: "re_1", refund_amount: 15_000)
      expect(payment.reload).to have_attributes(status: "refunded", refunded_by: user)
    end
  end

  context "when Stripe raises" do
    before { allow(Stripe::Refund).to receive(:create).and_raise(Stripe::InvalidRequestError.new("charge already refunded", nil)) }

    it "fails with the user-facing message, reports, and leaves the payment untouched", :aggregate_failures do
      allow(Honeybadger).to receive(:notify)

      expect { refund }.not_to change { payment.reload.status }
      expect(refund.error).to eq("…exact message from the service…")
      expect(Honeybadger).to have_received(:notify).with(kind_of(Stripe::InvalidRequestError), hash_including(context: hash_including(external_service: "stripe")))
    end
  end
end
```

(Illustrative: read the real service for names, statuses, and messages.)

## Prove it, then report

Green, then coverage `--baseline` with no `lost_lines`. Then 2–5 probes aimed at the main branch
condition, a boundary, a value written or returned, an argument sent to the external API, and a
rescue branch's `failure` or `notify` line, all KILLED. Lint with `bin/standardrb <spec>`, and
report per `test-quality.md` or the caller's format.
