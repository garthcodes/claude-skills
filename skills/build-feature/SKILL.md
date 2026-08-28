---
description: End-to-end feature build from PRD to PR — plan, review, implement, QA, and ship in a worktree
argument-hint: <path-to-prd.md>
---

# Build Feature: PRD to PR Pipeline

Automated end-to-end pipeline that takes a PRD document and produces a reviewed, QA-verified pull request. All work happens in a single git worktree, executed by **three sequential phase agents** — each phase gets a fresh context, and `.claude/pipeline-state.md` in the worktree is the formal handoff contract between them.

## Autonomous Execution Policy

**This pipeline runs end-to-end without stopping to ask the user for confirmation.** Do not pause at phase boundaries, retry limits, or when issues are found. When a retry limit is reached, when a review still has open feedback, or when a step partially fails:
- Make the best reasonable decision and keep going
- Record the remaining issue in `.claude/pipeline-state.md` and in the eventual PR description under a **Known Issues** section
- Only stop if a step is truly blocking (e.g., no PRD found, git push rejected, `bin/ci` fails after all retry cycles) — and even then, attempt to create the PR as a draft with the blockers documented rather than waiting for input

The only sanctioned "ask the user" moment is when the pipeline is genuinely unable to produce any PR output at all.

**The one deliberate exception to "always produce a PR" is the Acceptance Gate (Phase 9.5 /
Step 18).** The PRD's user-agreed Acceptance Criteria table is the contract: if any
**Must** criterion is still not VERIFIED by `/verify-acceptance` after the bounded fix cycles,
the pipeline pushes the branch, keeps the worktree and state file for a resumable relaunch,
and **stops without creating a PR**. Unverified **Should** criteria open the PR as a draft.
Every other gate (reviews, security, trace, CI) still degrades to "record it and ship".

## Pipeline Overview

```
PRD Document
  -> Read PRD (main conversation)
  -> Sweep merged/closed pipeline worktrees (bin/worktree-sweep)

  -> Agent A: PLAN (isolation: worktree — creates THE worktree)
    -> Copy gitignored files (.env, certs)
    -> Rename branch to feature/${FEATURE_NAME}
    -> Create isolated databases (DATABASE_SUFFIX in worktree .env)
    -> Assign worktree port (bin/worktree-port → PORT= in .env)
    -> Commit the PRD (traceability from code to requirements)
    -> /plan <prd-path> (create implementation plan — system tests excluded)
    -> /architect-review + /frontend-review (PARALLEL, two sub-agents)
    -> Merge both reviews into the plan (one edit pass)
    -> /architect-review + /frontend-review (parallel confirmation round)
    -> /tickets (convert refined plan to tickets)
    -> Write full handoff to .claude/pipeline-state.md
  <- Returns worktree path + plan/review summary

  -> Agent B: IMPLEMENT (plain agent, works in Agent A's worktree)
    -> Bootstrap from pipeline-state.md
    -> /code <tickets-file> (execute tickets — NO system tests)
    -> Commit implementation + quick gates (standardrb, brakeman)
    -> /full-review (/review + /scale-review -> /review-fixes -> /code)
    -> Commit review fixes + quick gates (standardrb, brakeman)
    -> /security-review (branch diff; fix Critical/High findings + commit)
    -> /trace-requirements (FR gate: every PRD requirement maps to code/spec)
    -> Fix gaps + re-trace (one cycle, if gaps found)
    -> Update handoff in .claude/pipeline-state.md
  <- Returns implementation + review summary

  -> Agent C: VERIFY & SHIP (plain agent, works in Agent A's worktree)
    -> Bootstrap from pipeline-state.md
    -> /plan-system-tests (scenario plan from branch diff + PRD)
    -> /system-test-expert (implement system tests from the plan)
    -> /fix-system-test (debug failures/flakes until stable)
    -> Commit system tests
    -> /create-qa-document --base-url=http://localhost:${WORKTREE_PORT} (QA plan from changes + PRD)
    -> /execute-qa (run QA scenarios; keep 2-4 key screenshots)
    -> Fix QA bugs (if any)
    -> /verify-acceptance (AC scorecard: PASS | PASS WITH SHOULD GAPS | FAIL)
    -> Close AC gaps + re-verify (max 2 cycles) -> close browser (server stays up)
    -> /simplify (diff-scoped cleanup pass) + commit
    -> bin/ci (final CI gate — must pass)
    -> Publish QA screenshots (screenshots/${FEATURE_NAME} branch)
    -> Draft PR body (from pipeline-state.md, BEFORE cleanup deletes it)
    -> Remove pipeline artifacts (feature-scoped patterns only)
    -> Rebase onto origin/main -> Push branch
    -> ACCEPTANCE GATE: PASS -> create PR | SHOULD GAPS -> draft PR | FAIL -> no PR
  <- Returns PR URL and summary (or GATE FAILED + unmet Must ACs)

  -> Report results to user
  -> Handoff: dev server running (detached), VSCode open, "Review at" URL (all outcomes)
```

## Orchestration Model

The pipeline is split into three sequential phase agents so that each phase starts with a
fresh context — one agent running everything would compact multiple times, and the phases
that suffer most from degraded context (implementation, QA, system-test debugging) would run
on the least of it.

**How the agents share one worktree:**
- **Agent A** is launched with `isolation: "worktree"` — Claude Code creates the worktree, and
  because Agent A changes files, it persists after the agent finishes. Agent A records its
  absolute path (`pwd`) in `.claude/pipeline-state.md` and returns it.
- **Agents B and C** are launched WITHOUT the `isolation` parameter (a second
  `isolation: "worktree"` would create a NEW, empty worktree — never do that). Their prompts
  receive `WORKTREE_PATH` and they run every command from that directory. The worktree lives
  under the main repo (`.claude/worktrees/...`), so normal session permissions apply.
- Launch each agent with `run_in_background: false` and wait for its result before launching
  the next — the phases are strictly sequential.

**The handoff contract** is `.claude/pipeline-state.md` in the worktree. Each agent finishes
by bringing it up to date; each subsequent agent starts by reading it. Required structure:

```markdown
# Pipeline State: ${FEATURE_NAME}

## Identity
- FEATURE_NAME: <slug>
- BRANCH: feature/<slug>
- WORKTREE_PATH: <absolute path>
- MAIN_DIR: <absolute path of the main repo checkout>
- WORKTREE_PORT: <assigned by bin/worktree-port in Phase 3>
- DB_SUFFIX: <suffix>
- PRD: .claude/prds/<slug>.md

## Phase Log
- [x] Agent A: Plan & Tickets
- [ ] Agent B: Implement & Review
- [ ] Agent C: Verify & Ship

## Artifacts
- Implementation plan: <path>
- Tickets: <path>
- (Agent B/C append: fix plan, test plan, QA plan paths, commit hashes)

## Results
- (verdicts, counts, and summaries appended per phase — see each phase's CHECKPOINT)

## Acceptance
- Verdict: (PASS | PASS WITH SHOULD GAPS | FAIL) — scorecard: <path>
- Must: X/Y • Should: X/Y
- (one line per non-VERIFIED AC: `AC-n (Must, FAILED|UNVERIFIED) — reason`)

## Known Issues
- (subsections per source: Architect Review, Frontend Review, Review, Security,
  Requirements Trace, System Tests, CI, QA)

## Deferred
- (P3 review tickets etc.)
```

**Recovery:** because all work is committed or on disk and the state file is authoritative, a
phase agent that dies or returns unusable output can simply be relaunched with the same prompt
— it re-reads `pipeline-state.md`, checks `git log`, and continues from where the last agent
left off. Never restart the whole pipeline from scratch.

Skill independence note: this orchestration lives entirely in this file. The composed skills
(`/plan`, `/tickets`, `/code`, `/full-review`, `/plan-system-tests`, `/system-test-expert`,
`/fix-system-test`, `/create-qa-document`, `/execute-qa`) know nothing about phase agents or
the state file and run unmodified — both inside this pipeline and standalone.

## Phase 1: Validate Input (Main Conversation)

### Step 0: Sweep stale pipeline worktrees

Before anything else, remove pipeline worktrees whose PR has since been merged or closed so
their ports and databases are freed:

```bash
bin/worktree-sweep
```

Show its output verbatim in the conversation (one line per worktree). Any non-zero exit
status, `gh` failure, or a missing script (checkout predates it — print "sweep unavailable")
→ print the reason and **continue to Step 1**. The sweep never blocks a build.

### Step 1: Read the PRD

Read the PRD document at "${1}".

If "${1}" is empty or not provided:
- Search for the most recent PRD: `ls -t .claude/prds/*.md 2>/dev/null | head -1`
- If no PRD found, inform the user and stop. Suggest running `/prd` first.

**Acceptance Criteria gate (second hard stop):** the PRD must contain a
`## Acceptance Criteria` table (`| ID | Criterion | FR | Priority | Verified by |`, rows
`AC-1`, …) with the `*Agreed with user: YYYY-MM-DD*` stamp beneath the heading. If the section
is missing, or the stamp is missing, **stop** and tell the user: "This PRD's acceptance
criteria haven't been agreed — run `/prd` (it will draft and walk you through them) and then
re-run `/build-feature`." The pipeline never starts on an unagreed contract, because that
contract is what decides whether a PR gets created at the end.

Extract from the PRD:
- **Acceptance Criteria** — the table, verbatim; count Must vs. Should rows
- **Feature slug** — PRDs generated by `/prd` declare it in the header
  (`*Feature slug: `feature-slug`*`). Use it verbatim as `FEATURE_NAME`. If the PRD has no
  slug line, convert the feature name to kebab-case instead.
- **Feature name** (for the PR title)
- **Executive summary** (for plan context)
- **Full requirements** (passed to /plan)

## Phase 2: Launch Agent A — Plan & Tickets

Launch the first phase agent with `isolation: "worktree"`. It creates the pipeline's worktree
and owns Phases 3–5 (setup, plan, reviews, tickets).

**Agent A's prompt MUST include:**
1. The **full PRD content** (paste the entire PRD text)
2. `FEATURE_NAME` = the kebab-case feature name
3. `MAIN_DIR` = the absolute path of the main repo checkout (the directory this skill is run from)
4. The **Autonomous Execution Policy** and the **Important Guidelines** and **Error Handling**
   sections from this document (every phase agent gets these)
5. ALL instructions from Phase 3 through Phase 5 below (copy them into the prompt), including
   the Agent A HANDOFF block

Agent A assigns `WORKTREE_PORT` in Phase 3 (`bin/worktree-port`) and returns it.

**Agent tool parameters:**
- `isolation: "worktree"`
- `description: "Plan ${FEATURE_NAME}"`
- `run_in_background: false`

When Agent A returns, note the `WORKTREE_PATH` **and `WORKTREE_PORT`** from its result — Agents B and C need them. If
Agent A failed before writing the state file, relaunch it; if it failed after, launch Agent B
anyway (it bootstraps from the state file and `git log`).

---

## Agent A Instructions (Include in Agent A Prompt)

Everything from here to "End of Agent A Instructions" goes in Agent A's prompt.

---

### Phase 3: Worktree Setup

The agent is already in a git worktree. Set it up for development:

```bash
# Copy gitignored files needed for development
# (skip the certs line if your dev setup doesn't use local HTTPS)
cp -r "${MAIN_DIR}/config/certs" ./config/
cp "${MAIN_DIR}/.env" ./.env

# Rename the auto-generated branch to the feature branch name
git branch -m "feature/${FEATURE_NAME}"
```

**Isolate this pipeline's databases.** The worktree must NOT share `<app>_development` /
`<app>_test` with the main repo (`<app>` = your app's database name prefix from
`config/database.yml`) — this feature's migrations would otherwise mutate the shared
dev DB (and leave schema drift behind if the PR is abandoned). `config/database.yml` appends
`ENV["DATABASE_SUFFIX"]` to both database names. Setting it in the worktree's `.env` means
every command run here (`bin/rails`, `bundle exec rspec`, `bin/ci`, foreman) picks it up via
dotenv automatically — no composed skill needs to know about it, and the main repo (where the
var is unset) is untouched.

```bash
# Sanitize the feature name into a Postgres-safe suffix (underscores, max 30 chars)
DB_SUFFIX="_$(echo "${FEATURE_NAME}" | tr '-' '_' | tr -cd 'a-z0-9_' | cut -c1-30)"
echo "DATABASE_SUFFIX=${DB_SUFFIX}" >> .env

# Create, load schema, and seed the isolated databases
bin/rails db:prepare        # <app>_development${DB_SUFFIX} — creates, loads schema, seeds
bin/rails db:test:prepare   # <app>_test${DB_SUFFIX}
```

**Assign this worktree's dev server port.** Each pipeline worktree serves on its own port so
several can be reviewed side by side with the main checkout on the default port:

```bash
WORKTREE_PORT="$(bin/worktree-port --assign .env)"   # lowest free port in 3010–3099
echo "WORKTREE_PORT=${WORKTREE_PORT}"
```

`bin/dev` reads `PORT=` from `.env`, so nothing else needs the number — but record it in
`.claude/pipeline-state.md` and return it. If the script exits 1 (range exhausted) → STOP with
its message (see Error Handling: Port range exhausted).

Verify setup:
```bash
git branch --show-current  # Should show feature/${FEATURE_NAME}
ls config/certs/            # Should have cert files
ls .env                     # Should exist
grep DATABASE_SUFFIX .env   # Should show the suffix
grep '^PORT=' .env          # 3010 ≤ n ≤ 3099
bin/rails runner 'puts ActiveRecord::Base.connection_db_config.database'
                            # Should print <app>_development${DB_SUFFIX} (NOT <app>_development)
```

If the printed database name has no suffix, STOP and fix the `.env` before proceeding —
running the pipeline against the shared dev database is not acceptable.

### Phase 4: Plan the Implementation

#### Step 1: Create Implementation Plan

Ensure the PRD exists in the worktree at `.claude/prds/${FEATURE_NAME}.md` — if it isn't
committed to the repo, write the PRD content (from this prompt) to that path. Then **commit
it** so the PR carries permanent traceability from code back to requirements (the artifact
cleanup in Phase 10 deliberately preserves `.claude/prds/`):

```bash
git add .claude/prds/${FEATURE_NAME}.md
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
docs: add PRD for ${FEATURE_NAME}

Co-Authored-By: [your standard Claude Code co-author line]
EOF
)"
```

Then invoke `/plan` with the PRD path so the plan is grounded in the full requirements:

```
/plan .claude/prds/${FEATURE_NAME}.md — system tests are EXCLUDED (QA is done via Playwright). The PRD's Acceptance Criteria table is the contract the PR is gated on: every AC-n row must map to a plan step and appear by ID in the plan's Success Criteria.
```

The plan will be saved to `.claude/implementation-plan-*.md`.

**Verify**: The plan MUST NOT include any system tests (`/plan` honors the exclusion, but
check). If system tests slipped in, remove those sections before proceeding.

#### Step 2: Parallel Plan Reviews (Round 1)

Run `/architect-review` and `/frontend-review` **in parallel** — they read the same plan
independently and write separately-named report files (`.claude/architect-review-*.md`,
`.claude/frontend-review-*.md`), so there is no conflict. Launch **two sub-agents in a single
message** (two Agent calls, `run_in_background: false`), one per review:

> **Reviewer sub-agent prompt (one for each skill):**
> Work in <worktree absolute path> — cd there first and run everything from that directory.
> Invoke the `/architect-review` [or `/frontend-review`] skill via the Skill tool with no
> argument (it resolves the latest `.claude/implementation-plan-*.md` itself and saves its
> report to disk). When it finishes, return: the report file path, the verdict/status, and a
> short digest of the top findings.

**CRITICAL: do NOT edit the implementation plan while the reviewers are running.** Both
reviewers must critique the same frozen version of the plan. All editing happens in Step 3,
after both have returned.

**Fallback:** if you cannot launch sub-agents in this environment, invoke the two skills
yourself back-to-back instead — but still do NOT edit the plan between them; collect both
reports first, then merge in Step 3 exactly as below.

#### Step 3: Merge Feedback, Then Confirm (Round 2)

**3a — One merge pass.** Read BOTH review reports in full, then edit the implementation plan
ONCE to incorporate the merged feedback:

1. **Incorporate nearly all feedback from both reviews** — not just critical issues/blockers,
   but also "Should Address" recommendations, high/medium priority items, and "Nice to Have"
   suggestions. Only skip advice with a strong, specific reason (it contradicts the PRD,
   introduces unnecessary complexity for this feature's scope, or conflicts with the other
   review's feedback).
2. From `/architect-review`, read all sections: Critical Issues, Recommendations (Should
   Address), Suggestions (Nice to Have) — update data model, service design, security,
   performance, and testing strategy accordingly.
3. From `/frontend-review`, read all sections: Component Reuse Audit, Thin Views Audit,
   Stimulus Controller Analysis, Turbo Integration, Accessibility, Responsive Design — ensure
   all UI elements use existing ViewComponents, views are thin, filters use auto-submit,
   accessibility is planned, responsive breakpoints are defined.
4. **Where the two reviews conflict**, the architect review wins on data model, services, and
   authorization; the frontend review wins on components, views, Stimulus, Turbo, and
   accessibility. Note each conflict resolution as a one-line comment in the plan.
5. Do NOT re-run `/plan` from scratch; surgically update the existing plan.
6. If you skip any piece of advice, note why briefly (one line) as a comment in the plan.

**3b — Parallel confirmation round.** Re-run both reviews exactly as in Step 2 (two parallel
sub-agents, plan frozen while they run).

- If both approve/pass → proceed to Phase 5.
- If either still has open findings → do ONE more merge pass (as in 3a, both reports together),
  then STOP reviewing: record any issues still open in `.claude/pipeline-state.md` under
  "Known Issues (Architect Review)" / "Known Issues (Frontend Review)" and proceed. Two rounds
  of review is the maximum — do NOT run a third round, and do NOT ask the user.

#### CHECKPOINT

All planning and review work is persisted in files (`.claude/implementation-plan-*.md`,
`.claude/architect-review-*.md`, `.claude/frontend-review-*.md`). Write a brief status summary
to `.claude/pipeline-state.md` capturing:
- `FEATURE_NAME`, branch name, `WORKTREE_PORT` (from `.env`)
- Path to the final implementation plan
- Architect review verdict
- Frontend review verdict
- Any skipped advice and why

Your context may be compacted automatically at any point from here on — `.claude/pipeline-state.md`
is the recovery mechanism. After any compaction, re-read it to restore variables, and do NOT
re-read the large planning/review artifacts unless a step requires them.

---

### Phase 5: Generate Tickets

#### Step 4: Convert Plan to Tickets

Use the `/tickets` skill with the refined plan:

```
/tickets .claude/implementation-plan-*.md
```

The tickets will be saved to `.claude/tickets-*.md`.

**IMPORTANT**: After ticket generation, review the tickets and **remove any tickets that create system tests** (type: `system_test` or files matching `spec/system/**` or `spec/features/**`) — system tests are written in Phase 8, not from tickets. Edit the tickets document to remove these entries and update the summary counts.

#### HANDOFF (end of Agent A)

You are the first of three phase agents; Agents B (implement) and C (verify & ship) will work
in this same worktree with fresh contexts. Bring `.claude/pipeline-state.md` up to the full
handoff schema (Identity including `WORKTREE_PATH` from `pwd`, `WORKTREE_PORT`, and `DB_SUFFIX`, Phase Log with
Agent A checked, Artifacts with the exact implementation-plan and tickets paths, Results with
both review verdicts, Known Issues, Deferred). Agent B knows ONLY what this file and the repo
contain — do not rely on anything that lives in your context.

Then **return**: the worktree absolute path, the branch name, the assigned port
(`WORKTREE_PORT`), the plan and tickets paths, both
review verdicts, and a 3-5 line summary of the planned approach.

---

## End of Agent A Instructions

---

## Launch Agent B — Implement & Review (Main Conversation)

When Agent A completes, launch Agent B. It owns Phases 6–7.5 (execute tickets, commit, full
review, commit fixes, requirements-traceability gate).

**Agent B's prompt MUST include:**
1. `WORKTREE_PATH` = the worktree path returned by Agent A
2. `FEATURE_NAME`, `MAIN_DIR` (same values as Agent A) and `WORKTREE_PORT` = the value Agent A
   returned (also in `.claude/pipeline-state.md` Identity and `PORT=` in the worktree `.env`)
3. The **Autonomous Execution Policy**, **Important Guidelines**, and **Error Handling** sections
4. The **Phase Agent Bootstrap** block below
5. ALL instructions from Phase 6 through Phase 7.5, including the Agent B HANDOFF block

**Agent tool parameters:**
- NO `isolation` parameter (Agent B works in Agent A's existing worktree — a new worktree
  would be empty and wrong)
- `description: "Implement ${FEATURE_NAME}"`
- `run_in_background: false`

### Phase Agent Bootstrap (include in Agent B and Agent C prompts)

> You are one of three sequential phase agents building this feature in a shared git worktree.
> Before doing anything else:
>
> 1. `cd ${WORKTREE_PATH}` — run EVERY command from this directory for the rest of your run.
>    Never run project commands from `${MAIN_DIR}`.
> 2. Read `.claude/pipeline-state.md` (in the worktree) — it is the authoritative record of
>    what prior agents did: paths to artifacts, review verdicts, commit hashes, known issues.
> 3. Verify you're in the right place: `git branch --show-current` shows
>    `feature/${FEATURE_NAME}`, and `grep -E '^(DATABASE_SUFFIX|PORT)=' .env` shows both the
>    database suffix and the worktree's dev server port.
> 4. Read the PRD at `.claude/prds/${FEATURE_NAME}.md` for feature context.
> 5. Check `git log --oneline main..HEAD` to see what has already been committed — if the
>    state file says a step you're about to do is already done, don't redo it (you may be a
>    relaunch after a failed run).
>
> All skills you invoke (via the Skill tool) operate on your current working directory — as
> long as you stay in the worktree, they need no special configuration.

---

## Agent B Instructions (Include in Agent B Prompt)

Everything from here to "End of Agent B Instructions" goes in Agent B's prompt, after the
Bootstrap block.

---

### Phase 6: Implement

#### Step 5: Execute Tickets

Use the `/code` skill, passing the tickets document explicitly (resolve the actual filename
from the Artifacts section of `.claude/pipeline-state.md` — do not let `/code` guess):

```
/code .claude/tickets-<actual-name>.md
```

**CRITICAL CONSTRAINTS during implementation:**
- **NO system tests yet** — Do NOT create any files under `spec/system/` during this phase. System tests are written in Phase 8 by `/plan-system-tests` + `/system-test-expert`, against the reviewed code. If `/code` attempts to create system tests, skip those tasks.
- **NO feature specs** — Do NOT create any files under `spec/features/` at any point (project policy).
- All other tests (model specs, service specs, controller specs, component specs, policy specs, request specs) ARE allowed and expected.

#### Step 6: Commit Implementation

```bash
# Stage all implementation files (be specific, don't use git add -A)
git add <specific files>

# Commit (end the message with your standard Claude Code co-author trailer)
git commit -m "$(cat <<'EOF'
feat: implement ${FEATURE_NAME}

Implements the feature as specified in the PRD.
See implementation plan and tickets for details.

Co-Authored-By: [your standard Claude Code co-author line]
EOF
)"
```

#### Quick Gates

Run the cheap CI gates NOW rather than discovering failures in Phase 10 (after QA has already
blessed the code):

```bash
bin/standardrb --fix    # then fix anything it can't auto-fix
bundle exec brakeman -q # fix any new warnings introduced by this branch
```

Commit any resulting fixes (fold them into a small `fix:` commit). Pre-existing brakeman
warnings on files this branch didn't touch: note them, don't chase them. (`bin/ci` remains
the full final gate in Phase 10 — don't run it here.)

#### CHECKPOINT

Implementation is committed and all code is on disk. Update `.claude/pipeline-state.md` with:
- Implementation commit hash (`git rev-parse HEAD`)
- Summary of what was implemented (brief, 2-3 lines)
- Any test or linting issues that were fixed

After any automatic compaction, re-read `.claude/pipeline-state.md` to restore variables.

---

### Phase 7: Code Review & Fixes

Now that the feature is implemented and committed, run a full code + scale review and apply the fixes **before** QA, so QA exercises cleaner, hardened code.

#### Run the Full Review Pipeline

Use the `/full-review` skill against the current branch:

```
/full-review
```

No PR exists yet at this point in the pipeline, so `/full-review` automatically falls back to the local branch diff (`git log ${BASE_BRANCH}..HEAD`). It will, in order:

1. `/review` → save code review to `.claude/reviews/branch-review-*.md`
2. `/scale-review` → save scale/architecture review to `.claude/scale-reviews/scale-review-*.md`
3. `/review-fixes` → consolidate both into `.claude/fix-plans/fix-plan-*.md`
4. `/code` → implement the fix-plan tickets (it stops at implementation; it does NOT commit, push, or run QA)

**Constraints during this phase:**
- **NO system tests / NO feature specs** — same as Phase 6 (system tests come in Phase 8). If `/code` tries to create files under `spec/system/` or `spec/features/`, skip those tickets.
- **Autonomous override:** `/full-review` normally surfaces the fix-plan's **Open Questions** and waits for the user before running `/code`. In this pipeline, do NOT stop. Make the best reasonable call for each open question, implement accordingly, and record every unresolved question in `.claude/pipeline-state.md` under "Known Issues (Review)" and later in the PR's Known Issues section.
- **Scope:** apply all P0/P1/P2 fix-plan tickets. P3 / nice-to-have tickets may be deferred — if deferred, record them in `.claude/pipeline-state.md` under "Deferred (Review)" so they surface in the PR.

#### Commit Review Fixes

```bash
# Stage only the files changed by the review fixes (be specific, don't use git add -A)
git add <specific files>

# Commit (skip this commit entirely if /code made no changes)
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
refactor: apply code & scale review fixes for ${FEATURE_NAME}

Addresses findings from /review and /scale-review consolidated via /review-fixes.

Co-Authored-By: [your standard Claude Code co-author line]
EOF
)"
```

#### Quick Gates

Same as Phase 6: `bin/standardrb --fix` and `bundle exec brakeman -q` on the review-fixed
code; fix and commit anything new this branch introduced. Cheap now, expensive after QA.

#### Security Review (HIPAA)

Run the `/security-review` skill against the branch changes (everything on
`feature/${FEATURE_NAME}` vs. `main`):

```
/security-review
```

Brakeman (in `bin/ci`) does static Rails checks, but this is a HIPAA app — pay particular
attention to findings in these categories, which Brakeman won't catch:
- PHI (names, DOBs, diagnoses, clinical content) passed into `Honeybadger.notify` context
  hashes or written to log lines (CLAUDE.md legislates both)
- Controller actions missing Pundit `authorize`/policy-scope calls
- Mass-assignment gaps in strong params on new endpoints

Handle findings with **one fix cycle**:
1. Fix every Critical and High finding.
2. Medium/Low findings: fix the quick ones; record the rest in `.claude/pipeline-state.md`
   under "Known Issues (Security)" with a one-line justification each.
3. Commit (skip if no changes):

```bash
git add <specific files>
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
fix: address security review findings for ${FEATURE_NAME}

Co-Authored-By: [your standard Claude Code co-author line]
EOF
)"
```

If a Critical/High finding cannot be fixed in one cycle, record it under "Known Issues
(Security)" marked **UNRESOLVED — blocker for merge** so it is prominent in the PR. Do NOT
ask the user; proceed.

#### CHECKPOINT

Review fixes and security fixes are committed and all reports are on disk. Update `.claude/pipeline-state.md` with:
- Code review verdict and scale review verdict
- Security review: findings by severity, fixed vs. recorded, and the commit hash if any
- Fix-plan path and ticket counts (P0/P1/P2/P3)
- Tickets implemented vs. deferred, and any unresolved Open Questions
- Review-fixes commit hash (`git rev-parse HEAD`), if a commit was made

After any automatic compaction, re-read `.claude/pipeline-state.md` to restore variables.

---

### Phase 7.5: Requirements Traceability Gate

The plan reviews critiqued the *plan* and `/full-review` critiqued the *code quality* — this
gate verifies the code actually implements the *PRD*. A dropped requirement survives both of
those and is expensive to discover in QA (or worse, after merge).

#### Run the Trace

Invoke `/trace-requirements` with no argument (it resolves the PRD from the branch name, the
same way it works standalone):

```
/trace-requirements
```

It maps every FR and Definition of Done item to code/spec evidence in `git diff main...HEAD`
and saves a report to `.claude/requirement-traces/trace-*.md` with a verdict:
`FULLY TRACED | GAPS FOUND | SIGNIFICANT GAPS`.

#### Handle the Verdict

**If FULLY TRACED** → proceed to the HANDOFF.

**If GAPS FOUND or SIGNIFICANT GAPS** → run exactly ONE fix cycle:

1. Implement every MISSING and PARTIAL item from the report's **Gaps & Recommended Actions**
   section (they are written as executable tickets). Same constraints as Phase 6: NO system
   tests, NO feature specs; write the unit/controller/component/policy specs for each fix.
2. If the report flags **Out of Scope violations**, remove that code — the PRD's "Do NOT
   Build" list is a hard boundary. Merely-untraceable changes (review-fix hardening etc.) need
   no action; they'll be noted in state.
3. Commit:

```bash
git add <specific files>
git commit -m "$(cat <<'EOF'
feat: close requirements-trace gaps for ${FEATURE_NAME}

Implements PRD requirements found MISSING/PARTIAL by /trace-requirements.

Co-Authored-By: [your standard Claude Code co-author line]
EOF
)"
```

4. Re-run `/trace-requirements` once to confirm.

After the re-trace, whatever is still not IMPLEMENTED goes in `.claude/pipeline-state.md`
under "Known Issues (Requirements Trace)" — one line per FR/DoD item with its status and
why it couldn't be closed. Then proceed. Do NOT run a second fix cycle, do NOT ask the user.

#### CHECKPOINT

Update `.claude/pipeline-state.md` with:
- Trace verdict (final), report path, FR counts (implemented/partial/missing, Must vs. Should)
- Definition of Done counts
- Gaps fixed this cycle (FR IDs + commit hash) and gaps remaining
- Scope-drift notes (out-of-scope code removed, untraceable changes)

#### HANDOFF (end of Agent B)

Agent C (verify & ship) works in this worktree next, with a fresh context. Make sure
`.claude/pipeline-state.md` fully reflects Phases 6–7.5 (check Agent B in the Phase Log;
commit hashes, review verdicts, security findings fixed vs. recorded, fix-plan path and
ticket counts, trace verdict and FR counts, deferred tickets, open questions in the
Results / Known Issues / Deferred sections). Agent C knows ONLY what this file and the repo
contain.

Then **return**: commit hashes, items completed/skipped from the tickets doc, review verdicts,
the security-review outcome (findings by severity, any UNRESOLVED), the requirements-trace
verdict with FR counts (and gaps fixed vs. remaining), fix tickets applied vs. deferred, and
a 3-5 line summary.

---

## End of Agent B Instructions

---

## Launch Agent C — Verify & Ship (Main Conversation)

When Agent B completes, launch Agent C. It owns Phases 8–10 (system tests, QA, CI gate, PR).

**Agent C's prompt MUST include:**
1. `WORKTREE_PATH`, `FEATURE_NAME`, `MAIN_DIR` (same values as before) and `WORKTREE_PORT` = the
   value Agent A returned (also in `.claude/pipeline-state.md` Identity and `PORT=` in `.env`)
2. The **Autonomous Execution Policy**, **Important Guidelines**, and **Error Handling** sections
3. The **Phase Agent Bootstrap** block (same as Agent B's)
4. ALL instructions from Phase 8 through Phase 10 (Phase 9.5, the Acceptance Gate, included),
   including the final return requirements

**Agent tool parameters:**
- NO `isolation` parameter (works in the existing worktree)
- `description: "Verify & ship ${FEATURE_NAME}"`
- `run_in_background: false`

---

## Agent C Instructions (Include in Agent C Prompt)

Everything from here to "End of Agent C Instructions" goes in Agent C's prompt, after the
Bootstrap block.

---

### Phase 8: System Tests

Now that the implementation is reviewed and hardened, add browser-layer regression coverage.
System tests were deliberately excluded from `/plan`, `/tickets`, and `/code` — **this phase
owns them**, planned against the final code rather than the pre-review design.

#### Step S1: Plan the System Tests

Invoke `/plan-system-tests` with no argument (branch mode — it analyzes `git diff main...HEAD`
and reads the PRD for Definition of Done journeys and edge cases):

```
/plan-system-tests
```

The scenario plan is saved to `tmp/test-plans/<feature-slug>-YYYYMMDD.md`.

#### Step S2: Implement the Tests

Invoke `/system-test-expert` with the plan path:

```
/system-test-expert tmp/test-plans/<feature-slug>-*.md
```

It implements every SC/EC scenario under `spec/system/`, runs each spec file as it goes, and
stability-checks the new suite 3 consecutive times. It reports any scenario it could not get
passing rather than thrashing on it.

#### Step S3: Fix Failures and Flakes

If `system-test-expert` reports failing or flaky specs, invoke `/fix-system-test` with the
failing spec paths (pipeline mode — it reads the test plan's handoff notes, budgets 3 fix
attempts per test, and verifies with `CI=true` so rspec-retry can't mask flakiness):

```
/fix-system-test <failing spec paths>
```

Maximum 2 rounds of `/fix-system-test`. If a test is still failing after that:
- Mark that spec `pending("<reason> — see PR Known Issues")` so the suite (and later `bin/ci`)
  stays green while the gap remains visible
- Record it in `.claude/pipeline-state.md` under "Known Issues (System Tests)" with the failure
  output and root-cause hypothesis
- If `/fix-system-test` determined the **application code** is at fault and fixed it, keep that
  fix and note it — an app bug caught here is the phase working as intended

#### Step S4: Commit System Tests

```bash
# Stage the new specs plus any app-code fixes made during S3 (be specific)
git add spec/system/... <app files fixed>

git commit -m "$(cat <<'EOF'
test: add system tests for ${FEATURE_NAME}

Browser-layer coverage implemented from the /plan-system-tests scenario plan.

Co-Authored-By: [your standard Claude Code co-author line]
EOF
)"
```

#### CHECKPOINT

Update `.claude/pipeline-state.md` with:
- Test plan path, scenarios implemented (spec paths), pass/flaky/pending counts
- Any app bugs found and fixed by the system tests
- System-tests commit hash

After any automatic compaction, re-read `.claude/pipeline-state.md` to restore variables.

---

### Phase 9: QA Verification

#### Step 7: Start Dev Server

Start this worktree's development server so Playwright can verify. `bin/dev` reads the port
from `PORT=` in `.env` (assigned in Phase 3), so no Procfile edits are needed. The server is
started **detached** because it is deliberately left running for review after the pipeline.

```bash
WORKTREE_PORT="$(grep -E '^PORT=' .env | cut -d= -f2)"
BASE_URL="http://localhost:${WORKTREE_PORT}"
if curl -sk -o /dev/null "$BASE_URL"; then
  echo "Dev server already running on ${WORKTREE_PORT} (resumed run) — reusing it"
else
  mkdir -p log
  nohup bin/dev </dev/null >log/dev-server.log 2>&1 &
  disown
fi
```

Wait for the server to be ready:

```bash
for i in $(seq 1 30); do
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL" 2>/dev/null)
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "302" ]; then
    echo "Dev server ready on port ${WORKTREE_PORT}"
    break
  fi
  sleep 1
done
```

If the server fails to start after 30 seconds:
1. Check `log/dev-server.log`, try `bundle install && bin/rails db:migrate`, then retry
2. If still failing, skip QA verification and note it in the PR

#### Step 8: Run Database Migrations

```bash
bin/rails db:migrate
```

This runs against the isolated `<app>_development${DB_SUFFIX}` database (via `DATABASE_SUFFIX`
in the worktree's `.env`) — the main repo's `<app>_development` is never touched.

#### Step 9: Create QA Document

Use the `/create-qa-document` skill to generate a QA plan based on the branch changes, passing
the worktree server's base URL:

```
/create-qa-document --base-url=http://localhost:${WORKTREE_PORT}
```

**Notes:**
- The QA document analyzes `git diff main...HEAD` to understand what changed and creates appropriate test scenarios.
- The skill also reads the PRD at `.claude/prds/${FEATURE_NAME}.md` — its Acceptance Criteria table becomes QA scenarios, each tagged `**Verifies:** AC-n`. Check the plan's **AC Coverage** table: every `browser` / `browser+spec` AC (especially every **Must**) should have a scenario. If any is listed under **Uncovered**, add a scenario for it now (edit the QA plan directly — it's a working document) — an uncovered Must AC will fail the Acceptance Gate later.
- Verify the generated document's `**Base URL:**` is `http://localhost:${WORKTREE_PORT}` (`/execute-qa` reads the base URL from the document).

#### Step 10: Execute QA

Use the `/execute-qa` skill to run the QA scenarios:

```
/execute-qa docs/qa-plans/{feature-name}-*.md
```

**IMPORTANT:** `/execute-qa` reads the base URL from the QA plan document — all Playwright navigation must use the worktree port (`http://localhost:${WORKTREE_PORT}`), never 3000. Do not start a second server with `bin/dev`; the worktree server from Step 7 is the target.

**Keep screenshots for the PR:** while (or right after) executing the happy-path scenarios,
capture **2–4 screenshots of the feature's key screens** (the primary flow a human reviewer
would want to see — not error states or intermediate clicks) and save them to
`tmp/pr-screenshots/` with descriptive kebab-case names (e.g. `client-list-with-filters.png`,
`new-superbill-form.png`). These are published alongside the PR in Phase 10. Keep each under
~1MB (default viewport PNG is fine).

#### Step 11: Handle QA Results

**If all scenarios PASS:**
- Proceed to Phase 10 (Finalize)

**If scenarios FAIL with bugs:**
1. Read each bug report
2. Fix the bugs
3. **Write a regression spec for every bug fixed** — a spec that would have caught the bug
   (fails on the pre-fix code, passes on the fix). Prefer the cheapest layer that reproduces
   it (model/service/controller/component spec); use a system spec only if the bug is
   inherently browser-level (system specs are allowed here — Phase 8 is done). The existing
   system tests were written before these fixes and by definition missed the bug.
4. Commit the fixes together with their regression specs
5. Re-execute the failed QA scenarios only
6. Maximum 2 bug-fix cycles — if still failing, note remaining issues in the PR

#### Step 12: (moved) — QA infrastructure stays up

Do **not** stop the dev server or close the browser yet: Phase 9.5 may need to execute
additional scenarios. Cleanup happens at the end of Phase 9.5.

#### CHECKPOINT

QA is complete and all bug fixes are committed. Update `.claude/pipeline-state.md` with:
- QA results (scenarios passed/failed, bugs found/fixed)
- Any remaining known issues

After any automatic compaction, re-read `.claude/pipeline-state.md` to restore variables.

---

### Phase 9.5: Acceptance Gate

QA exercised scenarios; this phase asks the only question that decides whether a PR is
created: **was every user-agreed acceptance criterion observed to hold?** The PRD's
`## Acceptance Criteria` table (`AC-n` rows, agreed with the user in `/prd`) is the contract.

#### Step A1: Score the criteria

Invoke `/verify-acceptance` with no argument (it resolves the PRD from the branch name):

```
/verify-acceptance
```

It joins the QA plan's `Verifies:` tags with `/execute-qa`'s PASS/FAIL results, runs the
branch's system specs (`CI=true`) and the specs that cover `spec` criteria, runs any `manual`
criteria's stated commands, and writes
`.claude/acceptance-scorecards/scorecard-${FEATURE_NAME}-*.md` with a verdict:
`PASS | PASS WITH SHOULD GAPS | FAIL`.

#### Step A2: Close gaps (max 2 cycles)

**If PASS** → go to Step A3.

**Otherwise**, work the scorecard's **Gaps & Recommended Actions**, Must rows first:
- **UNVERIFIED — coverage gap (browser)**: add a scenario to the QA plan
  (`docs/qa-plans/${FEATURE_NAME}-*.md`) with `**Verifies:** AC-n` whose expected results
  assert the criterion's *Then* clause literally, then run `/execute-qa` on **that scenario
  only**; or add a system spec example whose description contains `(AC-n)` and get it passing.
- **UNVERIFIED — coverage gap (spec)**: write the spec that exercises the criterion (unit /
  service / controller / component / policy) and get it passing.
- **FAILED**: fix the app bug **and write a regression spec** (same rule as Step 11), then
  re-execute the covering scenario / spec.
- **UNVERIFIED — manual**: run the stated command against the dev DB and confirm the output;
  if the criterion names no runnable command, it stays UNVERIFIED (note it — this is a PRD
  defect to surface).
- Commit each cycle's changes:

```bash
git add <specific files>
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
fix: close acceptance-criteria gaps for ${FEATURE_NAME}

Addresses non-VERIFIED rows of the /verify-acceptance scorecard.

Co-Authored-By: [your standard Claude Code co-author line]
EOF
)"
```

Then re-run `/verify-acceptance`. **Maximum 2 gap-closing cycles.** Never satisfy a criterion
by weakening a spec, deleting a scenario, or editing the PRD's table — the contract is the
user's, not yours.

#### Step A3: Close the browser; leave the server running

```bash
mcp__playwright__browser_close
```

Do NOT stop the dev server. The server on `${WORKTREE_PORT}` is deliberately kept alive — it
is the review server handed to the developer in Phase 11.

Delete any screenshots created during verification (in `.playwright-mcp/` or elsewhere) —
**EXCEPT `tmp/pr-screenshots/`**, which Phase 10 publishes with the PR.

#### CHECKPOINT

Update `.claude/pipeline-state.md`'s `## Acceptance` block with the **final** verdict, the
scorecard path, Must/Should counts, one line per non-VERIFIED AC (ID, priority, status,
reason), and the gap-fix commit hashes. **Continue to Phase 10 regardless of verdict** —
simplification, CI, and screenshots still run; the verdict is applied at Step 18.

After any automatic compaction, re-read `.claude/pipeline-state.md` to restore variables.

---

### Phase 10: Finalize and Create PR

#### Step 13: Simplification Pass

By this point the code has been patched by four different hands (implementation, review
fixes, system-test app fixes, QA bug fixes) and has accumulated cruft. Run the `/simplify`
skill — it reviews the branch's changed code for reuse, simplification, efficiency, and
altitude cleanups and applies the fixes:

```
/simplify
```

Then:
1. Run the specs for the files it touched (`bundle exec rspec <specs>`) — fix or revert
   anything it broke.
2. Commit (skip if it made no changes):

```bash
git add <specific files>
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
refactor: simplify ${FEATURE_NAME} after review and QA fixes

Co-Authored-By: [your standard Claude Code co-author line]
EOF
)"
```

This is quality-only cleanup — if any simplification would change behavior QA already
verified, skip that change. If Step 14's CI failures trace back to this commit and can't be
fixed within the normal cycles, `git revert` this commit rather than shipping a broken
simplification.

#### Step 14: Final CI Gate

Run CI one final time to ensure everything is clean:

```bash
bin/ci
```

If CI fails:
1. Fix the failures
2. Re-run `bin/ci`
3. Maximum 3 fix cycles — if still failing after 3 cycles, record the remaining CI failures in `.claude/pipeline-state.md` under "Known Issues (CI)", proceed to open the PR as a **draft** (subject to the Acceptance Gate in Step 18 — a FAIL verdict still means no PR), and surface the failures in the PR description's Known Issues section. Do NOT stop to ask the user.

CI should pass before creating the PR, but a draft PR with documented failures is preferred over halting the pipeline.

#### Step 15: Publish QA Screenshots

Publish the screenshots kept in `tmp/pr-screenshots/` (Step 10) to a dedicated orphan branch
so the PR body can embed them without committing binaries to the feature branch:

```bash
if ls tmp/pr-screenshots/*.png >/dev/null 2>&1; then
  SHOT_BRANCH="screenshots/${FEATURE_NAME}"
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

  # Build the orphan branch in a temporary worktree (keeps this checkout untouched)
  git worktree add --detach ../pr-shots-tmp
  cd ../pr-shots-tmp
  git checkout --orphan "$SHOT_BRANCH"
  git rm -rf --quiet . 2>/dev/null || true
  cp "${OLDPWD}/tmp/pr-screenshots/"*.png .
  git add ./*.png
  git commit -m "QA screenshots for ${FEATURE_NAME}"
  git push -f origin "$SHOT_BRANCH"
  cd "$OLDPWD"
  git worktree remove --force ../pr-shots-tmp
fi
```

Image URLs for the PR body (one per screenshot; these render for anyone with repo access):

```
https://github.com/${REPO}/blob/screenshots/${FEATURE_NAME}/<name>.png?raw=true
```

**If anything in this step fails** (no screenshots captured, push rejected), skip it — the PR
gets a "Screenshots: not available" line instead. Never let this step block the pipeline.

#### Step 16: Draft the PR Body

**Do this BEFORE removing pipeline artifacts** — the PR body is built from
`.claude/pipeline-state.md`, which Step 17 deletes. Drafting after cleanup (or after a context
compaction) would mean reconstructing Known Issues from memory, which is unreliable.

Read `.claude/pipeline-state.md` and write the complete PR body to `tmp/pr-body.md`
(gitignored, survives cleanup):

```markdown
## Summary

Implements ${FEATURE_NAME} as specified in the PRD (committed on this branch at
`.claude/prds/${FEATURE_NAME}.md`).

[2-3 bullet points describing what was built]

## Acceptance Criteria

**Verdict: PASS | PASS WITH SHOULD GAPS** — Must X/Y • Should X/Y (agreed [date]; scorecard
by `/verify-acceptance`)

| AC | Priority | Status | Evidence |
|----|----------|--------|----------|
| AC-1 | Must | VERIFIED | SC-003 PASS · `spec/system/…:12` |
[one row per AC from the scorecard; non-VERIFIED Should rows in bold with the reason]

## Screenshots

[One image per screenshot from Step 15, with a one-line caption:
![caption](https://github.com/{owner/repo}/blob/screenshots/{feature}/{name}.png?raw=true)
The `screenshots/{feature}` branch can be deleted after merge.
If Step 15 was skipped: "Screenshots: not available"]

## Reviews Completed

- Architect Review: [verdict]
- Frontend Review: [verdict]
- Security Review: [Critical/High fixed: N; recorded findings: N or "None"; UNRESOLVED
  blockers listed prominently if any]

## Requirements Trace

- FRs implemented: X/Y (Must: X/Y, Should: X/Y)
- Definition of Done traced: X/Y
- Gaps: [FR IDs still PARTIAL/MISSING with one-line reasons, or "None"]

## System Tests

- Scenarios Implemented: X (spec/system/...)
- Passing: X | Pending (documented): Y
- App bugs caught and fixed by system tests: [list or "None"]

## QA Results

- Scenarios Passed: X/Y
- Bugs Found and Fixed: Z

## Known Issues

[List any unverified Should acceptance criteria (with the scorecard reason), retry-limit
escalations, unresolved review feedback, failing CI checks, or QA bugs that were not resolved
within this pipeline. Pull these from `.claude/pipeline-state.md` NOW, while it still exists.
If none, write "None."]

## Changes

- `file1` - description
- `file2` - description

## Testing

- [ ] `bin/ci` passes (linting, security, tests)
- [ ] QA scenarios pass (Playwright verification)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Fill in every placeholder with real values from `.claude/pipeline-state.md` — the file written
to `tmp/pr-body.md` must be final, ready to submit verbatim.

#### Step 17: Remove Pipeline Artifacts

Read the Acceptance verdict from `.claude/pipeline-state.md` first — it changes what this step
and Step 18 do.

Delete the planning, review, ticket, and QA documents generated **by this pipeline run**.
These are working documents and should NOT be part of the PR.

**Delete by scoped filename pattern — NEVER by whole directory.** The worktree is a full
checkout: directories like `docs/qa-plans/` may contain files committed to `main` by other
work, and a directory-level `rm -rf` would delete tracked files (which the cleanup commit
would then destructively pick up).

```bash
# Planning and review artifacts (generated in this worktree by /plan, /architect-review,
# /frontend-review, /tickets, /full-review)
rm -f .claude/implementation-plan-*.md
rm -f .claude/tickets-*.md
rm -f .claude/architect-review-*.md
rm -f .claude/frontend-review-*.md
rm -f .claude/reviews/branch-review-*.md
rm -f .claude/scale-reviews/scale-review-*.md
rm -f .claude/fix-plans/fix-plan-*.md

# Requirements-trace reports and acceptance scorecards (feature-scoped)
rm -f .claude/requirement-traces/trace-${FEATURE_NAME}-*.md
rm -f .claude/acceptance-scorecards/scorecard-${FEATURE_NAME}-*.md

# QA plans and bug reports (feature-scoped)
rm -f docs/qa-plans/${FEATURE_NAME}-*.md
rm -rf docs/bug-reports/qa-${FEATURE_NAME}-*/

# System test plans (feature-scoped; the tests under spec/system/ are product code — KEEP them)
rm -f tmp/test-plans/${FEATURE_NAME}-*.md

# Remove now-empty artifact directories only (rmdir refuses non-empty ones)
rmdir .claude/reviews .claude/scale-reviews .claude/fix-plans .claude/requirement-traces \
      .claude/acceptance-scorecards docs/qa-plans docs/bug-reports tmp/test-plans 2>/dev/null || true

# Pipeline state file — ONLY when the Acceptance verdict is PASS or PASS WITH SHOULD GAPS.
# On FAIL, keep it (and copy the scorecard to tmp/) so a relaunched Agent C can resume:
#   cp .claude/acceptance-scorecards/scorecard-${FEATURE_NAME}-*.md tmp/acceptance-scorecard.md
rm -f .claude/pipeline-state.md
```

**On a FAIL verdict**, also keep the scorecard file itself (skip its `rm -f` above) — it is
the resume input for the next run. Delete only the other artifacts.

Preserve `.claude/skills/`, `.claude/prds/` (the PRD is intentionally committed), and every
other permanent file.

Check what the deletions touched:
```bash
git status --short
```

- If the deleted files were never committed, `git status` shows nothing to do — no cleanup
  commit is needed.
- If some artifact files WERE committed earlier in the pipeline, stage **those specific
  deletions only** (never `git add -A`) and commit:

```bash
git add <the specific deleted artifact paths>
git diff --cached --quiet || git commit -m "$(cat <<'EOF'
chore: remove pipeline artifacts

Co-Authored-By: [your standard Claude Code co-author line]
EOF
)"
```

#### Step 18: Rebase, Push, and Create PR

The pipeline runs for hours — `main` may have moved. Rebase onto the fresh remote base before
pushing so the PR isn't stale on arrival:

```bash
git fetch origin main
git rebase origin/main
```

- **Clean rebase, no new commits pulled in** (`git rev-list HEAD..origin/main` was empty):
  push directly.
- **Clean rebase over new main commits**: run the specs for this feature's files
  (`bundle exec rspec <this feature's spec files>`) as a smoke check, then push. Full `bin/ci`
  already ran in Step 14; don't repeat it unless the smoke check fails.
- **Conflicts**: resolve them — preserve BOTH intents (this feature's behavior and main's
  changes); when a conflict is in code unrelated to this feature, prefer main's side. After
  resolving, re-run the specs for every conflicted file. If the rebase turns into a mess
  (repeated conflicts you can't confidently resolve), `git rebase --abort` and push the
  un-rebased branch — note "branch is behind main; rebase needed before merge" in the PR's
  Known Issues instead. A pushable PR beats a mangled rebase.

Push the branch, then apply the **Acceptance Gate** using the verdict recorded in
`.claude/pipeline-state.md` (`## Acceptance`):

```bash
git push -u origin "feature/${FEATURE_NAME}"
```

- **PASS** → create the PR from the body drafted in Step 16 (do NOT compose the body inline):

  ```bash
  gh pr create --title "feat: ${FEATURE_NAME}" --body-file tmp/pr-body.md
  ```

- **PASS WITH SHOULD GAPS** → create it as a **draft**; the body's Acceptance Criteria section
  already leads with the unverified Should rows:

  ```bash
  gh pr create --draft --title "feat: ${FEATURE_NAME}" --body-file tmp/pr-body.md
  ```

- **FAIL** (any Must AC not VERIFIED after Step A2's cycles) → **do not create a PR.** The
  branch is pushed so nothing is lost. Leave `.claude/pipeline-state.md`, the scorecard, and
  `tmp/pr-body.md` in place (the worktree, databases, and server are kept — as for every
  outcome), and return `GATE FAILED` with the list of unmet Must ACs (ID + status + reason) and the
  scorecard path. This is the pipeline's one intentional stop short of a PR — do NOT open a
  draft "just to ship something", and do NOT edit the PRD's table to make it pass.

After a PR is created (PASS or draft):

```bash
# Remove the drafted body and published screenshots now that the PR exists
rm -f tmp/pr-body.md
rm -rf tmp/pr-screenshots/
```

#### Step 19: Databases are kept

Do NOT drop the databases. The worktree and both suffixed databases persist for review;
`/worktree-sweep` (run automatically at the start of the next `/build-feature`) removes them
once the PR is merged or closed.

**Return the PR URL (or `GATE FAILED` + unmet Must ACs + scorecard path), `WORKTREE_PORT`, the
acceptance verdict with Must/Should counts, and a summary of the pipeline results (system
tests, QA, CI, known issues).**

---

## End of Agent C Instructions

---

## Phase 11 (Main Conversation): Report Results and Hand Off

After Agent C completes, you will have:
- The PR URL (from Agent C)
- Pipeline results summaries (from all three agents)
- The worktree path and port (from Agent A)

### Step 1: Report to User

Present the final summary:

```
Feature Build Complete: ${FEATURE_NAME}

PRD: ${1}
Branch: feature/${FEATURE_NAME}
PR: [PR URL]
Review at: http://localhost:${WORKTREE_PORT}
Worktree: ${WORKTREE_PATH}

Pipeline Results:
- Acceptance Criteria: [verdict] — Must X/Y, Should X/Y (agreed [date])
- Plan: Created and refined
- Architect Review: [verdict]
- Frontend Review: [verdict]
- Implementation: Complete
- Tests: [passed/failed count]
- System Tests: [X scenarios, Y passing, Z pending]
- Linting: [passed/failed]
- Security Scan: [passed/failed]
- QA Scenarios: [X/Y passed]
- Bugs Fixed: [count]
- Screenshots: [screenshots/${FEATURE_NAME} branch — delete after merge | not available]
```

**If Agent C returned `GATE FAILED`:** the report's first line is
`Feature Build STOPPED at Acceptance Gate: ${FEATURE_NAME}` followed by each unmet **Must** AC
(ID, criterion, status, scorecard reason), the scorecard path, the pushed branch name, and the
same `Review at:` / `Worktree:` lines. Then
tell the user how to resume once the criteria or the code are fixed: relaunch Agent C with the
same prompt (it bootstraps from `.claude/pipeline-state.md` in the worktree, skips completed
steps, and re-enters Phase 9.5), or — if the PRD's criteria themselves were wrong — re-run
`/prd` to re-agree them and then relaunch Agent C. Step 2 runs for GATE FAILED too.

### Step 2: Hand off the worktree for review

Runs for **every** outcome (PR, draft PR, GATE FAILED), in the main conversation because it
outlives every phase agent. Make sure the review server answers, then open the worktree:

```bash
cd "${WORKTREE_PATH}"
WORKTREE_PORT="$(grep -E '^PORT=' .env | cut -d= -f2)"
BASE_URL="http://localhost:${WORKTREE_PORT}"
if ! curl -sk -o /dev/null "$BASE_URL"; then
  mkdir -p log
  nohup bin/dev </dev/null >log/dev-server.log 2>&1 &
  disown
  for i in $(seq 1 30); do curl -sk -o /dev/null "$BASE_URL" && break; sleep 1; done
fi
curl -sk -o /dev/null -w '%{http_code}\n' "$BASE_URL"   # expect 200/302
open -a "Visual Studio Code" "${WORKTREE_PATH}"
cd $MAIN_DIR
```

If the server still doesn't answer after 30 s: report the URL anyway, plus the manual command
`cd ${WORKTREE_PATH} && bin/dev` and the last 20 lines of `log/dev-server.log`.

### Step 3: Cleanup happens later

Nothing is removed now. The worktree, its databases, and its server stay for review; the next
`/build-feature` (Phase 1 Step 0) or `/worktree-sweep` removes them after the PR is merged or
closed.

## Important Guidelines

1. **Three phase agents, one worktree** — Agent A (`isolation: "worktree"`) creates the worktree; Agents B and C are plain agents that `cd` into it. Never give B or C the `isolation` parameter, never run them in parallel, and never do worktree work from the main conversation. `.claude/pipeline-state.md` is the only handoff between agents — each agent must leave it complete enough that the next agent (or a relaunch of itself) can proceed without any other context.
2. **System tests have a dedicated phase** — They are excluded from `/plan`, `/tickets`, and `/code`, then written in Phase 8 (`/plan-system-tests` → `/system-test-expert` → `/fix-system-test`) against the reviewed code. Feature specs (`spec/features/`) are never created (project policy). Playwright QA via `/execute-qa` remains a separate, additional verification layer.
3. **Incorporate review feedback into the plan** — Don't just note the feedback; actually edit the plan to address it before proceeding.
4. **Maximum retry cycles** — Plan reviews get max 2 parallel rounds (one merge pass each), the security review and requirements-trace gate get max 1 fix cycle each, bug fixes get max 2 cycles, acceptance-gap closing gets max 2 cycles, test fixes get max 3 cycles. When a limit is reached, record the remaining issue in `.claude/pipeline-state.md` and the PR's Known Issues section, then continue. Do NOT pause the pipeline to ask the user.
10. **The Acceptance Criteria table is the user's contract** — it decides PR / draft / no PR (Step 18). Never edit it, never weaken a spec or delete a QA scenario to turn a row green, and never mark a row VERIFIED from code reading. If the contract itself is wrong, that is a `GATE FAILED` outcome the user resolves by re-running `/prd`.
5. **Be transparent** — Report progress at each phase transition so the user can track the pipeline.
6. **Clean up after yourself** — Close the browser and delete temp files; the worktree dev server is intentionally **left running** for review.
7. **Commit incrementally** — Main implementation commit, then separate fix commits if needed.
8. **Per-worktree port** — The dev server port is `PORT=` in the worktree's `.env` (assigned by `bin/worktree-port` in Phase 3, range 3010–3099); always read it from `.env`/state, never hardcode a port number.
9. **Isolated databases** — `DATABASE_SUFFIX` in the worktree's `.env` gives the pipeline its own `<app>_development_*` / `<app>_test_*` databases. Never remove the suffix or run against the shared databases; they persist until `/worktree-sweep` removes the worktree. Because the suffix lives only in the worktree's `.env` (and `config/database.yml` treats an unset suffix as a no-op), all composed skills run unmodified — both inside this pipeline and standalone in the main repo.

## Error Handling

The pipeline should continue through to PR creation whenever possible. Record issues and keep moving — do NOT pause mid-pipeline to ask the user.

- **PRD not found**: Hard stop. Inform user, suggest `/prd` to create one.
- **PRD has no `## Acceptance Criteria` table, or it lacks the `Agreed with user` stamp**: Hard stop before any worktree is created. Tell the user to run `/prd` to draft and agree the criteria, then re-run `/build-feature`.
- **`/verify-acceptance` finds no QA report or no `Verifies:` tags**: browser ACs are UNVERIFIED, never assumed PASS. Fix the coverage (Step A2) — tag scenarios / add scenarios / add system specs — rather than arguing with the verdict.
- **Acceptance verdict still FAIL after 2 gap-closing cycles**: finish Phase 10 through the push, then stop without a PR (Step 18). The worktree, `.claude/pipeline-state.md`, the scorecard, and the isolated databases are kept (as always) for a resumable relaunch of Agent C. Report the unmet Must ACs to the user.
- **Acceptance verdict PASS WITH SHOULD GAPS**: open the PR as a draft with the unverified Should rows at the top of its Acceptance Criteria section.
- **Worktree setup fails**: Retry once, then report the error and stop (the pipeline cannot continue without a working tree).
- **A phase agent dies or returns unusable output**: Relaunch that agent with the same prompt (max 1 relaunch per agent). The bootstrap has it re-read `.claude/pipeline-state.md` and `git log` and skip already-completed steps — do NOT restart the pipeline from Agent A. If Agent A died before creating the worktree, relaunch Agent A (that's the one case where a fresh worktree is correct).
- **Isolated database setup fails** (`db:prepare` errors): Try `bundle install` then retry once. If it still fails, stop and report — do NOT fall back to the shared `<app>_development` database.
- **Plan reviews still have open findings after 2 parallel rounds**: Do a final merge pass, record remaining issues in `.claude/pipeline-state.md`, and proceed. Surface them in the PR's Known Issues section.
- **Implementation fails on specific tickets**: Skip the failing ticket, log it as a known issue, and continue with remaining tickets.
- **Requirements trace still shows gaps after the fix cycle**: Record each remaining PARTIAL/MISSING FR in `.claude/pipeline-state.md` under "Known Issues (Requirements Trace)" and proceed — they surface in the PR's Requirements Trace and Known Issues sections. A remaining Must-priority gap does NOT stop the pipeline, but it must be prominent in the PR description.
- **Security review Critical/High finding unfixable in one cycle**: Record it under "Known Issues (Security)" marked **UNRESOLVED — blocker for merge** and proceed; it must appear prominently in the PR's Reviews Completed and Known Issues sections.
- **Simplification pass breaks tests**: Fix within the normal CI cycles, or `git revert` the simplify commit — never ship a broken simplification, and never weaken specs to accommodate one.
- **Screenshot publish fails** (no captures, push rejected): Skip Step 15, write "Screenshots: not available" in the PR body, and continue. This step must never block the pipeline.
- **Rebase onto origin/main can't be resolved confidently**: `git rebase --abort`, push the un-rebased branch, and note "branch is behind main; rebase needed before merge" in the PR's Known Issues. Never push a rebase whose conflict resolutions you aren't sure of.
- **System test unfixable after 2 `/fix-system-test` rounds**: Mark the spec `pending` with an explanatory reason, record it in `.claude/pipeline-state.md` under "Known Issues (System Tests)", and continue. Never delete the test or weaken its assertions to force green.
- **Tests fail after 3 fix cycles**: Record the failing tests in `.claude/pipeline-state.md`, open the PR as a draft, and surface failures in the PR description.
- **Dev server won't start**: Check `log/dev-server.log`, try `bundle install && bin/rails db:migrate`, then skip QA if still failing. Note "QA skipped: dev server unavailable" in the PR.
- **QA finds bugs after 2 fix cycles**: Note remaining bugs in the PR description and continue.
- **PR creation fails**: Check if branch is pushed and `gh auth status`; retry once. If it still fails, leave the branch pushed and report the manual `gh pr create` command to the user at the end.
- **Port range exhausted** (`bin/worktree-port` exits 1): hard stop in Phase 3; relay the message and suggest `/worktree-sweep`.
- **Sweep fails or `gh` unauthenticated** in Phase 1: print the output and continue.
- **Handoff server won't start** in Phase 11: still report the URL and worktree path, plus the manual `cd <worktree> && bin/dev` command and the log tail.
