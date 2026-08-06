---
description: Generate a user-facing handbook document explaining how a feature works
argument-hint: <feature-name-or-description>
---

# User Documentation Generator

You are tasked with creating a comprehensive, user-friendly handbook document that explains how a feature works in the application. This document is for **end users** (e.g., staff, coordinators, admins, managers) — NOT engineers or technical people.

## Input

$ARGUMENTS

**An argument is required.** The argument describes the feature to document. It can be:
- A feature name (e.g., "billing", "client messaging", "supervision queue")
- A brief description of the feature area
- A path to a specific area of the app (e.g., "staff/appointments")

## Phase 1: Deep Feature Exploration

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
2. **Every page/screen** in the feature with its URL pattern
3. **All actions** a user can take (create, edit, delete, filter, search, export, etc.)
4. **All statuses/states** and how records transition between them
5. **Form fields** — what's required, what's optional, what validations exist
6. **Notifications** — emails, alerts, or messages triggered by actions
7. **Settings/Configuration** — any configurable aspects of the feature
8. **Integrations** — connections to other features or external services
9. **Turbo/Dynamic behavior** — real-time updates, inline editing, modals

### Step 3: Understand Permissions

Read the Pundit policies to build a complete authorization matrix:
- Which roles can view, create, edit, delete
- Any conditional permissions (e.g., "therapists can only edit their own records")
- Admin-only settings or actions

## Phase 2: Write the Document

### Step 4: Generate the Handbook Document

Create the document at: `docs/user_docs/{feature-name}.md`

Use kebab-case for the filename (e.g., `client-messaging.md`, `insurance-billing.md`).

Write in **plain, friendly language**. Assume the reader:
- Has no technical background
- Is learning the feature for the first time
- Needs to know what they can do, how to do it, and what to expect

### Document Structure

Follow this template:

```markdown
# [Feature Name]

[2-3 sentence overview of what this feature does and why it's useful.]

---

## Table of Contents

1. [Section 1](#section-1)
2. [Section 2](#section-2)
...

---

## Getting Started

[How to access this feature — where to click, what menu to use, what URL to visit.]

### Who Can Use This Feature

| Role | Access Level |
|------|-------------|
| Admin | [What admins can do] |
| Therapist | [What therapists can do] |
| Coordinator | [What coordinators can do] |
| ... | ... |

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

## Common Tasks

### How to [Common Task 1]

[Brief step-by-step]

### How to [Common Task 2]

[Brief step-by-step]

---

## Frequently Asked Questions

### [Question a user might ask]

[Clear, direct answer]

### [Another question]

[Clear, direct answer]

---

## Troubleshooting

### [Common issue]

**Problem:** [What the user sees]
**Solution:** [What to do about it]

---

## Related Features

- **[Related Feature 1]** — [How it connects to this feature]
- **[Related Feature 2]** — [How it connects to this feature]
```

## Writing Guidelines

1. **Use "you" language** — "You can create a new client by..." not "The user creates a new client by..."
2. **Bold UI elements** — Button names, menu items, field labels should be **bold**
3. **Be specific about navigation** — "Click **Clients** in the left sidebar" not "Go to the clients page"
4. **Explain the "why"** — Don't just say what a field does, explain why the user would use it
5. **Use tips and notes** — Call out important information with `> **Tip:**` or `> **Note:**`
6. **Use tables for reference data** — Statuses, permissions, field descriptions work well as tables
7. **Include all statuses and transitions** — If a record has statuses, document every status and how to move between them
8. **Cover error states** — What happens when something goes wrong? What should the user do?
9. **No technical jargon** — No mention of controllers, models, Turbo, Stimulus, database, API, etc.
10. **No screenshots** — Describe the UI in words; screenshots go stale quickly
11. **Date format** — Reference that dates display as MM/DD/YYYY
12. **Permissions are important** — Always document who can and cannot do things
13. **Keep it scannable** — Users skim documentation. Use headers, lists, and tables liberally

## Phase 3: Review and Finalize

### Step 5: Self-Review Checklist

Before finishing, verify:
- [ ] Every action available in the UI is documented
- [ ] All user roles and their permissions are covered
- [ ] All statuses and transitions are explained
- [ ] Required vs optional fields are clearly marked
- [ ] Navigation paths are specific and accurate
- [ ] No technical/engineering jargon is used
- [ ] The document reads naturally for a non-technical person
- [ ] FAQ section addresses likely user questions
- [ ] Related features are cross-referenced

## Output

When complete:
1. Announce the document location
2. Summarize what the document covers
3. List any areas where the feature behavior was unclear from the code and may need verification
