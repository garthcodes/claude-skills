---
description: Generate a build-ready PRD through codebase-grounded, question-driven discovery
argument-hint: [brief feature idea]
---

# PRD Generation Through Discovery

You are helping create a Product Requirements Document for: "${1:your feature idea}"

If no feature idea was provided, ask for one before doing anything else.

## Why This PRD Matters

The PRD you produce is the primary input to `/build-feature` — an **autonomous** pipeline
(`/acceptance-criteria` → `/review-acceptance-criteria` → `/plan` → architect/frontend review → `/tickets` → `/code` → `/full-review` → Playwright QA → `/verify-acceptance` → PR)
that runs end-to-end **without ever asking the user anything**. The full PRD text is pasted into
the build agent's prompt.

This has three hard implications:

1. **Every ambiguity in the PRD becomes an agent's silent guess.** This discovery conversation
   is the user's only chance to make decisions. Resolve everything or explicitly delegate it.
2. **The Acceptance Criteria contract is derived from this PRD mechanically.** `/build-feature`
   first runs `/acceptance-criteria`, which turns every FR, edge case, permission cell, UX
   state, and Out-of-Scope bullet into a Given/When/Then row, then `/review-acceptance-criteria`
   audits that contract for gaps and inventions. The pipeline builds to that contract, checks
   it at every phase, and finally runs `/verify-acceptance`: **a PR is not opened until every
   Must-priority row is VERIFIED** (unmet Should rows produce a draft PR). So every requirement
   you write must state an **observable outcome with concrete values** — a role, a route, a
   visible text, a count. A requirement the browser or a spec can't witness will never be
   checked, and an Out-of-Scope item you forget to list will never be guarded against.
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
   Playwright QA can verify them through the browser (`/acceptance-criteria` turns these, and
   every FR, into the contract the PR is gated on)
10. **Gap-finder** — ask once, near the end: *"Is there any outcome that — if it didn't work —
   you would reject the PR, that we haven't discussed?"* and *"Is there anything an eager
   engineer might add here that you specifically do NOT want?"* — the second answer feeds the
   Out of Scope list, which becomes guard criteria.

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
1. **OOS-1** — [Explicit exclusion, stated concretely enough that its *absence* can be
   observed: "no bulk-export button on the clients index", "no email is sent on X".]
2. **OOS-2** — …

[Numbered `OOS-n`. The build agent treats these as hard boundaries and
`/acceptance-criteria` writes one guard criterion per bullet — so name the surface the
extra would have appeared on. Include things that were discussed and deferred, plus adjacent
features an eager agent might "helpfully" add.]

### Future Considerations
[Anticipated evolution — design-for-later notes only where they change v1 decisions]

## Functional Requirements

### [Category]
| ID | Requirement | Priority | Observable outcome |
|----|-------------|----------|--------------------|
| FR-1 | [What the system must do] | Must / Should | [How a browser, spec, or command would witness it — role, route, visible text/values] |

[Every FR has an observable outcome; `/acceptance-criteria` turns each into ≥1 Given/When/Then
row. If you can't write the outcome column, the requirement isn't specific enough yet.]

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

| ID | Scenario | Decided Behavior |
|----|----------|------------------|
| EC-1 | [edge case] | [the decision — never "TBD" — stated as what the user observes] |

## Definition of Done
- [ ] FR-1: [the observable outcome, copied from the FR table]
- [ ] FR-2: …

[One line per **Must** FR, in order. No new content here — it is the human checklist view;
the machine-checked contract is generated from this PRD by `/acceptance-criteria` into
`.claude/acceptance-criteria/[feature-slug].md`.]

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

---

## Phase 5: Self-Review Gate

Before presenting the PRD, re-read it **as if you were the build agent** receiving it cold:

1. Is any FR ambiguous — could two reasonable engineers build different things from it?
2. Does every FR have an *Observable outcome* a browser, a spec, or a quoted command could
   witness — with concrete values? Could `/acceptance-criteria` write a Given/When/Then row
   from it without guessing? Is anything in that column verifiable only by reading code?
3. Is the Definition of Done exactly the Must FRs' outcomes, in order?
4. Does any edge case lack a decided behavior? Any "TBD", "maybe", or "possibly" anywhere?
5. Is every Out of Scope bullet numbered and concrete enough that its *absence* can be
   observed (it becomes a guard criterion)? Does the list cover the extras an eager agent
   would add?
6. Does Existing System Context name real files/classes (not vague "the reminder system")?
7. Is the permissions matrix complete for every FR action? (Each ❌ cell becomes a negative
   criterion; each record-scoping note becomes a different-owner criterion.)

Fix what fails. Then present to the user: the file path, a 3–5 bullet summary of what was
decided, the FR count (Must/Should) and Out-of-Scope count, and the next step:
`/build-feature .claude/prds/[feature-slug].md` (it derives and reviews the acceptance
criteria itself), or `/acceptance-criteria .claude/prds/[feature-slug].md` followed by
`/review-acceptance-criteria` to inspect the contract first.
