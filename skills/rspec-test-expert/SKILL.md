---
name: rspec-test-expert
description: Write, review, trim, and fix RSpec unit tests in a Rails app (models, services, jobs, mailers, helpers, lib, rake tasks, channels, initializers) so they test the code for real, with no padding. Owns the shared test-quality yardstick (test-quality.md) plus the coverage and mutation-probe scripts the other test skills use. Use whenever the user asks to write unit tests, add specs, improve or clean up existing specs, says tests are bloated, slow, or "not really testing anything", wants to know whether a spec actually catches bugs, or needs a failing unit spec fixed, even if they don't say "RSpec".
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# RSpec Test Expert

You write and review the app's unit specs. The goal is the smallest spec that **fails for every
behavior that matters** and **stays green through refactors that keep that behavior**. Coverage
counts and example counts are not the goal; this suite already has plenty of both and still lets
bugs through.

**Read `test-quality.md` (next to this file) before you write or change a spec.** It is the shared
yardstick: the fat catalogue, what "real" means, setup facts (tenant, roles, SoftDeletable),
the coverage and probe proof, concurrency-safe spec runs, and the review workflow. This file only
adds what is specific to the spec types routed here.

Specialist skills exist for models (`model-test`), services (`service-test`), policies
(`policy-test`) and components (`viewcomponent-test-expert`). If you were invoked for one of those
types, read that skill too. Jobs, mailers, helpers, lib, rake tasks, channels and initializers are
handled here.

## Two modes

- **Write**: no spec exists, or the user asked for new examples. Read the source, list its
  behaviors, write one example per behavior or decision, then prove it (coverage plus probes).
- **Review**: a spec exists and the user wants it improved, trimmed, or checked. Follow the review
  workflow in `test-quality.md`, steps 1–8. The rewrite is often shorter than the original. That
  is the point, provided `lost_lines` is empty and the probes are killed.

In both modes:

- run specs with your own `TEST_ENV_NUMBER` (2–9; see `test-quality.md`);
- never edit application code, and log suspected bugs as findings;
- don't commit unless the caller asks (the `/spec-sweep` orchestrator commits batches itself).

## Spec-type notes

### Jobs (`spec/jobs`)

A job is a thin adapter: arguments in, a service call or side effect out, plus retry/discard
policy. Test:

- `perform_now` with real records produces the side effect, or calls the service with the right
  arguments when the service has its own spec (that is the boundary; stubbing it here is fine);
- early returns (record missing or soft-deleted, already processed): assert nothing happens;
- `retry_on`/`discard_on`: assert behavior for the exception class that matters
  (`perform_enqueued_jobs` plus `assert_performed_jobs`, or call `perform_now` and check the
  discard side effect), not the declaration;
- `honeybadger_context` for jobs with PHI arguments: assert it omits the PHI.

Don't test `queue_as` or `perform_later` enqueuing itself (Rails), or that `ApplicationJob` is the
superclass.

### Mailers (`spec/mailers`)

Assert what the recipient gets: `to`, `subject`, key body text in **both** the HTML and text
parts, org branding present (the layout must be used, per CLAUDE.md), links pointing at the right
host and path, and no PHI where it is forbidden. One example per email action plus one per
conditional section. Don't snapshot whole bodies.

### Helpers (`spec/helpers`)

Pure input→output. Table-driven examples are ideal: list the cases inline with the expected
string and iterate. Dates render `MM/DD/YYYY`; times go through `StaffTimeHelper` or
`ClientTimeHelper` in the office zone (specs without an office render in
`America/Los_Angeles`).

### Lib, rake tasks, channels, initializers

- **lib/**: test like a service, through the public API.
- **Rake tasks** (`spec/tasks`): load once (`Rails.application.load_tasks` guarded, then
  `Rake::Task[...].reenable` per example). Production tasks must have a `DRY RUN`/`APPLY` banner
  first and exactly one `RESULT:` line last (CLAUDE.md, Production Safety). Assert dry-run writes
  nothing, `APPLY=1` writes, the `RESULT:` counts are right, and a re-run is idempotent. Those are
  the behaviors the user relies on before running against production.
- **Channels**: subscription accepted or rejected per actor, and what gets broadcast.
- **Initializers**: only the behavior they install (a Rack middleware decision, a
  `before_notify` hook that adds context). Not that a constant is set.

## Matchers worth reaching for

```ruby
expect(result).to be_success                               # Result predicates, not be_a(Result)
expect(result.error).to eq("Card was declined")            # exact user-facing copy
expect { call }.to change { invoice.reload.status }.from("draft").to("sent")
expect { call }.to have_enqueued_job(PushDeliveryJob).with(user.id, kind: "dm")
expect { call }.not_to have_enqueued_mail                  # the negative that carries the risk
expect(Honeybadger).to have_received(:notify).with(kind_of(Stripe::CardError), hash_including(context: hash_including(service: described_class.name)))
it "…", :aggregate_failures do … end                       # one scenario, several facets
```

## When a spec fails and the cause isn't obvious

Work through `debugging-checklist.md`. The app-specific usual suspects, in order:

1. stale or unseeded parallel DB (`Reference data not found`): re-run `parallel:prepare_with_seeds`;
2. a `build(:user, :role)` with no roles (roles need `create`);
3. a timezone or UTC-boundary flake in the hours when the local date and the UTC date differ: `travel_to` a fixed instant;
4. a soft-deleted record hidden by the default scope;
5. an async HIPAA audit write that needs `perform_enqueued_jobs`.

## Report

End with: what you changed (examples deleted, merged, added, tightened), lines and examples
before→after, coverage before→after with `lost_lines`, probes killed/total with any survivor
explained, and findings about the source code. Keep it short. If the caller gave you a report
format (e.g. `/spec-sweep`), use that one instead.
