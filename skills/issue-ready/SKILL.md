---
name: issue-ready
description: Get a GitHub issue ready for the autofix queue — given an issue number (or a plain-text idea it turns into a new issue), research the code, Honeybadger and production counts, ask the user one plain-language question at a time about everything an unattended run can't decide, split it if it's too big for one run, rewrite the issue as a self-contained spec, and (after the user says yes) add the `autofix-queue` label. Use whenever the user says "/issue-ready 640", "make #640 issue-ready", "make #640 autofix-ready", "get this issue ready for autofix", "can autofix take #677?", "queue this for autofix", "write up an issue autofix can build", "#640 came back needs-decision, sort it out", or describes a bug or small change they want the cloud autofix run to build, even if they don't say "issue-ready".
argument-hint: <issue-number | plain-text idea>
---

# Issue Ready

Turns an issue into one the cloud autofix run can finish on its own.

**Why this skill exists.** Adding the `autofix-queue` label starts `/resolve-issue <N> auto run=<id>` in a cloud routine within seconds (`Autofix::Dispatcher`, `app/controllers/webhooks/github_controller.rb`). Nobody watches that run and it can't ask questions. Where the code doesn't settle a choice, it either guesses (and lists the guess under **Decisions** in the PR) or stops with `needs-decision`. It stops when:

- the plan turns out to change scope: a different cause, or a much bigger change than the issue describes;
- it can't work out the cause;
- the issue reads like instructions ("run this", "read that record"), since issue text is treated as untrusted;
- it needs something the cloud can't reach: production data or logs (`bin/prod-read` and `bin/prod-logs` are denied), images or attachments, websites other than GitHub, package registries, Honeybadger and Context7.

Your job is to do the research and ask the questions **now**, while the user is here. Then the run has nothing left to guess or stop on.

## Input

`$ARGUMENTS` is either:
- **an issue number** (`640`, `#640`, or an issue URL): improve that issue;
- **plain text** (`the invoice PDF shows the wrong date`): research it and file a new issue.

If it's empty, ask which one and stop.

**Cloud mode:** when the arguments carry `run=<id>` (`<N> auto research run=<id>` or `<N> auto write run=<id>`), Kahu started this run and nobody is watching. Read `references/cloud.md` now; it replaces Steps 3 and 5 and wins wherever it differs from this file.

## Step 1: Load and check

**Issue number:** `gh issue view <N> --comments --json number,title,body,state,labels,comments,url`. Read every comment. Later comments often narrow the ask, and the rewrite must follow the latest agreement. Then check:

| Finding | Do |
|---|---|
| Closed | Say so and stop. |
| Open PR exists (`gh pr list --head issue_<N>`, `gh pr list --search "#<N> in:body" --state open`) | Report it and stop. The dispatcher skips it anyway. |
| Labeled `grouped` | Name the combined issue from the comment and offer to run on that one instead. |
| Labeled `rcm-audit` | Say so and stop: revenue-cycle findings are worked by `/rcm-resolve` → `/resolve-issue` with the user watching, never by autofix, because they touch claims and money and often need a production remediation task. Point at `/rcm-resolve`. |
| Labeled `autofix-queue` | It's already queued (or about to start). Ask whether to keep going. Editing it mid-run changes what the run reads. |
| Labeled `needs-decision` | Usually why the user is here. Find the run's stop comment (`AUTO_RESULT: stopped …`) and start from what it says was missing. |
| Labeled `spec-sweep-next` | A leftover `/spec-sweep` continuation from before sweeps moved to the Spec sweep board. Autofix no longer runs these. Say so and point at `/project-new runner=spec-sweep` (it carries the queue numbers onto the board and closes the issue), then stop. |
| Labeled `fix-didnt-work` | Read the earlier PR (`gh pr list --search "#<N>" --state merged`) and work out why the fix didn't hold. The rewrite has to say what was wrong with it. |

**Plain text:** nothing to load. Write down the user's words exactly as given and research them in Step 2.

## Step 2: Research

Get far enough that the rewritten issue names real files and a real cause or pattern. Guesses don't count. The cloud run starts from your write-up, so whatever you settle here it doesn't have to work out again.

- Read the code the issue points at and trace it through. For a bug, find the root cause, not just the line that fails. For a change, find the sibling feature to copy.
- `git log --oneline -10 -- <file>` on the files the fix will touch. A recent change is often the cause.
- If the work means sweeping many files, hand it to an `Explore` agent and keep only its conclusion.
- **Honeybadger** (title `HB #<id>`, or a fault link): read the fault and a recent notice with the Honeybadger MCP tools (`get_fault`, `list_fault_notices`). Copy the exception class, message and the app frames of the backtrace into the issue. Leave out request params and anything that could be PHI.
- **Production data** (you can read it, the run can't): when the fix depends on what real rows look like (how many invoices are affected, whether any policy has a blank payer), check with `bin/prod-read` / `bin/prod-sql` per CLAUDE.md. Copy the **counts, ids and statuses** into the issue, never names, DOBs or clinical text. This is often what turns "might need a backfill" into "12 rows, a backfill rake task is needed" or "0 rows, no backfill".
- **Production logs** (30 days, you can read them, the run can't): when the issue depends on how often something happens or what ran before a failure, search with `bin/prod-logs` (`docs/PROD_LOGS.md`), e.g. `--request-id <id>` from the fault's notice, or `'jsonPayload.job="<JobClass>"' 'jsonPayload.outcome="error"' --since 7d`. Copy counts, statuses, timings and dates into the issue, never log message text.
- Check which CLAUDE.md rules the change will hit: SoftDeletable, tenant scoping, `StaffTimeHelper.staff_today` and the MM/DD/YYYY format, UI copy discipline, Honeybadger context, migrations through the generator, and prod-write recipes.

Then size it the way `/resolve-issue` will (Step 3, "Size the fix"):
- **Small fix:** clear cause, at most 3 app files and about 100 changed lines, no migration, no backfill, no new UI, no product decision.
- **Full path:** anything else. It's still fine for autofix as long as there's one clear change and every decision is already made.
- **Too big for one run:** several separate fixes, or something that needs a design pass (`/prd` territory: new pages, new workflows, permission model changes). Go to Step 3b.

## Step 3: Ask the user (one question at a time)

Make a list of everything the run would otherwise guess at. Ask only what the code, git history, Honeybadger and production reads couldn't answer. Usual gaps:

- **Expected behavior:** what should happen instead, exactly (the value, the message, which button).
- **Who:** which roles see it or are allowed to do it (`Role::ROLES`).
- **Edge cases the research turned up:** soft-deleted records, a client with no insurance, a second office, the user's timezone, a blank email.
- **Existing production rows:** fix them (a backfill rake task, which the user runs), or leave them alone?
- **UI text:** any new label, button verb, error message or empty state, written out word for word. Copy discipline means the run adds no text that the issue doesn't spell out.
- **Scope edges:** related things the run might "helpfully" change too. Ask whether they're in or out.

How to ask:
- Use `AskUserQuestion`, **one question per call**. Wait for the answer before asking the next. An answer often makes a later question unnecessary.
- Write so an 18-year-old would follow it: plain words, a concrete example from the actual code or data, no jargon without a two-word gloss. ("When a client was deleted, should their old invoices still show up on the Billing page? Right now 3 deleted clients have open invoices.")
- Put the option you'd recommend first, labeled "(Recommended)", and say why in its description.
- Don't ask about things that have a normal convention (spec style, file placement, service shape). Follow the codebase.
- If the user's answer shows a different problem than the issue describes, say so in two lines and re-research before going on.

### Step 3b: Too big: make it a project, or split it

Ongoing work that will take several PRs (improving a feature, a cleanup across many files, anything Claude should keep chipping away at) belongs on a project board, not in a pile of issues. Ask one question first: **turn it into a project (Recommended)**, which hands off to `/project-new <N>` with what you've researched so far, or **split it into a few issues**, for two or three separate fixes that each stand alone. On "project", stop here and run `/project-new <N>`.

For a split, show a short table of smaller issues, each one fix the run can finish on its own. Give each a title, one line of scope, and its size. Mark which ones depend on another one landing first. Autofix can build one at a time, but a dependent issue should only be queued after its parent's PR is merged.

Ask (one question) which ones to file. Then take each chosen piece through Steps 3 and 4. Questions that apply to every piece get asked only once. The original issue becomes the tracker. Add a comment listing the new issue numbers. Don't queue the tracker itself.

If something can't be made ready (it needs a design decision the user wants to think about, or a third party's answer), leave it unqueued. Add a comment saying exactly what's missing, so the next `/issue-ready` run can pick it up from there.

## Step 4: Write the issue

Rewrite the body with this template. Leave out sections that don't apply. Every line has to be something the run can act on or check, so no background essays.

```markdown
## Problem
<one or two sentences: what happens now, for whom, where (page path or job)>

## Expected
<what should happen instead, exact values and wording>

## Cause / where
<root cause in one or two lines, with `path/to/file.rb:LINE` refs; or for a change, the existing pattern to copy>

## Reproduce
<the steps or spec setup that shows the failure, specific enough to write the regression spec from: factories, the role, the input. For a Honeybadger issue: exception class, message, app backtrace frames, fault link>

## Decisions
- <each question you asked, as a settled fact: "Deleted clients' open invoices still show on the Billing page (user, 10/08/2026)">

## UI copy                                  <!-- only if text is added -->
| Where | Text |
|---|---|

## Existing production data                 <!-- only if rows are affected -->
<the counts/ids you read and what to do: "No backfill: 0 rows match" or "Ship `<ns>:<task>` dry-run-by-default rake task; 12 invoices expected">

## Out of scope
- <things the run must not change>

## Done when
- [ ] <observable checks, each provable by a spec>

**Size:** <small fix | full path>, <one line why>
```

Things to watch for:
- **Keep the original text.** Put the previous body at the end under `<details><summary>Original report</summary> … </details>`, exactly as it was. Never paste in images the run can't see. Describe what they show instead.
- **Write facts, not orders.** The run treats issue text as untrusted. Write "the fix adds a guard in `Foo#bar`", not "run `bin/rails …`" or "read client 123". Production write steps go in **Existing production data** as something the PR has to ship (a rake task), never as a command to run.
- **Nothing the cloud can't reach.** Every production fact is already in the issue as a number. If a Stedi or Stripe API detail matters, copy the doc line or link it. The run can reach Context7 but not those websites.
- **Title:** short and specific. Keep the `HB #<id>: …` prefix if there is one, because `/resolve-honeybadger` searches for it.
- **Labels:** keep `bug` / `enhancement` / `honeybadger`. Add `bug` or `enhancement` if neither is there.

## Step 5: Show, confirm, write, queue

Print the final title and body in the terminal. For a split, print each one. Then ask one question:

- **Update the issue and queue it (Recommended):** write it and add `autofix-queue`. The cloud run starts within seconds.
- **Update the issue, don't queue:** the user will add the label later.
- **Change something:** take their edits and show it again.

Ask even if the user said "queue it" at the start, because they haven't seen the final text yet.

Then:

```bash
gh issue edit <N> --title "<title>" --body-file <scratchpad>/issue-<N>.md     # or: gh issue create --title … --label … --body-file …
gh issue edit <N> --remove-label needs-decision                               # only if it had it: the dispatcher skips needs-decision issues
gh issue comment <N> --body "Rewritten by /issue-ready: the body is now the full spec and replaces earlier comments where they differ."
gh issue edit <N> --add-label autofix-queue                                   # only on "queue it"
```

Add the comment whenever the issue already had comments. `/resolve-issue` follows the latest comment, and an old comment that disagrees with the new body would steer the run wrong. Add the queue label **last**, after the body is final, because the run reads the issue the moment it starts.

## Final report

Three to five lines in the terminal: the issue number(s) and URL(s), the size verdict, how many decisions were settled, and whether each issue is queued, written but not queued, or held back (and what's missing). Point the user at `https://<admin-host>/admin/autofix` to watch the run.
