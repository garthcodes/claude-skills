# Test quality: what a real unit test is, and what fat is

The one definition every test skill shares: `rspec-test-expert`, `model-test`, `service-test`,
`policy-test`, `viewcomponent-test-expert`, `component-test`, `test-changed`, and the `/spec-sweep`
orchestrator. Writing a new spec and reviewing an old one use the same yardstick.

## The two questions

Ask them of every example:

1. **If someone broke the behavior this example is named after, would it fail, and for that reason?**
   If not, it is fat (it asserts nothing that matters) or fake (it asserts a mock it set up itself).
2. **Would it fail when nothing a user, another class, or an operator relies on has changed?**
   If yes, it is brittle. It pins down markup, wording, or internals, and it will be "fixed" by
   rewriting the expectation, which teaches people to ignore red tests.

A spec is good when it is the smallest set of examples that fails for every behavior that matters
and stays green through every refactor that keeps that behavior.

Why this matters here: this suite was grown by skills that told agents to be "comprehensive" and
to keep "one assertion per test". That produced ~4,000 `be_present` checks, ~2,500 private-method
`send` calls, ~2,700 Tailwind-class assertions, and ~300 `superclass` tests. They make CI slow,
reviews noisy, and refactors expensive, and they still let real bugs through (see "Proof" below).

## Fat: delete it, or turn it into a real assertion

| Pattern | Why it is fat | Do instead |
|---|---|---|
| `described_class.superclass`, `included_modules`, `ancestors`, `respond_to(:x)` | The class cannot work without these. Any behavior test already fails if they break. | Delete. |
| Constructor echo: `instance_variable_get`, `service.document == document`, "initializes with empty errors" | Tests Ruby assignment. | Delete; test what the object *does* with its inputs. |
| `expect { described_class.new(x) }.not_to raise_error` as the only check | Passes for almost any implementation. | Assert the outcome of the call. |
| Type-only: `be_a(Result)`, `be_a(Integer)`, `be(true).or be(false)`, `have_key(:x)` | Any value of the right type passes. | Assert the value: `eq(42)`, `be_success`, `eq(session_info: {})`. |
| Loose presence: `be_present`, `be_truthy`, `not_to be_nil`, `(rendered).to be_present` | Passes for the wrong value too. | Assert the exact value, text, or selector you expect. |
| Constant self-tests: `to be_frozen`, `KEYS.size == 15`, re-listing a constant's contents | Restates the source; changes in lockstep with it. | Delete, unless the constant is an external contract (values persisted in the DB, sent to Stedi/Stripe, shown to users), where one example asserting the exact values is fine. |
| Factory self-tests ("creates a valid record", trait loops) | Every other example already uses the factory; a broken factory fails them all. | Delete. |
| Bare association mirrors: `it { is_expected.to belong_to(:organization) }` | Restates the declaration. | Keep only associations whose options carry behavior: `dependent:`, `optional`, non-obvious `class_name`/`foreign_key`, `inverse_of`. |
| Validations of things nobody relies on | Restates the declaration. | Keep validations that encode a business rule (uniqueness scope, numeric bounds, conditional presence). Test custom `validate` methods for real. |
| "One assertion per example" padding: 4–6 examples with identical setup that each re-run the call to check one more field | Each example re-creates the DB graph, so this is slow and repetitive. | One example per scenario with `:aggregate_failures`, asserting the whole outcome. |
| Parameter echoes: the same assertion for a string step name, a symbol step name, a frozen string… | Duplicates unless the code branches on it. | Keep one, plus one per real branch. |
| `.send(:private_method)` | Couples the spec to internals and blocks refactors. | Reach the branch through the public method. If that genuinely needs huge setup, keep the `send` test **only** when deleting it would let a probe survive, and note the design smell in the report. |
| Stubbing the subject: `allow(service).to receive(:step_two)`, `allow_any_instance_of(described_class)` | You test your stub, not the code. | Drive the real path with real data. |
| Mocking cheap in-app collaborators (models, in-app services, policies) | Creates fake worlds that drift from reality. | Use real records. Mock only at boundaries (below). |
| `Rails.logger` expectations | Logs are not behavior. | Delete, unless the log line *is* the contract (an audit or ops line someone greps for). |
| Tailwind class assertions (`['class']).to include('bg-…')`, `to_html).to include('px-4')`) | Pins styling; breaks on every redesign, catches no bug. | Delete, unless the class *is* the behavior: `hidden`/`sr-only` toggled by state, or the color mapping that is the whole purpose of a status badge (then one example per state). |
| `rendered.to_html).to include('…')` substring checks | Matches anywhere, including attributes and comments. | `expect(page).to have_css/have_link/have_button(…, text:)` on the element that matters. |
| `xit`, `skip`, `pending`, commented-out examples | Dead weight that looks like coverage. | Fix it or delete it. |
| Tests of Rails itself (`save` changes `count` with no logic of yours involved) | Rails is tested upstream. | Delete. |

## Real: what to keep and what to add

- **Exact outcomes.** Return values; persisted state after `reload`; enqueued jobs *with
  arguments* (`have_enqueued_job(X).with(id)`); mail recipients and subject; `Result#error` text
  when a user sees it.
- **One example per decision.** Every `if`/`case`/guard/early-return/`rescue` in the source has an
  example that fails if that decision goes the wrong way. Boundaries get both sides (`>=` vs `>`:
  test the edge value and one past it).
- **Negative cases where they carry the risk.** Authorization denials, records a scope must *not*
  return, notifications that must *not* go out, PHI that must *not* appear.
- **Error paths that ops depend on.** A `rescue` that calls `Honeybadger.notify` gets an example
  asserting the notify (with its `context:` keys) and the user-facing failure. CLAUDE.md makes
  that notify a requirement, so it is behavior.
- **Time is explicit.** `travel_to` a fixed instant, never "now". Timezone code is tested in the
  zone that matters (`America/Phoenix` has no DST; use a DST zone when DST is the point).

### Mock only at the boundary

Mock external services and nondeterminism: HTTP (WebMock/VCR), Stripe, Stedi, Vertex AI, RingRx,
Google Calendar, mediasoup, Mailgun, the clock, and randomness. Everything inside the app (models,
services, policies, jobs) runs for real. Mocking at the boundary also defines the contract:
assert the *arguments* sent to the external API (`hash_including(amount: 15000)`), because that
is what reaches the outside world.

### Setup facts that keep specs lean

- `rails_helper` already sets `ActsAsTenant.current_tenant` to the default org for every non-system
  spec. Use `$default_organization` (or nothing at all). Do not `create(:organization)` and
  re-set the tenant in every file, and do not wrap every example in `with_tenant`. Use
  `ActsAsTenant.with_tenant(other_org)` only when the example is *about* a second org.
- Cross-org access is enforced by `acts_as_tenant` at the query layer. Policy and model specs do
  not need "user from another org is denied" examples (CLAUDE.md, Multi-tenancy).
- User roles are added in `after(:create)`, so `build(:user, :admin)` has **no** roles. A bare
  `create(:user)` is a **therapist** (`role_names` defaults to `[:therapist]`); for "no role" use
  `role_names: []`. Real roles are `Role::ROLES`: admin, coordinator, therapist, manager,
  clinical_supervisor, biller, platform_admin. There is no `supervisor` and no `owner` role.
- SoftDeletable models: `destroy` soft-deletes (`deleted_at` set, row still in
  `Model.including_deleted`), `dependent: :destroy` does not cascade on soft-delete, and HIPAA
  audit rows for soft-deletes are written by a job (`perform_enqueued_jobs` first).
- Prefer `build`/`build_stubbed` when nothing queries the DB. Each `create` of a client or
  appointment builds a large graph, so share setup with `let` and avoid `let!` for records only
  some examples need.

## Proof: "it tests the code for real"

Reading a spec is not enough to know it bites. Two cheap, mechanical checks do. Run them with your
own `TEST_ENV_NUMBER` (see "Running specs" below).

**1. Coverage must not drop.** Take a baseline before editing and compare after:

```bash
S=app/services/foo_service.rb; P=spec/services/foo_service_spec.rb
TEST_ENV_NUMBER=$N bundle exec ruby .claude/skills/rspec-test-expert/scripts/line_coverage.rb $S $P --save tmp/spec-sweep/foo.before.json
# …rewrite…
TEST_ENV_NUMBER=$N bundle exec ruby .claude/skills/rspec-test-expert/scripts/line_coverage.rb $S $P --baseline tmp/spec-sweep/foo.before.json
```

`lost_lines` must be empty. A lost line means you deleted the only example that reached it:
add a real example back. Join a component's `.rb` and `.html.erb` with a comma to cover both.
Coverage only proves a line *ran*, not that anything checked its result, so it is necessary but
not sufficient.

**2. Probes must be killed.** A probe breaks one line of source on purpose, runs the spec, and
always restores the file:

```bash
TEST_ENV_NUMBER=$N bundle exec ruby .claude/skills/rspec-test-expert/scripts/probe.rb \
  --file $S --line 42 --from ">= 18" --to "> 18" --why "age boundary" $P
# → KILLED / SURVIVED / INVALID
```

Pick 2–5 probes aimed at what matters most in the source: the main decision branches, boundary
comparisons, the value returned or persisted, arguments passed to an external API, and the
`rescue` path (replace the notify or the failure line). Useful mutations: flip a comparison,
negate a condition, return a different constant, replace a statement with `nil`, drop a hash key
or argument. Don't probe log lines or comments.

- **KILLED**: good, the spec guards that behavior.
- **SURVIVED**: no example asserts it. Add or strengthen one, then re-probe. If you conclude the
  behavior really doesn't matter, say why in your report; never quietly accept a survivor.
- **INVALID**: your mutation broke loading (syntax or constant). That proves nothing; pick another.
- **Equivalent mutants.** Before writing an assertion for a survivor, ask whether the mutation
  changes behavior at all. Example: removing `html_options.dup` survives in `ButtonComponent`
  because the template only reads through `.except`, so nothing mutates the hash anymore. No
  test can kill that. Pick a different probe, and if the line is dead defensive code, record it
  as a finding. Don't contort a spec to "kill" a mutant that can't change behavior.

The probe refuses to touch a file with uncommitted changes, restores it on exit, and verifies
`git diff` is clean. You never edit `app/` yourself.

A real example from this suite: in `ComputeAllowedSendTimeService`, gutting the main computation
was killed by 10 of 11 examples, but the `rescue` branch (Honeybadger notify plus a user-facing
failure) was never executed. Changing its message survived. Coverage showed lines 26–27
uncovered, and the probe confirmed nothing guarded them.

## Running specs (concurrency-safe)

- Run a single spec with `TEST_ENV_NUMBER=<n> bundle exec rspec <spec>`. Each `<n>` (2..9) is its
  own database (`<app>_test<n>`).
- Without `TEST_ENV_NUMBER`, `rails_helper`'s `before(:suite)` truncates the shared `<app>_test`. Two
  agents doing that at once wipe each other's data and produce phantom failures.
- The parallel databases need the current schema and reference data.
  `bash .claude/skills/spec-sweep/scripts/db_ready.sh <n>` tells you whether yours does. If not
  (`Reference data not found in <app>_test<n>`, or a migration landed since the last prepare), run
  `PARALLEL_TEST_PROCESSORS=9 bundle exec rake parallel:prepare_with_seeds` (about 25 s), but only
  when no one else is running specs. It wipes `<app>_test` and `<app>_test2..9`. A stale schema left
  alone makes `maintain_test_schema!` silently drop and rebuild that DB *without* seeds, which can
  hang for minutes and then fail.
- Lint touched specs with `bin/standardrb <files>`. Never use bare `bundle exec standardrb` (see
  CLAUDE.md).

## Reviewing an existing spec: the workflow

1. **Read the source fully.** List its behaviors: decision points, outputs, side effects, error
   paths. This list, not the old spec, is what the new spec must cover.
   **Then check intent before pinning anything.** Find the callers (`grep -rn ClassName app`) and
   ask what each rule is *for*: who it protects, and what the user or caller experiences. Does the
   code achieve that? A spec pins behavior, so pinning a wrong rule makes the bug look intended.
   Example: a "max 5 attempts" limit on access tokens that increments on every *successful* use
   and never on a wrong guess locks real clients out on their 5th visit and doesn't slow
   brute-forcing at all. That is a finding worth more than the whole spec. Pay most attention to
   security, money, PHI and clinical-workflow rules.
   **No callers at all?** If nothing in `app/`, `lib/`, `config/` or a rake task references the
   class (and it isn't an entry point such as a job, mailer or controller), it's dead. Stop: mark
   the spec `skipped`, report a `dead_code` finding recommending deletion of the class and its spec,
   and spend the time on live code. A polished spec for dead code is pure cost.
2. **Baseline.** Run the spec. If it is already red, stop and report it; don't "fix" a spec you
   haven't understood. Save the coverage baseline. Note the example count and runtime.
3. **Map.** Tag each example: *keep*, *fat* (table above), *merge* (padding or duplicate), or
   *weak* (right target, loose assertion). Note behaviors from step 1 that no example guards.
4. **Rewrite.** Delete fat, merge padding into one example per scenario, tighten weak assertions,
   add examples for unguarded behaviors. Keep the file's sensible structure and good regression
   examples (anything named for a bug, AC, or incident stays unless it is literally a
   duplicate). Don't rename things for taste.
5. **Green, then coverage.** The spec passes; `lost_lines` is empty.
6. **Probes.** 2–5 probes, all KILLED (or each survivor explained).
7. **Lint** the spec file.
8. **Report** the one-line ledger entry (format in `/spec-sweep`, or plain prose when run
   standalone): lines and examples before→after, coverage before→after, probes killed/total,
   findings.

### When the source is wrong

Never edit `app/`, `lib/` or `config/` code during a test review. If an honest example of the
intended behavior fails because the code is buggy:

- don't commit an example that enshrines the bug, and don't commit a red spec;
- leave that edge unasserted, and write a finding with the file:line, the failing example, and
  why you believe the code is wrong.

Code smells such as dead code (lines no spec can reach), private logic that cries out to be its
own object, or nil-guards for impossible states also go in findings, not in code changes.
