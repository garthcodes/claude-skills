# claude-skills

A working library of 51 [Claude Code](https://claude.com/claude-code) skills for building Rails 8 + Hotwire applications — planning, implementation experts, test generation, QA automation, and the **orchestrator skills** that compose all of them into end-to-end pipelines.

This is my real, day-to-day setup (genericized for sharing — app names, hosts, and infra identifiers replaced with placeholders). It's shared so you can see how I work and borrow whatever is useful.

## Installation

Copy the `skills/` directory into your project's `.claude/` directory:

```bash
cp -R skills/. /path/to/your-project/.claude/skills/
```

Each skill becomes available as a slash command in Claude Code (`/plan`, `/build-feature`, …) and can also be invoked automatically by Claude when a task matches a skill's description. Take only the skills you want — they're independent files; the orchestrators just expect their leaf skills to be present (dependencies listed below).

## The orchestrator skills

The core idea: **small, single-purpose skills composed by orchestrators.** Leaf skills do one job well (write a PRD, plan a feature, generate model tests, hunt bugs in one feature). Orchestrator skills chain them into pipelines, usually by spawning each leaf skill in its own subagent so every stage gets a fresh context window.

```
/build-feature  (the master pipeline)
│
├── /prd ──────────────── product requirements, question-driven
├── /plan ─────────────── implementation plan from codebase exploration
│     ├── /architect-review ── critique the plan
│     ├── /frontend-review ─── verify front-end requirements are planned
│     └── /plan-system-tests ─ decide what deserves browser-level tests
├── /tickets ──────────── split the plan into executable tickets
├── /code ─────────────── execute tickets with specialized agents
├── /full-review
│     ├── /review ─────── code review (Claude Code built-in)
│     ├── /scale-review ── architecture at launch scale
│     ├── /review-fixes ── findings → prioritized fix tickets
│     └── /code ────────── apply the fixes
├── /create-qa-document → /execute-qa ── browser QA via Playwright
└── bin/ci ────────────── full local CI as the final gate
```

The other orchestrators follow the same pattern:

| Orchestrator | Pipeline |
|---|---|
| `/build-feature` | PRD → plan → reviews → tickets → code → review → QA → green CI. The whole feature lifecycle in one command. |
| `/build-feature-remote` | Kicks off `/build-feature` as a one-shot cloud routine for builds you don't want to babysit locally. |
| `/full-review` | `/review` → `/scale-review` → `/review-fixes` → `/code` against a PR or the current branch. |
| `/full-qa` | For every section of your feature catalog (`docs/APP_FEATURES.md`): `/create-qa-document` → `/execute-qa` with Playwright. Produces a resumable master bug index. Pure QA — never fixes. |
| `/full-qa-fix` | Walks `/full-qa`'s master index and runs `/fix-bug-index` per section, one commit per section. |
| `/fix-bug-index` | Walks one bug index and runs `/bug-hunt-fix` on each unskipped item. |
| `/bug-hunt-all` | `/bug-hunt` per feature section — lighter-weight sibling of `/full-qa`. |
| `/test-changed` | Detects changed models/services/policies/components/jobs on the branch, then fans out parallel test-generation agents (`/model-test`, `/service-test`, `/policy-test`, `/component-test`, test experts) — one per changed file category. |
| `/green-ci` | Runs `bin/ci`, diagnoses every failure, and routes each to the right fixer: `/rspec-test-expert`, `/fix-system-test`, or `/debug`. Loops until green. Never commits. |
| `/fix-honeybadger` | Pulls the latest production error, then `/plan` → reviews → `/code` → `/review-rails` → Playwright verification → PR. |

**Why this works:** each stage runs in a fresh subagent context, so a 10-stage pipeline never blows the context window; every stage leaves an artifact on disk (PRD, plan, tickets, QA docs, bug indexes), so pipelines are resumable and auditable; and review stages are separate skills from build stages, so the critic isn't grading its own work.

## Skill catalog

### Planning & product
| Skill | Purpose |
|---|---|
| `ideate` | Brainstorm solutions Paul Graham-style before writing a PRD |
| `prd` | Build-ready PRD through codebase-grounded, question-driven discovery |
| `plan` | Agent-executable implementation plan based on codebase exploration |
| `plan-questions` | Design a feature through guided question-driven discovery |
| `plan-system-tests` | Decide which system tests a feature needs, scenario by scenario |
| `tickets` | Convert an implementation plan into discrete executable tickets |
| `architect-guide` | Brainstorm with an experienced Rails architect / product thinker |
| `improve` | Critique exploration/planning docs and suggest better solutions |

### Review
| Skill | Purpose |
|---|---|
| `architect-review` | Critique plans for architectural problems |
| `frontend-review` | Verify front-end requirements are fully planned |
| `scale-review` | Analyze a feature's architecture against your launch-scale target |
| `review-fixes` | Turn review findings into a prioritized fix-ticket document |
| `review-rails` | Review the current branch for quality, security, Rails 8 conventions |
| `trace-requirements` | Map every PRD requirement to code/spec evidence in the branch diff |
| `full-review` | Orchestrator — see above |

### Implementation experts
Deep reference skills that Claude loads when doing that kind of work:

| Skill | Purpose |
|---|---|
| `model-expert` | Rails 8 models: validations, associations, multi-tenancy, soft deletion |
| `controller-expert` | RESTful controllers, Pundit, Turbo Stream responses |
| `backend-services-expert` | Service objects: Callable pattern, Result objects, external APIs |
| `frontend-expert` | Hotwire (Turbo + Stimulus), ViewComponents, Tailwind |
| `avo-admin-expert` | Avo 3.x admin resources, actions, dashboards |
| `devops-expert` | Fly.io deployment, GCP (Vertex AI, GCS, IAM), DNS, secrets |
| `code` | Execute implementation plans efficiently using specialized agents |
| `debug` | Structured debugging and error analysis |
| `worktree` | Spin up a git worktree with its own databases and dev server port |

### Testing
| Skill | Purpose |
|---|---|
| `rspec-test-expert` | Reliable RSpec for models, services, controllers |
| `system-test-expert` | Non-flaky Capybara/Selenium system tests with Hotwire |
| `viewcomponent-test-expert` | ViewComponent test patterns |
| `model-test` / `service-test` / `policy-test` / `component-test` / `system-test` | Per-category test generators |
| `fix-system-test` | Debug failing/flaky system tests with Playwright |
| `test-changed` / `green-ci` | Orchestrators — see above |

### QA & bug hunting
| Skill | Purpose |
|---|---|
| `create-qa-document` | Generate a QA plan from branch changes or a feature description |
| `execute-qa` | Execute a QA plan in the browser via Playwright, report bugs |
| `qa-tester` | Execute a single QA step like a senior E2E engineer |
| `feature-qa` | Deep QA of one feature on staging, across roles |
| `bug-hunt` | Hunt for bugs in one feature with Playwright |
| `bug-hunt-fix` | Fix one reported bug and verify the fix in the browser |
| `full-qa` / `full-qa-fix` / `bug-hunt-all` / `fix-bug-index` | Orchestrators — see above |

### Production ops
| Skill | Purpose |
|---|---|
| `fix-honeybadger` | Latest production error → planned, reviewed, verified fix → PR |
| `honeybadger-audit` | Audit a file for missing error-monitoring notifications |
| `impact-assessment` | Scope a production bug's blast radius + generate a remediation task |
| `user-docs` | Generate a user-facing handbook doc for a feature |

## Conventions these skills assume

These skills grew inside one Rails app, so they lean on a few conventions. Adapt to taste:

- **Stack**: Rails 8, RSpec + FactoryBot, Hotwire, ViewComponent, Tailwind, Pundit, PostgreSQL. The QA skills drive a browser through the **Playwright MCP server**.
- **`CLAUDE.md`** at the repo root — project conventions the skills defer to.
- **`docs/APP_FEATURES.md`** — a sectioned catalog of your app's features. `/full-qa` and `/bug-hunt-all` iterate over its top-level sections.
- **`bin/ci`** — one script that runs lint + security + tests locally. `/green-ci` and `/build-feature` treat it as the gate.
- **`.claude/prds/`** — where `/prd` writes and `/plan` reads product requirement docs.
- **Built-ins**: `/review`, `/security-review`, and `/simplify` are Claude Code built-in skills, referenced by the orchestrators but not part of this repo.
- **Placeholders**: anything in `<angle-brackets>` (`<app-name>`, `<gcp-project>`) or at `example.com` is yours to fill in.

## License

MIT — see [LICENSE](LICENSE).
