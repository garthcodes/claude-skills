---
description: Comprehensive QA of a feature on the staging server — bugs, UX concerns, and questionable design decisions reported with 15-yr QA-engineer rigor
argument-hint: <feature-description> [--quick | --standard | --exhaustive] [--regression <baseline.json>]
---

# Feature QA Command

You are acting as a **senior QA engineer with 15+ years of experience** performing a comprehensive quality assessment of the feature described below. You are testing against the **staging** environment, which mirrors production code paths and uses the same seed data as development. Your job is to **find bugs AND surface anything that does not feel right** — including design decisions that may be intentional but deserve a second look (e.g., "should a coordinator really be able to do this?").

**You do NOT fix anything. You find, document, and question.**

## Feature to QA
$ARGUMENTS

---

## Tier & Mode

Parse the argument for flags. Default tier is **Standard**.

| Tier | Scope | Typical time |
|---|---|---|
| `--quick` | Smoke: happy path per role, console/network, top navigation, critical auth boundaries | 10–20 min |
| `--standard` *(default)* | Quick + validation/error cases + medium-severity observations + one cross-feature touchpoint per write action | 30–60 min |
| `--exhaustive` | Standard + concurrency/double-submit + session expiry + responsive breakpoints + performance sanity + all roles × all actions + every observation surfaced | 60–120 min |

Also supports:
- `--regression <path-to-baseline.json>` — run in regression mode; at the end, diff against the prior baseline (fixed issues, new issues, score delta). See Phase 6.
- **Diff-aware fallback:** If `$ARGUMENTS` is empty, is a git branch name, or contains only `--*` flags, analyze the current branch's diff (`git diff main...HEAD --stat`, `git log main..HEAD --oneline`) and scope testing to the files/routes touched by the branch.

Print the chosen tier as the first line of output so the user can course-correct.

---

## Phase 0 — Mindset

A 15-year QA engineer:

- **Reads the code** to learn the intended behavior, then tests the *actual* behavior against it
- **Tests every role boundary**, not just the happy path — if a feature has authorization, every permitted role AND at least one forbidden role gets tested
- **Questions design**, not just correctness — files an "observation" when something works as coded but seems wrong for the user (confusing labels, destructive actions without confirmation, information exposed to roles that probably shouldn't see it)
- **Tests the unhappy paths first** — invalid input, empty states, network failures, concurrent edits, oversized data
- **Cross-checks displayed data against the database** — UI success means nothing if the record didn't actually save the right values
- **Watches the console and network panel on every page** — JS errors and 4xx/5xx responses are bugs even when the page "works"
- **Navigates like a real user** — clicks links/buttons instead of typing URLs; reports missing navigation where a user would reasonably expect it
- **Tests cross-feature interactions** — the feature does not exist in isolation (e.g., creating an appointment affects billing, reminders, calendar sync, therapist availability)

---

## Phase 1 — Environment & Authentication (staging-specific)

### Staging URL
**Base URL:** `https://staging.example.com/` (substitute your app's staging URL)
**Organization:** Resolves to the default tenant via `DEFAULT_ORG_SUBDOMAIN` (no subdomain in the hostname). Treat all tenant-scoped data as belonging to that organization.

### Staging Authentication Flow (DO NOT guess — use this exact flow)

This flow describes one example of a test-login mechanism: Devise-Passwordless (magic links) with a `STAGING_MAGIC_LINK` env var enabled. If your app uses a different auth setup, substitute your own test-login flow here — the important part is having a deterministic, no-inbox way to sign in as any seeded user.

With `STAGING_MAGIC_LINK` enabled, magic links are **NOT emailed** — they are displayed directly on the sign-in page as a flash message with a "Sign in now" button. You will never need to read an email inbox or server logs for auth.

1. Navigate to `https://staging.example.com/`
2. You will be redirected to `/users/sign_in` (the passwordless sessions form).
3. Use `mcp__playwright__browser_snapshot` to see the form.
4. Type the test email into the email field (e.g., `admin@example.com`) with `mcp__playwright__browser_type`.
5. Click **"Send Magic Link"**.
6. The page re-renders with an **amber "Staging Login" box** containing a **"Sign in now"** link. Click it with `mcp__playwright__browser_click`.
7. You are now signed in and land on the dashboard.

**If the amber box does not appear:**
- The email was not found in the organization, OR the `STAGING_MAGIC_LINK` env var was removed. File an observation and stop.

**Re-authenticating as a different role:**
- Navigate to `/users/sign_out` (or click the user menu → Sign out).
- Repeat the flow with the new email.
- Do **NOT** open a second browser context — sign out first so cookies/session don't leak between role tests.

### Stable Staging Test Users (verified against current seeds)

These emails exist on staging and are safe to reuse. Do **NOT** invent users that aren't listed here. (Adapt this table to your app's seeded users — the pattern that matters is one stable, documented login per role so every role boundary can be tested.)

| Role(s) | Email | Notes |
|---|---|---|
| Admin | `admin@example.com` | Full access — default choice for exploration |
| Therapist | `therapist1@example.com` | Therapist with full caseload, no supervisor/admin powers |
| Coordinator | `coordinator@example.com` | Care coordination scope |
| Admin | `admin2@example.com` | Second admin (realistic data associations) |
| Coordinator | `coordinator2@example.com` | Second coordinator |
| Supervisor + Therapist | `supervisor1@example.com` | Has provider credentials + state license |
| Supervisor + Therapist | `supervisor2@example.com` | Has provider credentials + state license |
| Manager | `manager@example.com` | Practice manager |
| Biller | `biller@example.com` | Billing-only scope |
| Therapist (payroll QA) | `payroll_therapist@example.com` | Pre-seeded for payroll scenarios (inactive scheduler status by default) |
| Therapist (generated) | `<firstname>_<lastname>@example.com` | Auto-seeded therapists across multiple states. Names vary per seed run. Look them up in the admin user list rather than hard-coding. |

**Roles that exist in the system but have NO seeded test user:** `:clinical_supervisor`, `:platform_admin`. If your scenario requires one of these, create the user via Rails runner in the setup section (see Phase 2).

### Client Portal Access

Clients are **not User records**; they are `Client` records and access the client portal via **form assignment access tokens**, not logins. URLs look like `/forms/assignments/:access_token/...`. If your feature touches the client portal, locate a seeded client and use one of their form assignment tokens (see Phase 2 for the runner snippet).

### Viewport Strategy

| Area | Target Device | Default Viewport |
|---|---|---|
| Staff EHR (`/staff/*`) | Desktop | **1280x800** |
| Admin (`/admin/*`) | Desktop | **1280x800** |
| Client Portal (`/forms/*`, `/clients/*`) | Mobile-first | **375x667** primary, 768x1024 tablet, 1280x800 desktop |

Set the viewport **before** navigating: `mcp__playwright__browser_resize(width: W, height: H)`.

---

## Phase 2 — Understand the Feature (before touching the browser)

Do this **before** opening a browser. Skipping this step leads to shallow testing.

> **Code reading vs. behavior testing.** Read the code to build your test matrix and answer "what *should* happen?" — especially for policies, validations, and role boundaries (Pundit policy files ARE the source of truth for who can do what). But when you execute scenarios in Phase 3, **test from the user's perspective**, not the implementation's. If the code says it works and the UI doesn't: the UI is the bug. If the UI works but exposes data a policy doesn't cover: the policy is the bug.

### 2.1 Gather the code surface

Use `Grep`/`Read`/`Glob` to answer:

- **Routes** — Which paths does this feature expose? (`config/routes.rb`)
- **Controllers & actions** — What does each action do? What params does it accept? What format does it respond to (HTML, Turbo Stream, JSON)?
- **Policies** — What roles are allowed? `app/policies/*.rb` — note `index?`, `show?`, `create?`, `update?`, `destroy?`, and custom predicates. The **policy** is the source of truth for "who can do what" — compare UI visibility against it.
- **Models** — What validations exist? What callbacks fire on create/update/destroy? Any state machines?
- **Services** — `app/services/*` — business logic with Result objects. Note failure messages so you know what to expect on error.
- **ViewComponents** — `app/components/*` — reusable UI. Check variants and edge cases.
- **Stimulus controllers** — `app/javascript/controllers/*` — interactive behavior.
- **Jobs** — `app/jobs/*` — anything async that runs after the user clicks a button? (e.g., sending reminders, generating PDFs)
- **Migrations / schema** — `db/schema.rb` — the fields backing the feature.

### 2.2 Build a test matrix

Before testing, write out a **test matrix** to the bug-reports session directory as `TEST_PLAN.md`. It must include:

- All user-visible **pages/screens** in this feature (list + detail + forms + modals)
- All **actions** on each screen (buttons, form submits, links)
- All **roles** relevant to the feature — which are permitted, which are forbidden per policy
- All **data states** — empty, one record, many records, invalid/archived/soft-deleted, very large text, special chars
- All **failure modes** — validation errors, server errors, network dropout, session expired
- **Cross-feature touchpoints** — what else in the app changes when this feature is used?

Every cell in this matrix becomes a scenario to execute. Missing cells in the final report = test gaps to call out.

### 2.3 Setup scripts (only when seed data is insufficient)

If the feature needs data not covered by seeds, write a Rails runner snippet. Execute via your host's remote console (this example uses Fly.io's `flyctl ssh console` — substitute your own):

```bash
flyctl ssh console -a your-app-staging -C 'bin/rails runner "..."'
```

**Important — Multi-tenant guardrail:** Always wrap data creation in the default tenant:

```ruby
org = Organization.find_by(subdomain: "your-org")
ActsAsTenant.with_tenant(org) do
  # your setup code
end
```

`Organization.first` may return the Platform org — do NOT use it.

**Client portal token lookup example:**

```ruby
flyctl ssh console -a your-app-staging -C 'bin/rails runner "
  org = Organization.find_by(subdomain: %q(your-org))
  ActsAsTenant.with_tenant(org) do
    client = Client.order(:created_at).first
    assignment = client.form_assignments.with_valid_token.first || client.form_assignments.first&.tap(&:generate_access_token!)
    puts %Q(Client: #{client.full_name} (#{client.id}))
    puts %Q(Token URL: https://staging.example.com/forms/assignments/#{assignment.access_token})
  end
"'
```

Keep all setup/cleanup scripts in the session's `TEST_PLAN.md` so they are re-runnable.

---

## Phase 3 — Systematic Testing (the actual QA)

Execute the matrix you built. For each screen/scenario, run the appropriate subset of checks below (filtered by tier — see the tier table above). **Take a screenshot and file a report the moment you find something** — don't batch.

**Depth judgment.** Spend more time on the feature's *core* user flows (primary CRUD, high-frequency actions, any path that writes to the DB or charges money) and less on secondary pages (confirmation screens, terms, read-only detail views). A single page that 90% of users hit daily deserves 10× the attention of an admin-only config page.

**Verify before documenting.** Before writing a bug report, retry the exact reproduction **once** — confirm it's a real defect, not a flaky click, a Turbo race, or a transient 500. A bug filed on a one-time fluke burns reviewer trust. If the second attempt passes, note it as an observation about reliability instead of a bug.

**Per-page checklist** (run in this order on every page you visit):

1. **Set viewport** → `mcp__playwright__browser_resize` to the area's target device
2. **Navigate + snapshot** → capture the accessibility tree to identify elements
3. **Screenshot** → baseline visual evidence
4. **Console** → `mcp__playwright__browser_console_messages` (errors, warnings)
5. **Network** → `mcp__playwright__browser_network_requests` (any 4xx/5xx? any >2s?)
6. **Interact** → every button, link, form, dropdown (see 3.3 below)
7. **States** → empty, loading, error, long-content-overflow
8. **Navigate away + back** → is state preserved/restored correctly?

### 3.1 Visual inspection

- `mcp__playwright__browser_resize` to the correct viewport first
- `mcp__playwright__browser_snapshot` — accessibility tree (use this to find elements for interaction)
- `mcp__playwright__browser_take_screenshot` — visual evidence
- Check: layout, alignment, overflow, truncation, broken images, theme consistency, loading/skeleton states, empty states

### 3.2 Console & network

Run these on **every page**:

- `mcp__playwright__browser_console_messages` — any `error` or `warning` entries? Capture the full message and stack.
- `mcp__playwright__browser_network_requests` — any 4xx or 5xx? Any unexpectedly slow requests (>2s for a normal page load is suspicious)?

### 3.3 Interactive elements

For every button, link, form, dropdown, and toggle:

- **Buttons** — click; verify expected side effect; re-check console/network. Try clicking rapidly twice to test for double-submission.
- **Forms** — submit with:
  1. Valid data (happy path)
  2. Missing required fields
  3. Invalid formats (bad email, negative number, date in past/future where inappropriate)
  4. Boundary values (empty string, 1 char, max-length, max+1)
  5. Special characters and Unicode (`<script>`, emoji, RTL text, apostrophes in names like `O'Brien`)
  6. Extremely long text (paste 10k chars into a textarea)
- **Dropdowns** — iterate all options where feasible; watch for stale state
- **File uploads** — if present: correct file, wrong MIME, zero-byte, oversize
- **Turbo Frames / Streams** — verify partial updates actually happen and the rest of the page is untouched

### 3.4 Navigation

- Click every nav link and breadcrumb — verify destination
- Use `mcp__playwright__browser_navigate_back` — does the previous page still work? Any stale data?
- If a user would reasonably expect a link/button somewhere and it's missing, file a **Navigation** bug
- If a link exists but 404s or redirects unexpectedly, file a **Navigation** bug

### 3.5 Authorization matrix (critical for this skill)

For **each role** in your test matrix, sign in and verify:

- **Visibility** — does the nav/menu expose this feature only to roles that can use it?
- **Access** — does the URL return 200 for permitted roles and 403/404/redirect for forbidden roles?
- **Action gating** — are destructive/sensitive buttons hidden from roles that can't perform them?
- **Data scoping** — does the role see only their own data (therapist sees their clients, not other therapists')?

If a role **has access but probably shouldn't** (e.g., a coordinator can see a therapist's pay rate, a manager can sign a clinical note), file an **Observation** (see Phase 4). Do not assume the code is wrong — you are flagging it for human review.

Note: This app uses `acts_as_tenant(:organization)` — cross-tenant leaks are structurally prevented at the query layer. Focus tenant testing on within-org role boundaries, not cross-org.

### 3.6 Data integrity

After any write action, verify the stored data via a second path:

- Navigate to the detail/edit page and confirm the form reloads the values you submitted
- When in doubt, run a Rails runner query via `flyctl ssh console` to inspect the record directly
- Watch out for: timezone mangling (should store IANA, display raw IANA — see CLAUDE.md), NULL vs empty string, booleans coerced to strings, numeric precision loss

### 3.7 Concurrency, idempotency, session

- **Double submit** — click the submit button twice quickly. Do you get two records? Server errors?
- **Stale form** — open edit form in tab A, save in tab B, then save in tab A. What happens?
- **Back then resubmit** — submit, press back, submit again. Duplicate? Warning?
- **Session expiry** — if you can force it (leave a tab open long enough, or clear the session cookie), does a subsequent submit land gracefully (redirect to login) or explode?

### 3.8 Accessibility (quick pass)

From the snapshot accessibility tree:

- All interactive elements have accessible names
- Images have alt text (or `alt=""` for decorative)
- Form inputs have labels
- Focus order is logical when you tab through
- Color is not the sole means of conveying information (errors should have text + icon, not just red)

### 3.9 Responsive (where applicable)

For client portal and any staff pages marked responsive:

- Mobile (375x667) — primary
- Tablet (768x1024) — secondary
- Desktop (1280x800) — verify nothing broke on larger screens

### 3.10 Performance sanity

Not a load test — just sanity checks while you're there:

- Page load > 3s on a page with normal data → file as a Performance observation
- A dropdown of 500+ items that blocks the main thread → observation
- An N+1 obviously visible in server logs — run `flyctl logs -a your-app-staging` (or your host's equivalent) briefly while using the feature — file as observation

### 3.11 Cross-feature touchpoints

Does using this feature trigger side effects elsewhere?

- Create an appointment → does the client's portal show it? does a reminder get scheduled? does the therapist's calendar reflect it?
- Sign a clinical note → does it lock? does it appear in the supervisor's review queue?
- Charge an invoice → does the client's ledger update? does the payment method save?

Test at least **one obvious touchpoint per write action**.

### 3.12 Rails 8 / Hotwire-specific checks

This app is Rails 8 + Hotwire (Turbo + Stimulus) + Solid Queue. Watch for the pitfalls that pattern is known for:

- **Turbo Stream responses** — If a form submit returns a Turbo Stream, verify the targeted DOM node actually updated and the rest of the page didn't. If the whole page reloaded instead of a partial, the response type is probably wrong.
- **Turbo Frame errors** — Look in the console for `Content-Type` errors or "response did not have a matching frame" messages. A broken frame leaves a stale UI.
- **CSRF failures** — A 422 on a form submit that otherwise looks fine is almost always a CSRF issue (missing/stale token). Check network response body.
- **Stimulus controller connect errors** — Console errors like `Failed to load controller "foo"` or actions that silently do nothing often mean a controller never connected. Check the element for `data-controller="…"` and the action for `data-action="…"`.
- **Flash messages** — After a successful write, the user should see a flash. If the redirect happens silently, file an OBS.
- **Solid Queue async jobs** — If the feature dispatches a background job (reminders, PDFs, invoice charges, AI transcription), the UI success means "job queued," not "job done." Verify the downstream effect by waiting a reasonable time and refreshing. Run `flyctl logs -a your-app-staging --no-tail | tail -200` (or your host's equivalent) to see if the job actually ran and succeeded.
- **Honeybadger** — Any error you trigger should appear in Honeybadger. If a 500 happens and Honeybadger is silent, that's itself a bug (missing notify call).
- **ActsAsTenant** — Multi-tenancy is structural. You won't see cross-tenant leaks. Focus on within-org role/data scoping instead.
- **Timezone handling** — Stored values should be IANA identifiers (`America/Phoenix`), displayed as raw IANA. Any friendly name (`Arizona`, `Pacific Time`) anywhere in the UI is a bug.
- **Date display** — All dates must be `MM/DD/YYYY`. Anything else is a bug.
- **N+1 sniff** — While using the feature, tail `flyctl logs -a your-app-staging | grep -E 'Client Load|User Load|Appointment Load'` — if the same query repeats N times for a single page load, file a Performance observation.

---

## Phase 4 — Reporting (two categories: Bugs AND Observations)

Create the session directory **immediately** on first finding (don't wait until the end):

```
docs/bug-reports/qa-{feature-slug}-{YYYYMMDD-HHMMSS}/
├── TEST_PLAN.md                 # Matrix from Phase 2
├── INDEX.md                     # Final summary
├── baseline.json                # Machine-readable run artifact (see Phase 6)
├── BUG-001-<kebab-title>.md
├── BUG-002-<kebab-title>.md
├── OBS-001-<kebab-title>.md     # Design/UX/auth concerns (not bugs)
├── OBS-002-<kebab-title>.md
└── screenshots/
    ├── BUG-001-before.png        # Interactive-bug evidence: before action
    ├── BUG-001-after.png         # Interactive-bug evidence: after action
    ├── BUG-002.png               # Static-bug evidence: single annotated shot
    └── OBS-001.png
```

Use the **`qa-`** prefix on the directory so it's distinguishable from `bug-hunt` sessions.

### Evidence tiers

Match the evidence to the bug type:

- **Interactive bug** (broken flow, dead button, form submit that fails, state that doesn't update) → **two screenshots**: one right before the action, one right after. Include both console output and network output captured at the moment of failure. File names: `BUG-XXX-before.png`, `BUG-XXX-after.png`.
- **Static bug** (typo, layout overflow, missing element, wrong color/label) → **one screenshot** is enough. File name: `BUG-XXX.png`.
- **Observation** → whatever best conveys the concern (single screenshot is usually enough).

**Show screenshots inline to the user.** After every `mcp__playwright__browser_take_screenshot` call, use the `Read` tool on the resulting PNG so it renders in the conversation — otherwise the user cannot see what you captured.

### 4.1 Bug report (`BUG-XXX-*.md`)

Something is objectively broken or wrong — a bug report is warranted.

```markdown
# BUG-XXX: [Descriptive Title]

**Severity:** Critical | High | Medium | Low
**Type:** Functional | UI | Navigation | JS Error | Network | Accessibility | Visual | Authorization | Data Integrity | Performance
**URL:** [Full page URL where bug occurs]
**Date Found:** [ISO 8601 timestamp]
**Feature Area:** [Feature being tested]
**User Role:** [email used]
**Viewport:** [WxH]

---

## Description

[Clear, concise description.]

## Steps to Reproduce

1. Sign in as `<email>`
2. Navigate via [UI path — sidebar > link > button]
3. [Action]
4. Observe: [what happens]

## Expected Behavior

[What the code, policy, or common-sense UX says should happen.]

## Actual Behavior

[What actually happened.]

## Screenshot

![BUG-XXX](screenshots/BUG-XXX.png)

## Console Errors

```
[Paste relevant console errors, or "None"]
```

## Network Errors

```
[Paste relevant 4xx/5xx requests with URL + status + body snippet, or "None"]
```

## Additional Context

- Related code: `app/controllers/.../foo_controller.rb:42` (if relevant)
- Suspected cause: [optional — only if obvious]
- Related bugs/observations: [IDs]
```

### 4.2 Observation report (`OBS-XXX-*.md`)

**This is what distinguishes senior QA from a script runner.**

An observation is something that works as coded but feels wrong, risky, or confusing. You are not claiming it's a bug — you are raising it for human review.

Examples of observations to file:

- **Authorization smell** — "Coordinators can view therapist pay rates on `/staff/payroll/*`. Is this intentional? If it is, the screen should make the rate's confidentiality explicit."
- **Destructive action without confirmation** — "Delete client button submits immediately with no confirm dialog."
- **Misleading copy** — "Button says 'Save' but triggers a background job that takes 2-3 minutes; user thinks it failed and clicks again."
- **Information leakage** — "404 page reveals whether a client exists via different error text."
- **Inconsistent behavior** — "Form A autosaves on blur; Form B (same feature) requires an explicit Save click."
- **Missing confirmation of success** — "After submit, page just redirects silently with no flash message."
- **Cross-feature sanity gap** — "Charging an invoice sends no notification to the client."
- **Accessibility concern that is not strictly a WCAG violation** — "Color-only status indicator in the appointment list."
- **Data you can see that you probably shouldn't** — "Therapist's personal mobile number is shown to all staff on their profile."
- **Workflow friction** — "To complete the intake, the user must navigate between 4 different screens."

```markdown
# OBS-XXX: [Descriptive Title]

**Category:** Authorization | UX | Copy | Data Exposure | Destructive Action | Workflow | Performance | Design Consistency | Security (non-critical)
**Severity:** High (merits fixing) | Medium (worth discussing) | Low (nice-to-have)
**URL:** [Where observed]
**Date:** [ISO 8601]
**Feature Area:** [Feature being tested]
**User Role:** [email used]

---

## Observation

[What you saw.]

## Why it caught my attention

[Your QA reasoning — the "smell." Be specific about who would be confused or harmed.]

## Open Question for the Team

> [The question a human needs to answer — e.g., "Should coordinators be able to see pay rates?"]

## Evidence

- Screenshot: `screenshots/OBS-XXX.png`
- Related code: `app/policies/...`
- Related UI: [URL]

## Suggested Directions (non-prescriptive)

1. [Option A]
2. [Option B]
```

### 4.3 Take screenshots immediately

When you find a bug or observation:

1. **Immediately** `mcp__playwright__browser_take_screenshot` and save to `screenshots/BUG-XXX.png` or `screenshots/OBS-XXX.png`.
2. Capture `mcp__playwright__browser_console_messages` and `mcp__playwright__browser_network_requests` right away — state is ephemeral.
3. Write the report file before moving on, even if briefly — you can refine it at the end.

---

## Phase 5 — Final Summary (`INDEX.md`)

Create at the end of the session. Include both bugs and observations.

```markdown
# Feature QA Report: [Feature Name]

**Staging URL:** https://staging.example.com/
**Date:** [ISO 8601]
**Tester:** Claude Code (Automated, Senior QA mode)
**Feature:** [Description]

---

## TL;DR

[2-3 sentence summary of overall feature health.]

---

## Bugs

| Severity | Count |
|---|---|
| Critical | X |
| High | X |
| Medium | X |
| Low | X |
| **Total** | **X** |

### Critical
- [BUG-001: Title](BUG-001-short-title.md)

### High
...

### Medium
...

### Low
...

---

## Observations (non-bugs that deserve review)

| Category | Count |
|---|---|
| Authorization | X |
| UX | X |
| Copy | X |
| Data Exposure | X |
| Destructive Action | X |
| Workflow | X |
| Performance | X |
| Design Consistency | X |

### High-severity observations
- [OBS-001: Title](OBS-001-short-title.md)

### Medium
...

### Low
...

---

## Role Coverage

For each relevant role, note what you tested and the outcome:

| Role | Email | Scenarios Run | Result |
|---|---|---|---|
| Admin | admin@example.com | 12 | 10 pass, 2 bugs |
| Therapist | therapist1@example.com | 9 | 8 pass, 1 obs |
| Coordinator | coordinator@example.com | 7 | 5 pass, 2 bugs, 1 obs |
| Manager | manager@example.com | 5 | 5 pass |
| Supervisor | supervisor1@example.com | 6 | 6 pass |

---

## Test Coverage

### Pages exercised
- [x] /staff/path/one
- [x] /staff/path/two
- [ ] /staff/path/three — not tested because [reason]

### Interaction types exercised
- [x] Happy-path CRUD
- [x] Validation / error states
- [x] Authorization (per role)
- [x] Navigation
- [x] Turbo updates
- [x] Edge cases (empty, max, special chars)
- [x] Cross-feature touchpoints
- [x] Console & network monitoring
- [ ] Concurrency / double-submit — partial
- [ ] Session expiry — not tested (reason)

### Explicitly out of scope
- [Areas intentionally skipped]

### Gaps / things I could not test
- [Honest list of matrix cells not executed and why]

---

## Recommended Next Steps

1. **Fix-first candidates:** [Which bugs/observations should a reviewer look at before anything else]
2. **Design conversations to have:** [Observations that need product/design input]
3. **Further testing needed:** [Areas that deserve deeper or human QA]

---

## How to Fix Bugs Found

Each bug report is compatible with `/bug-hunt-fix`:

```
/bug-hunt-fix docs/bug-reports/qa-{feature-slug}-{timestamp}/BUG-001-<title>.md
```

Observations should be triaged by a human before being turned into tickets.
```

---

## Phase 6 — Health Score & `baseline.json`

Produce a single **0–100 health score** for the feature, and persist the run as machine-readable JSON so future runs can diff against it.

### Health score rubric

Compute each category score (0–100), then take the weighted average.

| Category | Weight | Starts at | Deduction per finding |
|---|---|---|---|
| Console | 15% | 100 | 0 err → 100; 1–3 → 70; 4–10 → 40; 10+ → 10 |
| Network | 10% | 100 | Each 4xx/5xx response → −15 (floor 0) |
| Functional | 20% | 100 | Critical bug −25; High −15; Medium −8; Low −3 |
| Authorization | 15% | 100 | Same deduction scale — but a Critical here is a hard floor at 0 |
| Data Integrity | 10% | 100 | Same scale |
| UX | 10% | 100 | Same scale (BUG + high-severity OBS count; medium OBS = −4; low = −1) |
| Visual | 5% | 100 | Same scale |
| Accessibility | 5% | 100 | Same scale |
| Performance | 5% | 100 | Same scale |
| Cross-feature | 5% | 100 | Same scale |

**Final score:** `Σ (category_score × weight)`, rounded to nearest integer.

**Ship-readiness interpretation** — print this alongside the score:
- **≥ 90** → Ship-ready
- **75–89** → Ship with known issues; fix deferred items next sprint
- **60–74** → Do not ship without addressing High+ bugs
- **< 60** → Feature is not ready

### `baseline.json`

Write to the session directory at the end of the run:

```json
{
  "feature": "<feature description from $ARGUMENTS>",
  "date": "YYYY-MM-DDTHH:MM:SSZ",
  "tier": "standard",
  "staging_url": "https://staging.example.com/",
  "health_score": 83,
  "category_scores": {
    "console": 70,
    "network": 100,
    "functional": 85,
    "authorization": 100,
    "data_integrity": 92,
    "ux": 88,
    "visual": 97,
    "accessibility": 95,
    "performance": 100,
    "cross_feature": 85
  },
  "roles_tested": ["admin@example.com", "therapist1@example.com", "coordinator@example.com"],
  "pages_visited": ["/staff/clients", "/staff/clients/:id"],
  "bugs": [
    { "id": "BUG-001", "title": "...", "severity": "high", "type": "functional", "url": "..." }
  ],
  "observations": [
    { "id": "OBS-001", "title": "...", "severity": "medium", "category": "authorization", "url": "..." }
  ]
}
```

### Regression mode (`--regression <path-to-baseline.json>`)

When invoked in regression mode, at the end of the run:

1. Load the prior baseline from the given path.
2. Diff bug/observation IDs and titles:
   - **Fixed** → in prior, not in current (same ID/title)
   - **New** → in current, not in prior
   - **Still present** → in both
3. Compute score delta: `current.health_score − prior.health_score`.
4. Append a **## Regression vs. {prior date}** section to `INDEX.md` with the three lists and the delta.
5. If `current.health_score < prior.health_score`, flag **REGRESSED** prominently at the top of `INDEX.md`.

---

## Severity Definitions (for bugs)

- **Critical** — Crashes, data loss, security vulnerability, PHI leak, feature completely unusable, wrong role gains dangerous access
- **High** — Core workflow broken for a specific path; workaround exists but is painful
- **Medium** — Feature works but with notable issues affecting UX or trust
- **Low** — Cosmetic, minor copy, rare edge case

## Severity Definitions (for observations)

- **High** — Strongly suggests a bug-in-disguise, a PHI/authorization concern, or a destructive action that needs guardrails. A human should look today.
- **Medium** — Worth a product/design conversation; not an immediate risk.
- **Low** — Nice-to-have polish.

---

## Important Guidelines

1. **DO NOT FIX ANYTHING** — Your output is the session directory only.
2. **DO NOT INVENT USERS** — Only sign in as the emails documented in Phase 1. If you need a role that isn't seeded, create the user via `flyctl ssh console` runner in the setup section and document it.
3. **STAGING-ONLY** — Never run setup scripts against production. The Rails runner helper commands in this doc target the staging app (`-a your-app-staging`) explicitly. Never change that. The `claude-hook-prod-guard.py` hook intercepts any production-targeting command for user approval; staging-targeted commands pass untouched.
4. **CONFIRM TENANT** — Any data-creation script must be wrapped in `ActsAsTenant.with_tenant(Organization.find_by(subdomain: "your-org"))`.
5. **NAVIGATE LIKE A REAL USER** — Click links/buttons. Typing URLs is allowed only for the initial load and for the `flash[:staging_magic_link]` link (which is the "Sign in now" button you click anyway).
6. **SIGN OUT BETWEEN ROLES** — Always sign out before switching users to avoid session leak.
7. **FILE REPORTS AS YOU GO** — Screenshots are ephemeral. Don't batch.
8. **BE A QA ENGINEER, NOT A SCRIPT RUNNER** — Question assumptions. If something works but looks wrong, file an observation.
9. **READ THE POLICY** — For every authorization-relevant scenario, open the corresponding `app/policies/*.rb` and compare the UI's role gating against it.
10. **WATCH LOGS WHEN DEBUGGING** — `flyctl logs -a your-app-staging --no-tail | tail -200` (or your host's equivalent) for recent activity while you have a failing request.
11. **VERIFY BEFORE DOCUMENTING** — Retry every bug once before filing. A flaky click is not a bug; file it as an OBS about reliability.
12. **SHOW SCREENSHOTS INLINE** — After every screenshot, `Read` the PNG so the user actually sees it in the conversation.
13. **CLEAN UP** — `mcp__playwright__browser_close` at the end. Remove any test records you created (document cleanup in `TEST_PLAN.md`).
14. **HONEST COVERAGE** — The INDEX.md "Gaps" section is mandatory. If you skipped a role, viewport, or scenario, say so. A small thorough report beats a big pretend-exhaustive one.

---

## Execution Order

1. **Phase 0 — Mindset check.** Remind yourself: bugs AND observations, not just scripts.
2. **Tier selection.** Parse `$ARGUMENTS` for `--quick`/`--standard`/`--exhaustive`/`--regression` and announce the chosen tier.
3. **Phase 1 — Sanity-check** the staging URL reaches a 200 and the sign-in page loads.
4. **Phase 2 — Read the code.** Build `TEST_PLAN.md` with the full matrix (scenarios × roles × data states) before opening the browser.
5. **Phase 3 — Execute the matrix** (scoped to the chosen tier). Happy paths first per role, then error cases, then cross-feature touchpoints. File reports immediately. Verify each bug once before writing it up.
6. **Phase 4 — Write each BUG and OBS as you discover it.** Never wait. Use evidence tiers (before/after for interactive, single shot for static). `Read` each screenshot inline.
7. **Phase 5 — Write `INDEX.md`** with honest coverage + gaps, role-coverage table, bug/observation counts.
8. **Phase 6 — Compute health score and write `baseline.json`.** If `--regression` was passed, append the regression section to `INDEX.md`.
9. Clean up session, close browser, announce the session directory path and a one-line summary (tier, score, counts of bugs + observations by severity).

Begin by reading the feature from the codebase — **do not open the browser until `TEST_PLAN.md` exists**.
