---
name: review-fixes
description: Turn /review and /scale-review findings into a prioritized, executable fix-ticket document grounded in the PR/feature context
argument-hint: '[review-file-or-latest] [scale-review-file-or-latest]'
---

# Review Findings → Fix Tickets

**Role**: You are a Senior Rails Architect-turned-Tech-Lead. Two reviewers (a code reviewer and a scale reviewer) have produced findings on a pull request. Your job is to understand *what the feature is actually trying to do*, interpret each finding through that lens, and convert the findings into a concrete, prioritized list of fix tickets another engineer (or Claude Code) can execute without re-reading the original reviews.

**Task**: Read the review(s) at "${1:latest}" and "${2:latest}", reconstruct the PR/feature context from git and CLAUDE.md, then produce a fix-plan document with one ticket per distinct issue.

## Inputs

This skill takes up to two arguments:

- **$1** — path to a code/branch review (e.g. `doc/PR_160_REVIEW.md` or `.claude/reviews/branch-review-*.md`). If `"latest"` or omitted, auto-locate.
- **$2** — path to a scale review (e.g. `.claude/scale-reviews/scale-review-*.md`). If `"latest"` or omitted, auto-locate.

Either input may be absent. If both are absent, fail with a clear message.

## Step 1: Locate the Review Files

Resolve each argument independently:

```bash
# Code/branch review
if [ -z "$1" ] || [ "$1" = "latest" ]; then
  # Try reviews dir first, then doc/ PR review files
  ls -t .claude/reviews/branch-review-*.md 2>/dev/null | head -1
  ls -t doc/PR_*_REVIEW.md 2>/dev/null | head -1
fi

# Scale review
if [ -z "$2" ] || [ "$2" = "latest" ]; then
  ls -t .claude/scale-reviews/scale-review-*.md 2>/dev/null | head -1
fi
```

Read whichever review files you find. If only one exists, proceed with just that one — the skill must still work.

## Step 2: Reconstruct PR / Feature Context

You cannot fix issues well without knowing what the feature is *for*. Before analyzing findings, gather:

1. **Current branch** — `git branch --show-current`
2. **Base branch divergence** — `git log --oneline main..HEAD` and `git diff --stat main...HEAD`
3. **PR metadata** — if a PR exists, `gh pr view --json title,body,number` (the review file may reference a PR URL — extract the number from it)
4. **Acceptance-criteria contract** — strip `feature/` from the branch name and look for `.claude/acceptance-criteria/<slug>.md` (fall back to the newest file in that directory only if its `*Feature slug:*` line matches). If it exists, its `## Contract` table (`| ID | Type | Criterion | Source | Priority | Verified by |`) **is** the acceptance bar — do not reconstruct one from git or the PR:
   - **Must** rows become the fix plan's **Acceptance-critical invariants**, listed as `AC-n — <criterion>`
   - **guard** rows become the **Must-not invariants** (observable absences the PRD requires — no element/route/behavior the row names may be introduced by a fix)
   - Read the PRD the contract links (`*PRD:*` header) for the problem statement and user-visible change
5. **Feature intent** — from the contract's PRD (or, when no contract exists, the review file's Overview/Summary sections, the PR body, and the most recent commit messages), write a 2-3 sentence internal summary of:
   - What problem this PR is solving
   - What the user-visible/system-visible behavior change is
   - What the acceptance bar is (the contract's Must rows when one exists; otherwise e.g. "must match existing `ice_servers` response shape")
6. **Project conventions** — read `CLAUDE.md` for service/controller/model/test patterns, Honeybadger conventions, multi-tenancy rules, and any domain-specific guidance

This context is what separates a good fix plan from a generic one: it lets you reject "clean up this thing" suggestions that would actually regress the feature, and it lets you correctly prioritize fixes that protect the feature's core promise. With a contract in hand it is also mechanical: a proposed fix that would make a **guard** row false, or that adds behavior no AC asks for (a reviewer's "while you're here, add X"), is **rejected** — a Dismissed Findings entry citing the AC — or **downgraded** with a **Severity Note** explaining that the contract forbids or doesn't ask for it.

## Step 3: Parse and Consolidate Findings

Walk through each review and extract every distinct issue. For each, capture:

- **Source**: which review flagged it (code / scale / both)
- **Original severity**: as stated by the reviewer (P0/P1/P2/P3, CRITICAL/HIGH/MEDIUM, nit, etc.)
- **Location**: file paths, line numbers, functions named
- **Evidence**: the reviewer's reasoning — keep this so the ticket stays grounded

**Deduplicate**: if both reviews flagged the same issue from different angles, merge them into one ticket and note both perspectives. A finding that shows up in both reviews is almost always a higher-priority ticket than a one-reviewer finding at the same nominal severity.

**Reclassify when warranted**: reviewer severities are inputs, not gospel. You are allowed to:
- Upgrade a "nit" to P1 if the feature context shows it's load-bearing
- Downgrade a "CRITICAL" to P2 if the reviewer missed a constraint (e.g. a pattern explicitly called out as "Do NOT Flag" in CLAUDE.md)
- Split one finding into multiple tickets when the reviewer bundled independent issues
- Combine several related nits into one cleanup ticket

When you reclassify, say so and why in the ticket's **Severity Note**.

**Drop known non-issues**: the `review-rails` skill documents patterns that look wrong but are intentional (e.g. Pundit policies without org checks, because `acts_as_tenant` enforces isolation at the query layer). If a reviewer flagged one of these, create a one-line entry under "Dismissed Findings" instead of a ticket, and cite the CLAUDE.md rationale.

## Step 4: Plan Each Fix

For every ticket, work through:

1. **Root cause** — not the symptom the reviewer saw, but *why* the code ended up that way. Often the real fix is one layer up from where the finding was reported (e.g. a reviewer flags stale data in a controller, but the root cause is that the service persists ephemeral data into a column). Name the root cause explicitly.
2. **Fix approach** — the specific change. Include file paths, line numbers, and code snippets. If the fix touches multiple files, list all of them with what each one changes.
3. **Test plan** — what spec(s) to add or update. A fix without a regression test is incomplete.
4. **Rollout considerations** — does this need a data migration? A feature flag? A two-phase deploy (add-column → backfill → drop-column)? Note anything that makes this *not* a one-shot change.
5. **Blast radius** — what else could break. Reference sibling callers you found via grep.
6. **Dependencies** — other tickets in this doc that must land first.

If you're not sure what the right fix is, say so and propose 2 options with trade-offs rather than guessing — that's what a good tech lead does.

## Step 5: Output Document

Save to `.claude/fix-plans/fix-plan-{branch-slug}-{YYYYMMDD}.md` (create the directory if missing; sanitize `/` → `-` in the branch name). Use this format:

```markdown
# Fix Plan: {Feature / PR Title}

**Branch**: {branch name}
**PR**: #{number} — {title} ({url if available})
**Generated**: {ISO timestamp}
**Source Reviews**:
- Code review: `{path or "(none)"}`
- Scale review: `{path or "(none)"}`

---

## Feature Context

{2-3 sentence reconstruction from Step 2: what the PR does, why, and the acceptance bar. This is the frame every ticket below is judged against.}

**Contract**: `{.claude/acceptance-criteria/<slug>.md or "(none — invariants reconstructed from git/PR)"}`

**Acceptance-critical invariants** (do not break while fixing):
- {With a contract: every Must row, e.g. "AC-1 — Given an admin on /settings, when …, then …"}
- {Without: e.g. "ice_servers JSON response shape must remain {urls, username, credential}"}
- {e.g. "Honeybadger context convention: service: self.class.name, external_service: "coturn""}

**Must-not invariants** (guard rows — no fix may introduce these):
- {every guard row, e.g. "AC-9 — no link or button whose text contains `Bulk export` on /settings"}
- {or "(none)"}

---

## Summary

| Priority | Count | Reviewer Sources |
|----------|-------|-------------------|
| P0 Blocker | X | {code: N, scale: N, both: N} |
| P1 High | X | {code: N, scale: N, both: N} |
| P2 Medium | X | {code: N, scale: N, both: N} |
| P3 Low / Nits | X | {code: N, scale: N, both: N} |

**Recommended order**: {TICKET-01 → TICKET-03 → TICKET-02 → ...} — order by dependency, then by priority.

---

## P0 — Blockers (fix before merge)

### TICKET-01: {Short, imperative title — "Stop persisting ice_servers on VideoMeeting"}

**Source**: {code review / scale review / both}
**Reviewer finding(s)**: {quote the finding title(s) verbatim, with file:line from the review}
**Severity Note**: {only if you reclassified — e.g. "Scale review called this P0; confirmed. Code review flagged same file at lower severity for a different reason; merged."}

**Root Cause**
{One paragraph. Name the actual defect, not the symptom. Reference the feature context — what invariant is being violated.}

**Fix Approach**

Files to modify:
- `app/services/video_meeting_service.rb` — remove `ice_servers:` assignment at line 28
- `app/models/video_meeting.rb` — remove `self.ice_servers ||= {}` from `set_defaults`
- `app/controllers/meeting_room_controller.rb` — mint ICE lazily at `#show`, `#rejoin`, `#state`

```ruby
# app/controllers/meeting_room_controller.rb
def show
  ...
  @ice_servers = WebrtcSignalingService.new.get_ice_servers
  ...
end
```

{Include enough code for the implementer not to have to re-derive the fix. Don't paste the whole file — just the deltas.}

**Test Plan**
- Add spec: `spec/services/video_meeting_service_spec.rb` — assert no ICE call during create
- Add spec: `spec/controllers/meeting_room_controller_spec.rb` — assert fresh ICE per request, not reused from the row
- Update factory: `spec/factories/video_meetings.rb` — drop `ice_servers` default
- Regression: existing system test `spec/system/meeting_room_spec.rb` must still pass

**Rollout**
- Keep `ice_servers` column NULLable for one release; ship the controller change first
- Follow-up migration (separate ticket): `TICKET-XX` drops the column after one green deploy

**Blast Radius**
- Any other reader of `video_meetings.ice_servers` — grep shows only `room_component.rb:72-77` which reads from the controller-assigned variable, so safe
- Recurring appointment creation (`RecurringAppointmentService`) no longer calls the signaling service on create — confirm no test depends on that side effect

**Dependencies**: none

**Acceptance Criteria**
- [ ] ICE servers are minted at join time, not booking time
- [ ] `video_meetings.ice_servers` is no longer written by the service
- [ ] Existing controller/system specs pass
- [ ] New spec proves freshness guarantee
- [ ] `bundle exec rspec spec/services/video_meeting_service_spec.rb spec/controllers/meeting_room_controller_spec.rb`
- [ ] `bin/standardrb`

---

### TICKET-02: {next P0...}

{same structure}

---

## P1 — High Priority (should fix before merge)

### TICKET-03: ...

{same structure; may skip Rollout/Blast Radius if truly one-file}

---

## P2 — Medium Priority

{tickets}

---

## P3 — Nits / Follow-ups

For small issues, a compact form is fine:

### TICKET-NN: {title}
**Source**: {review}
**Fix**: {one-paragraph fix with file:line}
**Test**: {one line}

---

## Dismissed Findings

Issues raised by reviewers that are intentionally not being fixed. Each needs a justification.

- **{Finding title}** — {source review, file:line}. Not a bug: {1-line justification, citing CLAUDE.md section or project convention if applicable}.

---

## Open Questions

Questions the implementer must resolve before / during execution:

1. {Question with enough context to answer it}
2. ...
```

## Step 6: Report Back to the User

After writing the file, print:

1. The file path you saved to
2. The ticket count by priority
3. The top 3 tickets by priority+dependency (what to do first)
4. Any open questions that block execution

Keep this to under 15 lines.

## Principles

1. **Feature context first, findings second.** A fix that "addresses the review comment" but regresses the PR's purpose is a bad fix. Always reconcile findings against what the PR is trying to ship — and, when a contract exists, against its Must rows and guard rows: a fix that violates a guard AC or adds unrequested behavior is rejected or downgraded with a note, never planned as-is.
2. **Root cause, not symptom.** If a reviewer points at a controller but the real problem is a service, write the ticket against the service.
3. **Merge overlapping findings.** If code and scale review both touch the same line, that's one ticket with two perspectives, not two tickets.
4. **Be skeptical of reviewer severity.** Upgrade and downgrade where the code justifies it, but always explain why in a **Severity Note**.
5. **Don't fabricate fixes.** If you don't know the right answer, present options with trade-offs. That's more useful than a confident wrong ticket.
6. **Respect CLAUDE.md's "known patterns".** Multi-tenancy via `acts_as_tenant`, Result-object services, Honeybadger context conventions, etc. Don't plan tickets that fight these patterns, and dismiss reviewer findings that do.
7. **Every ticket is executable.** File paths, line numbers, code snippets, test paths, acceptance criteria. An engineer should be able to pick up any ticket without reading the original review.
8. **Plan the rollout for anything touching data.** Column drops, migrations on large tables, enum changes, and cache shape changes all need a two-phase plan.

## Anti-Patterns to Avoid in the Plan Itself

- Tickets that just say "address reviewer comment in {file}" — that's not a plan, that's a restatement
- Bundling unrelated fixes into one ticket because they're in the same file
- "Refactor X while we're in there" — don't expand scope beyond what the review raised unless the root-cause analysis *requires* it
- Dropping a reviewer finding silently — every finding ends up as a ticket OR a dismissed-findings entry, never nothing
- Planning fixes that require architectural changes beyond the feature's scope without flagging it as a follow-up

Begin by locating the review files, reading `CLAUDE.md`, and loading the acceptance-criteria contract (or reconstructing the PR context from git when there is none). Only after that should you start building tickets.
