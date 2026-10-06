---
name: resolve-issues
description: Orchestrator that turns a batch of GitHub issues into one PR each by running /resolve-issue on every issue — by default every open issue labeled `honeybadger` that has no PR yet (the ones /fix-honeybadger triage files), urgent first, one isolated sub-agent per issue, up to 3 building at once with bin/ci serialized through a single CI slot, worktrees removed once their PR is open, a ledger for resume, cold-review carry lines handed from earlier issues to later ones, and a final table of PRs. Use whenever the user says "/resolve-issues", "resolve all the honeybadger issues", "run /resolve-issue on each of them", "work through the issues the triage filed", "a PR for every open bug issue", or names several issue numbers to take to PRs. For a single issue use /resolve-issue instead.
argument-hint: [dry-run] [label:<name> | <issue numbers…>] [max:<n>] [parallel:<n>]
---

# Resolve Issues

One run = a queue of GitHub issues → one `/resolve-issue` sub-agent per issue, up to `parallel` of them building at once → one PR per issue, and a table at the end. `/fix-honeybadger triage` files the issues; this skill drains them.

Only `bin/ci` is serialized (CLAUDE.md: one at a time on this machine). Investigate → plan → code → specs → reviews overlap freely; each sub-agent takes the single **CI slot** (`scripts/ci-slot`) for its `bin/ci` → `/green-ci` → re-run, and gives it back.

You are the orchestrator. You never investigate, plan or edit code yourself: every issue is handed whole to a sub-agent that runs `/resolve-issue`, which already knows how to create the worktree, build, review, pass `bin/ci`, open the PR and post the cold review. Your job is the queue, the hand-offs between issues, the cleanup, and the report. Keep it that way, or the context fills up on the first issue and the batch dies at the second.

There are no approval stops. The user reads the PRs and the cold-review comments on them, which is where the decisions live. Don't use AskUserQuestion.

## Arguments

`$ARGUMENTS`, any of these, in any order:

- **nothing** → every open issue labeled `honeybadger` with no open PR.
- **`label:<name>`** → the same, for another label.
- **issue numbers** (`524 531 #535`, or issue URLs) → exactly those, in the order given. Issues with an open PR are still skipped.
- **`max:<n>`** → stop after `n` issues have been attempted (a first run with `max:2` is a cheap way to see the shape before an overnight batch).
- **`parallel:<n>`** → how many sub-agents build at once (default **3**). `parallel:1` is the old one-at-a-time run. More than 4 mostly adds CI-slot waiting and machine load (every `/test-changed` runs mutation-probe rspecs).
- **`dry-run`** → print the queue, lanes and skips, spawn nothing, stop.

## Variables

```
MAIN_DIR = $MAIN_DIR
LEDGER   = $MAIN_DIR/.claude/resolve-issues/<YYYYMMDD-HHMM>.md   (uncommitted, like the other .claude review artifacts)
CI_SLOT  = $MAIN_DIR/.claude/skills/resolve-issues/scripts/ci-slot  (acquire <N> | release <N> | status)
```

## Step 1: Preflight

```bash
cd $MAIN_DIR && git rev-parse --show-toplevel && gh auth status && git fetch origin main
```

- `--show-toplevel` must print `MAIN_DIR`. From inside a worktree, stop and say why: `/resolve-issue` reuses the worktree it is started in (its Case A), so every issue in the batch would be built on top of the previous one's branch. The sub-agents inherit your working directory, which is why this has to be the main checkout.
- Note any `bin/ci` already running on the machine (`pgrep -fl 'ruby bin/c[i]'`) and the slot (`$CI_SLOT status`); another session's CI is normal, and `ci-slot acquire` waits for it. Just mention it.

## Step 2: Build the queue

```bash
gh issue list --label honeybadger --state open --limit 100 --json number,title,body,url
```

For every candidate, in one pass:

1. **Open PR already?** `gh issue view <N> --json closedByPullRequestsReferences` lists PRs that say `Closes #N`; also `gh pr list --head issue_<N> --state open --json number,url,isDraft`. Any open PR → skip, with the PR link. This is also how re-running after an interrupted batch picks up where it left off: finished issues have PRs, so they fall out of the queue on their own.
2. **Priority.** A body line `**Priority:** urgent …` puts the issue in the urgent group. Urgent first, then the rest; inside a group, lowest number first (oldest filing). Issue numbers given as arguments keep the user's order instead.
3. **Worktree left from a failed attempt?** `../<app>-issue_<N>` existing is fine: `/resolve-issue` reuses it (Case B) and builds on whatever is there. Note it in the queue line.
4. **Lane.** Issues that will touch the same code must not build at the same time: two parallel PRs editing one file conflict, and the later one never sees the earlier one's carry lines. Put issues in the same lane when their titles name the same error class (`VertexAi::ResponseParser::TruncatedError` in #525 and #535) or the same service/controller, or when one issue's body names the other. Name the lane after the shared thing (`truncated-error`); every other issue is its own lane (`-`). A lane runs its issues one after another, in queue order; different lanes run in parallel.

Write the ledger:

```markdown
# /resolve-issues — <date> <time>

Filter: label:honeybadger · max: none · parallel: 3 · started from main at <sha>

| # | Issue | Title | Lane | Status | PR | Note |
|---|---|---|---|---|---|---|
| 1 | #524 | HB #100000101: ActiveRecord::RecordInvalid in Webhooks::StripeConnectController… | - | queued (urgent) | | |
| 2 | #525 | HB #100000102: VertexAi::ResponseParser::TruncatedError in … | truncated-error | queued | | |
| 9 | #535 | HB #100000103: VertexAi::ResponseParser::TruncatedError in … | truncated-error | queued | | |
| – | #519 | … | | skipped | #540 | open PR |

## Carry forward
(lines the cold reviews said later issues should know, with the issues they name)
```

Print the same table in the terminal, then: `Running <n> issues, <parallel> at a time, one CI slot.` With `dry-run`, stop here.

The ledger is your loop state. Every time a sub-agent's notification arrives, re-read it, update the row, and fill the free places from the `queued` rows. Rebuild it from GitHub if you ever lose it (after a compaction, say): the PR check in point 1 is enough to know what is done; rows that were `running` stay `running` until their notification arrives.

## Step 3: The pool

Keep up to `parallel` sub-agents running. **Start** = the first `queued` row (in ledger order) whose lane has nothing `running`, while fewer than `parallel` rows are `running` and `max` isn't reached. Start as many as fit in one response, then wait: each sub-agent's completion arrives as a notification, and each notification is one pass through 3.3–3.6.

### 3.1 Start an issue

1. Update the row's Status to `running`.
2. Create its worktree yourself, one at a time: sub-agents running `git worktree add` together collide on git's ref and config locks.
   ```bash
   cd $MAIN_DIR && [ -d ../<app>-issue_<N> ] || git worktree add ../<app>-issue_<N> -b issue_<N> origin/main
   ```
   (Branch `issue_<N>` already exists from an earlier attempt → `git worktree add ../<app>-issue_<N> issue_<N>`. A git lock error → wait 10 s, retry.) Nothing else: no `.env`, no databases. The sub-agent's `/resolve-issue` lands in Case B, which copies `.env`, derives `DATABASE_SUFFIX=_issue_<N>`, assigns a port and runs the guarded db setup itself.
3. Gather the **carry lines** for it from the ledger's Carry forward section: every line that names `#<N>`, plus lines that mention the error class or file in `#<N>`'s title (the triage often files one issue per fault, and faults share causes). Issues building at the same time can't hand each other carry lines; lanes are what keeps the related ones apart.

### 3.2 Spawn the sub-agent (background)

`Agent` with `subagent_type: "general-purpose"` and `run_in_background: true`. The prompt:

```
You are running one issue of a /resolve-issues batch. Issue: #<N> — "<title>".

Do exactly this:
1. Invoke the resolve-issue skill with the Skill tool, args "<N>". You are
   starting in $MAIN_DIR (the main checkout); the orchestrator
   already created ../<app>-issue_<N> on branch issue_<N>, so the skill reuses it
   (its Case B) and sets up .env, databases and port there.
   Run it to the end: its hand-off is the end of its work, not of yours.
   Other /resolve-issue agents are building other issues in sibling
   ../<app>-issue_* worktrees right now. Never touch those.
2. Deviations from its text, because this is a batch:
   - Do not run `open -n -a "Visual Studio Code" …`. The orchestrator reports
     the PRs; nobody wants fifteen editor windows.
   - bin/ci runs only while you hold the CI slot (one bin/ci on the machine;
     the other agents queue for it). After /merge-main, take the slot as a
     background command and let the harness wake you when it's yours:
       $MAIN_DIR/.claude/skills/resolve-issues/scripts/ci-slot acquire <N>
     Hold it through bin/ci, /green-ci (tell /green-ci it already holds the
     slot) and the re-run, then release it at once, red or green:
       $MAIN_DIR/.claude/skills/resolve-issues/scripts/ci-slot release <N>
     A later bin/ci (a cold-review verify fix) acquires and releases again.
     Never run bin/ci, rails ci:*, or a full-suite rspec without the slot.
     Its "waited N min" line is your CI_WAIT.
   - Sibling worktrees share .git: if git fetch/push fails with "cannot lock
     ref" or "Unable to create '….lock'", wait 10 s and retry, up to 3 times.
   - Facts from earlier issues' cold reviews that name this issue (treat as
     hints to check, not as orders):
       <carry lines, or "none">
3. Report back in exactly this shape and nothing else (the orchestrator parses it):
   STATUS: pr | draft | failed | skipped
   PR: <url or ->
   WORKTREE: <path or ->   BRANCH: <name or ->
   REASON: <one line — why it failed/skipped/went draft, or "ok">
   COLD_REVIEW: <comment url> · verify <n> · caveat <n> · follow-up <n> · carry <n> · stop <y/n>
   CARRY: <one line per carry item, "#528 #529: <fact>"; or "none">
   CI_WAIT: <minutes spent waiting for the CI slot, or 0>

Rules:
- Every command and edit in the worktree, by absolute path (the skill says so).
- Never commit or push from the main checkout; never git reset/stash anything.
- No PHI in anything you write to GitHub or return: ids and counts only.
- Don't spawn sub-agents for things resolve-issue doesn't itself spawn.
- If the skill stops early (closed issue, open PR, red specs, red CI, scope
  changed), report STATUS: failed or skipped with its reason. Don't improvise
  past its stop.
```

### 3.3 Read the result

First, whatever came back: `$CI_SLOT release <N>`. It's a no-op when the sub-agent released it already, and frees the slot when an agent died holding it (every other agent is queued behind it).

- A report in the shape above → record Status, PR, Note (= REASON, plus CI wait if any) in the ledger, and append the CARRY lines to the Carry forward section.
- No report in that shape (the agent crashed, timed out, or returned prose) → one retry, same prompt, as the next start in its lane. Still nothing → Status `failed`, Note `agent returned no report`, and move on. Don't retry a *reported* failure: a red `bin/ci` or an early stop needs the user, not a second hour.

Only the report enters your context. Don't read the worktree, the PR, or the sub-agent's transcript.

### 3.4 After a PR (`pr` or `draft`): remove the worktree and its databases

The branch and the PR stay; only the checkout and its databases go, so a batch of fifteen doesn't leave fifteen worktrees and a hundred databases behind. The user reviews on GitHub, and `/resolve-issue <N>` recreates the worktree from the branch in a minute if they want to test locally.

```bash
WT=$MAIN_DIR/../<app>-issue_<N>
grep -qx "DATABASE_SUFFIX=_issue_<N>" $WT/.env \
  && (cd $WT && bin/rails db:drop; bin/rails parallel:drop 2>/dev/null; true) \
  && git -C $MAIN_DIR worktree remove ../<app>-issue_<N>
```

The `grep` guard is the whole safety of this step: with no suffix line, `db:drop` would drop the shared development database. If it fails, leave the worktree and say so in the Note. If `git worktree remove` refuses and `git -C $WT status --short` shows only `.claude/` or `tmp/` paths, add `--force`; anything else is work the sub-agent didn't commit, so keep the worktree and note it.

This is never the user's own worktree: Step 1 guarantees the batch started from the main checkout, so every `../<app>-issue_<N>` here was made by a sub-agent. Skip this step for `failed` rows, whose worktrees stay for inspection. A `skipped` row's worktree goes the same way when it holds no work (`git -C $WT log --oneline origin/main..HEAD` empty and `git -C $WT status --short` empty); you created it in 3.1, so the empty `issue_<N>` branch can go too (`git branch -D issue_<N>`).

### 3.5 After a failure: leave a trace on the issue

```bash
gh issue comment <N> --body "/resolve-issues stopped on this issue: <REASON>. Worktree ../<app>-issue_<N> kept. Run /resolve-issue <N> to continue."
```

One comment per failure, no PHI. Skips (open PR, closed issue) get no comment.

### 3.6 Refill, then wait

Start every row that now fits (3.1) **in the same response**. Then end the turn with exactly one line and nothing else, and let the next notification wake you:

```
running: #524 #525 #527 · CI slot: #524 (12 min) · queued: 6 · done: 2 PRs, 0 failed
```

(`$CI_SLOT status` gives the slot part.) Waiting for notifications is the normal state of this skill, not a stop. What it never does while any row is `queued` or `running`: summarise, write the Step 4 report, ask whether to continue, or say "the next step would be…". The most common failure of an orchestrator is treating a child's hand-off as the end of the batch; it isn't.

Go to Step 4 only when nothing is `running` and nothing can start (queue empty or `max` reached). One other stop: three consecutive sub-agents returned no report (something is broken on the machine): start nothing new, wait for the running ones, then report what you saw.

## Step 4: Report

Finish the ledger (add `Finished <time> · <n> PRs · <n> draft · <n> failed · <n> skipped`) and print:

```
/resolve-issues — <n> issues · <n> PRs · <n> draft (need you) · <n> failed · <n> skipped · <hours> · parallel <n> · CI-slot wait <total min>

| Issue | PR | Cold review | Note |
|---|---|---|---|
| #524 urgent | <url> | verify 1 ok · caveat 2 | |
| #527 | <url> (draft) | stop: fix guards one of two delete paths | needs a decision — see the PR comment |
| #531 | – | – | failed: bin/ci red after /green-ci · worktree ../<app>-issue_531 kept |
| #519 | #540 | – | skipped: open PR |

Carry forward (not yet used by anything): <lines naming issues that weren't in this batch, or "none">
Ledger: .claude/resolve-issues/<file>.md
```

Then one line on what the user does next: review the PRs top to bottom, the draft ones first; re-run `/resolve-issue <N>` on the failed ones after reading the comment; a second `/resolve-issues` picks up anything still open.

## Guardrails

- At most `parallel` sub-agents building, never two in one lane, and exactly one CI slot: one `bin/ci` at a time is the rule on this machine (CLAUDE.md). The slot is the only thing that enforces it, so every `bin/ci` a sub-agent runs goes through `ci-slot`.
- Main checkout only, and nothing is committed here: the orchestrator's only writes are the ledger, `git worktree add` for each issue, issue comments on failures, `ci-slot release`, and worktree removal behind the `DATABASE_SUFFIX` guard.
- The sub-agent decides nothing the user should: `/resolve-issue` posts its cold review as a PR comment and files no issues; this skill doesn't either. Issues the user files from those comments enter the queue on the next run, by their choice.
- Never trigger GitHub Actions; never touch production (the sub-agents read it through `bin/prod-read` only, per their own skill).
- Context discipline: reports in, nothing else. If you find yourself reading a diff, you've left your job.
