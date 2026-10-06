---
name: settle-pr-review
description: Settle the review comments on one PR so it's ready to merge. Given a PR number, read its "## Cold review" comment (the one /resolve-issue, /refactor-sweep, /page-speed, /tweak, /fix-honeybadger, /build-feature and /spec-sweep's follow-up PRs post) and any other unresolved reviewer comments, look into each point, and ask the user only about the ones that matter (bugs, major UX changes, scope problems, security/PHI/billing compliance), one ELI18 question at a time. Everything else is handled without asking: harmless limits noted in the PR, after-deploy chores listed, carry lines passed on, no-effect nits logged and dropped. It files a new GitHub issue only when the user explicitly asks for one. Then carry out the answers: fixes go through /plan → /architect-review → /code → specs → /full-review → /simplify, the PR description and the named issues get their notes and comments, and every run ends with /merge-main and, if the user says yes when asked, a green bin/ci, plus a "Review decisions" comment on the PR saying whether it's ready to merge. Use whenever the user says "/settle-pr-review 545", "go through the review on PR 545", "handle the cold review comments", "decide what to do about the caveats on #548", "get PR 543 ready to merge", or pastes a PR link and asks what to do about its review, even if they don't say "cold review".
argument-hint: <pr-number>
---

# Settle PR Review

One run = one PR → the points that matter decided by the user, one question at a time, the rest handled without asking → those decisions carried out → the PR merge-ready (or plainly blocked), with a comment that records what was decided.

The cold review on a PR is a list of things the merger "should know". Most of them change nothing anyone would notice, and asking about each one makes settling a PR slow. The user wants this fast: spend their attention only on points that change what someone sees or gets (a bug, a major UX change, a PR that does the wrong thing), and handle the rest without asking. Nothing is silently dropped, because every point, asked or not, lands in the decisions comment. Nothing gets fixed that the user didn't choose to fix.

`$ARGUMENTS` is the PR number. Accept `#545`, `545`, or a PR URL; reduce it to `N`. One PR per run.

## Step 1: Read the PR and its review

```bash
gh pr view <N> --json number,title,body,state,isDraft,headRefName,baseRefName,url,closingIssuesReferences,comments,reviews
gh api repos/{owner}/{repo}/pulls/<N>/comments --jq '.[] | {id, path, line, user: .user.login, body, in_reply_to_id}'   # inline review comments
```

- **No number, or no such PR** (`gh pr view` fails, e.g. "Could not resolve to a PullRequest"): don't stop. Ask the user for the correct PR number in plain words (say what you tried: "I couldn't find PR #5400 in <owner>/<repo> — what's the right number?"), then run Step 1 again with their answer. Keep asking until a PR is found or the user says to stop. Don't guess a nearby number.
- **Merged or closed:** say so and stop.
- **The review:** the latest comment starting `## Cold review`. Also collect every other reviewer comment that asks for something: PR reviews with a body, inline comments without a reply, plain comments from people. Skip comments that only report status (CI, bots saying "deployed").
- **Already settled:** if a `## Review decisions` comment exists, items it lists are done. Only points added after it (a newer cold review, new reviewer comments) are this run's. Nothing new → report the PR's status (Step 7's verdict line) and stop.
- **No review at all:** say so and offer to stop. This skill decides on review points; it doesn't invent them.
- Read the linked issue (`closingIssuesReferences`) with its comments too: whether a caveat matters depends on what the issue asked for.

## Step 2: Worktree on the PR's branch

All work happens on the PR's own branch (`headRefName`, call it `BRANCH`), so the fixes land in this PR.

```bash
MAIN_DIR=$MAIN_DIR
TOP=$(git rev-parse --show-toplevel)
git -C $MAIN_DIR worktree list   # is BRANCH already checked out somewhere?
```

- **Session already in a worktree on `BRANCH`:** `WT=$TOP`.
- **Session in a worktree on another branch:** stop and say so. Editing a different PR's branch from here is the mistake to avoid.
- **`BRANCH` is checked out in an existing worktree** (`/resolve-issue` keeps `../<app>-issue_<n>`): `WT` = that path.
- **Nowhere:** create `../<app>-pr_<N>` on the existing branch, never a new one:

```bash
cd $MAIN_DIR && git fetch origin $BRANCH
git worktree add ../<app>-pr_<N> $BRANCH 2>/dev/null || git worktree add ../<app>-pr_<N> -b $BRANCH --track origin/$BRANCH
```

Then make it runnable on its own, adding only what's missing (same as `/resolve-issue` Step 2): `.env` + certs copied from `$MAIN_DIR` with `DATABASE_SUFFIX=`/`PORT=` lines stripped; a `DATABASE_SUFFIX=_pr_<N>` line (`printf '\nDATABASE_SUFFIX=%s\n' …`, leading newline on purpose); a port via `bin/worktree-port --assign .env`; and the guarded db setup:

```bash
cd $WT && SUFFIX=$(grep -E '^DATABASE_SUFFIX=' .env | cut -d= -f2)
bin/rails runner "n = ActiveRecord::Base.connection_db_config.database; abort(\"unsuffixed DB: #{n}\") unless n.end_with?(\"$SUFFIX\")" \
  && bin/rails db:create db:schema:load && bin/rails db:seed:mini
```

Never drop the `DATABASE_SUFFIX` line to get past a failure; sharing `<app>_development` is how the main dev database gets wiped.

**Sync with GitHub:** `git -C $WT fetch origin $BRANCH`. Behind → `git -C $WT merge --ff-only origin/$BRANCH`. Ahead with unpushed commits, or diverged, or uncommitted changes → leave them, say so in one line, and build on top (they're the user's). From here every command uses absolute `$WT` paths, and every child skill is told the worktree path and branch.

Tell the user in one line: PR, branch, worktree, port.

## Step 3: Look into every point before asking

A question is only easy to answer if you've done the homework. For each point, before the first question:

- Read the code it names, in `$WT`. Check whether it's true and how big it is: how many rows, which users, how often. Use `bin/prod-read` / `bin/prod-sql` when the size depends on production data (ids and counts, never names).
- Estimate what a fix in this PR would take: one line in one file, or a new feature.
- Work out your recommendation and why.

Then decide, for each point, whether it is worth the user's time. The test: **would a therapist, client, biller or admin notice it, or would money, data or compliance be wrong?** Your Step 3 finding decides this, not the reviewer's tone: a "caveat" that hit 3 real invoices matters, and a "follow-up" about naming doesn't.

| Ask the user | Handle without asking |
|---|---|
| `stop`: the PR does something other than what the issue asked (always asked, first) | `verify` marked **checked: holds** or **fixed in <sha>** → listed as done (ask only if the review says the fix is partial) |
| Bugs: wrong or lost data, wrong money (charges, invoices, claims, payouts), a crash or error users hit, an action that's blocked or silently does nothing | A real limit with no practical effect (needs a setting no org uses, a rare edge case, already covered elsewhere) → one line under **Known limits** in the PR body |
| Major UX changes: users see or do something different (a new step, removed or moved info, a changed flow, a confusing message) | "Someone must do X once it's live" (resolve an HB fault, flip a setting) → a checkbox under **After deploy** in the PR body |
| Security, PHI exposure, HIPAA, billing or clinical compliance | `carry` lines → a comment on each named open issue |
| A request from a person (not a bot or tool) that would change behavior | Code style, naming, refactors, test gaps, performance with no visible effect, "could be cleaner", bot/tool nits → no action, recorded as `auto: no effect` |

When you can't tell which side a point falls on, ask. A wrong skip costs more than a question. If two points are really the same decision, ask once. A headline line counts only if it says something none of the bullets do.

Print a short overview: the ask count, then the auto-handled points as a table, so the user can pull any of them back ("ask me about #4") before or during the questions:

```
**PR #545 — Stop the daily-charging zero-invoice notice** · issue_530 · ../<app>-issue_530 · port 3014
Asking 1 · auto-handled 4

| # | Point | Auto |
|---|---|---|
| 2 | caveat: noise returns if an org turns auto-charging on (none have) | known limit |
| 3 | caveat: resolve HB 100000104 after deploy | after deploy |
| 4 | follow-up: rename `zero_invoice?` | no effect |
| 5 | verify: guard runs before charge | done (holds) |
```

**Nothing to ask** → say so in the overview and go straight to Step 6 (Step 5 has nothing to fix).

## Step 4: Ask, one question at a time

Ask only the points Step 3 marked "ask", with AskUserQuestion, **one question per call**, then wait for the answer before the next. The user wants to push back on or talk through any single point, and a page of tabs makes that hard. Order: `stop` first (it can change everything after it), then bugs, then UX, then the rest.

Keep each question to about three lines, so an 18-year-old with no context gets it in one read:

- **What goes wrong, for whom**, with a concrete example. Not "the guard is skipped when `peer_id` is blank" but "if a therapist's browser never got an ID from the server, this error still gets reported".
- **What you found** in Step 3, in one line: "true, and it hit 3 invoices in the last month".
- **The options**, the one you recommend first with "(Recommended)", each with its consequence in the description. Use the ones that fit; 2–4 per question:

| Option | When it fits | What happens |
|---|---|---|
| Fix it in this PR | small, and inside what the issue is about | goes into the Step 5 plan |
| Note it in the PR | a real limit that's fine to ship with | a line under **Known limits** in the PR body |
| After-deploy task | someone must do something by hand once it's live (resolve an HB fault, flip a setting) | a checkbox under **After deploy** in the PR body |
| Tell the other issue | `carry` lines | a comment on each named issue (if it's still open) |
| Leave it | not worth acting on, or real but outside this PR | recorded as "no action" with the user's reason |
| Hold the PR | the answer needs a person outside this session ("confirm with the practice owner") | the PR stays blocked on it; nothing else waits |

For a `stop`, the options are different: change the PR to do what the issue asked (goes into the plan) · keep the PR and update the issue and PR body to say why the scope moved · close the PR (only on an explicit answer; never close it on a recommendation).

**Never offer "file an issue" as an option, and never file one on your own judgment.** The user files issues themselves unless they ask. A real problem outside this PR gets "Note it in the PR" (under **Known limits**, so it isn't lost) or "Leave it". Only when the user's own answer asks for an issue ("file an issue for it", "make a ticket") does one get filed.

The user can always answer in their own words ("Other"). Take what they say literally; if it's ambiguous, ask a short follow-up about that one point before moving on.

After each answer, append it to `$WT/tmp/settle-pr-review/pr-<N>.md` (point, decision, user's words if any). If the session is interrupted, the next run reads this file and continues from the first unanswered point instead of asking again.

If the user pulls back an auto-handled point, ask it like any other. After the last question, print the decisions (asked and auto) as one table and **continue straight into Step 5**. The user already decided each point; there's no further approval to ask for.

```
| # | Point | Decision |
|---|---|---|
| 1 | caveat: noise returns once one org turns auto-charging on | note in PR |
| 2 | caveat: resolve HB 100000104 after deploy | after-deploy task |
| 3 | follow-up: due_date exact match skips stuck invoices | fix in this PR |
| 4 | follow-up: rename `zero_invoice?` | auto: no effect |
```

## Step 5: Fix what the user chose to fix

Skip this step if nothing was "fix in this PR" or "change the PR to do what the issue asked".

1. `/plan Settle review on PR #<N> (<title>): <each chosen fix, with the reviewer's point, your Step 3 finding and file:line>; worktree $WT, branch $BRANCH. Smallest change for each; nothing else.` Note the plan path.
2. `/architect-review <plan path>`; fold in Critical Issues. A recommendation that widens scope goes under `## Review notes` as "not taken: <why>". (`/frontend-review` too if the plan touches views, components, Stimulus, Turbo or Tailwind.)
3. `/code <plan path>` in `$WT`, with CLAUDE.md's rules and these: only the chosen fixes; migrations via `bin/rails generate migration` + `db:migrate` (never hand-edit `db/schema.rb`); any production data change ships as a dry-run-by-default rake task with CLAUDE.md's snapshot + go/no-go recipe.
4. Specs: each fix gets a spec that fails without it (a review point that wasn't caught by the PR's specs is exactly the gap to close). Then `/test-changed` in `$WT` (base `main`). Run what's affected:

```bash
cd $WT
bundle exec rspec <specs added or changed, plus the existing specs of changed app files>
bin/standardrb <changed .rb files>                  # never bare `bundle exec standardrb`
npx prettier --check <changed app/javascript files>  # only if JS changed
```

`ls` each path first; `bin/rails tailwindcss:build` first if a system spec is in the list. Fix until green; still red after two honest attempts → stop and report with the output. Commit `fix: address review on #<N> — <short>`.

5. `/full-review` in `$WT` (branch `$BRANCH`, every command there). Keep only changes about this PR's code, revert the rest, re-run the specs and lint, commit `fix: address full-review findings`.
6. `/simplify` on the branch diff, same keep/revert rule, re-run, commit `refactor: simplify` (skip if nothing changed).

Child skills know nothing about this one. When one reaches its own "final report", that's one step here: carry on. Their artifacts (`.claude/reviews`, `.claude/scale-reviews`, `.claude/fix-plans`, `.claude/implementation-plan-*`, `.claude/architect-review-*`) stay uncommitted.

If a fix turns out much larger than it looked in Step 3 (a different cause, a new feature), don't build it. Tell the user in two lines and ask one question: build it here anyway, or note it in the PR and leave it.

## Step 6: Merge main and, if the user says so, pass bin/ci

Every run ends here, fixes or not: a PR that was green a week ago can conflict with `main` or fail against it today, and "ready to merge" has to mean today.

1. `/merge-main` in `$WT`. Record the `origin/main` SHA.
2. Ask one question (AskUserQuestion) before running `bin/ci`: run it now, or skip it. It takes a while, so the user decides. Skip → go to Step 7; the verdict says `bin/ci` wasn't run.
3. Yes → `bin/ci`, one at a time on this machine, holding the shared CI slot:

```bash
$MAIN_DIR/.claude/skills/resolve-issues/scripts/ci-slot acquire pr-<N>   # in the background; it wakes you when the slot is yours
cd $WT && bin/ci > tmp/ci.log 2>&1
$MAIN_DIR/.claude/skills/resolve-issues/scripts/ci-slot release pr-<N>   # after the last bin/ci of this step, red or green
```

Read `tmp/ci.log` after it ends (`grep -nE "examples,|^rspec \./|Failures:|FAILED|error" tmp/ci.log`); never pipe a running `bin/ci` through `grep`/`tail`.

4. Red → `/green-ci` in `$WT`, commit `test: get bin/ci green`, run once more. Still red → the PR is **blocked**: say so in Step 7 with the failing specs.

Never trigger GitHub Actions (`gh workflow run`, `gh run rerun`, …). The user runs CI on GitHub.

## Step 7: Carry out the rest, push, and record

Stage specific paths (never `-A`, never review artifacts or `tmp/`), end each commit with the session's attribution line, and push: `git -C $WT push origin $BRANCH`.

Then the non-code decisions:

- **Issues the user asked for** (only these; there are no others): `gh issue create --title "<plain words>" --body-file <scratchpad>/pr-<N>-issue-<k>.md`. Body: what's wrong (from the reviewer and your Step 3 finding, with file:line), why it was left out of PR #<N>, and "Found in the cold review of #<N>". Label `bug` when it's a bug, `enhancement` when it's a want; add `honeybadger` only if it's about an HB fault. No PHI.
- **Carry lines:** `gh issue comment <issue> --body …` on each named issue that's still open: the fact, and "from the cold review of PR #<N>". Closed issue → skip and note it.
- **PR body:** add or update **Known limits** and **After deploy** sections (`gh pr edit <N> --body-file …`, built from the current body so nothing else changes). Link any issue the user asked for there.
- **Stop answered "keep the PR":** update the PR body's Why section and comment on the issue explaining the scope change.
- **Draft PR:** mark it ready (`gh pr ready <N>`) only if the reason it was a draft (a `stop`) is settled and nothing is on hold.

Post the record as a PR comment (`gh pr comment <N> --body-file <scratchpad>/pr-<N>-decisions.md`):

```markdown
## Review decisions

_Points that affect users, money, data or compliance were decided by <the user>; the rest were handled automatically (marked `auto`)._

| # | Point | Decision | Done |
|---|---|---|---|
| 1 | caveat: … | noted in PR | Known limits |
| 2 | caveat: … | after-deploy task | in PR body |
| 3 | follow-up: … | fixed in this PR | a1b2c3d (spec: `spec/…`) |
| 4 | verify: … | already checked by the build | — |
| 5 | follow-up: … | auto: no effect (naming only) | — |

**Checks:** <architect, full-review, simplify counts | no code changes> · <`bin/ci` green | `bin/ci` not run (user's choice)> after merging origin/main (<sha>)
**Verdict:** Ready to merge. ← or: Blocked — <hold item / red CI / open stop>
```

## Step 8: Hand off

Don't merge the PR; the user does. Keep the worktree (`/worktree-sweep` cleans up later). If this run created it, open it: `open -n -a "Visual Studio Code" $WT`.

Finish with these lines and nothing else: the verdict (**Ready to merge** or **Blocked: <why>**) with the PR link; the decisions comment link; what changed (commits, issues commented on, and any issue filed at the user's request); `bin/ci` green (or not run, at the user's choice) against which main SHA; the worktree URL (`cd $WT && env -u PORT bin/dev-url`); any after-deploy tasks, since those are the user's to remember.

## Guardrails

- The user decides every point that matters (Step 3's "ask" column, and anything you're unsure about). Auto-handling only notes, lists, comments or drops: it never changes code, closes the PR, or files an issue. Nothing gets fixed without the user's answer.
- No new GitHub issues unless the user explicitly asks for one in their answer.
- One question per message, short, plain words, recommendation first. No question for points with no effect.
- One PR per run, on its own branch. Never push to another PR's branch, never open a new PR, never merge.
- Production is read-only: `bin/prod-read` / `bin/prod-sql` only. Writes are the user's, via CLAUDE.md's recipe.
- No PHI in questions, commits, issues or comments: ids, counts and code paths.
- Never run `bin/ci` without asking first (Step 6). Never `bin/ci` in parallel with another (hold the CI slot), and never trigger GitHub Actions.
