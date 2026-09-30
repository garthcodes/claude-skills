---
description: Senior-QA-engineer orchestrator. Audits the entire application across every relevant role and feature using Playwright, producing a resumable bug index. Composes /create-qa-document (extended) and /execute-qa. Pure QA — does not fix.
argument-hint: [<path-to-existing-full-app-qa-dir-to-resume>]
---

# Full App QA Command

You are tasked with running deep, role-aware QA against **every top-level section** of `docs/APP_FEATURES.md`, aggregated into a single, resumable session. You orchestrate `/create-qa-document` (extended for full-feature mode) and `/execute-qa` per feature/role and produce a master index that `/fix-bug-index` can later consume. **You do NOT fix bugs.**

This is a healthcare app. Every bug matters. Behave like a senior QA engineer who has worked in regulated SaaS for fifteen years — find functional, UX, visual, accessibility, data-integrity, permission/security, performance, and HIPAA-compliance bugs across every interactive element and every user journey.

## Argument
$ARGUMENTS

- If `$ARGUMENTS` is empty: start a new sweep — create a fresh session directory.
- If `$ARGUMENTS` is a path to an existing `docs/bug-reports/full-app-qa-*` directory: resume that sweep — pick up where it stopped.

---

## CRITICAL: Continuous Execution (Non-Negotiable)

**This skill must run to completion in a single user invocation. The most common failure mode of orchestrator skills (including `/bug-hunt-all`) is stopping after one or two features and waiting for the user to say "continue." DO NOT DO THIS.**

After each child skill invocation returns, the next thing you do is invoke the next pending child — in the same response — until every non-skipped row in `MASTER_INDEX.md` shows `done` or `error`.

### Banned phrasings (do not write any of these until the run is complete)

- "ready to continue?"
- "let me know if you want me to proceed"
- "I'll start the next feature next"
- "should I continue?"
- "let me know if you'd like..."
- "I'll pause here so you can review"
- "the next step would be to..."

If you feel the urge to write a sentence like any of these, instead **invoke the next child skill**.

### Legitimate stop conditions (exhaustive — no others are valid)

1. Every non-skipped row in `MASTER_INDEX.md` shows `done` or `error` → write the rollup, close the browser, print the final recap, stop.
2. The same hard environmental block occurs on three consecutive features and cannot be auto-recovered (e.g., dev server unreachable after retries on three different feature attempts) → write what's needed clearly, stop.

No other stop conditions are valid. "Wait for the user" is not a stop condition.

### Resume-from-compaction

If you reach this skill mid-run after a context compaction (you do not remember writing the MASTER_INDEX but the disk says you did):
- Scan `docs/bug-reports/full-app-qa-*/` and pick the most recently modified session dir.
- Read its `MASTER_INDEX.md`.
- Rebuild your TaskList from any rows with status `pending` or `error`.
- Resume by invoking the next child for the first pending row.
- **Do not ask the user "should I resume?"** — you have enough info to act.

### Retry policy for sub-agent failures

On any transient sub-agent failure (timeout, MCP error, browser crash, child skill error):
1. Retry once immediately.
2. Retry again after a 30-second wait.
3. If both retries fail, mark the row `error` in `MASTER_INDEX.md` with a one-line reason, log a `META-BUG-NNN` entry in the feature's `INDEX.md`, and move to the next feature.
4. **Never report run failure to the user** unless an environmental block prevents progress on three consecutive features.

---

## Phase 0: Pre-flight Auto-Fix

Run these checks in order. Auto-fix what is safe. The user invoked this skill knowing it would QA the whole app, so destructive setup on the local DB is consented.

### Step 0.1: Base URL and dev server

This checkout may be the main repo (default port) or a `/build-feature` worktree with its own
server and database (`PORT=` in `.env`). Resolve the URL first — everything downstream,
including the sub-agent prompts, uses `$BASE_URL`.

```bash
BASE_URL="$(bin/dev-url)"   # $PORT > PORT= in .env > 3000
curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL" 2>/dev/null || echo "not running"
```

If not 200: start `bin/dev` in the background (it reads `PORT=` from `.env`) and wait until curl returns 200 (10–15s typical). If after 60s the server is still unreachable, stop with a clear message: "Dev server failed to start. Run `bin/dev` in another terminal, then re-invoke."

### Step 0.2: `STAGING_MAGIC_LINK` is `true`

Read `config/environments/development.rb` and confirm line ≈49 contains `ENV["STAGING_MAGIC_LINK"] ||= "true"` and is not commented out. If missing or commented:
- Report exact line to add or uncomment.
- Stop. You cannot proceed — staff login depends on the dev-shortcut button.

### Step 0.3: Seeded users for in-scope roles

Read `db/seeds/users.rb` and `db/seeds/form_assignments_with_receipts.rb`. Build the role → email mapping:

| Role | Expected seeded email |
|------|----------------------|
| admin | `admin@example.com` |
| therapist | `therapist@example.com` |
| coordinator | `coordinator@example.com` |
| supervisor | `supervisor1@example.com` |
| clinical_supervisor | `supervisor1@example.com` (granted via `db/seeds/supervision_relationships.rb`) |
| client (portal) | `testclient@example.com` |

Verify each exists in the live DB:

```bash
bin/rails runner '
roles = { admin: "admin@example.com", therapist: "therapist@example.com",
          coordinator: "coordinator@example.com", supervisor: "supervisor1@example.com",
          clinical_supervisor: "supervisor1@example.com" }
roles.each do |role, email|
  u = User.find_by(email: email)
  puts "#{role}: #{u ? (u.has_role?(role) ? "OK" : "exists but missing role #{role}") : "MISSING"}"
end
puts "client: #{Client.joins(:emails).find_by(emails: {email: "testclient@example.com"}) ? "OK" : "MISSING"}"
puts "portal_token: #{FormAssignment.with_valid_token.first&.access_token ? "OK" : "MISSING"}"
'
```

**If any role is MISSING**, run `bin/rails db:seed:validate` to see what is absent. On an empty database run `bin/rails db:seed` silently (no prompt; `db:seed` skips a database that is already seeded) and re-check. If still missing, stop with a clear gap report.

### Step 0.4: Stripe test mode (warn-only)

Check `ENV["STRIPE_SECRET_KEY"]` is present (anywhere `bin/rails runner 'puts ENV["STRIPE_SECRET_KEY"].present?'` returns true). If absent and any billing feature is in scope, **warn but continue** — billing features will likely produce `error` rows and that is acceptable for v1.

### Step 0.5: Print pre-flight summary

One-paragraph summary: "Pre-flight passed. Sweep beginning across every top-level section of docs/APP_FEATURES.md × 6 in-scope roles (smart-hybrid: only relevant roles per feature)." Do not ask the user to confirm. Proceed to Phase 1.

---

## Phase 1: Parse `docs/APP_FEATURES.md` and Cross-Check Routes

### Step 1.1: Read the feature catalog

Read `docs/APP_FEATURES.md` (repo-relative). Same structure as `/bug-hunt-all` parses:

```
## 1. Client Management
### 1.1 Subsection
- Feature bullet
---
## 2. Appointments & Scheduling
...
```

Build an ordered list of top-level sections. For each `## N. Title` heading:
- `number` — integer N (zero-padded to `NN` for filenames)
- `title` — full heading text after `N. `
- `slug` — kebab-case from title (strip parens/ampersands/slashes; collapse whitespace; lowercase)
- `body` — everything between this heading and the next `## ` heading (verbatim — passed to `/create-qa-document`)

Use `grep -nE '^## [0-9]+\.' docs/APP_FEATURES.md` to locate boundaries. Parse every top-level section — do not hardcode a section count.

### Step 1.2: Cross-check `config/routes.rb` for drift

Scan `config/routes.rb` for top-level resource declarations. For each `resources :foo` or `namespace :foo` not represented in any `APP_FEATURES.md` section, record as **undocumented drift** and append a row to the in-memory feature list with `title: "Undocumented: <resource>"`, `slug: "undocumented-<resource>"`. These drift rows are included in the sweep but flagged in `MASTER_INDEX.md` under a `## Drift Findings` section.

Heuristic for "represented in a section": grep each section's body for the resource name (singular or plural). If no match, it's drift.

---

## Phase 2: Session Setup

### Step 2.1: Choose the session directory

**New sweep (`$ARGUMENTS` empty):**
1. Generate timestamp `YYYYMMDD-HHMMSS` from local time.
2. Session dir: `docs/bug-reports/full-app-qa-{YYYYMMDD-HHMMSS}/`
3. Create it.

**Resume (`$ARGUMENTS` is a path):**
1. Verify the path exists and matches `docs/bug-reports/full-app-qa-*`. If not, abort with a clear error.
2. Use it as the session dir. Do NOT regenerate `MASTER_INDEX.md` from scratch — preserve user edits (especially `[SKIP]` markers).

### Step 2.2: Dedupe scan against prior runs

List existing `docs/bug-reports/full-app-qa-*/` directories (excluding the current one). For each, read every `<NN>-<slug>/INDEX.md` and extract bug bullets matching the pattern `- [BUG-NNN: ...](...)`. Build an in-memory lookup keyed by `(feature_section, role, normalized_title, url)` → `{prior_session, prior_path}`.

This lookup is consulted later in Phase 5 when about to write a new bug. Matching new bugs are still written (the user should see what was re-found) but are tagged `[DUPLICATE]` in the bullet and reference the original.

If no prior sessions exist, the lookup is empty and you proceed normally. Record the scanned prior sessions in the `## Dedupe` section of `MASTER_INDEX.md`.

### Step 2.3: Write the skeleton `MASTER_INDEX.md` (new sweep only)

Path: `<session-dir>/MASTER_INDEX.md`. Template:

```markdown
# Full App QA Sweep

**Date started:** YYYY-MM-DD HH:MM
**Source:** docs/APP_FEATURES.md (+ routes.rb drift cross-check)
**Base URL:** [the $BASE_URL resolved in Step 0.1]
**In-scope roles:** admin, therapist, supervisor, clinical_supervisor, coordinator, client

This sweep generates role-aware QA plans for each top-level section of `docs/APP_FEATURES.md`, executes them, and aggregates findings. Each section gets its own subdirectory with `INDEX.md` and `BUG-*.md` files. Open any section's `INDEX.md` to feed it to `/fix-bug-index`.

To skip a section, add `[SKIP]` to its line below before (re-)running this skill. Strikethrough (`~~...~~`) also works.

## Progress

| # | Section | Status | Roles Tested | Crit | High | Med | Low | Total | Subdir |
|---|---------|--------|--------------|------|------|-----|-----|-------|--------|
| 01 | Client Management | pending | – | – | – | – | – | – | [01-client-management/](01-client-management/INDEX.md) |
| 02 | Appointments & Scheduling | pending | – | – | – | – | – | – | [02-appointments-scheduling/](02-appointments-scheduling/INDEX.md) |
| ... |
| NN | Last Section | pending | – | – | – | – | – | – | [nn-last-section/](nn-last-section/INDEX.md) |

## Drift Findings

Features present in `config/routes.rb` but not in `APP_FEATURES.md` (added to the sweep as "undocumented"):

_Filled in during Phase 1._

## Dedupe

Bugs matching prior runs are flagged `[DUPLICATE]` in their per-feature INDEX.md and reference the original. Prior sessions scanned:

_Filled in at Phase 2.2._

## Sections

- [01. Client Management](01-client-management/INDEX.md)
- [02. Appointments & Scheduling](02-appointments-scheduling/INDEX.md)
- ...
- [30. Superbills](30-superbills/INDEX.md)

## Rollup

_Filled in after the sweep completes._
```

Populate every row from the parsed section list — do not abbreviate with `...`.

### Step 2.4: Apply skip markers

Same rules as `/bug-hunt-all`: a section is **SKIPPED** if its row contains `[SKIP]` (case-insensitive), `<!-- skip -->`, or `~~strikethrough~~`. Skipped sections do not get hunted and do not appear in the TaskList. Record skip reason as the raw marker text.

### Step 2.5: Detect already-completed sections (resume only)

For each section, check whether `<session-dir>/{NN}-{slug}/INDEX.md` exists. If yes:
- Read its severity counts (parse the summary table at the top of the sub-INDEX)
- Update the `MASTER_INDEX.md` row to `status: done` with those counts
- Do NOT include in TaskList

---

## Phase 3: Create the TaskList

Create one task per non-skipped, not-yet-completed section using TaskCreate. Task title: `Full-QA section NN: <title>`. Order = section number ascending.

The TaskList is your loop state. It is the **only reliable way** to know what's left when control returns from a child invocation.

After all tasks created, print a one-paragraph plan: total sections, count to QA, count skipped, count already done, count of drift findings. **Do not ask the user to confirm.** Proceed directly to Phase 4.

---

## Phase 4: Shared Authentication Setup

Browser viewport and login are best handled once up-front, with re-authentication during the loop as roles change.

### Step 4.1: Browser

Resize for staff/admin (most sections):

```
mcp__playwright__browser_resize(width: 1280, height: 800)
```

Client Portal sections (13, parts of 11.4) require mobile (375x667). Re-resize per-feature as needed.

### Step 4.2: Staff login (dev-shortcut button)

This is the **preferred auth path** — it bypasses the magic-link email and is faster than reading server logs. The browser-based shortcut works because `STAGING_MAGIC_LINK=true` (verified in Phase 0).

Auth flow for any staff user:

```
1. mcp__playwright__browser_navigate to $BASE_URL/devise/passwordless/users/sign_in
2. Find the email input (label "Email") and fill with the role's seeded email
3. Click submit ("Send Magic Link" button)
4. Wait for the amber flash box ("Staging Login" header) to appear
5. Click the "Sign in now" link inside it
6. Wait for navigation away from /sign_in
7. Verify auth via the header avatar / signed-in nav
```

If at any step the "Sign in now" link does NOT appear after submit, fall back to:
```
- tail -100 log/development.log | grep -A5 "magic_link"
- Navigate directly to the extracted magic link URL
```
…and continue.

### Step 4.3: Client portal login

```
1. bin/rails runner 'puts FormAssignment.with_valid_token.first&.access_token'  # capture token
2. Navigate to $BASE_URL/client-portal/<token>
3. Look up the seeded client's DOB:
   bin/rails runner 'c = Client.joins(:emails).find_by(emails: {email: "testclient@example.com"}); puts c.date_of_birth.strftime("%m/%d/%Y") if c'
4. Fill the birth_date field (verification[birth_date]) with the formatted DOB
5. Click submit
6. Wait for redirect to /client-portal/<token>/dashboard (or /documents)
```

---

## Phase 5: The Per-Feature Loop

For each pending feature task (one feature section at a time, in numeric order):

### Step 5.1: Mark feature task in_progress
Mark the feature-level task `in_progress` via TaskUpdate.

### Step 5.2: Derive accessible roles for this feature

For each in-scope role, determine whether this feature is accessible. Use the algorithm:

1. From the section body, extract resource name(s) (e.g., "Client Management" → `clients`).
2. Grep `config/routes.rb` for the resource → controller path.
3. Open the corresponding policy at `app/policies/<model>_policy.rb` (or the controller's `authorize` calls if no policy).
4. For each action method (`index?`, `show?`, `create?`, `update?`, `destroy?`, custom actions), extract role checks via regex: `has_role?(:foo)`, `has_any_role?(:a, :b)`, `user.has_role?(:bar)`.
5. Union across action methods = set of accessing roles.
6. If the feature has any `/client-portal/` route → add `client` to the set.
7. Intersect with in-scope roles (admin, therapist, supervisor, clinical_supervisor, coordinator, client).

Record the role list in the per-feature INDEX.md and in the MASTER_INDEX row's `Roles Tested` column.

### Step 5.2b: Create per-role sub-tasks (MANDATORY — encodes the role loop in TaskList state)

**This step exists because the role loop in Step 5.4 is too easy to silently truncate.** By turning each `(feature, role)` pair into a discrete TaskList entry, you:
- Cannot quietly stop after one role without leaving visible `pending` rows.
- Survive context compaction without losing track of which roles still need QA.
- Give the user an accurate progress signal in the live TaskList.

Immediately after deriving the accessible role set in Step 5.2:

1. For each role in the deterministic order (`admin` → `coordinator` → `supervisor` → `clinical_supervisor` → `therapist` → `client`, skipping any not accessible), call TaskCreate:
   - **subject:** `Full-QA section NN / <role>: <feature title>` (e.g., `Full-QA section 01 / admin: Client Management`)
   - **description:** `Generate role-scoped QA plan via /create-qa-document --full-feature --role=<role> and execute it via /execute-qa for section NN.`
   - **activeForm:** `QA-ing <Feature short title> as <role>`
2. The parent feature task (created in Phase 3) stays `in_progress` and acts as the umbrella. It is only marked `completed` in Step 5.6 once **every** child role task is `completed` (or `error`).
3. If the feature has zero accessible in-scope roles (rare — would indicate a feature only the platform sees), skip child task creation, log this in the per-feature INDEX.md as an observation, and jump directly to Step 5.6 to complete the parent.

**Resume note:** On resume from a compacted session, rebuild the TaskList from disk by scanning the per-feature subdirs for partial bug INDEX.md files. Any `(feature, role)` pair without a corresponding completed plan or aggregated bug entries is still `pending` and must get its child task re-created.

### Step 5.3: Decide whether to reset DB

Smart per-feature judgment. Reset if the **prior feature** did anything globally durable that could pollute this feature's tests. Conservative default: do NOT reset unless one of these is true:
- Prior feature involved billing (Stripe charges, payment captures, invoice settlement)
- Prior feature signed clinical documents
- Prior feature archived/soft-deleted shared resources (clients, charts) that this feature depends on listing

If reset is warranted:
```bash
bin/rails db:reset    # drops, reloads the schema, and runs the full seed (~10 min)
```
…and re-confirm seeded users still exist via the Phase 0.3 check (db:reset wipes everything).

### Step 5.4: Iterate the per-role sub-tasks created in Step 5.2b — each one runs in a sub-agent

Walk the child role tasks created in Step 5.2b in the deterministic order (`admin` → `coordinator` → `supervisor` → `clinical_supervisor` → `therapist` → `client`, skipping any not in the role set from 5.2). **For each child role task:**

#### 5.4.0: Mark the child role task `in_progress` via TaskUpdate.

Update the role-level task you are about to work on. This makes the live TaskList show the user exactly which `(feature, role)` pair is being driven right now.

#### 5.4.1: Delegate the entire (feature, role) cycle to a sub-agent — MANDATORY

**Why a sub-agent:** Playwright accessibility snapshots can be 50K–400K characters each. Running `/create-qa-document` + `/execute-qa` inline in the orchestrator's context would exhaust the context window after a handful of features. The Agent tool exists exactly for this — "protecting the main context window from excessive results."

**Concurrency rule (CRITICAL):** Playwright MCP is a single shared browser session. Sub-agents that drive Playwright **must run serially** — call `Agent` synchronously (do **not** set `run_in_background: true`). Concurrent agents will collide on the browser and corrupt each other's state.

**How to spawn:**

```
Agent(
  description: "Full-QA NN/<role>: <feature title>",
  subagent_type: "general-purpose",
  prompt: <the self-contained brief below>
)
```

**Self-contained agent prompt template** (substitute the bracketed values):

```
You are the QA execution agent for one (feature, role) pair in a /full-qa sweep.

CONTEXT:
- Feature: Section [NN] of docs/APP_FEATURES.md — "[feature title]"
- Role under test: [role] (seeded email: [seeded-email-for-role])
- Master session dir: docs/bug-reports/full-app-qa-[TS]/
- Per-feature subdir: docs/bug-reports/full-app-qa-[TS]/[NN]-[slug]/
- Dev server is running at [the $BASE_URL from Step 0.1 — substitute the literal URL here] and STAGING_MAGIC_LINK=true so the dev-shortcut "Sign in now" button is available after submitting the email form.

YOUR JOB (end-to-end):
1. If a different user is currently authenticated in the browser, log out via /users/sign_out.
2. Log in as the seeded user for this role using the dev-shortcut flow:
   - Navigate to [BASE_URL]/passwordless/users/sign_in
   - Fill the Email textbox with [seeded-email-for-role]
   - Click "Send Magic Link"
   - When the amber "Staging Login" box appears, click "Sign in now"
   - Verify you've landed on /dashboard (or the role's home).
3. Generate the role-scoped QA plan by invoking the /create-qa-document skill with args:
   "[feature title] --full-feature --role=[role]"
   This writes the plan to docs/qa-plans/[slug]-[role]-[YYYYMMDD].md.
4. Execute the plan by invoking the /execute-qa skill with the plan path. It will drive Playwright through every SC-NNN and write bug reports under docs/bug-reports/qa-[slug]-[role]-<TS>/.
5. Aggregate the bugs into the master session subdir:
   - If docs/bug-reports/full-app-qa-[TS]/[NN]-[slug]/INDEX.md does not exist, create it from the template in /full-qa SKILL.md Step 5.4e.
   - Append each BUG-NNN-*.md (renumbered to continue the existing sequence, with **Role:** [role] and a **Category:** tag prepended) into that subdir, plus the matching screenshots/BUG-NNN.png file.
   - Append one bullet per bug to the INDEX.md under the appropriate severity heading, in the format documented in /full-qa SKILL.md Step 5.4e.
   - Update the INDEX.md summary tables (Severity + Category counts) to reflect the aggregate including any prior roles' bugs already in this subdir.

CONTEXT DISCIPLINE (CRITICAL — you must follow these to fit):
- Use depth-limited snapshots: pass depth: 4-6, never take a full-tree snapshot.
- Use target=<ref> to scope to a single subtree whenever you know the area of interest.
- For element-finding work, prefer dumping the snapshot to a file via the filename: parameter and grepping it from disk over pulling it into your context.
- Do NOT take fullPage screenshots unless you're capturing a confirmed bug for the report.
- Re-snapshot only after a DOM change you care about, not "to see what's there."

RETURN VALUE (this is what the orchestrator sees — keep it under 5 lines):
"Section [NN] / [role]: <total> bugs (Critical: <c>, High: <h>, Medium: <m>, Low: <l>). <scenarios-executed>/<scenarios-planned> scenarios. Subdir: docs/bug-reports/full-app-qa-[TS]/[NN]-[slug]/"

Do NOT return bug descriptions, scenario detail, or any Playwright output in your final message. Everything belongs on disk; the orchestrator only needs counts.

ERROR HANDLING:
- If /create-qa-document or /execute-qa errors, retry once, then once more after 30 seconds. After the second failure, return:
  "Section [NN] / [role]: ERROR — <one-line reason>. No bugs aggregated."
- Do NOT swallow errors silently. The orchestrator needs the ERROR sentinel to mark this role's task as `error` in the TaskList.

NEVER:
- Run git commit/push/reset/stash. Leave the working tree dirty.
- Modify /full-qa, /create-qa-document, or /execute-qa skill files.
- Spawn additional sub-agents — you ARE the sub-agent.
```

#### 5.4.2: Parse the sub-agent's return value

The agent's final message will be one of:
- `Section NN / <role>: X bugs (Critical: c, High: h, Medium: m, Low: l). N/P scenarios. Subdir: <path>` → success.
- `Section NN / <role>: ERROR — <reason>. No bugs aggregated.` → mark the role's task as `error` in the next step, log a `META-BUG-NNN` line in the per-feature INDEX.md, continue.

Capture the counts; you'll need them for the MASTER_INDEX row update in Step 5.5.

#### 5.4e: Aggregation template — referenced BY the sub-agent (not done by the orchestrator)

The sub-agent spawned in Step 5.4.1 performs the aggregation itself. This subsection documents the canonical format the agent must follow so the orchestrator never has to read bug files. **The orchestrator does NOT execute this step — the sub-agent does, using the rules below as its specification.**

Target: `<session-dir>/<NN>-<slug>/`

Steps the sub-agent runs:
1. If `<session-dir>/<NN>-<slug>/INDEX.md` does not yet exist, create a new one using the template below. It mirrors `/bug-hunt`'s output format so `/fix-bug-index` can parse it.

```markdown
# Bug Hunt Summary: <Feature Title>

**Date:** YYYY-MM-DD HH:MM
**Feature:** <Feature Title> (Section NN of docs/APP_FEATURES.md)
**Roles tested:** <comma-separated list>

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |
| **Total** | **0** |

| Category | Count |
|----------|-------|
| Functional | 0 |
| UX | 0 |
| Visual | 0 |
| A11y | 0 |
| Data | 0 |
| Security | 0 |
| Perf | 0 |
| HIPAA | 0 |

## Bugs

### Critical
_(none)_

### High
_(none)_

### Medium
_(none)_

### Low
_(none)_

## Observations
_(none)_
```

Append each new bug bullet to the appropriate severity section under `## Bugs`. Keep `## Observations` as a separate section even if empty — `/fix-bug-index` parses both. If no bugs were found for the entire feature across all roles, leave the template as-is (zero counts, `_(none)_` placeholders) — this is a valid "zero bugs found" stub that the master index can link to.
2. For each `BUG-NNN-*.md` from the just-completed `/execute-qa` run:
   - Renumber to continue the sequence in the master subdir's INDEX (if 5 bugs already exist, the new one becomes BUG-006).
   - Prepend a `**Role:** <role>` line to the bug body if not already present.
   - Prepend a `**Category:** [Functional|UX|Visual|A11y|Data|Security|Perf|HIPAA]` tag (judge from bug content — HIPAA if it came from the HIPAA & Compliance scenario group; Security if from a permission-negative scenario; etc.).
   - **Dedupe check**: query the Phase 2.2 lookup with `(feature_section, role, normalized_title, URL)`. If a match:
     - Append a `**Duplicate of:** [prior_session/path]` line to the bug body.
     - Mark the INDEX bullet for this bug with a trailing `[DUPLICATE]` tag.
   - Move the file into `<session-dir>/<NN>-<slug>/` and add its bullet to the INDEX.
3. Copy the matching `screenshots/BUG-NNN.png` over too (renumbered).

The per-feature INDEX bullet format (preserving `/fix-bug-index` compatibility — the parser pulls `[BUG-NNN: TITLE](filename.md)`, the rest is ignored):

```
- [BUG-001: Brief title](BUG-001-brief-title.md) — `[Functional]` — Severity: High — As therapist — short summary
- [BUG-002: Duplicate of prior bug](BUG-002-duplicate.md) — `[HIPAA]` — Severity: Critical — As admin — `[DUPLICATE]` short summary
```

#### 5.4f: Mark the child role task `completed` (or `error`)

Based on the sub-agent's return value parsed in Step 5.4.2:
- Success line → `TaskUpdate` the current role-level task to `completed`.
- ERROR line → `TaskUpdate` to `completed` with metadata noting the error (the per-feature INDEX.md will already carry the `META-BUG-NNN` line). Do NOT block the sweep on an isolated role failure; move to the next role.

Then move to the next role child task. **Do not jump ahead to Step 5.5 until every child role task for this feature is resolved.**

If any child role task remains `pending` for this feature, return to Step 5.4.0 with that role. Do not summarize, ask the user, or move to a different feature.

### Step 5.5: Update MASTER_INDEX row

After all child role tasks for this feature are `completed` (or `error`):
- Set `Status` to `done`
- Set `Roles Tested` to a comma-separated list of roles actually QA'd (exclude any rows that ended as `error`)
- Fill in severity counts (Crit / High / Med / Low / Total) from the per-feature INDEX.md summary table

### Step 5.6: Mark the parent feature task completed

`TaskUpdate` the feature-level task (the umbrella created in Phase 3) to `completed`. This must only happen after every child role task is resolved.

### Step 5.7: Anti-stop check (see checklist below)

If any feature task or role-level child task remains `pending`, go back to Step 5.1 (for a new feature) or Step 5.4 (for an unfinished role within the current feature) **right now**. Do not pause, summarize, ask the user, or write the rollup.

### Step 5.8: Error handling within the loop

If `/create-qa-document` or `/execute-qa` errors:
- Apply the retry policy from the top of this file (1 immediate retry, 1 after 30s, then mark `error`).
- Continue to the next pending feature.
- If `error` rows accumulate to three in a row from the same root cause (e.g., dev server crashed), stop per legitimate stop condition #2.

### Step 5.9: Do not commit

Leave the working tree dirty for the user. Do not run `git add`, `git commit`, `git stash`, `git reset`, or `git push`. Read-only git commands are fine.

---

## Phase 6: Final Rollup

Only after every task is `completed` (or `error`):

### Step 6.1: Write the rollup

Update `<session-dir>/MASTER_INDEX.md`:
- Add `**Date finished:** YYYY-MM-DD HH:MM` near the top
- Fill in the `## Rollup` section:

```markdown
## Rollup

### By Severity
| Severity | Count |
|----------|-------|
| Critical | X |
| High | X |
| Medium | X |
| Low | X |
| **Total** | **X** |

### By Category
| Category | Count |
|----------|-------|
| Functional | X |
| UX | X |
| Visual | X |
| A11y | X |
| Data | X |
| Security | X |
| Perf | X |
| HIPAA | X |

**Sections QA'd:** X
**Sections skipped:** Y (see [SKIP] markers above)
**Sections with errors:** Z
**Sections with zero bugs:** W
**Drift findings:** D
**Duplicates flagged:** F

To fix bugs from a single section:
`/fix-bug-index docs/bug-reports/full-app-qa-<TS>/<NN>-<slug>/INDEX.md`

To process every section's bugs sequentially, run `/fix-bug-index` against each sub-INDEX in turn.
```

### Step 6.2: Close the browser

`mcp__playwright__browser_close`.

### Step 6.3: Final message to the user

Two lines:
1. `Full-QA done. QA'd: X | Skipped: Y | Errors: Z | Bugs found: <total> | Duplicates: <count>`
2. `Master index: docs/bug-reports/full-app-qa-<TS>/MASTER_INDEX.md (nothing committed)`

---

## Resumability Notes

- The master session dir is the source of truth for progress. If the conversation crashes or is interrupted, the user re-invokes `/full-qa <path-to-session-dir>` and you pick up.
- TaskList state is NOT persisted across conversations. On resume you rebuild it from disk: any section whose sub-INDEX.md exists with a complete `Roles Tested` column counts as completed; everything else (minus skips) goes back into pending.
- Skip markers added between runs are honored — re-read MASTER_INDEX.md fresh on each resume.
- If a section has a sub-INDEX.md but the user wants to re-QA it, they should delete that subdirectory before resuming.
- **Resume-from-compaction (within the same conversation)** is automatic per the Continuous Execution rules above. Do not ask the user to confirm resume.

---

## Important Guidelines

1. **DO NOT FIX BUGS.** Only find and document them. The user runs `/fix-bug-index` afterward.
2. **Do not commit, stage, stash, push.** The user reviews manually.
3. **Respect skip markers** exactly as `/fix-bug-index` defines them: `[SKIP]`, `<!-- skip -->`, `~~strikethrough~~`.
4. **Process sections in numeric order.** Within a section, process roles in the deterministic order from Step 5.4.
5. **Pass the correct flags to `/create-qa-document`**: `--full-feature --role=<role>`. The extended skill needs these to enter full-feature mode.
6. **One feature = N invocations of `/create-qa-document` + N invocations of `/execute-qa`** where N = number of accessible roles. Do not merge or skip per-role plans.
7. **Use the dev-shortcut button for staff auth.** It is faster and more reliable than parsing magic links from logs.
8. **Re-authenticate every time the role changes.** Logout cleanly. Do not assume session carries across roles.
9. **Keep MASTER_INDEX.md edits idempotent.** Update the existing row in place rather than appending.
10. **Tag every bug with a Category.** Functional / UX / Visual / A11y / Data / Security / Perf / HIPAA. This drives the rollup table.
11. **Honor the dedupe lookup.** Do not silently skip duplicates — flag them so the user can verify.
12. **Never write the banned phrasings** until the run is complete.

---

## Execution Flow (Summary)

1. Pre-flight (server, env, seeds, Stripe warn)
2. Parse `APP_FEATURES.md` → 30 sections; cross-check routes.rb → drift list
3. New vs. resume from `$ARGUMENTS`
4. Dedupe scan against prior `full-app-qa-*` dirs
5. Write or read MASTER_INDEX skeleton (preserve skip markers on resume)
6. Detect already-completed sections from existing sub-INDEX.md files
7. Apply skip markers
8. TaskCreate one task per non-skipped, not-yet-done section
9. Print plan, do shared browser+auth setup
10. **Loop**: while any feature task is pending:
    a. Mark feature task `in_progress`
    b. Derive accessible roles for the feature
    c. **TaskCreate one child task per accessible role (Step 5.2b)** — this encodes the role loop in TaskList state so it cannot be silently truncated
    d. Decide DB reset (smart heuristic)
    e. For each child role task (in order): mark `in_progress`, **spawn a `general-purpose` sub-agent (Step 5.4.1)** that runs the entire (login → `/create-qa-document` → `/execute-qa` → aggregate-to-master-subdir) cycle in its own context and returns ONE LINE of summary, parse that summary (Step 5.4.2), mark child `completed` or `error`. Sub-agents run **serially** — Playwright is a single shared browser session
    f. After every role child is resolved: update MASTER_INDEX row
    g. Mark parent feature task `completed`
    h. **Anti-stop check** — immediately continue to next pending feature task
11. After last task: rollup, close browser, print recap

**Why this loop fits in context:** the orchestrator never personally drives Playwright. It only reads ~one line per (feature, role) pair from each sub-agent. For 30 features × ~4 roles = ~120 sub-agent spawns, the orchestrator's running context cost is ~120 short summaries plus scaffolding — well within budget. Each sub-agent gets a fresh context for ~one plan + one execution, and its Playwright snapshots never reach the orchestrator. This is the textbook use of the Agent tool: "protecting the main context window from excessive results."

---

## Anti-stop checklist (run after every child skill invocation returns)

- [ ] Did `/execute-qa` produce its INDEX.md and BUG files (or report zero bugs)?
- [ ] Did I aggregate the bugs into the master session subdir with correct renumbering, Role prefix, Category tag, and dedupe flag?
- [ ] Did I mark the **child role task** for this `(feature, role)` pair as `completed`?
- [ ] Does the current feature have any other `pending` role child tasks (per Step 5.2b)?
- [ ] If yes → loop back to Step 5.4 with the next role RIGHT NOW. Do not summarize, do not ask, do not write the parent-feature row, do not move to a different feature.
- [ ] Only after every role child task for the current feature is `completed` (or `error`) do you update the MASTER_INDEX row (Step 5.5) and complete the parent feature task (Step 5.6).
- [ ] Are there any `pending` feature-level TaskList items?
- [ ] If yes → invoke the next pending feature's flow (back to Step 5.1) RIGHT NOW. Do not summarize. Do not ask. Do not write the rollup.
- [ ] If no pending items → re-derive from MASTER_INDEX. Any row with status `pending` is a pending item.
- [ ] Only when MASTER_INDEX has zero `pending` rows (and no `pending` role child tasks) do you write the final rollup and stop.

Begin by running the Phase 0 pre-flight.
