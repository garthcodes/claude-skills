---
name: rcm-audit
description: Audit the practice's revenue cycle — sessions, eligibility, claims, ERAs, invoices and Stripe collection — for weaknesses or bugs that make the practice get paid late or not at all. Starts from a read-only production health snapshot, picks the stage where money is sitting (or the one audited least recently), digs through the code with /stedi-billing-expert's billing discipline, proves the problem with production counts and dollars, and brings ONE finding to the user in the terminal to decide: fix now (/resolve-issue), file a GitHub issue, or skip. Remembers every decision so nothing is raised twice, then offers the next finding. Use whenever the user says "/rcm-audit", "audit the revenue cycle", "audit billing", "find billing bugs", "why aren't we getting paid", "where are we leaking money", "check claims / invoices / ERAs for problems", "RCM review", or asks what's slowing down payment, even if they don't say "audit".
---

# Revenue-cycle audit

One run = find the most expensive weakness in how the practice gets paid, prove it is real, show it to the user in about 30 seconds of reading, and do what they decide. Then offer the next one.

The audit itself is **read-only**: it reads code and reads production through `bin/prod-read` / `bin/prod-sql`. It never edits code (fixes go through `/resolve-issue`) and never writes to production. The user's billing team acts on what you raise, so a false alarm costs real trust — a finding is only raised once it is verified.

## Files in this skill

| File | Use |
|---|---|
| `references/audit-areas.md` | The ten stages A1–A10: the money question, code paths, typical leaks, prod probes. Read the section for the area you pick. |
| `scripts/rcm_snapshot.rb` | Read-only production snapshot: counts, dollars and ages per stage, tagged with area codes. |

The ledger lives at `tmp/rcm-audit/ledger.md` **in the main checkout** (gitignored, so it survives across runs without dirtying git). Filed and fixed findings are also GitHub issues labelled `rcm-audit`, which is the durable record.

## Step 1 — Get oriented (2 minutes)

1. Work from the main checkout on `main`. Production reads run the local code, so a stale or feature branch gives misleading results: `git fetch origin main`; if on a clean `main`, `git pull --ff-only`; otherwise tell the user what branch you're on and why the numbers may differ.
2. Read the ledger (create it from the template at the bottom of this file if missing) and `gh issue list --label rcm-audit --state all --limit 200 --json number,title,state,stateReason`. Anything there is already decided: don't raise it again unless the money at stake has at least doubled since — then raise it as "it got worse", quoting both numbers.
3. Skim the memory index (`MEMORY.md`) for billing context that explains numbers which look alarming but are known (for example, ERAs for some claims still land in the legacy system — `/legacy-claim-status` handles those, so `accepted` claims that "never get paid" may not be an application bug).

## Step 2 — Snapshot production

```bash
bin/prod-read < .claude/skills/rcm-audit/scripts/rcm_snapshot.rb
```

If the connection fails, ask the user to turn on the WireGuard tunnel — don't try other routes. Show the user only the non-zero lines, as a compact table (area, metric, value). This takes a few lines and tells them where money is sitting right now.

The snapshot shows *symptoms*; the finding is the *cause*. A large number is a lead, not a finding.

## Step 3 — Pick one area

In order of preference:

1. **The user named one** ("check ERA posting") → use it.
2. **A snapshot signal the ledger doesn't explain** — the biggest dollar amount or oldest age that no prior finding or known situation covers.
3. **Rotation** — the area with the oldest "last audited" date in the ledger (never-audited areas first).

Say which area and why in one line.

## Step 4 — Hunt

Read `references/audit-areas.md` for the area. For A2–A7 (anything Stedi touches), invoke `/stedi-billing-expert` with the Skill tool and follow its Review-mode discipline: its P0–P3 severity scale, its revenue-critical checklist, and verifying payload and field assumptions against Stedi's live docs rather than memory. Its severity scale is the one this audit uses for every area.

Trace the money path end to end, the way a dollar travels: the trigger (a session ending, a webhook, a scheduled job) → services → models and state transitions → the screen or alert where a human would notice if it went wrong. Billing bugs live at the seams between those steps. Questions that find them:

- Where does this path **return early, rescue, or skip** — and does that skip reach a human (a failure record, a task, a work queue, an alert someone actually receives)?
- Which **statuses or types are excluded** from a scope, a job, an alert or a report? Is any real case left with no owner?
- What happens on the **second run** (job retry, duplicate webhook, duplicate 835)? Double money or lost money?
- Is there a **time limit** (filing limit, appeal deadline, card retry window) that can pass while the item waits?
- Is money math in **integer cents** throughout, and do the signs (reversals, refunds, credits) survive?

Use production to test a suspicion as soon as you have one — it is the fastest way to tell a real leak from a theoretical one. Write a short probe to the scratchpad and run it with `bin/prod-read < <file>` (or `bin/prod-sql -c "…"`). Wrap model queries in `ActsAsTenant.with_tenant(org)` per organization. Print counts, dollar sums, ages, statuses and record ids only — never names, DOBs, emails or clinical text, since output enters the conversation.

For a large area you may run up to three Explore agents in parallel to trace separate sub-paths; keep the judgment and the verification yourself.

If an area turns up nothing worth raising after an honest look, record it as clean in the ledger and move to the next area by Step 3's order. After three clean areas in one run, tell the user plainly that nothing material turned up, show what was checked, and stop — don't lower the bar to manufacture a finding.

## Step 5 — Verify before raising

A finding is raised only when all of these hold:

1. **The path is traced end to end**, including any backstop: another job, sweep, or work queue that would catch the item later. A gap that a nightly sweep closes is at most P3.
2. **It isn't already known**: not in the ledger, not an open `rcm-audit` or `bug` issue (`gh issue list --search "<key words>"`), not an open PR (`gh pr list --search "<key words>"`).
3. **It is sized**: a production probe shows how many records and dollars it affects now, or — if nothing is affected yet — the concrete scenario that would trigger it and how often that scenario occurs.
4. **Severity is P0–P2.** P3 hygiene goes in the ledger's notes, not to the user.

Label confidence honestly: **Confirmed** (production rows show it happening, or the code path is unambiguous and has no backstop) or **Likely** (strong code evidence, not yet observed). Never present Likely as Confirmed.

If several findings survive, raise the most expensive one and note the others in the ledger as `queued` so the next round starts there.

## Step 6 — Bring it to the user

Print the finding card — about 15 lines, readable in 30 seconds, plain language, no jargon without a few words of explanation:

```
━━ RCM finding · P1 · A6 ERA posting ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Payer reversals are posted as new payments

Money at stake  $1,240 across 9 claims since 08/01/2026 (production)
What happens    A payer pays $150 on a 90837, then takes it back in the
                next remittance. The application records +$150 again instead of -$150,
                so the claim shows paid and nobody rebills it.
Where           app/services/era_processor.rb:142 → app/models/claim_payment.rb:58
Evidence        9 claim payments from reversal lines stored as positive
                (probe); no spec covers reversal status code 22
Confidence      Confirmed — production rows + code path, no backstop
Fix idea        Post reversal lines as negative payments and reopen the claim;
                a dry-run/APPLY task corrects the 9 existing rows.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Dates are `MM/DD/YYYY`. Then ask one question with AskUserQuestion:

| Option | Meaning |
|---|---|
| Fix now | File the issue, then run `/resolve-issue` on it |
| File an issue | File it for later |
| Skip | Not a problem / accepted risk — remember and don't raise again |
| Stop | End the audit; record the finding as `queued` |

The user can also type a reply (e.g. a reason for skipping, or "fix it but only the forward path") — honour it.

## Step 7 — Act on the decision

**File an issue** (also the first step of *Fix now*). Create the label once if missing: `gh label create rcm-audit --color B60205 --description "Found by /rcm-audit"`. Then `gh issue create --label bug --label rcm-audit` with a self-contained body that `/resolve-issue` (or an unattended autofix run) can build from without this conversation:

- **Problem** — the card's "what happens", in two or three sentences.
- **Money at stake** — counts and dollars with the as-of date, and the probe that produced them as a fenced ```ruby block (for `bin/prod-read`) or ```sql block (for `bin/prod-sql`). The block must be self-contained: it loops the organizations and wraps `ActsAsTenant.with_tenant` itself, and prints one line `count=N dollars=X ids=[…]`, so `/rcm-resolve` can re-run it verbatim to re-size the finding later.
- **Where** — `file:line` for each step of the path.
- **Fix** — the forward fix, and, when existing production rows are wrong, that the fix includes a remediation rake task (dry-run by default, `APPLY=1` to write, `DRY RUN`/`APPLY` banner, one `RESULT:` line) with the snapshot-first run recipe and go/no-go blurb required by `CLAUDE.md`.
- **Done when** — the observable check (a spec scenario, and the probe returning zero after remediation).

No PHI in the issue — counts and record ids at most. Never add the `autofix-queue` label: `rcm-audit` issues stay out of autofix (`/next-issues` and `/issue-ready` skip them) and are worked by `/rcm-resolve` with the user watching.

**Fix now** — after filing, invoke `/resolve-issue <number>` with the Skill tool. It creates its own worktree and runs to a PR on its own. When it returns, add the PR link to the ledger row.

**Skip** — record the reason (the user's words if they gave one) so the same finding isn't raised again.

## Step 8 — Record and offer the next one

Update the ledger: the finding row (date, area, key, severity, decision, issue/PR, money, note) and the area's "last audited" date and result. Then ask with AskUserQuestion: **Find the next one** / **Stop here**. On "next", go back to Step 3 (the snapshot from this run is still current; the ledger now excludes what was just decided, and `queued` items come first).

When the run ends, print a short summary table: findings raised this run, decision for each, issue/PR links, areas checked clean. `/rcm-resolve` ranks the filed findings by today's money at stake and works them later.

## Ledger template

```markdown
# RCM audit ledger

## Areas
| Area | Last audited | Result |
|---|---|---|
| A1 Session → billable event | — | — |
| A2 Eligibility & cost share | — | — |
| A3 Claim generation & validation | — | — |
| A4 Claim submission & acknowledgment | — | — |
| A5 Claim follow-up & timely filing | — | — |
| A6 ERA ingest, matching & posting | — | — |
| A7 Denials, corrections & appeals | — | — |
| A8 Patient invoicing & pricing | — | — |
| A9 Patient collection (Stripe) | — | — |
| A10 Ledger, reconciliation & visibility | — | — |

## Findings
| Date | Area | Key | Sev | Decision | Issue / PR | Money at stake | Note |
|---|---|---|---|---|---|---|---|
```

The **Key** is a short stable slug for the root cause (`era-reversal-posted-positive`), so a later run recognises the same problem even when the numbers change.
