---
name: issues-ready
description: Batch version of /issue-ready — take the top issues from the /next-issues report just printed in this conversation (up to 10), research them all in parallel, ask the user only the questions an unattended run can't settle (one at a time, plain language), fold issues that touch the same files into one, rewrite each as a self-contained spec, and after one final yes add `autofix-queue` to all of them in rank order. Use whenever the user says "/issues-ready", "queue the next 10", "get these all autofix-ready", "issue-ready the whole list", "enqueue everything next-issues found", or runs it right after /next-issues, even if they don't say "issues-ready". For one issue use /issue-ready; for building issues locally use /resolve-issues.
argument-hint: [dry-run] [max:<n>] [<issue numbers…>]
---

# Issues Ready

One run = the top of the `/next-issues` list → each issue researched by its own agent → the user answers only what nothing else can decide → every issue rewritten and queued for autofix.

The goal is the least work for the user: they answer a short run of questions and say yes once. Everything else (research, drafting, deduping questions, writing to GitHub) happens without them.

**Read `.claude/skills/issue-ready/SKILL.md` first.** Its rules (why the run can't guess, what to research, the issue template, the "write facts, not orders" and "nothing the cloud can't reach" checks, the GitHub write commands) apply to every issue here unchanged. This skill only changes how many run at once and when the user is asked.

## Input

`$ARGUMENTS` (all optional):
- issue numbers: use exactly these, in this order.
- `max:<n>`: batch size, default 10, never more than 10.
- `dry-run`: do everything except write to GitHub; print what would be written.

With no numbers, take the issues from the `/next-issues` report earlier in this conversation: its last line (`Order: …`, or `/issue-ready <N>` commands in older reports) lists the issues in rank order, so use that order (it can differ from the table's when the report moved a security or money bug up). Take the first `max` of them. Leave out anything the report put under "Already done", "Blocked" or "Not autofix work". If there is no `/next-issues` report in the conversation, say "run /next-issues first, or pass issue numbers" and stop.

## Step 1: Load and check (all at once)

Run `/issue-ready` Step 1's checks for every issue in one go (parallel `gh issue view <N> --comments` and `gh pr list --head issue_<N>` calls). Drop closed, has-a-PR, `rcm-audit`, `grouped` and `spec-sweep-next` (leftover sweep continuations: sweeps run from the Spec sweep board now) issues with a one-line reason each, and refill the batch from the next ones in the list so it stays at `max`. Never pick a `spec-sweep-next` issue, even when its number was passed in.

## Step 2: Research in parallel

Spawn one `general-purpose` agent per remaining issue, **all in one message** so they run together. Each gets this brief, with the placeholders filled in:

```
Research GitHub issue #<N> (<title>) so a cloud autofix run can build it unattended.
Follow Steps 2 and 4 of $MAIN_DIR/.claude/skills/issue-ready/SKILL.md, and the repo's CLAUDE.md rules.
Do NOT ask the user anything, and do NOT write to GitHub (no gh issue edit/comment/label).
Write the rewritten issue body (Step 4 template, original body kept under <details>) to <scratchpad>/issues-ready/issue-<N>.md.
Where a decision is still open, write "Decision pending: Q<k>" in the Decisions section.

Only raise a question when the code, git history, Honeybadger, production reads and the CLAUDE.md
rules all leave it open AND a wrong guess would change what ships. If a house rule already decides
it (MM/DD/YYYY dates, theme colors, jobs raise on a failed Result, no new UI copy), settle it in
Decisions with the rule as the source and don't ask. A needs-decision issue's own question always counts.

Reply with only this JSON:
{"number": N, "title": "<new title>", "size": "small|full|too-big",
 "files": ["app/... files the fix will change"],
 "questions": [{"id": "Q1", "question": "<plain words, a real example from the code or data>",
   "options": [{"label": "...", "description": "..."}], "recommended": 0}],
 "hold": "<empty, or why this can't be made ready now>"}
```

Wait for every agent. Keep only their JSON; the drafts are on disk.

## Step 3: Shape the batch

- **Too big** (`size: too-big`): leave it out of this batch and tell the user to run `/project-new <N>` on it (ongoing work, several PRs) or `/issue-ready <N>` to split it into a few issues. Don't split here: a split needs its own conversation.
- **Hold** (`hold` set): leave it out, and in Step 5 post the comment `/issue-ready` Step 3b describes, saying what's missing.
- **Overlapping files**: autofix runs up to 3 issues at once (`Autofix::Dispatcher::MAX_RUNNING`), each from `main`, so two issues that change the same file come back as conflicting PRs. When two or more issues in the batch share a file in `files`, ask one question proposing to fold them into one combined issue, recommended. On yes, write one combined body (`## Part 1: <name> (was #<a>)`, `## Part 2: …`, as in `.claude/skills/group-issues/SKILL.md` Step 4), file it as a new issue in Step 5, and label the originals `grouped` with a comment pointing at it. On no, queue them anyway; the conflict is settled at merge time.

Don't refill the batch for issues left out here; say how many were left out instead.

## Step 4: Ask, one question at a time

Gather every agent's questions. Merge duplicates: the same question raised for several issues (same component, same rule) is asked once, and the answer goes into each of them. Then go in rank order:

- One `AskUserQuestion` call per question, one question per call, wait for the answer before the next. Start the question text with the issue, e.g. `#1023 (Charge button label): …`, and use `#1023` as the header.
- Use the agent's options with its recommended one first, labeled "(Recommended)". Keep its plain-language example: the user should be able to answer without opening the code.
- After each answer, replace `Decision pending: Q<k>` in that issue's draft with the settled fact (`<fact> (user, MM/DD/YYYY)`). Drop any later question the answer made moot.
- If an answer shows the issue is a different problem than researched, send it back to its agent (`SendMessage`) with the answer and wait for the new draft and questions; if it now needs a design pass, move it to held-back.
- An issue with no questions isn't mentioned in this step.

Before going on, `grep -l "Decision pending" <scratchpad>/issues-ready/*.md` must find nothing for any issue still in the batch.

## Step 5: One confirmation, then write and queue

Print a compact table, one row per issue to queue (combined issues as one row):

```
| Rank | Issue | New title | Size | Decisions | Draft |
|------|-------|-----------|------|-----------|-------|
| 1 | #1023 | Charge button label is cut off on long client names | small | 1 | /full/path/issue-1023.md |
```

Below it, list held-back and too-big issues with one reason each. Then one `AskUserQuestion`:

- **Write and queue all of them (Recommended):** every issue's cloud run starts as dispatch slots free up.
- **Write all, queue none:** the user adds the labels later.
- **Let me change some first:** ask which issue numbers, show those drafts in full, take the edits, then come back to this question.

Then, per issue in rank order, run `/issue-ready` Step 5's commands (edit title and body from the draft file, remove `needs-decision` if present, add the "Rewritten by /issue-ready" comment if it had comments, `autofix-queue` last). Finish every write for one issue before labeling it, and label in rank order: the dispatcher starts the oldest queued issue first, so this order is the build order. In `dry-run`, print the commands instead of running them.

If a `gh` call fails, stop labeling, and report which issues were queued and which weren't, so a rerun with those numbers picks up the rest.

## Final report

```
Queued <K>: #1023, #1024, … (build order)  ·  written, not queued <W>  ·  held back <H>  ·  too big <B>
```

Then one line per held-back or too-big issue with what it needs (`/issue-ready 944`: needs a split). End with: watch the runs at `https://<admin-host>/admin/autofix`.
