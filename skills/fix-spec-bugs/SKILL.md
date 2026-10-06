---
name: fix-spec-bugs
description: Fix every bug in a code-level bug index (the docs/bug-reports/spec-sweep-*/INDEX.md that /spec-sweep writes, or any INDEX.md in that shape) test-first — for each bug, a regression spec that fails on the current code, the smallest root-cause fix, the spec green, then proof the spec goes red again with the fix reverted — one commit per bug on the current branch, plus a FIX_SUMMARY.md. Use when the user says /fix-spec-bugs, hands over a spec-sweep bug index or BUG-*.md file, or wants bugs found by reading code or tests (not by clicking through the app) fixed with regression specs. For bugs found in the browser by /bug-hunt, use /fix-bug-index instead.
argument-hint: <path-to-INDEX.md or BUG-NNN-*.md>
---

# Fix Spec Bugs

Bugs found by reading code are proved with a spec, not a browser. For every bug this skill makes
the proof explicit: a regression example that fails on the code as it is, passes with the fix, and
fails again when only the fix is taken away. That last step is what shows the spec guards the fix
rather than passing by accident.

You are the orchestrator. Each bug is fixed by one worker agent, one bug at a time, because the
bugs share a checkout and often the same files. Your context holds the index, the loop, and the
workers' JSON replies; the source reading belongs to the workers.

## 0. Preconditions

- `git branch --show-current` must not be `main`. Bug fixes are committed one per bug, so they
  need a branch (normally `fix/spec-sweep-bugs-<date>`, which `/spec-sweep` creates). On `main`,
  stop and say so.
- The working tree must be clean apart from the bug-report folder. A dirty tree would leak
  unrelated changes into the per-bug commits.
- This checkout's databases: in a pipeline worktree `.env` sets `DATABASE_SUFFIX`, and rspec run
  **without** `TEST_ENV_NUMBER` seeds `<app>_test<suffix>` itself. Run single specs that way. Never
  run `bin/ci` here; the caller owns the final gate.

`SKILLS` = the absolute path of the directory containing this skill (`<repo>/.claude/skills`).

## 1. Parse the index

Read the index. Each bullet links a `BUG-NNN-*.md` file (paths relative to the index's directory).
Skip a bullet that carries `[SKIP]`, `<!-- skip -->`, or `~~strikethrough~~`, or whose bug file
already has a `## Fix Applied` section with status `FIXED` (that makes re-running resume). Keep the
index order: highest severity first.

Print one line: `N bugs: X to fix, Y skipped (reasons)`. Then make one task per bug and go
straight into the loop. Don't ask for confirmation.

A single `BUG-NNN-*.md` argument means a one-bug run: same loop, one item, no summary file.

## 2. The loop

For each bug, in order: dispatch one worker with the prompt below (`subagent_type:
"general-purpose"`, `model: "opus"`). If the Agent tool isn't available to you, follow the worker
prompt yourself for that bug. Wait for its JSON before starting the next one.

When the worker returns:

1. Check the reply: the JSON parses; for `FIXED`, the commit exists and `git show --stat <sha>`
   touches only the files it lists. Both proof fields must be true: `red_before` and
   `red_with_fix_reverted`. A `FIXED` without both is really `ATTEMPTED`. Record it that way.
2. `git status --porcelain` must be empty (apart from bug files of bugs not yet processed). If a
   worker left changes behind, restore them (`git checkout -- <files>`, delete new untracked
   specs) and record the bug as `FAILED` with "left a dirty tree".
3. Mark the task done and start the next bug **in the same response**. One finished bug is one
   loop iteration, not the end of the task.

Keep going after a `FAILED`, `NOT_REPRODUCED`, or `NEEDS_DECISION`: one hard bug never stops the
batch.

### Worker prompt

Fill in every `<…>`. The worker starts with no context.

> You are fixing one application bug, test-first. Work only in `<checkout abs path>` (`cd` there
> for every command). Run rspec **without** `TEST_ENV_NUMBER`. Never run `bin/ci`,
> `parallel_rspec`, `git push`, or anything against production except the read-only `bin/prod-read`.
>
> **Bug file:** `<abs path to BUG-NNN-*.md>`
>
> Read first: the bug file; `<SKILLS>/rspec-test-expert/test-quality.md` (what a real assertion
> is); and the test skill for the spec you'll add to: `model-test` for `spec/models`,
> `service-test` for `spec/services`, `policy-test` for `spec/policies`,
> `viewcomponent-test-expert` for `spec/components`, `rspec-test-expert` for anything else
> (`<SKILLS>/<skill>/SKILL.md`). Then the cited source, its callers, and the existing spec.
>
> 1. **Understand the cause.** Read the cited lines and every caller that matters. If the bug is
>    marked *Likely*, confirm it before writing anything. The fix goes at the root cause, not
>    where the symptom shows up.
> 2. **Red first.** Add the smallest regression example(s) to the spec the bug file names under
>    **Regression spec** (or the matching spec for the source; create it only if none exists).
>    Assert the correct behavior exactly. Run it: it must **fail, and for the bug's reason**: read
>    the failure message. A failure from setup, a typo, or a missing factory doesn't count. If you
>    can't make it fail for the right reason, the bug isn't real as described: remove your example,
>    status `NOT_REPRODUCED`, and explain in `note`.
> 3. **Fix.** The smallest change that removes the cause, following CLAUDE.md (service objects,
>    Pundit, `Honeybadger.notify` context, SoftDeletable rules, no PHI in logs). Use the
>    `/frontend-expert` skill for any view, component, Stimulus, or Turbo change. Don't refactor
>    around the fix. Don't hand-edit `db/schema.rb`; a fix that needs a migration, a production data
>    backfill, or a behavior choice the bug file doesn't settle (who should be allowed, what a user
>    should see) is `NEEDS_DECISION`: revert everything and describe the options in `note`.
> 4. **Green.** The regression example passes. Then run every spec file for the files you changed
>    (`spec/<same path>_spec.rb`), plus the specs that call the changed method
>    (`grep -rln "<method or constant>" spec`). All green. `bin/standardrb <changed .rb files>`
>    clean (never bare `bundle exec standardrb`).
> 5. **Prove the spec guards the fix.** Take away only the fix and keep the spec:
>    `git stash push -- <changed app/ lib/ config/ files>`, run the regression example: it must be
>    **red**. Then `git stash pop` and run it once more: green. If it stays green without the fix,
>    the example doesn't test the bug yet: tighten it and repeat from 4.
> 6. **Existing data.** Production is live. If the bug could have written wrong rows (wrong
>    amounts, missing records, leaked logs), check how many with a read-only query (`echo '…' |
>    bin/prod-read`). Print counts and ids only, never names or clinical text. Report it in
>    `prod_data`. Don't write a remediation task; the user decides.
> 7. **Document.** Append to the bug file:
>    ```markdown
>    ---
>
>    ## Fix Applied
>
>    **Date:** <YYYY-MM-DD>  **Status:** FIXED
>
>    - **Cause:** <one line>
>    - **Change:** <file:line — one line each>
>    - **Regression spec:** `<spec path>:<line>` — red before the fix, green after, red again with
>      the fix reverted
>    - **Existing data:** <none | N rows affected — ids/counts, how found>
>    ```
> 8. **Commit** only your files: `git add <changed source files> <spec files> <bug file>` and
>    `git commit -m "fix: <bug title, lowercase, ≤ 70 chars>" -m "<cause in one or two lines>" -m
>    "Regression: <spec path>:<line>. Spec-sweep <BUG-NNN>." -m "Co-Authored-By: Claude Opus 5.5
>    <noreply@anthropic.com>"`. For any status other than `FIXED`, commit nothing and leave the
>    tree exactly as you found it (`git checkout -- <files>`, delete new spec files), except that
>    you may append a `## Fix Attempted` section to the bug file explaining why. Leave that
>    uncommitted; the orchestrator commits it with the summary.
>
> Reply with **only** this JSON:
> `{"bug":"BUG-NNN","status":"FIXED|NOT_REPRODUCED|NEEDS_DECISION|FAILED","commit":"<sha or null>","files":["…"],"regression_spec":"<path:line or null>","red_before":true,"red_with_fix_reverted":true,"related_specs":"<N files, M examples, 0 failures>","prod_data":"none | <counts>","note":"…"}`

## 3. Summary

Write `<index directory>/FIX_SUMMARY.md`:

```markdown
# Fix summary: <index title>

**Date:** <YYYY-MM-DD>  **Branch:** <branch>
**Fixed:** X  **Needs decision:** Y  **Not reproduced:** Z  **Failed:** W  **Skipped:** V

| Bug | Severity | Status | Regression spec | Commit | Existing data |
|---|---|---|---|---|---|
| BUG-001 — <title> | High | FIXED | `spec/…:42` | abc1234 | none |

## Needs decision
- **BUG-00N** — <title>: <the options, one line each, and which one you'd pick and why>

## Not reproduced / failed
- **BUG-00N** — <title>: <one line>
```

Commit it with any `## Fix Attempted` notes: `git add <index dir> && git commit -m "docs: fix
summary for <index dir name>"` (plus the Co-Authored-By trailer). Never push. The caller (the user
or `/spec-sweep`) pushes and opens the PR.

Final message, two lines: the counts, and the summary path.
