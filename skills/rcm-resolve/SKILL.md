---
name: rcm-resolve
description: Work the open /rcm-audit findings in money order. Read-only orchestrator that collects every open GitHub issue labelled rcm-audit (plus Filed/queued rows in the audit ledger) that nobody is building yet, re-runs each issue's saved "Money at stake" probe against production through bin/prod-read so the ranking uses today's counts and dollars, ranks by severity then dollars then deadline risk, shows one short table, asks one question, and hands the chosen issues to /resolve-issue or /resolve-issues (which do the worktree, PR and review). Writes the PR link back to the ledger. Use whenever the user says "/rcm-resolve", "fix the rcm findings", "work the RCM backlog", "resolve the most important billing issues", "which billing bug costs the most right now", "what's open from the billing audit", or wants the open revenue-cycle findings ranked, prioritised or fixed, even if they don't say "rcm" or "audit".
argument-hint: "[dry-run]"
---

# RCM resolve

One run = every open `/rcm-audit` finding, re-sized from live production, ranked, and the top one (or the ones the user picks) handed to `/resolve-issue`.

`/rcm-audit` finds and files; this skill prioritises and dispatches; `/resolve-issue` builds. Keeping those apart is what makes each one short: this skill reads code and production, writes nothing but the audit ledger, and never files, closes or labels an issue. Fixes go through `/resolve-issue`, and production writes stay user-run per `CLAUDE.md`.

Shared pieces live elsewhere and are referenced, not copied: the ledger (`tmp/rcm-audit/ledger.md` in the main checkout; format and P0–P3 scale in `.claude/skills/rcm-audit/SKILL.md`), the skip rules (`/resolve-issues` Step 2) and the build chain (`/resolve-issue`).

`$ARGUMENTS`: `dry-run` prints the table and stops before the question. Useful for a quick "what's open and what does it cost today" without committing to a build.

## Step 1: Preflight

Main checkout on `main`: `git rev-parse --show-toplevel` must print `$MAIN_DIR`. Production probes run the local code against production data, so a worktree or feature branch can give misleading numbers. If `main` is clean, `git pull --ff-only`; otherwise say which branch you are on and why the numbers may differ, and carry on.

## Step 2: Collect the open findings

```bash
gh issue list --label rcm-audit --state open --limit 100 --json number,title,body,labels,createdAt,url
```

Drop, with the same rules as `/resolve-issues` Step 2, so the two skills never build the same issue:

| Drop when | Why |
|---|---|
| Label `autofix` or `autofix-queue` | The autofix dispatcher owns it. |
| Label `grouped` | Folded into a combined issue. |
| `gh issue view <N> --json closedByPullRequestsReferences` lists a PR, or `gh pr list --head issue_<N> --state open` finds one | Already being built; keep the PR link for the summary. |
| `gh pr list --head issue_<N> --state merged` finds a PR | The fix shipped but never linked the issue, so it stayed open. Keep it in the table, flagged `fix merged (PR #M) — close?`, sorted with the zero-money rows. |

The traffic only runs one way: `/next-issues` and `/issue-ready` skip the `rcm-audit` label, so these findings never enter autofix unless the user labels one by hand.

Then read the ledger's Findings table and join it to the issues by number:

- A `Filed` row whose issue is still open is the same item. Take its area, key and **severity** from the row: filed issues don't carry a P-level in their body, so the ledger is where severity lives. An issue with no ledger row and no `P0`–`P2` in its body counts as P2 and gets a `sev assumed` mark in the table.
- A `queued` row has no issue yet. List it at the bottom of the table as "not filed, `/rcm-audit` files it" and never hand it off: `/resolve-issue` needs an issue number, and filing is the audit's job (it knows how to write a body a build can run from).

Nothing left → print `No open rcm-audit findings.` and stop.

## Step 3: Re-size each one in production

Every filed issue has a `## Money at stake` section with the probe that sized it. Re-run it, because the number that matters is today's: a finding filed at $185 may have grown to $900, and one that now measures zero has probably been fixed by a merged PR or by hand.

- A fenced ` ```ruby ` block → write it to the scratchpad and `bin/prod-read < <file>`.
- A fenced ` ```sql ` block → `bin/prod-sql -c "<query>"`.
- No block, or the probe errors → keep the filed numbers and mark the row `no probe` / `probe failed`. Don't rewrite the probe here; its shape belongs to `/rcm-audit` Step 7.

Record count and dollars now beside the filed count and dollars from the issue text. Print counts, dollars, statuses and record ids only, never names, DOBs or clinical text: everything the probe prints enters the conversation. If the connection fails, ask the user to turn on the WireGuard tunnel and stop; don't try other routes.

## Step 4: Rank

Order, top first:

1. **Severity** P0 → P1 → P2.
2. **Dollars now**, largest first.
3. **Deadline risk**: the nearest date-bound item the issue names (days since DOS against the payer's timely-filing limit, an appeal window, a card retry window). Nothing named → last within its group.

A finding whose probe now returns zero, or whose fix PR is already merged, goes to the bottom whatever its severity, flagged `may already be fixed — close?` / `fix merged (PR #M) — close?`. Closing is the user's call: a zero can also mean the probe no longer matches the data, and a merged fix can leave a work queue behind (#859's fix shipped, but five rejected claims still waited for someone to press Resubmit).

## Step 5: Show the table, ask one question

```
| # | Issue | Sev | $ now | $ filed | Deadline | Problem |
|---|-------|-----|-------|---------|----------|---------|
| 1 | #912 Reversals posted as payments | P1 | $1,240 / 9 | $900 / 6 | — | payer take-backs recorded as new money |
| 2 | #920 Denied claims never rebilled | P2 (sev assumed) | $610 / 4 | $610 / 4 | 11/30/2026 appeal | nobody owns a denial after 30 days |
| 3 | #905 Copay 0 on insured sessions | P2 | $0 / 0 | $240 / 8 | — | may already be fixed — close? |
| – | (queued) era-virtual-card-uncharged | P2 | — | $380 / 2 | — | not filed, /rcm-audit files it |
```

One line per finding: dollars as `$X / N` (amount / record count), dates `MM/DD/YYYY`, deadline as the date plus a word for what it is, and the problem in a few plain words. `dry-run` stops here.

Then one AskUserQuestion:

| Option | Meaning |
|---|---|
| Resolve the top one | `/resolve-issue` on rank 1 |
| Pick others | The user types issue numbers; several go to `/resolve-issues` |
| Stop | End here, nothing handed off |

## Step 6: Hand off

- One issue → invoke `/resolve-issue <N>` with the Skill tool.
- Several → invoke `/resolve-issues <N1> <N2> …` with the Skill tool.

They create their own worktrees, build, review, pass `bin/ci` and open the PR; this skill re-implements none of it, so when a child reaches its own final report that is the end of its step, not a reason to take over. Take the PR link from that report: `/resolve-issue` ends with `AUTO_RESULT: pr <url>` (or `AUTO_RESULT: stopped <reason>`); `/resolve-issues` ends with a table of issue → PR.

## Step 7: Update the ledger and summarise

For each issue handed off, put `#N / PR #M` in the row's `Issue / PR` column of `tmp/rcm-audit/ledger.md` (add a row with today's date if the issue has none). A stopped run gets `#N / stopped: <reason>`. While there, give any `Filed` row whose issue is now closed its closing PR (`closedByPullRequestsReferences`), so the ledger stops saying a finding is open when GitHub says it isn't. The next `/rcm-audit` run reads this to know the finding is handled, and the next `/rcm-resolve` run drops it because it has a PR.

Print three lines and nothing else: what was handed off and its PR links; what stopped and why; what is still open (`k findings, top: #N $X`). When the child's report says `Next: /settle-pr-review <PR>`, repeat that line.

## Guardrails

- Reads only: code, `gh`, `bin/prod-read` / `bin/prod-sql`. The ledger is the only file this skill writes; it never commits.
- Never writes to production, never proposes `fly ssh console` for a read.
- Never files issues, never adds `autofix-queue`, never closes an issue: "may already be fixed" is a flag for the user.
- Never triggers GitHub Actions.
