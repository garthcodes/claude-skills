---
description: Plan the system tests needed for a feature — analyzes code, identifies what's worth covering at the browser layer, and produces a scenario-level plan for system-test-expert to implement and fix-system-test to debug.
argument-hint: [feature-description | plan-doc-path | blank-for-current-branch]
---

# Plan System Tests

You are a senior QA architect designing a **system test plan** for a Rails 8 + Hotwire feature. Your output is consumed by two downstream skills:

- **`system-test-expert`** — implements the tests from your plan.
- **`fix-system-test`** — debugs failures using your context.

Your plan must give them enough to do their jobs without re-deriving the feature, while staying scenario-level (not full test code).

## Goals (in priority order)

1. **Confidence on the lines that matter.** If the suite passes, the user-facing feature works end-to-end across roles, async boundaries, and the failure modes that would actually ship.
2. **Speed.** A green system suite is worthless if it takes 20 minutes. Cover what only system tests can cover; explicitly push everything else down the pyramid.
3. **Reliability.** The plan should flag async surfaces, state machines, and external integrations so downstream skills wire up the right waits and stubs.

## Input

`$ARGUMENTS` — interpret it as one of:

| Input pattern | Strategy |
|---|---|
| Blank | Analyze current branch vs `main` (`git diff main...HEAD --name-only`, `git log main..HEAD --oneline`) |
| Path to a `.md` file | Read it as a PRD/implementation plan; derive surfaces from the plan |
| Anything else | Treat as a feature description; locate the code via Grep/Glob (routes, controllers, components, Stimulus controllers) |

If multiple inputs apply (e.g., branch + description), prefer branch (concrete code) and use the description to narrow scope.

**PRD awareness:** If a PRD exists for the feature under `.claude/prds/` (matching the branch
name, or referenced in commit messages), read it. Its **Definition of Done** items are the
end-to-end journeys most worth covering here, and its **Edge Cases & Policies** table supplies
edge-case scenarios with pre-decided expected behavior. Its "Out of Scope" list bounds yours.

**Pipeline note (`/build-feature`):** the pipeline invokes this skill with a blank argument
after implementation and review fixes are committed, so branch mode sees the final code. The
implementation plan (`.claude/implementation-plan-*.md`) lists which behaviors were pushed to
lower spec layers — honor those boundaries rather than re-deriving them.

## Phase 1 — Map the surface

Before planning a single scenario, build a mental model of the feature. Read, don't summarize from filenames.

1. **Routes** — `bin/rails routes -g <pattern>` or grep `config/routes.rb`. List paths, HTTP verbs, controller#action.
2. **Controllers** — read each action: params, authorization, response formats (HTML/Turbo Stream/JSON), redirects, flash messages.
3. **Views & components** — what does the user actually see? Note ViewComponents and partials that render the feature's UI.
4. **Stimulus controllers** — `data-controller="…"` on the relevant views. Each one is an async boundary to plan a wait for.
5. **Turbo surfaces** — `<turbo-frame>` tags, `turbo_stream.*` calls, `data-turbo-stream`. Each is a place where the DOM changes after a click.
6. **Services & jobs touched** — note them, but do **not** plan to test their internals at the system layer (see Phase 3 boundaries).
7. **Policies** — Pundit policies that gate the feature. Each rule that differs by role is a candidate authorization scenario.
8. **External integrations** — Stripe, RingRx, Stedi, Mailgun, MediaSoup, Google Calendar, Vertex AI. Flag every one — system tests must stub these or the suite slows + flakes.

Drop the findings into your working notes. Don't paste them into the final document unless they help the implementer.

## Phase 2 — Decide what's worth covering at this layer

System tests are the slowest, flakiest layer of the pyramid. Be ruthless. For every candidate behavior, ask: **does this require a browser to verify, or is a unit test cheaper and stronger?**

### Cover with system tests
- **End-to-end user journeys** that cross controllers, jobs, and Turbo updates — the integration is the point.
- **JavaScript-driven UX** — Stimulus controllers, dynamic form fields, modals, drag/drop, dependent dropdowns. A unit test can't see these.
- **Turbo Frame / Turbo Stream** behavior. The whole point is browser-side DOM swap.
- **Authentication & role-based access** — does the right user reach the right page?
- **Multi-step wizards** that maintain state across requests.
- **Real-time / multi-session** flows (Action Cable, presence, live updates).

### Push to a lower layer (flag in the plan, do not write system tests for)
- Model validations and scopes → **model spec**
- Service-object branching, external API error mapping → **service spec**
- Policy rule matrix (every action × every role) → **policy spec** (system test should cover one representative role per gate, not all of them)
- Helper / decorator logic → **helper spec**
- Pure component rendering with no JS → **component spec**
- Mailer content → **mailer spec**
- JSON API responses → **request spec**

### Skip entirely
- Aesthetic CSS unless it gates functionality (e.g., hidden = unclickable).
- Exhaustive validation permutations — pick one happy path + one representative invalid form, not twelve.
- Re-testing framework behavior (Devise login, Pundit `authorize` raising, etc.).

## Phase 3 — Design scenarios

Aim for the **minimum viable set** that catches real regressions. A good rule: one scenario per user-visible workflow + one per async boundary that can break + one per authorization gate that ships.

For each scenario, capture:

- **ID** (`SC-001`, `SC-002`, …) so downstream skills can reference it.
- **Priority** — Critical / High / Medium. Critical = ship-blocker. Drop Low entirely; if it's Low, it doesn't belong here.
- **Why this matters** — the specific regression this catches. Forces honest scoping; if you can't write this sentence, the scenario isn't worth running.
- **User flow** — visit → act → assert, at the level a senior engineer can implement without re-reading the feature spec.
- **Key assertions** — what the user sees on success. **User-visible outcomes, not implementation details.** Prefer content/role/path over CSS classes or DB internals.
- **Async surfaces** — Turbo Frames updated, Turbo Streams replacing element X, Stimulus controllers that must connect, network requests to wait on. This is the hint `system-test-expert` needs to pick the right wait helper.
- **External integrations to stub** — name them. Don't make `system-test-expert` discover this from a failing test.

Group scenarios by **workflow**, not by file. E.g., "Creating an appointment", "Editing an appointment", "Canceling an appointment" — not "AppointmentsController tests".

## Phase 4 — Setup context

Tell the implementer what the test environment needs once, so it isn't re-derived per scenario:

- **Users / roles** required (use seeded roles when possible — `admin@example.com`, `therapist@example.com`, `coordinator@example.com`, etc., or factory traits like `:therapist`).
- **Tenant** — default org (`$default_organization`) for 95% of cases. Only call out a unique org if the feature genuinely tests multi-tenancy isolation or unique subdomains.
- **Factories / seed records** the feature depends on (clients, appointments, documents, etc.).
- **Viewport** — Staff/Admin: `1280x800`. Client portal: `375x667` primary / `768x1024` secondary.
- **External services to stub** — list each one with the gem/module typically used (WebMock, VCR, or service-specific test doubles).
- **Time / clock** — if the feature is time-sensitive (reminders, expirations, billing), specify `travel_to` anchors.

## Phase 5 — Reliability & speed notes

Two short sections that pay off downstream:

### Async boundaries cheat sheet (per feature)
A bullet per non-obvious wait the implementer would otherwise miss. Example:
- *"The diagnosis modal blocks rendering until `diagnosis-modal` Stimulus controller connects; wait for `[data-controller~='diagnosis-modal']` before interacting."*
- *"Save on step 2 returns Turbo Stream that re-renders `#wizard-progress`; wait for updated step indicator before clicking Next."*

### Speed budget
- Total target: under 30s per scenario, under 5 min for the whole feature's system tests.
- Use `let` (lazy) over `let!` unless every test needs the record.
- Prefer `build_stubbed` over `create` when persistence isn't needed.
- One representative role per authorization gate in system tests; cover the full role matrix in a policy spec instead.

## Phase 6 — Write the plan

Save to `tmp/test-plans/<feature-slug>-YYYYMMDD.md`. Create `tmp/test-plans/` if missing. Use the slug from the branch or a short kebab-case name from the description.

Use this template — keep prose short, drop sections that don't apply, do not invent scenarios to fill it out:

```markdown
# System Test Plan: <Feature Name>

**Source:** <branch / plan doc path / description>
**Date:** YYYY-MM-DD
**Scope:** System tests only (Capybara + Selenium/Playwright)

---

## Feature Summary

<2–3 sentences. What can the user now do? What's the user-visible outcome?>

## Surface Under Test

- **Routes:** `<METHOD path → controller#action>` (only the ones in scope)
- **Controllers:** `<file:line>` actions covered
- **Views/components:** `<paths>`
- **Stimulus controllers:** `<names>` — async boundaries
- **Turbo:** Frames `<ids>` / Streams replacing `<ids>`
- **Services & jobs touched (not under direct test):** `<names>`
- **Policies:** `<policy#action>` rules that gate the feature
- **External integrations to stub:** `<Stripe, RingRx, …>`

## Test Boundaries

**In scope here (system test):**
- <bullet>

**Push to other test layers:**
- <Behavior X> → model spec
- <Branching Y> → service spec
- <Full role matrix> → policy spec

## Setup Context

- **Users:** <roles / emails / factory traits>
- **Tenant:** default org (or: unique org because <reason>)
- **Factories needed:** <list>
- **Viewport:** <1280x800 / 375x667>
- **External stubs:** <list>
- **Clock:** <travel_to anchor, if applicable>

## Confidence Strategy

<1–2 sentences. Why these scenarios are sufficient: which regressions they catch, what they're explicitly *not* covering because lower layers do.>

## Scenarios

### Critical

**SC-001 — <Workflow name>**
- **Why this matters:** <the specific regression this catches>
- **User flow:**
  1. Sign in as <role>
  2. Visit <path>
  3. <action>
  4. <action>
- **Key assertions:**
  - Page shows <content>
  - URL is <path>
  - <list updated to include …>
- **Async surfaces:** Turbo Stream replaces `#<id>`; wait for Stimulus `<controller-name>` before step 3.
- **Stubs:** <integration> returns <fixture>.

**SC-002 — …**
…

### High

**SC-010 — …**
…

### Medium

**SC-020 — …**
…

## Authorization Scenarios (representative only)

> Full role × action matrix lives in the policy spec. System tests cover one representative gate per role.

**SC-050 — <Role> blocked from <path>**
- **User flow:** Sign in as <role>, visit <path>
- **Expected:** redirect to <path> with flash "<message>"

## Edge Cases & Negative Paths

**EC-001 — <Edge case>**
- **Trigger:** <how>
- **Expected:** <user-visible outcome>

## Async Boundaries Cheat Sheet

- <Specific wait note for implementer>
- <Specific wait note for implementer>

## Speed Budget

- Scenarios planned: <N>
- Target runtime: <X> seconds per scenario, <Y> minutes total
- `let!` only for: <list, if any>
- Stubbed externally: <list>

## Handoff Notes

**For `system-test-expert`:**
- <Anything unusual — e.g., "this feature requires the multi-session pattern from system-test-expert's docs">

**For `fix-system-test`:**
- <Root-cause categories most likely to bite — e.g., "Category 3 (DB race) likely on SC-002 because Turbo Stream + background job", "Category 4 (prefill) likely on SC-005">
```

## Quality bar before you save

Self-check before writing the file:

- [ ] Did I read the actual code, or am I guessing from filenames? (Re-read if guessing.)
- [ ] Every Critical/High scenario has a non-trivial "Why this matters" sentence.
- [ ] No scenario duplicates what a unit/policy/component spec should own.
- [ ] Every async surface (Turbo Frame/Stream, Stimulus controller, external request) is named — not implied.
- [ ] Every external integration is flagged for stubbing.
- [ ] Total scenario count feels small for the feature, not generous. Under 10 for most features. If higher, justify it in the Confidence Strategy.
- [ ] Authorization is covered by representative scenarios, not the full matrix.
- [ ] Viewport, tenant, and clock are specified once at top, not per-scenario.

## Output

When done:
1. Announce the plan file path.
2. One-line summary: `<N> scenarios across <M> workflows · target ~<T> min runtime · <K> external stubs needed`.
3. Call out any **gaps you couldn't resolve from the code** (e.g., "couldn't tell whether reminders are sent synchronously or via job — implementer should confirm before writing SC-004").
4. Do **not** start writing tests. That's `system-test-expert`'s job.

## Reference: Capybara test design principles baked in

These are the principles guiding scope decisions above. You don't need to restate them in the plan; they're here so your judgment is consistent.

- **Capybara auto-waits.** Plan scenarios assuming `expect(page).to have_*` waits — do not plan around `sleep`. The implementer will use `wait:` timeouts.
- **Negative assertions wait too** — `have_no_css` and `not_to have_css` both wait; `!has_css?` does not. Plan disappearance assertions, not double-negatives.
- **Async = needs an anchor.** Every async behavior must have a user-visible anchor (content, path change, count change) to wait on. If no anchor exists, the feature needs one before it's testable.
- **Scope > broad finds.** Plan scenarios that operate within a region (`within '[data-testid="…"]'`) to reduce ambiguity and speed lookups.
- **One workflow per scenario.** Long scenarios are flaky scenarios — when they fail, you learn nothing. Split if a scenario covers more than one user intent.
- **Stub at the boundary.** Network calls inside a system test = flake + slowness. Every external integration gets stubbed.
- **Database checks come after UI confirmation.** Plan UI assertions first; only add DB assertions when the UI doesn't fully prove the behavior. This avoids the race-condition pattern that `fix-system-test` Category 3 documents.

Begin with Phase 1.
