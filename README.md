# claude-skills

A working library of 74 [Claude Code](https://claude.com/claude-code) skills for building Rails 8 + Hotwire applications: planning, implementation experts, test generation, QA automation, and the **orchestrator skills** that chain all of them into end-to-end workflows.

This is my real, day-to-day setup, genericized for sharing (app names, hosts and infra identifiers are replaced with placeholders). It's here so you can see how I work and borrow whatever is useful.

- [Installation](#installation)
- [How it fits together](#how-it-fits-together)
- [My workflows](#my-workflows): [new feature](#1-a-new-feature), [small change](#2-a-small-change-to-something-that-already-exists), [production errors](#3-production-errors), [settling PRs](#4-settling-a-pr-before-merge), [performance](#5-performance-rotation), [code health](#6-code-health-sweeps), [QA](#7-qa-sweeps)
- [The building blocks the orchestrators share](#the-building-blocks-the-orchestrators-share)
- [Skill catalog](#skill-catalog)
- [Conventions these skills assume](#conventions-these-skills-assume)

## Installation

Copy the `skills/` directory into your project's `.claude/` directory:

```bash
cp -R skills/. /path/to/your-project/.claude/skills/
```

Each skill becomes a slash command in Claude Code (`/plan`, `/build-feature`, …), and Claude can also pick one up on its own when a task matches the skill's description. Take only what you want. Leaf skills stand alone; orchestrators expect the skills they call to be present (listed with each workflow below). The helper scripts and the production guard hook live in [`tooling/`](tooling/).

## How it fits together

**Small, single-purpose skills, composed by orchestrators.** A leaf skill does one job well: write a PRD, plan a change, test one service, hunt bugs in one feature. An orchestrator chains leaf skills into a workflow, usually spawning each stage in its own sub-agent so every stage starts with a fresh context window.

Four ideas run through every orchestrator:

1. **Every change gets its own worktree.** Each run builds in an isolated git worktree with its own branch, its own databases (`DATABASE_SUFFIX`) and its own dev-server port, so several runs can go at once without stepping on each other or on `main`. `/worktree-sweep` cleans them up.
2. **Every stage leaves a file on disk.** PRDs, acceptance contracts, plans, tickets, review reports, QA documents, bug indexes and ledgers. That makes runs resumable after a crash and auditable afterwards.
3. **The builder never grades its own work.** Reviews (`/architect-review`, `/full-review`, `/security-review`) are separate skills from the build skills, and every PR ends with a **cold review**: a read-only agent that never saw the build reads only the original ask and the finished diff, and posts what the merger should know as a PR comment.
4. **The human is asked as little as possible, and only about decisions.** Most orchestrators have no approval stops at all: they print the plan for the record, take the recommended option wherever the code can't settle a choice, and list those choices under **Decisions** in the PR. The ones that do stop (`/tweak`, `/fix-honeybadger`, `/page-speed`) stop exactly once or twice, show a short plan in the terminal, and wait for "implement". Judgment calls are collected afterwards by `/settle-pr-review`, one plain-language question at a time.

The picture, end to end:

```
                     ┌───────────────── where work comes from ─────────────────┐
  idea / PRD         small request       production error       slow page      code/test debt
      │                   │                    │                    │                │
 /build-feature        /tweak          /fix-honeybadger        /page-speed     /refactor-sweep
 (nine phase agents)  (one context)     │ urgent: fix now       (rotation)      /spec-sweep
      │                   │             │ rest: file issues        │                │
      │                   │             ▼                          │                │
      │                   │      /resolve-issues ──► /resolve-issue (one per issue)  │
      │                   │                               │        │                │
      ▼                   ▼                               ▼        ▼                ▼
   ──────────────────────────────────────  PR + cold-review comment  ──────────────────────────
                                                    │
                                          /settle-pr-review   (you decide the few points that matter)
                                                    │
                                                  merge
```

## My workflows

### 1. A new feature

```
/ideate  →  /prd  →  /acceptance-criteria  →  /review-acceptance-criteria  →  /build-feature <prd>  →  /settle-pr-review <PR>
```

`/ideate` is optional brainstorming. `/prd` writes a build-ready PRD through codebase-grounded, question-driven discovery (`/prd-worktree` gives you a bare worktree to write it in). `/acceptance-criteria` turns the PRD into a contract, one observable Given/When/Then row per requirement, edge case, permission denial and out-of-scope guard, and `/review-acceptance-criteria` audits that contract against the PRD and stamps it PASS.

Then **`/build-feature`** runs the whole build unattended. It's a coordinator that spawns nine phase agents in sequence, each with a fresh context; their instructions live in `skills/build-feature/phases/`, and they hand off through `.claude/pipeline-state.md`:

```
/build-feature <prd>
│
├── gate: the AC contract must be stamped PASS (hard stop otherwise)
├── 01 setup + /plan ───────────── port-isolated worktree, implementation plan
├── 02 plan reviews + /tickets ─── /architect-review, /frontend-review, /plan-system-tests → tickets in lanes
├── 03 /code ───────────────────── fresh worker sub-agents per ticket, up to three lanes in parallel
├── 04 /full-review ────────────── /review → /scale-review → /review-fixes → /code
├── 05 /security-review + /trace-requirements ── every PRD requirement and AC row mapped to code/spec evidence
├── 06 /system-test-expert → /fix-system-test
├── 07 /create-qa-document → /execute-qa ── Playwright drives the real app
├── 08 /verify-acceptance ──────── AC scorecard: unmet Must → no PR, unmet Should → draft PR
└── 09 ship ────────────────────── /simplify, /merge-main, bin/ci as the final gate, PR, cold review
```

The worktree stays up after the PR so you can click through the feature yourself (`/qa-branch` walks you through it scenario by scenario in your own Chrome). `/build-feature-remote` starts the same pipeline as a one-shot cloud routine when you don't want to babysit it locally.

### 2. A small change to something that already exists

```
/tweak "let supervisors see the balance column on the client list"  →  /settle-pr-review <PR>
```

**`/tweak`** is the mini `/build-feature`, for modifying a feature that already works: no PRD, no issue. It sizes the request (and sends you to `/prd` if it's really a new feature), creates a worktree, reads the feature's code, then **interviews you one question at a time** until the problem is fully understood. It shows a short plan with a checkable **Done when** list and waits for "implement". After that it builds with specs, re-runs the feature's existing specs so nothing that worked breaks, reviews the diff, opens the PR and runs the cold review.

You're involved twice (interview and plan), and because the interview comes first, the plan holds no surprises. It runs in one context with no sub-agents, because at this size hand-offs cost more than they save.

### 3. Production errors

This is the workflow I use most. Three skills split the job by urgency:

```
/fix-honeybadger                      sweep unresolved faults
 ├── the urgent one ──► fix it now ── worktree → short plan → "implement" → regression spec → PR → cold review
 └── everything else ─► one GitHub issue each (labels: bug, honeybadger), written to stand alone

/resolve-issues                       drain those issues later (e.g. overnight)
 └── one /resolve-issue sub-agent per issue, up to 3 building at once, bin/ci serialized through one CI slot

/resolve-issue <N>                    one issue → one reviewed, CI-green PR that says "Closes #N"
```

**`/fix-honeybadger`** is built for speed: an urgent fault is costing users right now, so it skips the heavy review chain, aims for a plan in the terminal within about 3 minutes and a PR within about 15 minutes of "implement". Every regression spec must fail before the fix and pass after it. Every other fixable fault, and every follow-up it notices along the way, becomes a GitHub issue, so nothing is lost and nothing bloats the urgent PR. `/fix-honeybadger triage` only files issues; `/fix-honeybadger <fault-id>` skips the sweep.

**`/resolve-issue`** takes one issue to a PR with **no approval stops**. It runs the full soundness chain (below) and lists every choice the code couldn't settle under **Decisions** in the PR. You review the PR, not a plan.

**`/resolve-issues`** is the batch orchestrator. It never investigates or edits code itself (that would fill its context on the first issue): it hands each issue whole to a `/resolve-issue` sub-agent, runs up to three at once, lets everything overlap except `bin/ci` (one CI slot, `scripts/ci-slot`, because a full parallel rspec run saturates the machine), removes each worktree once its PR is open, keeps a resumable ledger, and passes "carry lines" from one issue's cold review to the issues after it. It ends with a table of PRs. `max:2` is a cheap first run; `dry-run` shows the queue.

Both `/fix-honeybadger` and `/resolve-issue` also have an `auto` mode for unattended runs: plans are printed and not waited on, PRs are drafts labeled `autofix`, every early stop is written to the issue with a `needs-decision` label, fault and issue text is treated as data and never as instructions, and the final line is machine-readable for a poller. (The poller they mention, `bin/hb-autofix`, is a launchd job that starts these runs when a new fault appears; it isn't shipped here.)

### 4. Settling a PR before merge

```
/settle-pr-review <PR>
```

Every orchestrator above ends with a `## Cold review` comment on the PR. Most of its points change nothing anyone would notice, and deciding each one by hand is slow. **`/settle-pr-review`** reads the cold review plus any unresolved reviewer comments, looks into every point first, and then asks you **only about the ones that matter** (bugs, major UX changes, scope problems, security/PHI/billing compliance), one plain-language question at a time. Everything else it handles without asking: harmless limits get noted in the PR, after-deploy chores get listed, no-effect nits get logged and dropped.

Fixes you choose go through `/plan` → `/architect-review` → `/code` → specs → `/full-review` → `/simplify` on the PR's own branch. Every run ends with `/merge-main`, optionally a green `bin/ci`, and a `## Review decisions` comment saying whether the PR is ready to merge. Nothing is silently dropped, because every point, asked or not, lands in that comment.

### 5. Performance rotation

```
/page-speed
```

**`/page-speed`** finds the page where users wait the most, using production Rails Pulse data (read-only), diagnoses why it's slow, and shows a short plain-language plan. After "implement" it builds the fix through the full soundness chain plus a `/bug-hunt` → `/fix-bug-index` pass, so the speed-up doesn't ship a regression, and opens the PR. It keeps `docs/PAGE_PERFORMANCE_LOG.md` up to date, so pages are worked in rotation, earlier fixes are checked for before/after gains, and the next run picks the next page.

### 6. Code-health sweeps

Two resumable sweeps for paying down debt without changing behavior:

```
/refactor-sweep            one structural refactor per run → PR that changes structure, not behavior

/spec-sweep                whole-suite unit-spec cleanup
 ├── sweep PR ──────────── parallel workers trim bloated specs; coverage never drops, every mutation probe is killed
 ├── bugs PR ───────────── /fix-spec-bugs: the app bugs workers found, fixed test-first
 └── cleanup PR ────────── dead code and duplication workers found: /plan → /architect-review → /code → /full-review
```

**`/refactor-sweep`** works a ranked queue of targets (callbacks that belong in services, model logic that belongs elsewhere, `call`-style services, fat jobs, partials without strict locals, non-resource routes, missing unique indexes), one per run. A refactor's whole promise is that nothing a user, a record, a job queue or an outside system sees is different afterwards, so most of its effort goes into proving that. First comes a **behavior lock**: specs that pin every observable effect of the code being moved, proven green on the old code before anything changes, and still passing unchanged afterwards. Then a **caller audit**: a table of every path that reaches the moved code, including the indirect ones grep misses. Progress is kept in a tracked ledger.

**`/spec-sweep`** ranks every unit spec by bloat and fans batches out to parallel workers in their own worktrees. Each worker uses the matching test skill (`/model-test`, `/service-test`, `/policy-test`, `/viewcomponent-test-expert`, `/rspec-test-expert`) and is held to one yardstick, `rspec-test-expert/test-quality.md`. Workers commit one batch at a time to `chore/spec-sweep`, and the sweep resumes from its ledger. Along the way they report real app bugs and dead code, which become two stacked follow-up PRs. `/fix-spec-bugs` fixes each bug test-first: a regression spec that fails on the current code, the smallest root-cause fix, then proof the spec goes red again with the fix reverted. Behavior-changing findings become questions for you rather than silent changes. `--audit` reports without editing.

The narrower audits follow the same report → fix shape: `/time-display-audit` (every date/time the app renders, against per-surface timezone and format rules, then fixes every finding) and `/audit-fixer` (walks any severity-ranked audit document, `/plan` → `/code` per finding).

### 7. QA sweeps

```
/full-qa  →  /full-qa-fix            every section of docs/APP_FEATURES.md: QA plan → Playwright run → master bug index → fixes
/bug-hunt-all  →  /fix-bug-index     the lighter version: /bug-hunt per section, then /bug-hunt-fix per bug
/native-bug-hunt  →  /native-bug-hunt-fix     the same for the iOS/Android WebView shell, on the emulator
/qa-branch                           hand QA: you watch in your own Chrome while it walks one scenario at a time
```

`/full-qa` is pure QA and never fixes: for each feature section it runs `/create-qa-document` → `/execute-qa` and builds a resumable master bug index. `/full-qa-fix` walks that index and runs `/fix-bug-index` per section (one commit per section), which runs `/bug-hunt-fix` on each bug and verifies the fix in the browser.

## The building blocks the orchestrators share

The orchestrators above don't re-implement review, testing or CI. They call the same middle-layer skills, which are useful on their own too:

| Skill | What it does | Called by |
|---|---|---|
| **The soundness chain** | `/plan` → `/architect-review` (→ `/frontend-review`) → `/code` → `/test-changed` → `/full-review` → `/simplify` → `/merge-main` → `bin/ci` (→ `/green-ci`) → PR → cold review | `/resolve-issue`, `/page-speed`, `/refactor-sweep`, `/settle-pr-review` fixes, `/build-feature` (as phases) |
| `/full-review` | `/review` → `/scale-review` → `/review-fixes` → `/code`: finds P0–P2 findings and fixes them | every chain above |
| `/test-changed` | Finds every changed model, service, policy, component and job on the branch and fans out one test agent per category. Each spec has to prove itself with line coverage and mutation probes, not just pass | every chain above |
| `/green-ci` | Runs `bin/ci`, diagnoses every failure, routes it to `/rspec-test-expert`, `/fix-system-test` or `/debug`, stabilizes flaky tests, loops until green. Never commits; flags any behavior-affecting app change for review | every chain above |
| `/merge-main` | Merges `origin/main`, resolves each conflict keeping both sides' intent, verifies, commits and pushes | every chain above |
| Cold review | `skills/resolve-issue/references/cold-review.md`: the builder writes honest notes (assumptions, what wasn't verified, scope drift), then a read-only agent that never saw the build reviews the ask plus the diff. Its `verify` points get checked and fixed; the rest is posted as the `## Cold review` comment that `/settle-pr-review` reads | every PR-opening orchestrator |
| `/worktree` / `/worktree-sweep` | Create an isolated worktree (own branch, databases, port) / remove old ones, keeping any with uncommitted or unpushed work, an open PR, a running Claude session, or recent changes and no PR (`--all` removes everything) | by hand |

**Why this works:** each stage runs in a fresh sub-agent context, so a long pipeline never runs out of context. Every stage leaves an artifact on disk, so pipelines can resume and be audited. Review stages are separate skills from build stages, so the critic isn't grading its own work. And because the human's attention goes to the PR and a handful of real decisions, not to approving every step, several of these can run at once.

## Skill catalog

### Orchestrators
| Skill | Purpose |
|---|---|
| `build-feature` | PRD → AC gate → plan → reviews → tickets → code → review → system tests → QA → acceptance gate → green CI → PR (nine phase agents) |
| `build-feature-remote` | Starts `/build-feature` as a one-shot cloud routine |
| `tweak` | Small change to an existing feature: worktree → interview → plan → "implement" → specs → review → PR → cold review |
| `resolve-issue` | One GitHub issue → worktree → soundness chain → CI-green PR that closes the issue, with no approval stops |
| `resolve-issues` | A batch of issues → one `/resolve-issue` sub-agent each, up to 3 in parallel, `bin/ci` serialized, ledger, table of PRs |
| `fix-honeybadger` | Triage production faults; fix the urgent one fast, file a standalone issue for every other one |
| `settle-pr-review` | Decide a PR's cold review: ask only about what matters, handle the rest, record a `## Review decisions` comment |
| `page-speed` | Slowest page from production Rails Pulse data → diagnosis → plan → soundness chain → PR; keeps a rotation log |
| `refactor-sweep` | One structural refactor per run, behavior-locked and caller-audited, from a ranked queue |
| `spec-sweep` | Whole-suite unit-spec cleanup with parallel workers, plus stacked bug-fix and cleanup PRs |
| `full-review` | `/review` → `/scale-review` → `/review-fixes` → `/code` |
| `test-changed` | Parallel spec generation/review for everything changed on the branch |
| `green-ci` | Drive `bin/ci` to green, routing each failure to the right fixer |
| `full-qa` / `full-qa-fix` | QA every feature section → master bug index → fix per section |
| `bug-hunt-all` / `fix-bug-index` | `/bug-hunt` per section / `/bug-hunt-fix` per bug in an index |
| `fix-spec-bugs` | Fix every bug in a code-level bug index test-first, one commit per bug |
| `audit-fixer` | Walk a severity-ranked audit and `/plan` → `/code` each finding |
| `worktree-sweep` | Remove old worktrees with their servers and databases, keeping in-flight ones |

### Planning & product
| Skill | Purpose |
|---|---|
| `ideate` | Brainstorm solutions Paul Graham-style before writing a PRD |
| `prd` | Build-ready PRD through codebase-grounded, question-driven discovery |
| `prd-worktree` | Bare git worktree for writing a PRD (no databases, no port) |
| `acceptance-criteria` | PRD → Acceptance Criteria contract: one observable Given/When/Then row per requirement, edge case, permission denial and out-of-scope guard |
| `plan` | Agent-executable implementation plan from codebase exploration |
| `plan-questions` | Design a feature through guided, question-driven discovery |
| `plan-system-tests` | Decide which system tests a feature needs, scenario by scenario |
| `tickets` | Implementation plan → discrete, executable tickets |
| `architect-guide` | Brainstorm with an experienced Rails architect / product thinker |
| `improve` | Critique exploration/planning docs and suggest better solutions |
| `product-question` | Answer a product question in plain language from the code alone, never docs |
| `product-question-tldr` | `/product-question`, boiled down to one ELI18 takeaway |

### Review
| Skill | Purpose |
|---|---|
| `architect-review` | Critique plans for architectural problems |
| `frontend-review` | Verify front-end requirements are fully planned |
| `scale-review` | Check a feature's architecture against your launch-scale target |
| `review-fixes` | Review findings → prioritized fix-ticket document |
| `review-rails` | Review the branch for quality, security and Rails 8 conventions |
| `review-acceptance-criteria` | Audit an AC contract against its PRD (completeness, fidelity, verifiability), fix it in place, stamp it PASS |
| `trace-requirements` | Map every PRD requirement and AC row to code/spec evidence in the diff |
| `verify-acceptance` | Score every AC row against QA results and specs; the scorecard `/build-feature` gates the PR on |

### Implementation experts
Deep reference skills Claude loads when doing that kind of work:

| Skill | Purpose |
|---|---|
| `model-expert` | Rails 8 models: validations, associations, multi-tenancy, soft deletion |
| `controller-expert` | RESTful controllers, Pundit, Turbo Stream responses |
| `backend-services-expert` | Service objects, Result objects, external APIs |
| `frontend-expert` | Hotwire (Turbo + Stimulus), ViewComponents, Tailwind |
| `avo-admin-expert` | Avo 3.x admin resources, actions, dashboards |
| `devops-expert` | Fly.io deployment, GCP (Vertex AI, GCS, IAM), DNS, secrets |
| `stedi-billing-expert` | Healthcare billing via the Stedi clearinghouse: eligibility (270/271), claims (837P), status (276/277), ERAs (835), verified against live Stedi docs |
| `code` | Execute implementation plans with specialized agents |
| `debug` | Structured debugging and error analysis |
| `merge-main` | Merge `origin/main`, resolve conflicts keeping both sides' intent, verify, push |
| `worktree` | Git worktree with its own databases and dev-server port |

### Testing
| Skill | Purpose |
|---|---|
| `rspec-test-expert` | Unit specs that test the code for real. Owns the shared yardstick (`test-quality.md`) and the line-coverage and mutation-probe scripts the other test skills use |
| `model-test` / `service-test` / `policy-test` / `component-test` | Write or trim the spec for one model / service / Pundit policy / ViewComponent against that yardstick |
| `viewcomponent-test-expert` | ViewComponent specs that assert what a user sees and can do, not CSS classes |
| `system-test` / `system-test-expert` | Reliable, non-flaky Capybara system tests with Hotwire |
| `fix-system-test` | Debug failing or flaky system tests with Playwright |

### QA & bug hunting
| Skill | Purpose |
|---|---|
| `create-qa-document` | QA plan from branch changes or a feature description |
| `execute-qa` | Run a QA plan in the browser via Playwright, report bugs |
| `qa-tester` | Execute a single QA step like a senior E2E engineer |
| `feature-qa` | Deep QA of one feature on staging, across roles |
| `bug-hunt` / `bug-hunt-fix` | Hunt bugs in one feature / fix one and verify it in the browser |
| `qa-branch` | Hand QA in your own Chrome: seeds data, signs in as the right role, walks one scenario at a time |
| `native-bug-hunt` / `native-bug-hunt-fix` | Hunt and fix bugs in a Ruby Native (iOS/Android WebView shell) app on the Android emulator, reading inside the WebView via a dev-only debug beacon |
| `time-display-audit` | Audit every rendered date/time against per-surface timezone/format rules, fix every finding, drive `bin/ci` green |

### Production ops & docs
| Skill | Purpose |
|---|---|
| `honeybadger-audit` | Audit a file for missing error-monitoring notifications |
| `impact-assessment` | Scope a production bug's blast radius and generate a remediation task |
| `user-docs` | User-facing handbook doc for a feature (also the corpus for an in-app help assistant) |
| `sync-user-docs` | Sync the user-doc corpus with everything deployed since the last sync, and open a PR |

## Conventions these skills assume

These skills grew inside one Rails app, so they lean on a few conventions. Adapt to taste:

- **Stack**: Rails 8, RSpec + FactoryBot, Hotwire, ViewComponent, Tailwind, Pundit, PostgreSQL, GitHub (`gh` CLI). The QA skills drive a browser through the **Playwright MCP server**; `/qa-branch` uses Claude in Chrome.
- **`CLAUDE.md`** at the repo root: project conventions the skills defer to.
- **`bin/ci`**: one script that runs lint + security + tests locally. Every orchestrator treats it as the gate, and they run it one at a time.
- **Worktrees**: each worktree gets its own `PORT=` and `DATABASE_SUFFIX` in `.env`. `bin/dev-url`, `bin/worktree-port` and `bin/worktree-sweep` are shipped in [`tooling/`](tooling/).
- **`docs/APP_FEATURES.md`**: a sectioned catalog of your app's features. `/full-qa` and `/bug-hunt-all` iterate over its top-level sections.
- **`.claude/prds/`**, **`.claude/acceptance-criteria/`**, **`.claude/audits/`**: where the planning and sweep skills read and write their artifacts.
- **Honeybadger** for errors (`/fix-honeybadger` uses its MCP server) and **Rails Pulse** for performance data (`/page-speed`).
- **Production safety**: the ops skills never run a production-targeting command without explicit per-command approval. The `claude-hook-prod-guard.py` PreToolUse hook in [`tooling/`](tooling/) enforces that. Production reads (`/page-speed`, `/impact-assessment`, `devops-expert`) assume read-only wrappers, `bin/prod-read` (Ruby on stdin) and `bin/prod-sql` (raw SQL), connecting as a read-only database role; these aren't shipped here. Writes are always run by the user, after a database snapshot.
- **Built-ins**: `/review`, `/security-review` and `/simplify` are Claude Code built-in skills. The orchestrators call them, but they aren't part of this repo.
- **Placeholders**: anything in `<angle-brackets>` (`<app-name>`, `<app-host>`, `<app>` for the database prefix, `<gcp-project>`, `<practice-name>`) or at `example.com` / `localhost:3000` is yours to fill in.

## License

MIT, see [LICENSE](LICENSE).
