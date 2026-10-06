# Behavior lock

The lock is a set of specs that describe what the code does **today**, written before the refactor and left untouched by it. If they pass on the old code, still pass on the new code, and fail when the effect is removed, the refactor kept behavior. Everything else in this file serves those three conditions.

## Where the examples go

`spec/refactor_locks/<slug>/<caller>_spec.rb`, one file per caller boundary. That folder runs in `bin/ci` and the GitHub unit step. Lock specs stay after the merge as regression tests for the new structure.

## Pick a boundary that survives the refactor

The lock must call the code the same way before and after. Ask "what will still exist, with the same signature, once this PR lands?" and call that:

| Target kind | Lock through | Not through |
|---|---|---|
| `callback` | the **callers** that trigger the save: the service, job or model method that stays public, the controller action (see below), the Avo action | `record.save`/`update` directly (after the refactor the model no longer fires the effect, by design), or the callback method |
| `model_logic` | the callers of the model method, and the model method itself if it stays as a thin delegate | private helpers |
| `callable` | `OldService.call(...)` / `OldService.new(...).call` from today's callers. If the PR keeps the old name as a delegate, the lock calls it; if every caller is rewritten, lock through those callers instead | the new class (it doesn't exist yet) |
| `fat_job` | `Job.perform_now(id)` and `perform_enqueued_jobs` around the enqueue site | the job's private methods |
| `locals` | a render of the parent view or component that uses each partial (`render_inline`, or a view spec in the locks folder), asserting the visible text and the attributes that matter | the partial in isolation with made-up locals |
| `route` | a request for the old path and the new one: status, redirect target, record changes | — |
| `unique_index` | `save(validate: false)` of a duplicate row → `ActiveRecord::RecordNotUnique` (written red on the old schema, green after: the one lock that's expected to flip; say so in the PR) | — |

**Controller callers.** When the only boundary is an HTML controller action, a `type: :request` example in the locks folder is acceptable: it's a temporary behavior harness, not feature coverage, which is what CLAUDE.md's Request Specs Policy governs. Keep it to the effect (`expect { patch appointment_path(appt), params: … }.to have_enqueued_job(CalendarEventPushJob).with(appt.id)`), not the HTML. If a system spec already drives that path, prefer adding the assertion to a lock-folder system spec only when no service boundary exists; system specs are slow and flaky to use as a lock.

## What each example asserts

One example per effect per meaningful condition, using the matchers the suite already uses:

- jobs: `have_enqueued_job(Klass).with(args)` (+ `.on_queue`, `.at` when `wait`/`wait_until` matter); count with `.exactly(n).times` when duplicates would be a bug;
- mail: `have_enqueued_mail(Mailer, :action).with(...)`;
- broadcasts: `have_broadcasted_to(stream)`, or `expect(Turbo::StreamsChannel).to receive(:broadcast_…_to).with(...)` matching how the code broadcasts today;
- external calls: the existing Stripe/Stedi helpers or `stub_request` with an assertion that it was requested, never a live call;
- records: the exact columns written, the records created (`change(Model, :count).by(n)`), and the ones left alone;
- return values and errors: the `Result` (success, data, error message) or the exception class;
- the **negative side**: each `if:`/`unless:`/guard. An effect that fires when it shouldn't is as much a behavior change as one that stops firing.
- **timing** when it matters: an effect that runs after commit must not run when the transaction rolls back (`ActiveRecord::Base.transaction { …; raise ActiveRecord::Rollback }` → `not_to have_enqueued_job`). The app's specs run in transactions, so use `perform_enqueued_jobs`/commit-aware helpers the existing specs for that model already use.

Tenant: build records inside the default tenant (rails_helper sets it). Add one example with `ActsAsTenant.with_tenant(other_org)` when the effect carries an org id, since moving code out of a callback is where tenant context gets lost.

## Proving the lock

1. Green on the old code, run alone and together (`bundle exec rspec spec/refactor_locks/<slug>/`).
2. Probe each effect on the old code with `$SKILLS/rspec-test-expert/scripts/probe.rb`, aimed at the line that produces it:
   ```bash
   bundle exec ruby $SKILLS/rspec-test-expert/scripts/probe.rb --file app/models/appointment.rb --line 724 \
     --replace "  # probe" --why "drop calendar push" spec/refactor_locks/<slug>/
   ```
   Every probe KILLED. A SURVIVED effect is not locked: tighten the example (`.with(args)`, `exactly`), then probe again. INVALID means the mutation broke loading; pick a different mutation.
3. Commit the lock files alone, before any app change: `test(refactor): lock behavior of <id>`. That commit is `LOCK_SHA`.
4. After the refactor (Step 7), `git diff $LOCK_SHA -- spec/refactor_locks/` must be empty, the locks green, and 2–3 probes re-aimed at the effect's **new** line still KILLED.

## When a lock can't be written

Some effects are hard to observe (a `Rails.cache` write, a log line, a metric). Write down the effect and how you verified it instead (read the code, ran it in the console of the worktree), and list it under **Behavior lock** in the PR as "verified by reading, not locked". Never skip an effect silently.
