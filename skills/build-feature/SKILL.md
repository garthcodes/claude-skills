---
description: End-to-end feature build from PRD to PR — plan, review, implement, QA, and ship in a worktree
argument-hint: <path-to-prd.md>
---

# Build Feature: PRD to PR Pipeline

Automated end-to-end pipeline that takes a PRD document and produces a reviewed, QA-verified pull
request. All work happens in a single git worktree, executed by **nine phase agents** (sequential except two parallel pairs, B2 ‖ B3 and C1 ‖ C2) —
each gets a fresh context, and `.claude/pipeline-state.md` in the worktree is the formal handoff
contract between them. Implementation itself runs in **fresh worker sub-agents** (one per ticket
phase, model `IMPLEMENT_MODEL`, default `sonnet`) so no single context ever carries the whole build.
`/plan` and `/tickets` split the work into a serial Foundation, independent lanes, and a serial
Integration phase, so B1 can run up to three lanes at once (the tickets doc's `## Phase Schedule`).

This file is the **coordinator's** instructions (main conversation). Every phase agent's
instructions live in `phases/` next to it and are read by the agent itself:

| File | Contents |
|---|---|
| `phases/_shared.md` | Autonomous policy, bootstrap, state-file schema, context hygiene, worker recipe, guidelines, error handling |
| `phases/01-setup-plan.md` … `phases/09-ship.md` | One file per phase agent: Inputs → Steps → CHECKPOINT → RETURN |

## Why nine agents

Every tool call re-reads an agent's whole context, so tokens grow with the square of what one agent
lets in. Past three-agent runs peaked at 400k–880k tokens per agent with 100M–1B input tokens per
phase; the same steps cut at the existing checkpoints run at a fraction of that with identical
gates. Nothing about *what* is checked changed — only where the context boundaries are.

## Autonomous Execution Policy

**This pipeline runs end-to-end without stopping to ask the user for confirmation.** Phase agents
record issues in `.claude/pipeline-state.md` (surfaced in the PR's **Known Issues**) and keep going;
the coordinator relaunches an agent that dies (max once) instead of asking. The only hard stops
before a worktree exists are "no PRD" and a FAIL contract review (Step 1b). The one deliberate stop
short of a PR is the **Acceptance Gate** (C3/C4): an unmet **Must** criterion pushes the branch and
returns `GATE FAILED` instead of opening a PR; unmet **Should** criteria open a draft.

## Pipeline Overview

```
PRD Document
  -> Read PRD (main conversation)
  -> /acceptance-criteria <prd> -> /review-acceptance-criteria (the CONTRACT; hard stop on FAIL)

  A1 Setup & plan        (creates THE worktree under ${PRIMARY_DIR}/.claude/worktrees/)
     git worktree add, .env + certs, DATABASE_SUFFIX, bin/worktree-port, commit PRD + contract, /plan
  A2 Plan reviews & tickets
     /architect-review + /frontend-review (parallel) -> merge -> confirmation round -> /tickets
  B1 Implement           one Sonnet worker per ticket phase running /code — scope: Phase N, wave by wave
                         (a `parallel` wave's 2–3 phases run concurrently, own files + own test DB); commit per wave; branch specs; quick gates
  ┌ B2 Code review       /full-review --plan-only -> worker /code <fix-plan> — scope: P0–P2; commit; quick gates   (lead)
  └ B3 Security & trace  /security-review + /trace-requirements (read-only) ‖ wait for B2 ✓ -> fix cycles -> contract diff check
  ┌ C1 System tests      /plan-system-tests -> /system-test-expert -> existing red specs -> /fix-system-test (≤2) -> commit   (lead)
  └ C2 QA                dev server -> /create-qa-document -> /execute-qa ‖ wait for C1 ✓ -> bug fixes (≤2) + screenshots
  C3 Acceptance gate     /verify-acceptance -> close gaps (≤2) -> close browser (server stays up)
  C4 Ship                /simplify -> bin/ci (≤3, polled) -> screenshots branch -> PR body -> cleanup -> rebase -> push -> PR -> cold review
                         ACCEPTANCE GATE: PASS -> PR | SHOULD GAPS -> draft PR | FAIL -> no PR

  -> Report results to user
  -> Handoff: dev server running (detached), VSCode open, "Review at" URL (all outcomes)
  -> PR / draft PR opened from a /prd-worktree? Remove that PRD worktree
```

## Orchestration Model

- **A1** creates the worktree itself with `git worktree add` at
  `${PRIMARY_DIR}/.claude/worktrees/${FEATURE_NAME}` and returns its path. No agent is launched with
  `isolation: "worktree"`: Claude Code would nest that worktree inside the launching checkout, so
  removing a `/prd-worktree` checkout would delete the pipeline worktree with it, and
  `bin/worktree-port` would not see its port.
- **A2 … C4** receive `WORKTREE_PATH` and `cd` there first.
- Launch each agent with `run_in_background: false` and wait for its RETURN block before launching
  the next — **except the two parallel pairs, B2 ‖ B3 and C1 ‖ C2**, whose members are launched
  together (two Agent calls in one message) and both awaited before the next step. In each pair the
  first agent is the *lead* (writes freely); the second is the *follower* — it does its read-only
  work at once and holds every commit, tracked-file edit, and state-file write until the lead has
  checked its Phase Log box (protocol in `_shared.md` → Parallel pairs). Relay one line per RETURN.
- Agents read their instructions from **`${MAIN_DIR}/.claude/skills/build-feature/phases/`** (the
  launching checkout, always the newest version) — never paraphrase those files into the prompt.
- **Recovery:** an agent that dies or returns an unusable RETURN block is relaunched once with the
  identical prompt; it bootstraps from the state file and `git log`. Never restart from A1 unless A1
  itself died before creating the worktree.
- **Model:** phase agents inherit the session model (omit `model`). Implementation workers inside
  B1/B2/B3 use `IMPLEMENT_MODEL` (`sonnet` unless the user says otherwise; `inherit` disables the
  override). The Max-plan docs don't publish per-model weighting, so treat this as the user's call.

Skill independence note: the composed skills (`/acceptance-criteria`, `/review-acceptance-criteria`,
`/plan`, `/architect-review`, `/frontend-review`, `/tickets`, `/code`, `/full-review`,
`/security-review`, `/trace-requirements`, `/plan-system-tests`, `/system-test-expert`,
`/fix-system-test`, `/create-qa-document`, `/execute-qa`, `/verify-acceptance`, `/simplify`) know
nothing about phase agents or the state file and run unmodified standalone. `/code`'s optional
`scope:` argument and `/full-review`'s `--plan-only` flag exist for this pipeline but are plain
skill features.

## Phase 1: Validate Input (Main Conversation)

### Step 1: Read the PRD

Read the PRD document at "${1}".

If "${1}" is empty or not provided:
- Search for the most recent PRD: `ls -t .claude/prds/*.md 2>/dev/null | head -1`
- If no PRD found, inform the user and stop. Suggest running `/prd` first.

Extract from the PRD:
- **Feature slug** — PRDs generated by `/prd` declare it in the header
  (`*Feature slug: `feature-slug`*`). Use it verbatim as `FEATURE_NAME`. If the PRD has no
  slug line, convert the feature name to kebab-case instead.
- **Feature name** (for the PR title)
- **Executive summary** (for plan context)
- **Full requirements** (passed to /plan)

Ignore any `## Acceptance Criteria` section embedded in the PRD — the contract is always
generated fresh in Step 1b.

### Step 1b: Build the contract (second hard stop)

The Acceptance Criteria contract is what every later phase builds to, reviews against, and
gates the PR on. Generate it and review it **now, in the main conversation, before any
worktree exists**, so a defective contract costs seconds rather than a full pipeline run.

1. Invoke `/acceptance-criteria` with the PRD path:

   ```
   /acceptance-criteria ${1}
   ```

   It writes `.claude/acceptance-criteria/${FEATURE_NAME}.md` — one Given/When/Then row per
   FR, permission denial, edge case, UX state, and Out-of-Scope **guard** (an observable
   absence — the rows that catch extras). If the file already exists with
   `*Review status: PASS …*`, the skill writes a timestamped copy instead; **use the existing
   reviewed contract** and delete the copy — a PASS contract is not regenerated by the
   pipeline.

2. Invoke `/review-acceptance-criteria` on it:

   ```
   /review-acceptance-criteria .claude/acceptance-criteria/${FEATURE_NAME}.md
   ```

   It audits the contract against the PRD in both directions (nothing left out, nothing
   invented), fixes the contract in place (max 2 cycles), and stamps `*Review status:*`.

3. Apply the verdict:
   - **PASS** or **PASS WITH MINORS** → continue. Set
     `AC_PATH=.claude/acceptance-criteria/${FEATURE_NAME}.md` and `AC_REVIEW=<report path>`.
   - **FAIL** → **hard stop.** Print the review's open BLOCKER/MAJOR findings and its
     `## PRD Defects` list, and tell the user: "The acceptance-criteria contract can't gate a
     build yet — resolve the PRD defects above (`/prd` on this PRD), then re-run
     `/build-feature`." This and "no PRD" are the only stops before a worktree is created.

Extract from the contract: the `## Contract` table verbatim, the counts (Must / Should, and
how many rows are `guard`), and the review report path. Show the counts in the conversation.

Also derive `MAIN_DIR` = the absolute path of the checkout you are running in (`pwd`; normally
the main repo checkout), and `PRIMARY_DIR` = the primary checkout:

```bash
PRIMARY_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
PRD_BRANCH="$(git branch --show-current)"
[ "$MAIN_DIR" != "$PRIMARY_DIR" ] && [ -f "$(git rev-parse --absolute-git-dir)/prd-worktree" ] \
  && echo PRD_WORKTREE=1 || echo PRD_WORKTREE=0
```

`PRD_WORKTREE=1` means you were launched from a `/prd-worktree` checkout; Phase 11 Step 3 may
remove it. If the user asked for a different implementation model, set
`IMPLEMENT_MODEL` accordingly; otherwise `IMPLEMENT_MODEL=sonnet`.

## Phase 2: Launch the phase agents (Main Conversation)

Launch the agents **in order** — A1, A2, B1, then **B2 + B3 together**, then **C1 + C2 together**
(only after both B2 and B3 have returned), then C3, then C4 — each step after the previous RETURN
block(s) arrive. Every prompt is the
same short template — only `PHASE`, the phase file, and (after A1) `WORKTREE_PATH` change:

```
You are phase agent ${PHASE} (${PHASE_NAME}) of the /build-feature pipeline for ${FEATURE_NAME}.
Identity:
  PHASE=${PHASE}  FEATURE_NAME=${FEATURE_NAME}  MAIN_DIR=${MAIN_DIR}  PRIMARY_DIR=${PRIMARY_DIR}
  WORKTREE_PATH=${WORKTREE_PATH}      # A1: "you create it"
  PRD=${1}  AC_PATH=${AC_PATH}  AC_REVIEW=${AC_REVIEW}  IMPLEMENT_MODEL=${IMPLEMENT_MODEL}
First Read ${MAIN_DIR}/.claude/skills/build-feature/phases/_shared.md, then
${MAIN_DIR}/.claude/skills/build-feature/phases/${PHASE_FILE}. Follow them exactly — they are your
complete instructions — and end with the RETURN block the phase file specifies.
```

| PHASE | PHASE_NAME | PHASE_FILE | Agent tool parameters |
|---|---|---|---|
| A1 | Setup & plan | `01-setup-plan.md` | `description: "Plan ${FEATURE_NAME}"` |
| A2 | Plan reviews & tickets | `02-plan-review-tickets.md` | `description: "Review plan ${FEATURE_NAME}"` |
| B1 | Implement | `03-implement.md` | `description: "Implement ${FEATURE_NAME}"` |
| B2 | Code review | `04-code-review.md` | `description: "Code review ${FEATURE_NAME}"` |
| B3 | Security & trace | `05-security-trace.md` | `description: "Security & trace ${FEATURE_NAME}"` |
| C1 | System tests | `06-system-tests.md` | `description: "System tests ${FEATURE_NAME}"` |
| C2 | QA | `07-qa.md` | `description: "QA ${FEATURE_NAME}"` |
| C3 | Acceptance gate | `08-acceptance.md` | `description: "Acceptance gate ${FEATURE_NAME}"` |
| C4 | Ship | `09-ship.md` | `description: "Ship ${FEATURE_NAME}"` |

All: `subagent_type: "general-purpose"`, `run_in_background: false`, no `model` parameter, no
`isolation`.

After **A1** returns, take `WORKTREE_PATH` from its RETURN block (it is also in the state file's
Identity) and pass it to every later agent. Ports are always re-read from the worktree `.env` by the
agents themselves, so you never need to forward a port number.

**Coordinator rules while agents run**
- Do not do worktree work yourself; do not read the large artifacts (plan, tickets, reports) into the
  main conversation — the RETURN blocks carry what the user needs.
- After each RETURN, print one line: `✓ ${PHASE} ${PHASE_NAME} — <headline from the RETURN>`.
- An agent's RETURN says `STILL_RUNNING` or the agent returned while `bin/ci` was still going (C4)?
  Relaunch C4 — its phase file makes it resume from the CI step and poll to completion. Never watch a
  pid from the main conversation.
- A1 died before writing the state file → relaunch A1 (its Step 1 clears the leftover worktree). Any other
  agent died → relaunch it once with the identical prompt; if it dies again, stop and report the
  phase, the worktree path, and the state file location so the user can resume manually.
- **Before any relaunch**, make sure the previous run left nothing behind: its task notification says
  it stopped with no live children, and `pgrep -fl "rspec|bin/ci"` shows nothing running in the
  worktree. A RETURN marked INCOMPLETE while a worker is still running → wait for that worker's own
  report (or its "stopped" notification) first; relaunching on top of it duplicates the worker and
  deadlocks the test DB.
- **Parallel pairs**: if one member of a pair dies, relaunch only that member (the other keeps
  running); the next step waits for both RETURNs. A follower whose lead dies waits — it resumes when
  the relaunched lead checks its box.
- C4 returns `GATE FAILED` → that is an expected outcome, not an error. Proceed to Phase 11.

## Phase 11 (Main Conversation): Report Results and Hand Off

After C4 completes, you will have:
- The PR URL or GATE FAILED (from C4)
- The nine RETURN blocks
- The worktree path (from A1); the port is in the worktree `.env`

### Step 1: Report to User

Present the final summary:

```
Feature Build Complete: ${FEATURE_NAME}

PRD: ${1}
Contract: ${AC_PATH}
Branch: feature/${FEATURE_NAME}
PR: [PR URL]
Review at: http://localhost:${WORKTREE_PORT}
Worktree: ${WORKTREE_PATH}

Pipeline Results:
- Acceptance Criteria: [verdict] — Must X/Y, Should X/Y, Guards X/Y (contract review PASS [date])
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
- Cold Review: [comment link — tag counts — verify results | skipped: GATE FAILED]
```

When the cold review comment holds anything beyond `verify` lines, add: "Next: `/settle-pr-review <PR>` to decide on the review."

**If C4 returned `GATE FAILED`:** the report's first line is
`Feature Build STOPPED at Acceptance Gate: ${FEATURE_NAME}` followed by each unmet **Must** AC
(ID, criterion, status, scorecard reason), the scorecard path, the pushed branch name, and the
same `Review at:` / `Worktree:` lines. Then
tell the user how to resume once the criteria or the code are fixed: relaunch C3 then C4 with the
same prompts (they bootstrap from `.claude/pipeline-state.md` in the worktree, skip completed
steps, and re-enter the acceptance gate), or — if the PRD's criteria themselves were wrong — re-run
`/prd` to re-agree them and then relaunch C3 and C4. Step 2 runs for GATE FAILED too.

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
cd "$MAIN_DIR"
```

If the server still doesn't answer after 30 s: report the URL anyway, plus the manual command
`cd ${WORKTREE_PATH} && bin/dev` and the last 20 lines of `log/dev-server.log`.

### Step 3: Remove the PRD worktree

Only when `PRD_WORKTREE=1` **and** C4 returned a PR or DRAFT PR. GATE FAILED, hard stops, and
runs launched from the primary checkout or a plain `/worktree` skip this step (the PRD may still need
revising there). Every check must pass; otherwise keep the worktree and report the failed check:

```bash
cd "${PRIMARY_DIR}"
git -C "${WORKTREE_PATH}" cat-file -e "HEAD:${PRD}" && git -C "${WORKTREE_PATH}" cat-file -e "HEAD:${AC_PATH}" \
  || echo "KEEP: PRD or contract not committed on the feature branch"
git -C "${MAIN_DIR}" status --porcelain --untracked-files=all \
  | grep -vE '^.. \.claude/(prds|acceptance-criteria|acceptance-criteria-reviews)/' \
  && echo "KEEP: other uncommitted changes in the PRD worktree"
[ -z "$(git log --oneline "main..${PRD_BRANCH}")" ] || echo "KEEP: ${PRD_BRANCH} has commits not on main"
```

No `KEEP:` line → remove it (it has no databases, server, or port):

```bash
git worktree remove --force "${MAIN_DIR}" && git branch -D "${PRD_BRANCH}"
```

Add to the report: `PRD worktree ${MAIN_DIR} removed — close its VSCode window and this session`
(the session's working directory is gone; run nothing else from it). Or, if kept:
`PRD worktree ${MAIN_DIR} kept — <KEEP reason>`.

### Step 4: Pipeline worktree cleanup happens later

The pipeline worktree, its databases, and its server stay for review; run `/worktree-sweep` by
hand to remove them (it removes every pipeline worktree).

## Guidelines and Error Handling

The phase agents' Important Guidelines and Error Handling live in `phases/_shared.md` and apply to
the coordinator too. Coordinator-specific rules:

1. **Nine phase agents, one worktree** — A1 creates it with `git worktree add` under
   `${PRIMARY_DIR}/.claude/worktrees/`; every other agent `cd`s into it. Never give any agent the
   `isolation` parameter, never run two phase agents in parallel
   except the defined pairs (B2 ‖ B3, C1 ‖ C2), never do worktree work from the main conversation.
2. **Prompts are identity only** — the phase files are the instructions. If a phase file needs to
   change, edit the file; do not compensate in the prompt.
3. **Be transparent** — one line per phase transition so the user can track the pipeline.
4. **Relaunch, don't restart** — max one relaunch per agent, identical prompt.
5. **Measure** — `python3 .claude/skills/build-feature/scripts/token_report.py ${FEATURE_NAME}` after
   a run prints per-agent turns, peak context, and total input tokens; peaks above ~250k mean a phase
   file is letting too much into context.

- **PRD not found**: hard stop; suggest `/prd`.
- **`/review-acceptance-criteria` FAIL in Step 1b**: hard stop before any worktree; print the open
  BLOCKER/MAJOR findings and PRD Defects; tell the user to fix the PRD and re-run.
- **`/acceptance-criteria` finds an existing PASS contract**: use it, delete the timestamped copy.
- **A1 fails before the state file exists**: relaunch A1. **Port range exhausted** (A1 returns it):
  hard stop; relay the message and suggest `/worktree-sweep`.
- **Any later agent dies or returns nothing usable**: relaunch once; then stop and report how to
  resume (the state file and worktree survive).
- **Handoff server won't start** in Phase 11: report the URL and worktree path anyway, plus
  `cd <worktree> && bin/dev` and the last 20 lines of `log/dev-server.log`.
