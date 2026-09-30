---
name: resolve-issue
description: Resolve a GitHub issue end to end — given an issue number, create an isolated ../<app>-issue_<N> worktree (own branch, databases and port), investigate, show a short plan in the terminal, wait for the user to say "implement" or adjust it, then implement with specs, run the affected specs and lint, and open a PR that closes the issue. Use whenever the user says "/resolve-issue 123", "work on issue #123", "fix issue 123", "pick up #123", "take issue 123 to a PR", or pastes a github.com/…/issues/<N> link and wants it built, even if they don't mention worktrees or PRs.
argument-hint: <issue-number>
---

# Resolve Issue

One run = one GitHub issue → one worktree → one reviewed plan → one PR that says `Closes #<N>`.

The user reviews exactly once: the plan. Everything before it (setup, investigation) and after it (implementation, verification, PR) runs without prompts, so the plan is the one thing that has to be right, short, and clear.

`$ARGUMENTS` is the issue number. Accept `#123`, `123`, or an issue URL; reduce it to the bare number `N`. If it's missing, ask for it and stop.

## Variables

```
MAIN_DIR = $MAIN_DIR
BRANCH   = issue_<N>
WT       = $MAIN_DIR/../<app>-issue_<N>
```

These match the existing `../<app>-issue_NNN` worktrees, so `/worktree-sweep` and your habits keep working. From Step 2 on, **every** read, edit, search, test, lint and git command uses absolute `$WT` paths (or `cd $WT && …`). The session's own cwd stays in the main checkout, so a relative path silently edits `main`. That's the most likely mistake in this skill, so double-check paths.

## Step 1: Read the issue

```bash
gh issue view <N> --comments --json number,title,body,state,labels,assignees,comments,url
```

- **Closed:** say so and stop, unless the user says to go ahead anyway.
- **Already has a PR:** `gh issue view <N> --json closedByPullRequestsReferences` (PRs that say `Closes #N`) and `gh pr list --head issue_<N>`. If an open one exists, report it and stop. Don't open a second PR for the same issue.
- Read every comment. Later comments often narrow or change the ask, and the plan should follow the latest agreement, not the original body.
- Images or attachments in the issue can't be seen from here. If the issue depends on one, say so in the plan rather than guessing what it shows.

## Step 2: Set up the worktree

If `$WT` already exists (an earlier run, or `/worktree issue_<N>`), **reuse it**: check `git -C $WT status` and `git -C $WT log --oneline origin/main..HEAD`, say what's already there, and skip to Step 3. Never delete or reset someone's existing work.

Otherwise:

```bash
cd $MAIN_DIR && git fetch origin main
git worktree add ../<app>-issue_<N> -b issue_<N> origin/main
cd ../<app>-issue_<N>
cp -r $MAIN_DIR/config/certs ./config/ && cp $MAIN_DIR/.env ./.env
sed -i '' '/^DATABASE_SUFFIX=/d;/^PORT=/d' .env
# printf's leading newline matters: .env may not end in one, and a glued-on line is ignored
printf '\nDATABASE_SUFFIX=_issue_%s\n' "<N>" >> .env
PORT=$(bin/worktree-port --assign .env)
# Refuse to load a schema unless Rails really points at the suffixed database —
# schema:load against the shared <app>_development would wipe it.
bin/rails runner 'n = ActiveRecord::Base.connection_db_config.database; abort("unsuffixed DB: #{n}") unless n.end_with?("_issue_<N>")' \
  && bin/rails db:create db:schema:load && bin/rails db:seed:mini
```

If `bin/rails` fails on missing gems, run `bundle install` in `$WT` once and retry. If DB setup still fails, tell the user. Never drop the `DATABASE_SUFFIX` line to get past it, because sharing `<app>_development` with main is how the main dev database gets wiped.

Don't copy `.env.prod-read`. `bin/prod-read`/`bin/prod-sql` fall back to the main checkout's copy.

Tell the user in one line: worktree path, branch, and port.

## Step 3: Investigate

Understand the issue well enough that the plan names real files and a real cause, not guesses.

- Read the code the issue points at, and trace it through. For bugs, find the root cause (the *why*), not just the line that fails. For features, find the existing pattern to follow, since the codebase almost always has a sibling to copy.
- `git -C $WT log --oneline -10 -- <file>` on the hot files. A recent change is often the cause, and linked PRs in the issue are worth reading.
- If answering needs a broad sweep across many files, hand it to an Explore agent and keep the conclusion, not the file dumps. Tell it to search `$WT`.
- If the issue involves production data (a specific claim, invoice, client), read it only through `bin/prod-read` / `bin/prod-sql` (see CLAUDE.md). Print ids, counts and statuses, not names or clinical text.
- Check CLAUDE.md rules the change will touch: SoftDeletable, tenant scoping, timezone/date display, UI copy discipline, Honeybadger context, no hand-edited `db/schema.rb`.

If the issue is ambiguous in a way the code can't settle (two reasonable readings that lead to different changes), put it in the plan as an explicit **Question**. Don't stop mid-investigation to ask, because the plan is where the user answers.

## Step 4: Present the plan and wait

Write the plan in the terminal and **stop**. The user replies **implement**, or says what to change. Don't use AskUserQuestion, don't ask for approval per change, and don't write any code until they say so. If they adjust, apply it and show only what changed. Show the whole plan again only if it changed a lot.

The user should be able to read it in about 30 seconds, so use tables and one-line rows, not paragraphs. Aim for about 20 lines. Use plain words, and define jargon in passing. Use this shape:

```
**#431 — Production alerting: detect job stalls** · worktree ../<app>-issue_431 · port 3012

**Cause** — Workers heartbeat even when they claim no jobs, so "healthy" hides a stall.
(`config/queue.yml:12` — queue names were comma strings; `/up` only proves Rails booted)

**Plan**
| # | Change | Where |
|---|---|---|
| 1 | Job that pings a Honeybadger check-in every 5 min per worker group | `app/jobs/queue_heartbeat_job.rb` (new) |
| 2 | Schedule it on each group's first queue | `config/recurring.yml` |
| 3 | `/up/deep` checks DB + queue latency, 503 when stale | `app/controllers/health_controller.rb` |

**Tests** — job spec (check-in sent per group), request spec for `/up/deep` (200 / 503).
**Prod** — none (additive; no data change). ← or: the snapshot + go/no-go recipe, if data changes
**Not doing** — paging integrations (issue says "later").
**Question** — Should `/up/deep` require a token? I'd say yes, reusing `HEALTH_TOKEN`.

Reply **implement**, or tell me what to change.
```

That example is illustrative. Every file and cause in the real plan comes from Step 3. Leave out the **Question** / **Not doing** / **Prod** lines when they don't apply, except **Prod**. Always state whether production data changes, because prod is live and the user needs to know before approving.

## Step 5: Implement (after "implement")

Build exactly the plan, including any adjustments. If you find mid-way that the plan was wrong in a way that changes scope (a different cause, a much larger change), stop and tell the user in two or three lines rather than quietly building something else.

- Follow CLAUDE.md conventions and match the surrounding code. Make the smallest change that resolves the issue, and don't refactor nearby code the plan didn't mention.
- Migrations come from `bin/rails generate migration` and run with `bin/rails db:migrate` in `$WT`, which regenerates `db/schema.rb`. Never hand-edit it. Prod has live data, so large-table indexes use `algorithm: :concurrently` + `disable_ddl_transaction!`.
- Any production data change (backfill, remediation) ships as a dry-run-by-default rake task backed by a service with specs, and gets CLAUDE.md's snapshot + go/no-go recipe in the rake header and PR body.
- Write specs for the change, following the Request Specs Policy in CLAUDE.md: model/service/job/component/policy specs for logic, system specs for UI behaviour.

## Step 6: Verify: affected specs and lint

Run only what the change touches, not `bin/ci`:

```bash
cd $WT
bundle exec rspec <every spec file added or changed, plus the spec files of changed app files that already have one>
bin/standardrb <changed .rb files>                  # never bare `bundle exec standardrb`
npx prettier --check <changed app/javascript files>  # only if JS changed
```

- If you run any system spec, first run `bin/rails tailwindcss:build` in `$WT`, or pages render unstyled and specs fail for the wrong reason.
- Fix failures and re-run until green. If a failure is clearly unrelated to this change (it fails on `origin/main` too), note it for the PR instead of chasing it.
- Don't run `bin/ci`, and never trigger GitHub Actions. The user runs CI.
- If something still fails after two honest attempts, stop and report it with the output. Don't open a PR over red specs.

## Step 7: Commit, push, and open the PR

Stage specific files (`git add <paths>`, not `-A`). One commit is fine for a small fix. For larger work, split it into a few commits that each make sense on their own. End each commit message with the attribution line from the session's system reminder.

```bash
cd $WT && git push -u origin issue_<N>
gh pr create --title "<what changed, plain words>" --body "$(cat <<'EOF'
Closes #<N>.

## Why
<one short paragraph: the problem, in the user's terms>

## What
| Change | Where |
|---|---|
| … | `path` |

## Tests
<specs added; what was run and that it passed; anything unrelated that failed>

<## Production — only if data changes: the dry run → snapshot → apply recipe and go/no-go blurb from CLAUDE.md>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

`Closes #<N>.` must be the first line. It's what links the PR and closes the issue on merge. Keep the body short, and put detail in tables.

## Step 8: Hand off

Keep the worktree, since the user tests in it and `/worktree-sweep` cleans up later. Open it:

```bash
open -n -a "Visual Studio Code" $MAIN_DIR/../<app>-issue_<N>
```

Finish with three lines: the PR link, the worktree plus `bin/dev` URL (`cd $WT && bin/dev-url`), and what was verified (specs run, lint), including anything skipped.

## Guardrails

- Production is read-only here: `bin/prod-read`/`bin/prod-sql` only, never `fly ssh`, never a console. Writes are the user's, via the recipe.
- No PHI in the plan, commits, or PR: ids and counts, not names or clinical text.
- One issue per run. Related problems noticed along the way go under "Also noticed" in the final summary (or a suggested follow-up issue), not into this PR.
