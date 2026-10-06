---
name: policy-test
description: Write or review the RSpec spec for one Pundit policy so every role × action decision, every relationship rule (assigned therapist, clinical supervisor, portal actor), and every policy scope's inclusions AND exclusions are asserted, using the real roles from Role::ROLES and no redundant cross-org or delegation padding. Use when the user asks for policy tests, points at app/policies or spec/policies, asks "who can do X" to be locked down in tests, or wants a policy spec trimmed or checked.
argument-hint: '<app/policies/... or spec/policies/... path> [review|write]'
---

# Policy Test

Write or review the spec for the policy at `$ARGUMENTS`. First read
`.claude/skills/rspec-test-expert/test-quality.md` (the fat catalogue, the proof, concurrency-safe
spec runs, and the review workflow). Policies are the security boundary of a HIPAA app, so here a
missing **denial** is worse than a missing permission.

Map paths: `app/policies/client_portal/foo_policy.rb` ↔ `spec/policies/client_portal/foo_policy_spec.rb`.

## Facts that decide the setup

- Roles are `Role::ROLES`: `admin coordinator therapist manager clinical_supervisor biller
  platform_admin`. There is no `supervisor` and no `owner` role (`InsurancePolicyPolicy#owner?`
  and the factory's `:owner` trait are dead code).
- Roles are added in `after(:create)`. Use `create(:user, :biller)`; `build` has no roles. A bare
  `create(:user)` is a therapist. For "no role" use `create(:user, role_names: [])`.
- `ApplicationPolicy` defines `new?` → `create?` and `edit?` → `update?` and the role predicates.
  Test a delegating action only when **this** policy overrides it.
- Tenant isolation is `acts_as_tenant`'s job (CLAUDE.md, Multi-tenancy). Don't write "admin from
  another org is denied" examples, and don't add org-equality checks to make them pass.
- Many rules hinge on relationships, not roles: `client_therapist` assignment, clinical
  supervision of the treating therapist, the client-portal actor (client or guardian),
  `platform_admin` on the admin subdomain. Read each predicate and find which records make it
  true.

## Shape: a permission grid per action, then the scope

Read every predicate and build the grid **from the code**: for each action, which actors are
allowed and which are denied. Then express it compactly. Pundit predicate matchers keep each cell
to one line:

```ruby
RSpec.describe SuperbillPolicy, type: :policy do
  subject(:policy) { described_class.new(user, superbill) }

  let(:client) { create(:client) }
  let(:superbill) { create(:superbill, client:) }

  context "as admin" do
    let(:user) { create(:user, :admin) }
    it { is_expected.to be_show }
    it { is_expected.to be_destroy }
  end

  context "as the client's assigned therapist" do
    let(:user) { create(:user, :therapist).tap { create(:client_therapist, user: _1, client:) } }
    it { is_expected.to be_show }
    it { is_expected.not_to be_destroy }
  end

  context "as a therapist NOT assigned to the client" do
    let(:user) { create(:user, :therapist) }
    it { is_expected.not_to be_show }
  end
end
```

(There is no `permit_actions` matcher in this repo. Use `be_<action>` / `not_to be_<action>`
predicates as `spec/policies/superbill_policy_spec.rb` does. That file is a good reference.)

For every action, include:

- every role the code **allows**, plus the near-miss actors it must **deny**. The interesting
  denials are the almost-allowed ones: an unassigned therapist, a supervisor of a *different*
  therapist, a biller on a clinical record, a coordinator on a destroy;
- each relationship branch: assigned vs. not, supervising vs. not, the portal actor vs. another
  client;
- record-state branches the policy reads (signed or locked note, soft-deleted record, `draft?`):
  both sides.

When a role is irrelevant to the policy (it never appears in any predicate and falls through to
the default deny), one denial example for that role is enough. Don't build an exhaustive 7-role
matrix of `false`s.

### Scopes

`Pundit.policy_scope!(user, Model)` (or `described_class::Scope.new(user, Model.all).resolve`) for
each role branch in `resolve`. Every scope example must assert **both** what is included **and**
what is excluded. A scope test that only checks `include(record)` passes for `scope.all`, which is
exactly the bug that leaks PHI.

```ruby
it "shows a therapist only their assigned clients", :aggregate_failures do
  mine = create(:client).tap { create(:client_therapist, user:, client: _1) }
  theirs = create(:client)
  expect(Pundit.policy_scope!(user, Client)).to contain_exactly(mine)
  expect(Pundit.policy_scope!(user, Client)).not_to include(theirs) # explicit, for the reader
end
```

## Policy-specific fat

- Cross-organization examples and `ActsAsTenant.without_tenant` org setups (tenancy is enforced
  elsewhere).
- Seven-role matrices where five rows are the same default denial.
- `new?`/`edit?` re-tested when not overridden; `expect(policy.new?).to eq(policy.create?)`.
- Nil-user examples, unless the policy explicitly handles nil (client-portal policies sometimes
  do). Controllers authenticate first.
- `superclass` checks, and roles that don't exist (`:supervisor`, `:owner`).
- `create(:organization)` plus re-setting `current_tenant` in every file; use the default tenant.

## Prove it, then report

Green, then coverage `--baseline` with no `lost_lines`. Probe the riskiest predicates, all KILLED:

- drop the relationship check (`assigned_client?(…)` → `true`);
- widen a role list (`has_any_role?(:admin)` → `has_any_role?(:admin, :therapist)`);
- in `Scope#resolve`, replace the filtered relation with `scope.all`.

Lint with `bin/standardrb <spec>` and report per `test-quality.md` or the caller's format.
