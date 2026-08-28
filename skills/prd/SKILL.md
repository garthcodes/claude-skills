---
description: Generate a build-ready PRD through codebase-grounded, question-driven discovery
argument-hint: [brief feature idea]
---

# PRD Generation Through Discovery

You are helping create a Product Requirements Document for: "${1:your feature idea}"

If no feature idea was provided, ask for one before doing anything else.

## Why This PRD Matters

The PRD you produce is the primary input to `/build-feature` — an **autonomous** pipeline
(`/plan` → architect/frontend review → `/tickets` → `/code` → `/full-review` → Playwright QA → PR)
that runs end-to-end **without ever asking the user anything**. The full PRD text is pasted into
the build agent's prompt.

This has three hard implications:

1. **Every ambiguity in the PRD becomes an agent's silent guess.** This discovery conversation
   is the user's only chance to make decisions. Resolve everything or explicitly delegate it.
2. **Acceptance criteria are the contract the PR is gated on.** The pipeline verifies them
   through the browser twice — system tests (Capybara) and Playwright QA against a dev server
   — and then runs `/verify-acceptance`, which scores every `AC-n` row. **A PR is not opened
   until every Must-priority criterion is VERIFIED** (unmet Should criteria produce a draft
   PR). So a criterion that is vague, wrong, or unverifiable doesn't get "interpreted" — it
   blocks shipping. Criteria a browser or a spec can't check will never be checked.
3. **The PRD must be self-contained and lean.** The whole document rides along in agent prompts
   through many pipeline phases. Comprehensive, but no filler.

## Your Role

You are a thorough product manager who **never assumes on product decisions** — but who also
**never wastes the user's time** asking questions the codebase, project conventions, or the
user's own description already answer. Investigate first, then ask sharp questions with
concrete options.

---

## Phase 1: Ground Yourself in the Codebase (Before Any Questions)

Before asking the user anything, launch an **Explore agent** (search breadth: medium) to map the
territory around the feature idea. Have it report:

- **Similar or adjacent existing features** — models, services, controllers, ViewComponents,
  routes, and Stimulus controllers this feature would touch, extend, or should pattern-match
- **The relevant section(s) of `docs/APP_FEATURES.md`** — where this fits in the app's feature map
- **User roles and permissions** — which Rolify roles exist and how Pundit policies gate the
  adjacent features (app roles: `admin`, `therapist`, `supervisor`, `clinical_supervisor`,
  `coordinator`, `client` for the portal)
- **UI surfaces** — the navigation/screens where this feature would plausibly live
- **Existing integrations** relevant to the idea (mailers, TextMessageService, Stripe,
  Google Calendar, AI services, background jobs)

While the agent runs (or after), skim anything it flags as load-bearing yourself.

**Use what you learn in two ways:**
- **Don't ask** questions the exploration answered — *confirm* instead ("The app already has
  `ReminderConfiguration` per office — should this reuse it or be practice-wide?")
- **Ground your options** — every question you ask should offer choices anchored in what
  actually exists, not abstract hypotheticals

### Never ask about (already decided by CLAUDE.md conventions)

Styling (Tailwind-only), component approach (ViewComponent), JS framework (Stimulus),
authentication (Devise passwordless), primary keys (UUID), date display format (MM/DD/YYYY),
timezone storage (IANA), multi-tenancy (acts_as_tenant), test frameworks, error monitoring
(Honeybadger), email delivery (branded mailer layout), pagination (Pagy). Reference these as
constraints in the PRD where relevant — don't burn questions on them.

---

## Phase 2: Discovery Interview

Conduct the interview with the **AskUserQuestion tool** — up to 4 questions per round, each with
2–4 concrete options (put your recommended option first, labeled "(Recommended)"), using
`multiSelect` where choices aren't mutually exclusive. The user can always answer "Other" with
free text. Fall back to free-form prose only when a topic genuinely can't be framed as options
(e.g., "walk me through the workflow as you imagine it").

**Aim for 2–4 rounds.** Group questions by theme per round:

1. **Round 1 — Problem, users, scope shape**: what problem, for whom, why now, and the rough
   v1 boundary
2. **Round 2 — Workflow & UX decisions**: entry points, the step-by-step happy path, key
   screens/states
3. **Round 3 — Permissions, data, integrations**: who can do what, what's captured/displayed,
   notifications, retention
4. **Round 4 — Edge-case policies & definition of done**: the decisions that would otherwise
   become guesses

Ask follow-ups (another round or free-form) whenever an answer opens a genuine fork. Stop when
another question would no longer change what gets built.

### Decision checklist — every area must be COVERED (asked, confirmed from exploration, or consciously defaulted)

1. **Problem & trigger** — what breaks today, who feels it, why solve it now
2. **Users → real app roles** — map every user type to actual roles (`admin`, `therapist`,
   `supervisor`, `clinical_supervisor`, `coordinator`, `client`)
3. **Core workflow** — the step-by-step happy path, from entry point to success state
4. **Scope boundary** — v1 vs. later; propose explicit out-of-scope items yourself and get
   them confirmed (this is the scope-creep guard for the build agent)
5. **Permissions** — which roles can perform each action; view vs. manage distinctions
6. **Data** — what's captured/displayed; is any of it PHI; does it need soft-delete and/or
   HIPAA audit logging; retention expectations
7. **Integrations & notifications** — email (branded mailer), SMS (TextMessageService), Stripe,
   calendar, AI, background jobs — only where plausibly relevant
8. **Edge-case policies** — empty states, limits, concurrent edits, external-service failure
   behavior, what happens on deletion of related records. **Every edge case you raise must end
   in a decided behavior**, not a shrug.
9. **Definition of done** — the user-visible outcomes that prove the feature works, phrased so
   Playwright QA can verify them through the browser (these become the Acceptance Criteria
   contract in Phase 3.5)

### Question style

- Challenge assumptions — ask "why" and "what happens when…"
- Prefer "what should happen" over "how should it be built" (the how belongs to `/plan`)
- When the user's answer conflicts with something you found in the codebase, surface the
  conflict immediately rather than writing down both
- Periodically restate what you've locked in, in one or two sentences, so drift is caught early

---

## Phase 3: Confirm Understanding

Before writing anything, present a compact restatement: the problem, the v1 scope boundary,
the core flow, and the key decisions made. Ask one final round: "Anything wrong, missing, or
that you want to change?" Incorporate corrections, then proceed.

---

## Phase 3.5: Draft and Agree the Acceptance Criteria

The Acceptance Criteria table is the **contract** `/build-feature` gates the PR on. It must be
explicitly agreed by the user — never inferred, never silently written. Do this after Phase 3
and before writing any of the PRD.

### Drafting rules

Draft the full table from the decisions locked in during discovery:

- **One row per user-visible outcome**, written as **Given / When / Then** with concrete data
  ("Given the seeds are loaded, when a therapist searches `Z63` in the treatment-plan diagnosis
  search, then 0 results are shown and searching `F43` still returns results" — not "Z codes
  are hidden").
- **IDs** `AC-1`, `AC-2`, … in reading order; stable once agreed (never renumber after sign-off —
  drop rows leave gaps).
- **FR** — every AC maps to ≥1 FR; every **Must** FR has ≥1 **Must** AC. If an FR has no AC, it
  is either not really a requirement or the AC list is incomplete — fix one or the other.
- **Priority** — `Must` (PR is blocked until verified) or `Should` (PR opens as draft if
  unverified). Default to Must; a Should is a conscious downgrade the user makes.
- **Verified by** — the cheapest layer that can *observe* the outcome:
  - `browser` — Playwright QA scenario and/or Capybara system test (default for anything a user
    sees or does)
  - `spec` — model/service/controller/component/policy spec (server-side rules a browser can't
    isolate, e.g. "a non-F code in the AI response is filtered before rendering")
  - `browser+spec` — both required (typically validation that has a UI and a server rule)
  - `manual` — only for things neither can reach (a rake task's dry-run output, a mailer's
    rendered text). The criterion must then say **exactly** what command to run and what
    output proves it.
- **Negative and permission cases get their own rows** — "Given a `therapist`, when they visit
  `/x` directly, then they see 403 / are redirected to …". Empty state, error state, and every
  decided edge-case policy that a user can observe also gets a row.
- **Nothing that is only verifiable by reading code.** "The service uses a Result object" is a
  plan concern, not an AC.

### Sign-off loop (AskUserQuestion)

1. Present the **entire** draft table in chat as markdown — the user must be able to read it
   whole, not in fragments.
2. Then walk it with **AskUserQuestion**, one question per FR category (≤4 per round). Each
   question offers: **"Approve as written (Recommended)"**, **"Edit — I'll say which rows"**,
   **"Drop rows"**, **"Add missing criteria"**. Where you're unsure about priorities, add a
   `multiSelect` question: "Which of these should block the PR (Must)?"
3. Always include this gap-finder question once: *"Is there any outcome that — if it didn't
   work — you would reject the PR, that isn't in this list?"*
4. Apply the answers, re-present **only the changed/added rows**, and loop until every category
   is approved. Cap at 3 rounds; if a row is still disputed after that, keep it as **Should**
   and record the disagreement in Resolved Decisions.
5. When every group is approved, the table is frozen. Stamp it `*Agreed with user: YYYY-MM-DD*`
   directly under the heading in the PRD. **A PRD without this stamp is not ready for
   `/build-feature`** — its Status line must say `Draft — acceptance criteria not agreed`.

---

## Phase 4: Write the PRD

Write to `.claude/prds/[feature-slug].md` where the slug is the kebab-case feature name
(e.g., `.claude/prds/client-appointment-reminders.md`). Create `.claude/prds/` if it doesn't
exist. `/build-feature` will use the slug for the branch name (`feature/[feature-slug]`), so
choose it deliberately and state it in the header.

Keep the document **comprehensive but lean** — typically 150–350 lines. Cut anything that
wouldn't change what the build agent does.

```markdown
# PRD: [Feature Name]

*Feature slug: `feature-slug`* (branch: `feature/feature-slug`)
*Generated: [YYYY-MM-DD] • Status: Ready for /build-feature*
[Status must be `Draft — acceptance criteria not agreed` until Phase 3.5 sign-off is complete.]

## Executive Summary
[2–4 sentences: what it is, who it's for, the core value. /build-feature extracts this
verbatim for planning context — make it stand alone.]

## Problem & Context

### The Problem
[What breaks today, for whom, and the cost of not solving it]

### Why Now
[The trigger]

### Existing System Context
[From Phase 1 exploration — the models, services, components, routes, and screens this
feature touches or should pattern-match. Name files/classes. This is the build agent's
head start; be specific.]

## Users & Roles

| Role | Involvement | Goal |
|------|-------------|------|
| [actual app role] | [primary/secondary/none] | [what they accomplish] |

## Scope

### In Scope (v1)
1. [Numbered, concrete capabilities]

### Out of Scope — Do NOT Build
- [Explicit exclusions. The build agent treats these as hard boundaries. Include things
  that were discussed and deferred, plus adjacent features an eager agent might "helpfully"
  add.]

### Future Considerations
[Anticipated evolution — design-for-later notes only where they change v1 decisions]

## Functional Requirements

### [Category]
| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-1 | [What the system must do] | Must / Should | AC-1, AC-3 |

[Every FR references ≥1 row of the Acceptance Criteria table below (the contract). A short
inline phrase is fine too, but the AC IDs are what the pipeline traces.]

## User Experience

### Entry Points
[Where in the existing navigation/screens users find this]

### Primary Flow
1. [Step-by-step happy path — screen by screen, action by action]

### States
- **Empty**: [what shows when there's no data]
- **Loading / in-progress**: [if relevant]
- **Error**: [what users see and can do when things fail]
- **Success**: [confirmation feedback]

[Responsive/accessibility only where feature-specific — conventions cover the rest.]

## Permissions

| Action | admin | therapist | supervisor | clinical_supervisor | coordinator | client |
|--------|-------|-----------|------------|--------------------|-------------|--------|
| [action] | ✅ / ❌ | … | | | | |

[Trim columns for roles with no involvement. Note any record-level scoping needs
(e.g., "therapists see only their own clients' X") for Pundit policy scopes.]

## Data

- **New/changed models** (directional — /plan owns the final design): [model: key fields,
  associations]
- **PHI**: [which fields are PHI; never in logs or Honeybadger context]
- **Soft-delete**: [needed? cascades?]
- **HIPAA audit logging**: [which actions need audit trails]
- **Retention**: [any retention requirements]

## Integrations
[Only subsections that apply: email (uses branded mailer layout — dedicated mailer action),
SMS via TextMessageService, Stripe, Google Calendar, AI services, background jobs. Delete
this section entirely if none apply.]

## Edge Cases & Policies

| Scenario | Decided Behavior |
|----------|------------------|
| [edge case] | [the decision — never "TBD"] |

## Acceptance Criteria
*Agreed with user: YYYY-MM-DD*

| ID | Criterion | FR | Priority | Verified by |
|----|-----------|----|----------|-------------|
| AC-1 | Given <precondition>, when <action>, then <observable result with concrete values> | FR-1 | Must | browser |
| AC-2 | Given …, when …, then … | FR-2 | Must | spec |
| AC-3 | Given a `therapist`, when they visit `/…` directly, then … | FR-2 | Must | browser |
| AC-4 | Given …, when `bin/rails z:task DRY_RUN=1` is run, then it prints "Would delete N" and deletes nothing | FR-4 | Should | manual |

[This table is the contract. `/build-feature` will not open a PR until every Must row is
VERIFIED by `/verify-acceptance`; unverified Should rows make the PR a draft. Rows are frozen
after sign-off — do not renumber. The per-FR "Acceptance Criteria" column above may simply
reference the AC IDs (e.g. "AC-1, AC-3").]

## Definition of Done
- [ ] AC-1: [criterion text, copied verbatim]
- [ ] AC-2: …

[Derived from the table: one line per **Must** AC, in order. No new content here — it exists
so humans (and `/plan-system-tests`, `/create-qa-document`) have a checklist view.]

## Resolved Decisions
| Decision | Choice | Why |
|----------|--------|-----|
| [fork that came up in discovery] | [what was chosen] | [one line] |

## Implementer Discretion
[Things intentionally left to /plan and implementation judgment, with any guardrails.
E.g., "exact empty-state copy — keep tone consistent with existing screens".]
```

**There is no "Open Questions" section.** If a question is still open, either resolve it with
the user now or move it — with explicit guardrails — into Implementer Discretion. An open
question handed to an autonomous pipeline is a coin flip.

**Write the Acceptance Criteria table exactly as agreed in Phase 3.5** — same IDs, same text,
same priorities. Any change after sign-off requires going back to the user.

---

## Phase 5: Self-Review Gate

Before presenting the PRD, re-read it **as if you were the build agent** receiving it cold:

1. Is any FR ambiguous — could two reasonable engineers build different things from it?
2. Is every AC row Given/When/Then with concrete values, a `Verified by` layer, and ≥1 FR?
   Does every Must FR have a Must AC? Is any AC verifiable only by reading code (then it's
   not an AC)? Does every `manual` row name the exact command and the proving output?
3. Is the `*Agreed with user: <date>*` stamp present, and does the table match what the user
   approved in Phase 3.5 word for word? Is the Definition of Done a faithful derivation?
4. Does any edge case lack a decided behavior? Any "TBD", "maybe", or "possibly" anywhere?
5. Is the Out of Scope list explicit enough to stop an eager agent from gold-plating?
6. Does Existing System Context name real files/classes (not vague "the reminder system")?
7. Is the permissions matrix complete for every FR action, and does each ❌ cell that matters
   have a negative AC row?

Fix what fails. Then present to the user: the file path, a 3–5 bullet summary of what was
decided, the AC count (Must/Should), and a note that it's ready for
`/build-feature .claude/prds/[feature-slug].md`.
