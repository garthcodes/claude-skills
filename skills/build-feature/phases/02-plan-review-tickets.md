# A2 — Plan reviews & tickets

## Inputs

- Bootstrap per `_shared.md`. From the state file: the implementation plan path.
- Read the plan once in full. The review reports are written to disk by the reviewer sub-agents.

## Steps

### Step 1: Parallel plan reviews (round 1)

Run `/architect-review` and `/frontend-review` **in parallel** — they read the same plan
independently and write separately-named report files (`.claude/architect-review-*.md`,
`.claude/frontend-review-*.md`). Launch **two sub-agents in a single message** (two Agent calls,
`run_in_background: false`), one per review:

> **Reviewer sub-agent prompt (one for each skill):**
> Work in `${WORKTREE_PATH}` — cd there first and run everything from that directory.
> Invoke the `/architect-review` [or `/frontend-review`] skill via the Skill tool with no
> argument (it resolves the latest `.claude/implementation-plan-*.md` itself and saves its
> report to disk). The acceptance-criteria contract for this feature is at
> `.claude/acceptance-criteria/${FEATURE_NAME}.md` — the skill reads it and reports a
> **Contract Fidelity** section: ACs with no plan step (omissions), plan steps serving no AC
> or FR (extras), and steps that would violate a `guard` AC.
> When it finishes, return (≤ 40 lines): the report file path, the verdict/status, the Contract
> Fidelity findings, the Copy Audit rows marked remove/missing (frontend review), and a short digest
> of the other top findings.

**CRITICAL: do NOT edit the implementation plan while the reviewers are running.** Both reviewers
must critique the same frozen version of the plan. All editing happens in Step 2.

**Fallback:** if you cannot launch sub-agents, invoke the two skills yourself back-to-back — still
do NOT edit the plan between them; collect both reports first, then merge exactly as below.

### Step 2: Merge feedback, then confirm (round 2)

**2a — One merge pass.** Read BOTH review reports in full, then edit the implementation plan ONCE:

1. **Incorporate nearly all feedback from both reviews** — not just blockers, but "Should Address",
   high/medium items, and "Nice to Have" suggestions. Skip advice only with a strong, specific reason
   (contradicts the PRD or contract, unnecessary complexity for this scope, conflicts with the other
   review). **Contract Fidelity findings are applied first and always**: add a step for every
   uncovered AC; delete every step that serves no AC/FR (a reviewer's "nice to have" that isn't in
   the contract is an extra — do not add it, note why in one line); never accept a suggestion that
   would violate a `guard` AC.
2. From `/architect-review`: Critical Issues, Recommendations, Suggestions — update data model,
   service design, security, performance, and testing strategy.
3. From `/frontend-review`: Component Reuse Audit, Thin Views Audit, Stimulus Controller Analysis,
   Turbo Integration, Accessibility, Responsive Design, **Copy Audit** — existing ViewComponents for
   all UI, thin views, auto-submit filters, planned accessibility, defined breakpoints. Every Copy
   Audit row marked **remove** is deleted from the plan (and from `### Copy`); every row marked
   **missing** is either added to `### Copy` with a real reason or deleted. Never resolve a copy
   finding by adding text.
4. **Where the two reviews conflict**, the architect review wins on data model, services, and
   authorization; the frontend review wins on components, views, Stimulus, Turbo, and accessibility.
   Note each resolution as a one-line comment in the plan.
5. Do NOT re-run `/plan` from scratch; surgically update the existing plan.
6. If you skip any piece of advice, note why briefly (one line) as a comment in the plan.

**2b — Parallel confirmation round.** Re-run both reviews exactly as in Step 1 (two parallel
sub-agents, plan frozen while they run).

- Both approve/pass → Step 3.
- Either still has open findings → ONE more merge pass (as in 2a, both reports together), then STOP
  reviewing: record still-open issues in the state file under "Known Issues (Architect Review)" /
  "Known Issues (Frontend Review)" and proceed. Two rounds is the maximum — no third round, no asking.

### Step 3: Convert the plan to tickets

```
/tickets .claude/implementation-plan-*.md
```

Tickets are saved to `.claude/tickets-*.md`.

**IMPORTANT**: review the tickets and **remove any that create system tests** (type `system_test`,
or files matching `spec/system/**` or `spec/features/**`) — system tests are written in C1, not from
tickets. Edit the tickets document and update the summary counts.

**Contract check** (`/tickets` performs this itself; verify its output): every `AC-n` in the contract
appears as an acceptance criterion on ≥1 ticket, and every ticket cites ≥1 AC or is tagged `infra`
with a one-line justification. Guard ACs appear as "Must NOT" lines on the tickets they constrain. If
an AC has no ticket, add one; if a ticket cites nothing and isn't infra, delete it.

**Schedule check**: B1 launches one implementation worker per `## Phase N` section of the tickets
doc, wave by wave from the doc's `## Phase Schedule`, running the phases of a `parallel` wave
concurrently in this one working tree. Confirm:
- every ticket lives under a phase heading that has `**After:**` and `**Owns:**` lines
- no ticket depends on a ticket in a later wave
- within each `parallel` wave, no file in any ticket's Files to Create / Modify matches two
  phases' `Owns:`, and no phase owns a hot file (migrations/`db/`, `config/routes.rb`,
  `config/importmap.rb`, locales, initializers, existing shared models, `Gemfile*`)
Fix a violation by moving the ticket to the Foundation/Integration phase or marking the wave
`serial`. Missing schedule → add one (all-serial is acceptable).

## CHECKPOINT

Update the state file: Phase Log A2 checked; Artifacts with the exact tickets path; Results with
both review verdicts (round 1 and round 2), the AC→ticket counts (ACs covered / total; tickets
citing an AC / infra / total), the number of ticket phases and waves (max width); Known Issues / skipped advice with reasons.

## RETURN

```
A2 DONE
PLAN: <path>   TICKETS: <path>   PHASES: <n> (<ticket count> tickets)   WAVES: <w> (max width <k>)
ARCHITECT: <round1 verdict> → <round2 verdict>
FRONTEND:  <round1 verdict> → <round2 verdict>
CONTRACT: <x>/<y> ACs on tickets; <g> guards as Must-NOT lines
OPEN ISSUES: <none | one line each>
```
