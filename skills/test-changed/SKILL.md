---
name: test-changed
description: Orchestrate parallel test generation/review for all changed components, jobs, models, policies, and services in the current branch — making sure the changed behavior is guarded by real assertions (proved with coverage + mutation probes), without padding. Native replacement for scripts/test-changed-all.sh. For a whole-suite cleanup use /spec-sweep instead.
argument-hint: '[options] [base-branch]'
---

# Test Changed — Parallel Test Coverage Orchestrator

Native Claude orchestrator that mirrors `scripts/test-changed-all.sh`. Discovers files changed in the current branch across five categories, then dispatches one specialized test-generation agent per category **in parallel** to create or improve specs for each changed file.

| Category   | Source dir         | Spec dir         | Skill to invoke              |
|------------|--------------------|------------------|------------------------------|
| components | `app/components/`  | `spec/components/` | `viewcomponent-test-expert`  |
| jobs       | `app/jobs/`        | `spec/jobs/`     | `rspec-test-expert`          |
| models     | `app/models/`      | `spec/models/`   | `model-test`        |
| policies   | `app/policies/`    | `spec/policies/` | `policy-test`       |
| services   | `app/services/`    | `spec/services/` | `service-test`               |

Every skill above shares one yardstick, `.claude/skills/rspec-test-expert/test-quality.md`: test the
behavior the change introduced, prove it with coverage plus mutation probes, and add no padding. This
orchestrator measures success by "the changed behavior is guarded", not by how many examples were
added.

## Inputs

Parse `$ARGUMENTS` for these flags (any order; pass-through behavior matches the original script):

- `--dry-run` — Discover files and print what would be processed, then stop. No agents are dispatched.
- `--every-file` — Process every file in each source dir, not just files changed on the branch.
- `--include-specs` — Also pass any changed spec files to the relevant agent for review/improvement (not just new/missing specs).
- `-h` / `--help` — Print the table above plus this options list, then stop.
- Any non-flag positional argument is treated as the base branch (default `main`).

## Hard-Stop Guards

Before discovery, verify:

1. The working directory is inside a git repo (`git rev-parse --is-inside-work-tree`).
2. `git branch --show-current` returns a non-empty branch name.
3. The base branch exists locally (`git rev-parse --verify <base>`). If not, suggest `git fetch origin <base>` and abort.
4. The merge base (`git merge-base <base> HEAD`) resolves. If not, abort with a clear message.

If `--every-file` is set, only guards 1 and 2 apply.

## Step 1 — Discover Files

Run discovery for all five categories. Use Bash to compute the diff once, then filter in-process. Pseudocode (adapt to actual paths):

```bash
BASE="${BASE_BRANCH:-main}"
MERGE_BASE=$(git merge-base "$BASE" HEAD)

if [ "$EVERY_FILE" = true ]; then
  CANDIDATES=$(find app/components app/jobs app/models app/policies app/services -name "*.rb" -type f | sort)
else
  CANDIDATES=$(git diff --name-only --diff-filter=AMR "$MERGE_BASE" HEAD)
fi
```

Then bucket each candidate path into a category and skip these excluded files (they have no business spec):

- `app/components/application_component.rb`
- `app/jobs/application_job.rb`
- `app/models/application_record.rb`, `app/models/concerns/**` (concerns are tested via includers — skip them unless `--include-specs` is set and a concern spec already exists)
- `app/policies/application_policy.rb`
- `app/services/application_service.rb`, `app/services/base_service.rb`, `app/services/concerns/**`

For each kept source file, derive:

- **Class name** — snake_case path under `app/<dir>/` → CamelCase with `::` separators. Example: `app/services/billing/charge_service.rb` → `Billing::ChargeService`.
- **Spec path** — swap `app/` for `spec/` and append `_spec.rb`. Example: `app/services/billing/charge_service.rb` → `spec/services/billing/charge_service_spec.rb`.
- **Spec status** — `[spec exists]` or `[no spec]` (used to choose the agent's prompt).

If `--include-specs` is set, also pick up changed files under `spec/<dir>/`. Map each spec back to its source path and add it to its category's list (deduped).

## Step 2 — Print Discovery Summary

Print a compact summary BEFORE dispatching agents, grouped by category:

```
Discovered changes vs <base> (merge-base <short-sha>):

  components (2)
    UserAvatarComponent (app/components/user_avatar_component.rb) [spec exists]
    Billing::InvoiceRowComponent (app/components/billing/invoice_row_component.rb) [no spec]
  jobs (0)
  models (1)
    Client (app/models/client.rb) [spec exists]
  policies (0)
  services (3)
    ...

Dispatching 3 agents (skipping empty categories: jobs, policies).
```

If `--dry-run`, stop here.

If every category is empty, print a green "Nothing to do — no changed files in any category." and exit.

## Step 3 — Dispatch Agents in Parallel

**Test databases first.** Parallel agents must not share `<app>_test`: `rails_helper`'s `before(:suite)`
truncates it, so concurrent runs wipe each other's data. Give agent *k* (1-based) `TEST_ENV_NUMBER=k+1`
(2..6). Before dispatching, run `bash .claude/skills/spec-sweep/scripts/db_ready.sh 2 3 4 5 6`. If any DB
is NOT READY, run `PARALLEL_TEST_PROCESSORS=9 bundle exec rake parallel:prepare_with_seeds` (~25 s), but only when
nothing else is running specs: it reloads, i.e. wipes, <app>_test and <app>_test2..9.

For each non-empty category, dispatch **one Agent in parallel** (single message, multiple Agent tool uses). Use `subagent_type: "general-purpose"`. Each agent's prompt must be self-contained and include:

1. The category name and the list of `(class_name, source_path, spec_path, spec_status)` tuples to process.
2. The skill the agent should invoke per file (from the table at the top).
3. A loop instruction: for each tuple, invoke the appropriate skill with a prompt tailored to whether the spec exists.
4. The expected report format (see Step 4).

### Prompt template (per agent)

> You are processing the `<category>` category for the test-changed orchestrator. Process the files below sequentially. For each file, invoke `/<skill-name>` via the Skill tool with the prompt indicated.
>
> Run every rspec / line_coverage / probe command with `TEST_ENV_NUMBER=<n>` — your own database; never run rspec without it. Never edit app code; record suspected bugs as findings.
>
> Files to process:
> 1. `<ClassName>` — source: `<source_path>`, spec: `<spec_path>`, status: `<spec_status>`
> 2. ...
>
> **If status is `[no spec]`** invoke the skill with:
>
> > Write mode: create the RSpec spec for the `<ClassName>` `<singular-category>`.
> >
> > - Source file: `<source_path>`
> > - Spec file to create: `<spec_path>`
> >
> > One example per behavior/decision in the source, exact assertions, no padding (see test-quality.md). Run with `TEST_ENV_NUMBER=<n>` until green, then 2–5 probes, all KILLED.
>
> **If status is `[spec exists]`** invoke the skill with:
>
> > Review mode, scoped to this branch's change: `<ClassName>` `<singular-category>`.
> >
> > - Source file: `<source_path>`
> > - Spec file: `<spec_path>`
> >
> > - What changed: `git diff <merge-base> HEAD -- <source_path>`
> >
> > Make sure every behavior the diff adds or changes is guarded by an exact assertion (add examples only where a changed decision is unguarded). Delete fat that touches the changed area; leave unrelated old examples alone — a full trim is `/spec-sweep`'s job. Coverage (`line_coverage.rb --baseline`) must not drop; probe the changed lines, all KILLED.
>
> After each file, record one of: `PASS (+<added>/-<removed> examples, probes <k>/<n>)`, `FAIL <one-line reason>`, or `SKIP <reason>`, plus any findings about the source.
>
> When done, return a **single message** with this exact shape:
>
> ```
> CATEGORY: <category>
> RESULTS:
>   <ClassName> — PASS | FAIL: <reason> | SKIP: <reason>
>   ...
> SUMMARY: <N pass> / <N fail> / <N skip>
> ```
>
> Do not commit, push, or create PRs.

`<singular-category>` is `component`, `job`, `model`, `policy`, or `service`.

### Parallelism rule

All non-empty category agents are dispatched in a **single assistant turn** with multiple Agent tool calls so they run concurrently — the same shape as the original bash `&` + `wait` pattern.

## Step 4 — Aggregate and Report

Once all agents return, print a combined summary (mirrors the bash script's COMBINED SUMMARY block):

```
========================================
COMBINED SUMMARY
========================================

  PASS  components (2/2)
  FAIL  services   (2 pass, 1 fail)
  ...

----- Failures -----
  services / Billing::ChargeService — spec failed after 3 iterations: ActiveRecord::RecordInvalid on factory(:invoice)

Next steps:
  1. Review changes: git diff
  2. Re-run any failed category: bundle exec rspec <failed_spec_paths>
  3. Commit when satisfied
```

Exit non-zero (in spirit — i.e. surface clearly to the user) if any category reported failures, matching the script's exit-1 behavior.

## Principles

1. **One message dispatches all categories.** This is the entire point of "parallel" — do NOT serialize the Agent calls.
2. **Mirror the bash script's file-selection rules exactly.** Same excludes, same `--diff-filter=AMR`, same merge-base comparison, same class-name derivation.
3. **Don't shell out to the original scripts.** This skill is the native replacement; calling `scripts/test-changed-all.sh` would defeat the purpose.
4. **Don't commit anything.** The user reviews `git diff` and commits themselves — same as the original script.
5. **Empty categories are skipped silently in agent dispatch but listed in the discovery summary** so the user can see they were considered.
6. **`--include-specs` is additive**, not a mode switch — it adds spec-file-driven entries to whatever the changed-source pass produced.
