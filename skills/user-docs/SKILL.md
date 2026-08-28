---
description: Generate a user-facing handbook document that doubles as knowledge corpus for the dashboard help assistant
argument-hint: <feature-name-or-index-row>
---

# User Documentation Generator

You are tasked with creating a user-friendly handbook document that explains how a feature works in the application. Each document serves **two consumers**:

1. **End users** (e.g., staff, coordinators, admins, managers, billers) reading it directly — NOT engineers.
2. **The dashboard help assistant** — an AI Q&A panel that answers staff questions **exclusively** from the `docs/user_docs/` corpus. If a behavior isn't written in a doc, the assistant tells users "I don't have information on that." If a doc says something wrong, the assistant repeats it confidently.

This second consumer changes the stakes: **every sentence must be traceable to code you actually read**, and every doc must be structured so an AI can find it, quote a short answer from it, and frame that answer by role.

## Input

$ARGUMENTS

**An argument is required.** The argument describes the feature to document. It can be:
- A feature name or index row from `docs/user_docs/0_USER_DOCS_INDEX.md` (e.g., "Insurance Claims", "row 37")
- A brief description of the feature area
- A path to a specific area of the app (e.g., "staff/appointments")

Check the index first: the feature you're documenting almost certainly has a row there, and the row's feature name determines the filename and index link you'll update in Phase 3.

## Phase 1: Deep Feature Exploration

### Grounding Rules (non-negotiable)

- **Code is the only source of truth.** Explore models, controllers, services, views, components, policies, jobs, mailers, and Stimulus controllers. **Never** base content on existing docs, `docs/APP_FEATURES.md`, READMEs, code comments describing intent, or the doc you are replacing — these are exactly what may be stale. If a doc contradicts the code, the code wins.
- **Verify reachability.** A behavior isn't real unless it's routed, authorized, and rendered. A model method with no UI path does not belong in a handbook.
- **Never guess.** If you can't confirm a behavior in code, leave it out entirely — an omission makes the assistant say "I don't know"; an invented sentence makes it fabricate instructions. Omission is safe; invention is not. List anything you couldn't confirm in your final summary instead.

### Step 1: Find All Relevant Code

Search broadly across the codebase to find everything related to this feature:

```bash
# Search routes for relevant endpoints
grep -n "feature_keyword" config/routes.rb
```

Use `Grep` and `Glob` to find:
- **Routes** — all URLs and actions available
- **Controllers** — what each action does, what data it loads, what responses it renders
- **Views/Partials** — what the user sees, form fields, buttons, links, labels
- **ViewComponents** — reusable UI elements related to the feature
- **Models** — data relationships, validations, enums (status values, types)
- **Policies (Pundit)** — who can do what (authorization rules per role)
- **Services** — business logic, workflows, side effects
- **Stimulus controllers** — interactive behaviors (dropdowns, modals, real-time updates)
- **Mailers/Jobs** — emails sent, background processes triggered
- **Locales/I18n** — user-facing text and labels

### Step 2: Map the Complete Feature

From the code, determine:

1. **All user roles** that interact with this feature and what each can do
2. **Every page/screen** in the feature with how the user navigates to it
3. **All actions** a user can take (create, edit, delete, filter, search, export, etc.)
4. **All statuses/states** and how records transition between them
5. **Form fields** — what's required, what's optional, what validations exist
6. **Notifications** — emails, alerts, or messages triggered by actions
7. **Settings/Configuration** — any configurable aspects of the feature
8. **Integrations** — connections to other features or external services
9. **Dynamic behavior** — real-time updates, inline editing, modals (described in user terms)

### Step 3: Build the Complete Permission Picture

Read the Pundit policies and build a full authorization matrix using the **canonical role names**: `admin`, `therapist`, `supervisor`, `clinical_supervisor`, `coordinator`, `manager`, `biller` (plus `owner` and `platform_admin` where policies check them, and "Client (Portal)" where relevant).

- Which roles can view, create, edit, delete — **and which roles cannot access the feature at all**. Explicit "no access" rows matter: the assistant must be able to tell a therapist "voiding an invoice requires a biller or admin." A role missing from the table is a question the assistant can't answer.
- Any conditional permissions (e.g., "therapists can only edit their own records")
- Admin-only settings or actions

**Role implication rule:** every `supervisor` and `clinical_supervisor` user ALSO holds the `therapist` role (enforced by `User#supervisor_roles_require_therapist_role`). Never write "No access" for supervisor/clinical_supervisor when therapist has access — they inherit at least the therapist level.

**Verify UI reachability separately from Pundit.** A Pundit policy that allows a role means nothing if the UI gives that role no path to the feature. For every role in the table, trace the actual navigation: the sidebar (`app/components/sidebar_component.html.erb`), settings page cards (`app/views/settings/index.html.erb`), billing hub cards (`app/views/billing/index.html.erb`), client-profile panels (`app/views/clients/show.html.erb` — note panel gates like `ClientPolicy#show_insurance?`), and the global-search page jumps (`app/services/global_search/page_jump_resolver.rb`). Document the paths that actually exist for each role; if a role passes the policy but has no navigation path, do NOT document a route they can't take — flag the discrepancy to the developer instead (it is an app bug; see `.claude/audits/authorization-consistency-audit.md`).

## Phase 2: Write the Document

### Step 4: Generate the Handbook Document

Create the document at: `docs/user_docs/{feature-name}.md` — kebab-case, matching the index row's feature name (e.g., `insurance-claims.md`, `fee-schedules.md`).

- **All corpus files live in `docs/user_docs/`.** If the index row currently points elsewhere (e.g., `BILLING_USER_GUIDE.md`), write a fresh doc in `docs/user_docs/` and repoint the index; do not link outside the corpus directory.
- **Grouping**: closely related index rows may share one doc with a `## Section` per row (see how `charts-and-clinical-documents.md` covers 12 rows via anchors). Group only when the features genuinely share a workflow; each index row must link to its doc (with an anchor when grouped).
- **Client-portal features** get docs too, written for the staff reader: describe what *the client* sees and does, so staff can answer "what does my client experience when…". Set `audience: client-portal` in frontmatter.

Write in **plain, friendly language**. Assume the reader has no technical background, is learning the feature for the first time, and needs to know what they can do, how to do it, and what to expect.

### Document Structure

Follow this template:

```markdown
---
title: [Feature Name]
audience: staff | client-portal | admin
roles: [admin, biller]            # roles that can use the feature (canonical names)
keywords: [invoice, charge, void, refund, payment link]   # words users would actually type when asking about this
summary: One sentence saying what this feature does — used to pick relevant docs for a question.
---

# [Feature Name]

**TLDR:** [1–2 plain-English sentences a help assistant could quote verbatim as a complete short answer to "how does {feature} work?". No setup, no "this document describes…".]

[2–3 sentence overview expanding on the TLDR: what this feature does and why it's useful.]

---

## Getting Started

[How to access this feature — where to click, what menu to use.]

### Who Can Use This Feature

| Role | Access Level |
|------|-------------|
| Admin | [What admins can do] |
| Biller | [What billers can do] |
| Therapist | [What therapists can do — or "No access"] |
| ... | [Include EVERY staff role, even as "No access"] |

---

## [Core Workflow Section]

### [Subsection for each major action]

[Step-by-step instructions with clear numbered steps:]

1. Navigate to **[Menu Name] > [Submenu]**
2. Click the **[Button Name]** button
3. Fill in the following fields:
   - **Field Name** (required) — [What to enter and why]
   - **Field Name** (optional) — [What this controls]
4. Click **Save**

> **Tip:** [Helpful tip about this action]

### What Happens Next

[Explain any automatic actions, emails sent, status changes, etc.]

---

## [Status/Workflow Section — if applicable]

### Understanding Statuses

| Status | What It Means | What You Can Do |
|--------|--------------|-----------------|
| **Status 1** | [Plain language explanation] | [Available actions] |
| **Status 2** | [Plain language explanation] | [Available actions] |

### Status Flow

[Describe how a record moves through statuses, what triggers each transition]

---

## [Settings/Configuration Section — if applicable]

[Explain any settings the user can configure and what each setting controls]

---

## Common Questions

### [Question phrased exactly the way a user would ask it — e.g., "Who can void an invoice?"]

[Lead with the direct answer in the first sentence, then any needed detail.]

### [Another natural-phrasing question]

[Direct answer first.]

---

## Troubleshooting

### [Common issue]

**Problem:** [What the user sees]
**Solution:** [What to do about it, using the app itself]

---

## Related Features

- **[Related Feature]** ([related-feature.md]) — [How it connects, in one sentence that stands alone]
```

Notes on the template:
- **No Table of Contents.** The headers are the navigation; a ToC is pure overhead for both readers and the assistant's context window.
- **The TLDR line is load-bearing** — the assistant's answers are TLDR-first, and this line is what it will reach for. Make it a genuinely complete short answer.
- **Common Questions replaces FAQ** and is retrieval-critical: phrase each question the way staff actually ask ("Who can…", "How do I…", "What happens when…", "Why can't I…"), and answer it in the first sentence. These map directly onto assistant queries.
- **Keep each doc self-contained.** When another feature matters, restate the one essential fact inline and *then* point to the other doc — the assistant may load only this one file.

## Writing Guidelines

1. **Use "you" language** — "You can create a new client by..." not "The user creates a new client by..."
2. **Bold UI elements** — Button names, menu items, field labels should be **bold**
3. **Be specific about navigation** — "Click **Clients** in the left sidebar" not "Go to the clients page"
4. **Explain the "why"** — Don't just say what a field does, explain why the user would use it
5. **Use tips and notes** — Call out important information with `> **Tip:**` or `> **Note:**`
6. **Use tables for reference data** — Statuses, permissions, field descriptions work well as tables
7. **Include all statuses and transitions** — If a record has statuses, document every status and how to move between them
8. **Cover error states** — What happens when something goes wrong? What should the user do?
9. **No technical jargon** — No mention of controllers, models, Turbo, Stimulus, database, API, class names, or file paths anywhere in the prose
10. **No screenshots** — Describe the UI in words; screenshots go stale quickly
11. **Date format** — Reference that dates display as MM/DD/YYYY
12. **Name roles precisely** — Always use the canonical role names when saying who can do what; "staff" or "some users" is an answer the assistant can't act on
13. **Don't punt to support** — Troubleshooting answers should resolve inside the app; where a fix needs elevated permissions, say "ask your admin" (or the specific role), not "contact support"
14. **Be dense, not padded** — The whole corpus rides along in the assistant's context. Every sentence should carry a fact. Cut throat-clearing, repeated overviews, and filler transitions; keep the scannable structure
15. **Never editorialize about the future** — No "coming soon," no "this may change," no describing planned behavior. Only what the code does today

## Phase 3: Update the Index

After writing the doc, update `docs/user_docs/0_USER_DOCS_INDEX.md`:

1. Change the feature's row from `Needs docs` to `[Documented](user_docs/{feature-name}.md)` (with `#anchor` for grouped rows). Match the existing link style in the index.
2. Update the **Summary** table counts at the bottom of the index.

The index is the assistant's table of contents for picking relevant docs — a row that still says "Needs docs" after the doc exists means the assistant may never find it.

## Phase 4: Review and Finalize

### Self-Review Checklist

Before finishing, verify:
- [ ] Frontmatter is present and complete: `title`, `audience`, `roles`, `keywords`, `summary`
- [ ] The TLDR reads as a complete, quotable short answer on its own
- [ ] Every claim in the doc traces to code you read this session — nothing carried over from old docs, nothing guessed
- [ ] Every action available in the UI is documented
- [ ] The permissions table covers **every** staff role, including explicit "No access" rows, using canonical role names
- [ ] No "No access" row for supervisor/clinical_supervisor where therapist has access (role implication rule)
- [ ] All statuses and transitions are explained
- [ ] Required vs optional fields are clearly marked
- [ ] Navigation paths are specific and accurate — AND verified reachable in the UI for every role the doc says can use them (not just Pundit-allowed)
- [ ] No technical/engineering jargon, class names, or file paths appear in the prose
- [ ] Common Questions are phrased as users would ask them, answered direct-first
- [ ] No "contact support" punts; no speculation about future behavior
- [ ] Related features are cross-referenced by doc filename
- [ ] The index row now links to this doc and the summary counts are updated

## Output

When complete:
1. Announce the document location and the index rows it satisfies
2. Summarize what the document covers
3. List any behaviors you found in the UI but could not fully confirm in code — these were **omitted** from the doc and need human verification before being added
