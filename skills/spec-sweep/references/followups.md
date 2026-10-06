# Follow-up PRs: bugs and findings

Step 5 of `/spec-sweep`. You (the coordinator) set up two worktrees, dispatch two helpers in
parallel, check what they built, run the final gate, and write the PR descriptions. The helpers run
the long skill chains; you keep the judgment calls: what's in scope, whether the evidence holds,
and what the user reads.

Inputs from step 3: `BUG_INDEX=<integration worktree>/docs/bug-reports/spec-sweep-$STAMP/INDEX.md`
(skip the bugs PR if it lists no unskipped bug), `FINDINGS=.claude/audits/spec-sweep/findings-$STAMP.md`,
and the fix-item ids (this run's **Fix** section plus earlier ids now `answered`). `SWEEP_PR` = the
sweep PR number from step 4. `DATE=$(date +%Y%m%d)`.

## 1. Worktrees

```bash
bash $SKILLS/spec-sweep/scripts/followup_worktree.sh spec-sweep-bugs     fix/spec-sweep-bugs-$DATE
bash $SKILLS/spec-sweep/scripts/followup_worktree.sh spec-sweep-findings chore/spec-sweep-findings-$DATE
```

Each prints `path=… branch=… port=… db=…`. Both are cut from the tip of `chore/spec-sweep`, which
already holds the bug index and the findings file. Run them one after the other (each loads a
schema). If one aborts because the worktree is on another branch, an earlier run's follow-up is
still there: report it and skip that PR rather than touching its work.

## 2. Dispatch both helpers in one message

Two Agent calls, `subagent_type: "general-purpose"`, `model: "opus"`, `run_in_background: true`.
Wait for both notifications. Fill in every `<…>`; the helpers start with no context.

Both prompts share this preamble:

> Work only in `<worktree abs path>`: `cd` there for every command; it is a separate checkout with
> its own databases (`DATABASE_SUFFIX` in its `.env`). Run rspec **without** `TEST_ENV_NUMBER`.
> Never run `bin/ci` or `parallel_rspec` (the coordinator runs the final gate, one worktree at a
> time), never trigger GitHub CI (`gh workflow run`, `gh run rerun`), never touch `main`, never write
> to production. Invoke skills with the Skill tool. A skill below may tell you to dispatch agents;
> if the Agent tool isn't available to you, do that work yourself. When a child skill reaches its
> own "final report" step, that is one step of your task, not the end of it: carry on with the next
> step. Stage files by path, never `git add -A`. Review artifacts under `.claude/reviews`,
> `.claude/scale-reviews`, `.claude/fix-plans`, `.claude/implementation-plan-*` and
> `.claude/architect-review-*` stay uncommitted. End every commit message with
> `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

### Bugs helper

> **Task:** fix the application bugs in `<abs BUG_INDEX inside this worktree>` and open a draft PR
> for them, stacked on #<SWEEP_PR>.
>
> 1. Invoke `/fix-spec-bugs <abs BUG_INDEX>`. It commits one fix per bug, each with a regression
>    spec proved red → green → red-without-the-fix, plus a `FIX_SUMMARY.md`.
> 2. If nothing was `FIXED`, stop here and report (no PR).
> 3. `git push -u origin <branch>`, then `gh pr create --draft --base chore/spec-sweep --head
>    <branch> --title "fix: bugs found by spec-sweep (<DATE>)" --body "Stacked on #<SWEEP_PR>.
>    Description to follow."`
> 4. Invoke `/full-review <new PR number>`. The PR's base is `chore/spec-sweep`, so it reviews only
>    the bug fixes. Its `/code` step leaves changes uncommitted. Read the diff; every change must
>    trace to a fix-plan item about this PR's code. Revert anything else. Run the spec files of the
>    changed files and `bin/standardrb <changed .rb files>`. Commit as `fix: address full-review
>    findings on spec-sweep bugs` and push.
>
> Reply with **only** JSON:
> `{"pr":<n or null>,"url":"…","summary":"<FIX_SUMMARY.md path>","fixed":X,"needs_decision":Y,"not_reproduced":Z,"failed":W,"full_review":{"fix_plan":"<path>","implemented":N,"skipped":["<ticket — reason>"],"open_questions":["…"]},"notes":"…"}`

### Findings helper

> **Task:** implement the **fix** items of the spec-sweep findings file `<abs FINDINGS inside this
> worktree>` (ids: `<F-ids>`; an id from an earlier run is an answered question: build its
> `**Answer:**`), one commit per finding, and open a draft PR stacked on #<SWEEP_PR>. Don't touch the
> **Decide** items that have no answer.
>
> 1. **Plan.** Invoke `/plan` with this argument (verbatim, with the path filled in):
>    "Implement the fix items `<F-ids>` from `<abs FINDINGS>`. Make one phase per finding, headed
>    `## Phase N — <F-id>: <title>`, in dependency order. Every phase has these steps:
>    (a) **guard first**: if the item's Guard is `unswept` or `none`, first write or tighten that
>    spec to `.claude/skills/rspec-test-expert/test-quality.md` using the matching test skill
>    (model-test, service-test, policy-test, viewcomponent-test-expert, rspec-test-expert), and
>    record `line_coverage --save` for the source before changing it;
>    (b) the change itself, nothing more;
>    (c) for a deletion, everything that goes with the dead code: its spec, factories nothing else
>    uses, routes, policy and policy spec, locale keys, Avo resource, importmap pins, and mentions in
>    `docs/` and `docs/user_docs/`. Afterwards `grep -rn` for the name across app, lib, config, spec
>    and docs returns nothing;
>    (d) verification: the guard spec and the specs of every touched file are green; for a refactor
>    (not a deletion), `line_coverage --baseline` shows no lost lines on the touched source.
>    Fix items must not change behavior. An answered question may change behavior, and its phase adds
>    an example pinning the new behavior. No migrations, no `db/schema.rb` changes, no new system
>    specs."
> 2. **Architect review.** Invoke `/architect-review <plan path>`. Fold its Critical Issues and
>    Recommendations into the plan file, as `/build-feature` does. Don't let it widen the scope: a
>    recommendation that adds a feature, or touches files no finding names, goes in a
>    `## Review notes` section at the top of the plan as "not taken: <why>" instead.
> 3. **Build, one finding at a time.** For each phase N in order: invoke `/code <plan path> — scope:
>    Phase N`. Then run that phase's verification yourself and `bin/standardrb <changed .rb
>    files>`. If it holds, stage exactly the files that phase changed and commit
>    `refactor(spec-sweep): <F-id> — <title>` (`chore(spec-sweep): …` for a pure deletion). If it
>    fails or is BLOCKED and you can't fix it within the phase, restore its files (`git checkout --
>    <files>`, delete new files), record it as skipped with the reason, and go on to the next phase.
> 4. `git push -u origin <branch>`, then `gh pr create --draft --base chore/spec-sweep --head
>    <branch> --title "refactor: spec-sweep cleanup (<DATE>)" --body "Stacked on #<SWEEP_PR>.
>    Description to follow."`
> 5. Invoke `/full-review <new PR number>`. Same rules as the build: every change its `/code` makes
>    must trace to a fix-plan item about this PR's code; revert the rest; specs and standardrb green.
>    Commit `refactor: address full-review findings on spec-sweep cleanup`, push.
>
> Reply with **only** JSON:
> `{"pr":<n or null>,"url":"…","plan":"<path>","architect_review":"<path>","not_taken":["…"],"phases":[{"id":"F-…","status":"done|skipped","commit":"<sha or null>","guard":"<spec path> (written|tightened|as is)","note":"…"}],"full_review":{"fix_plan":"<path>","implemented":N,"skipped":["…"],"open_questions":["…"]},"notes":"…"}`

## 3. Check what came back

For each PR, from its worktree:

1. `gh pr view <n> --json baseRefName,isDraft` shows base `chore/spec-sweep`.
2. `git diff --stat chore/spec-sweep...HEAD` holds only what the PR is about. No `db/schema.rb`,
   no migrations, no new `spec/system/` files, none of the review artifacts listed in the preamble.
   Bugs PR: every changed source file is named in a `## Fix Applied` section. Findings PR: every
   commit names an F-id or the full-review fix, and each `done` phase has its commit. Anything else
   is a protocol breach: revert it in a commit of its own and say so in the PR body.
3. Spot-check one deletion per findings PR: rerun its `grep` yourself and read its evidence.

## 4. Final gate, one worktree at a time

`cd <bugs worktree> && bin/ci`, then the same in the findings worktree. Never both at once: 8 rspec
workers each saturate the machine's Postgres connections and cores. If one is red, invoke
`/green-ci` in that worktree, commit what it changes (`test: get bin/ci green`), push, and rerun
`bin/ci` once. Still red: the PR stays a draft and the report says why.

## 5. PR descriptions

`gh pr edit <n> --body-file <file>` with the body below, then `gh pr ready <n>` when `bin/ci` was
green. The PRs are for a reviewer who hasn't seen the sweep, so lead with what the PR changes and
how to read it.

### Bugs PR body

```markdown
> Stacked on #<SWEEP_PR> (spec-sweep). Merge that first, then retarget this PR before merging it:
> `gh pr edit <n> --base main` (this repo keeps merged branches, so GitHub won't retarget it).

## Summary
Fixes <X> application bugs that the spec sweep found while pinning behavior. Each fix is its own
commit with a regression spec that fails without the fix.

| Bug | Severity | What was wrong | Regression spec | Commit |
|---|---|---|---|---|
| BUG-001 | High | <one line> | `spec/…:42` | abc1234 |

## Needs a decision (not fixed)
- **BUG-00N** <title>: <options, and the recommendation>

## Existing production data
<per bug: none, or N rows affected (counts/ids). No remediation in this PR.>

## Review fixes
`/full-review`: <N> items fixed, <M> skipped (<why>).

## Test plan
- [x] Each regression spec: red before the fix, green after, red again with the fix reverted
- [x] `bin/ci` green in an isolated worktree

Bug write-ups: `docs/bug-reports/spec-sweep-<STAMP>/` (each ends with a "Fix Applied" section).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### Findings PR body

```markdown
> Stacked on #<SWEEP_PR> (spec-sweep). Merge that first, then retarget this PR before merging it:
> `gh pr edit <n> --base main` (this repo keeps merged branches, so GitHub won't retarget it).

## Summary
Cleanup the spec sweep turned up: <N> findings, one commit each. Fix items don't change behavior,
and each one was refactored under a spec that was swept or written first.

| Finding | What changed | Guard spec | Commit |
|---|---|---|---|
| F-…-01 | Deleted unused `XPolicy::Scope` and its spec | `spec/policies/x_policy_spec.rb` (swept) | abc1234 |

## Why the deleted code is dead
- **F-…-01** `XPolicy::Scope`: no entry point of its own; no callers by name or symbol in
  app/lib/config; not in routes, Avo, recurring.yml or rake tasks.

## Questions for you
Answer with a comment on this PR (`F-…-07: allow it`), under the item in
`.claude/audits/spec-sweep/findings-<STAMP>.md`, or by telling Claude at the start of the next
`/spec-sweep`. The next run builds answered items into its cleanup PR.
- **F-…-07** <question>. Recommend: <option>, because <why>. If <A>: <consequence>. If <B>:
  <consequence>.

## Not built
<skipped phases and architect-review recommendations not taken, one line each with why>

## Test plan
- [x] Per finding: guard spec green; refactors keep line coverage on the touched source
- [x] `/architect-review` on the plan, `/full-review` on the PR
- [x] `bin/ci` green in an isolated worktree

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## 6. Cold review, one per PR

Run this after the PR body is up, because the reviewer reads it. The bugs PR changes app behavior,
and the findings PR claims not to, so a reader who never saw the sweep is worth having on both. You
didn't build either PR, but you chose their scope, so spawn the reviewer anyway. Don't review the sweep
PR itself: it only changes specs. Follow `.claude/skills/resolve-issue/references/cold-review.md`
once per PR, with:

| Slot | Bugs PR | Findings PR |
|---|---|---|
| `<WHAT>` | "fixed application bugs that a spec sweep found, test-first" | "cleaned up dead code and duplication a spec sweep found, as behavior-preserving refactors" |
| `<WT>` | the bugs worktree | the findings worktree |
| `<ASK>` | `1. The bug index: <abs BUG_INDEX>` and its `FIX_SUMMARY.md` | `1. The findings file: <abs FINDINGS>` (fix ids `<F-ids>`) and the plan |
| `<NOTES>` | from the helper's JSON and your step 3 checks: `needs_decision` / `not_reproduced` / `failed` bugs, full-review skips and open questions, anything you reverted | `not_taken`, skipped phases, guard specs written or tightened only for this PR, full-review skips, anything you reverted |
| `<FOCUS>` | "Each fix should change only the buggy behavior. Look for a regression spec that pins the symptom rather than the cause, and for callers that relied on the old (buggy) behavior." | "Fix items must not change behavior. Look for 'dead' code that is reachable by a path the grep misses (string-built constant names, `send`, routes, Avo, recurring.yml, rake tasks, `.claude/skills/`) and for a refactor that a guard spec doesn't actually cover." |
| `<STOP>` | default | "the PR changes behavior outside an answered question" |
| `<RECHECK>` | the changed files' specs and `bin/standardrb`, then `bin/ci` in that worktree (one at a time, as in step 4) | same |

A `stop` makes the PR a draft again, even when step 5 marked it ready.

## 7. Record and finish

- In the integration worktree, append to `findings.jsonl`: `in_pr` (with `"pr"`) for each built
  finding, and `open` again (with a `"note"`) for each skipped one, so the next run retries it.
  Commit `chore(spec-sweep): record follow-up PRs` on `chore/spec-sweep` and push. This touches
  only `.claude/audits/`, so the follow-up branches don't need it.
- Stop any dev server you started in a follow-up worktree. Leave the worktrees in place:
  `/worktree-sweep` (run by the user) removes them with their databases.
- Mark a finding `fixed` only when its PR has merged: the next run's Preflight checks `in_pr`
  entries with `gh pr view <n> --json state` and records the merged ones.
