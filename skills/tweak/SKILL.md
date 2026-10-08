---
name: tweak
description: Small change to an existing feature, from a plain-text request to a PR — isolated ../<app>-<slug> worktree, read the feature's code, interview the user one question at a time until the problem is fully understood, show a short plan, wait for "implement", then build with specs, re-run the feature's existing specs, review the diff, open a PR, and have a separate reviewer agent read the finished PR cold (its assumptions get verified; the rest is posted as a PR comment for the user). The mini /build-feature. Use whenever the user says "/tweak …", "small change to X", "tweak the Y page so …", "make X also do Y", "add a column/filter/field to an existing screen", "let <role> also see …", or wants a modest modification to something already built — no PRD, no issue number. For new features use /prd → /build-feature; for GitHub issues use /resolve-issue.
argument-hint: "<what to change, in plain words>"
---

# Tweak

One run = one small change to a feature that already exists → one worktree → one interview → one plan → one PR.

This sits between `/resolve-issue` (one issue, plan, PR) and `/build-feature` (PRD, contract, nine agents, QA). It keeps the parts of `/build-feature` that matter when you modify something that already works: the existing specs must still pass, there's a checkable **Done when** list, and the diff gets reviewed. It drops the rest. The work is small, so everything runs in this one context with no sub-agents (handoffs cost more than they save at this size). The one exception is the cold reviewer in Step 9, which is useful only because it did not see the build.

The user is involved at two points: the **interview** and the **plan**. Everything else runs without prompts. Because the interview comes first, the plan should hold no surprises.

`$ARGUMENTS` is the request in free text. If it's empty, ask what to change and stop. If it is only an issue number or URL, suggest `/resolve-issue <N>` and stop.

## Variables

```
MAIN_DIR = $MAIN_DIR
SLUG     = 2–4 word kebab-case name for the change, ≤ 30 chars (e.g. supervisor-balance-col)
BRANCH   = tweak/<SLUG>
WT       = $MAIN_DIR/../<app>-<SLUG>
SUFFIX   = _<SLUG with - replaced by _>
```

Siblings named `../<app>-*` are what `/worktree-sweep` cleans up. From Step 2 on, **every** read, edit, search, test, lint and git command uses absolute `$WT` paths (or `cd "$WT" && …`). The session's cwd stays in the main checkout, so a relative path silently edits `main`. That's the most likely mistake in this skill, so double-check paths.

## Step 1: Size check (quick)

Read the request and glance at the code it names (a `grep` or two). The request is **not** a tweak if it clearly needs any of these:
- a new model/table, or a new top-level page or section
- product decisions that span several screens or roles at once
- more than about 10 app files

If so, say so in two lines and suggest `/prd` → `/build-feature`. Stop unless the user says to go ahead. If it's unclear, continue: the interview will settle it (see Step 4).

## Step 2: Set up the worktree

If `$WT` already exists, **reuse it**: check `git -C "$WT" status` and `git -C "$WT" log --oneline origin/main..HEAD`, say what's there, and skip to Step 3. Never delete or reset existing work.

Otherwise:

```bash
cd "$MAIN_DIR" && git fetch origin main
git worktree add ../<app>-<SLUG> -b tweak/<SLUG> origin/main
cd ../<app>-<SLUG>
cp -r "$MAIN_DIR/config/certs" ./config/ && cp "$MAIN_DIR/.env" ./.env
sed -i '' '/^DATABASE_SUFFIX=/d;/^PORT=/d' .env
# printf's leading newline matters: .env may not end in one, and a glued-on line is ignored
printf '\nDATABASE_SUFFIX=%s\n' "<SUFFIX>" >> .env
PORT=$(bin/worktree-port --assign .env)
# Refuse to load a schema unless Rails really points at the suffixed database —
# schema:load against the shared <app>_development would wipe it.
bin/rails runner 'n = ActiveRecord::Base.connection_db_config.database; abort("unsuffixed DB: #{n}") unless n.end_with?("<SUFFIX>")' \
  && bin/rails db:create db:schema:load && bin/rails db:seed:mini
```

Run the DB setup in the background (`run_in_background`) and investigate while it runs. Check it finished before Step 6. If `bin/rails` fails on missing gems, run `bundle install` in `$WT` once and retry. Never drop the `DATABASE_SUFFIX` line to get past a failure, because sharing `<app>_development` with main is how the main dev database gets wiped. Don't copy `.env.prod-read`.

Tell the user in one line: worktree path, branch, and port.

## Step 3: Investigate the feature

Learn the feature well enough that every interview question is about *this* code, not a generic one.

- Find the feature's files: routes → controller → policy → service/model → views/components → Stimulus. Find the pattern the change should copy, since a sibling almost always exists.
- **Find its existing specs**: `spec/models|services|components|policies/…` for the touched files, and the feature's folder under `spec/system/` (`grep -rl` for the page or component name). These become the regression set in Step 6.
- `git -C "$WT" log --oneline -10 -- <hot files>` shows recent changes and the PRs that built the feature. A PRD under `.claude/prds/` may explain the original intent.
- Check the CLAUDE.md rules the change will touch: tenant scoping, SoftDeletable, Pundit roles (`Role::ROLES` is the truth), timezone and MM/DD/YYYY dates, UI copy discipline, Honeybadger context, no hand-edited `db/schema.rb`.
- If prod data matters (how many rows, which statuses exist), read it only through `bin/prod-read` / `bin/prod-sql`, and print ids and counts, not PHI.
- If you need a broad sweep across many files, send it to an Explore agent searching `$WT` and keep only the conclusion.

## Step 4: Interview until you understand it

The point is to build the right thing the first time. A small change built from a wrong guess wastes more of the user's time than a few questions do. Keep asking until you can state all of the following **without guessing**:

| Must know | Example of a gap |
|---|---|
| **Problem**: what is wrong or missing today, and for whom | "Supervisors can't see balances" vs "balances are wrong" |
| **Who**: which roles; staff app, client portal, native app | Should billers get it too? |
| **Behavior**: what happens after the change, including edge cases | empty state, soft-deleted rows, other office/timezone, zero/nil values |
| **What must not change** | existing exports, emails, portal view |
| **Done when**: how the user will check it | "On a client page as supervisor, Balance column shows $X" |

How to ask:
- **One question per message**, then stop and wait for the answer. Each answer can change the next question.
- **Ground it in the code.** Say what you found, then ask. Give 2–3 concrete options and the one you'd pick, with a reason. Keep it plain (an 18-year-old should get it):
  > Today only the assigned therapist sees the Balance column (`ClientPolicy#show_balance?`, `app/policies/client_policy.rb:42`). Should supervisors see it too?
  > A) Yes, for their supervisees · B) Only billers and admins · C) No change
  > I'd pick **A**: supervisors already see those clients' notes.
- **Don't ask what the code can answer.** Look it up instead. Ask about intent, priorities and edge-case behavior, not facts.
- Don't use AskUserQuestion. Write the question as plain text so the user can answer in their own words.
- If the user says "use your defaults" (or similar), stop asking. Every remaining unknown becomes an **Assumption** line in the plan.
- If the answers show the change is bigger than a tweak (Step 1's list), say so and suggest `/prd`. Continue only if the user wants to.

When nothing is left to guess, **play it back** in 3–4 lines: "Here's what I understand: …" (problem, who, behavior, what stays the same). The user confirms or corrects it. A correction means more questions; a confirmation moves on to Step 5.

## Step 5: Present the plan and wait

Write the plan in the terminal and **stop**. The user replies **implement** or says what to change. Write no code until they say implement. If they adjust it, apply the changes and show only what changed.

The user should be able to read it in about 30 seconds: tables, one-line rows, about 20 lines. Shape:

```
**Tweak: supervisors see client balances** · ../<app>-supervisor-balance-col · port 3014

**Change**
| # | What | Where |
|---|---|---|
| 1 | Allow supervisors of the assigned therapist | `app/policies/client_policy.rb` |
| 2 | Show Balance column when policy allows | `app/components/client_row_component.html.erb` |

**Done when**
- [ ] Supervisor sees the balance for a supervisee's client
- [ ] Supervisor does NOT see it for other therapists' clients
- [ ] Therapist and biller views unchanged

**Tests** — new: policy spec rows for supervisor (both cases). Re-run: `spec/policies/client_policy_spec.rb`, `spec/components/client_row_component_spec.rb`, `spec/system/clients/`.
**Copy** — none. ← or: each new string + one-line reason (CLAUDE.md UI Copy Discipline)
**Prod** — none (no data change). ← or: the snapshot + go/no-go recipe
**Assumptions** — only if the user said "use your defaults".

Reply **implement**, or tell me what to change.
```

That example is illustrative. Every file comes from Step 3 and every **Done when** line from the interview. Always include **Prod**. **Done when** lines must be observable (something a person or spec can check), because Step 7 verifies each one.

## Step 6: Implement (after "implement")

Build exactly the plan. If you find mid-way that it was wrong in a way that changes scope, stop and tell the user in two or three lines rather than quietly building something else.

- Follow CLAUDE.md and match the surrounding code. Make the smallest change that delivers the plan, and don't refactor what the plan doesn't mention.
- Migrations come from `bin/rails generate migration` and run with `bin/rails db:migrate` in `$WT`. Never hand-edit `db/schema.rb`. Prod has live data, so new columns must handle existing rows, and large-table indexes use `algorithm: :concurrently` + `disable_ddl_transaction!`.
- Prod data changes ship as a dry-run-by-default rake task backed by a service with specs, with CLAUDE.md's snapshot + go/no-go recipe.
- Write specs for the new behavior (per CLAUDE.md's Request Specs Policy). When an existing spec breaks because the behavior was *meant* to change, update it. When it breaks for any other reason, it's a regression: fix the code, not the spec.

## Step 7: Verify, review, tick off

**Specs and lint.** Run the regression set from Step 3 plus everything added or changed. Not `bin/ci`.

```bash
cd "$WT"
bin/rails tailwindcss:build                        # before any system spec, or pages render unstyled
bundle exec rspec <changed/added specs> <the feature's existing unit specs> <the feature's spec/system files>
bin/standardrb <changed .rb files>                 # never bare `bundle exec standardrb`
npx prettier --check <changed app/javascript files> # only if JS changed
```

- Check that every path in the regression set exists before you run it (`ls` them). Paths from an Explore agent are sometimes wrong (e.g. `spec/requests/clients_controller_spec.rb` when the file is in `spec/controllers/`), and a single missing file aborts the whole run with "0 examples".
- Write long runs (anything with system specs) to a log, in the background: `bundle exec rspec … > tmp/<name>.log 2>&1`, then `grep -E "examples,|^rspec \./|Try error" tmp/<name>.log`. Never pipe a running suite through `grep` or `tail`: you see nothing until it ends, and a hung run looks the same as a slow one.

Fix failures and re-run. If a failure also happens on `origin/main`, note it for the PR instead of chasing it. If something still fails after two honest attempts, stop and report it with the output, and don't open a PR over red specs. Never trigger GitHub Actions.

**Review.** Run the `code-review` skill at `medium` on the branch diff, fix the findings it confirms, and re-run the affected specs. Skip a finding that's outside the plan's scope and list it under "Also noticed".

**Tick off Done when.** For each line, give its evidence: the spec example that proves it (`spec/…:LINE`), or the `file:line` for something only a human can see. A line with no evidence gets a spec, or it goes in the PR as unverified.

## Step 8: Commit, push, PR

Stage specific files (`git add <paths>`, not `-A`). One commit is usually right. End it with the attribution line from the session's system reminder.

```bash
cd "$WT" && git push -u origin tweak/<SLUG>
gh pr create --title "<what changed, plain words>" --body "$(cat <<'EOF'
## Why
<one short paragraph: the problem as the user described it in the interview>

## What
| Change | Where |
|---|---|
| … | `path` |

## Done when
- [x] <line> — `spec/…:LINE`
- [x] <line> — `app/…:LINE` (visual)

## Tests
<specs added; regression set run (files); lint; anything unrelated that failed on main too>

<## Production — only if data changes: dry run → snapshot → apply recipe and go/no-go blurb from CLAUDE.md>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

## Step 9: Cold review

Follow `.claude/skills/resolve-issue/references/cold-review.md` with:

- `<WHAT>`: "made a small change to an existing feature at the user's request"; `<WT>`: `$WT`; slug `tweak-<SLUG>`
- `<ASK>`: `1. The request and the agreed plan, below the notes` (paste `$ARGUMENTS`, the interview's answers in one line each, and the plan's **Done when** list under the notes, because the reviewer has no issue to read)
- `<NOTES>`: the default list, and specifically: what you inferred in the interview that the user never said outright, the existing behaviors you assumed stay the same, roles you didn't check, and everything under "Also noticed"
- `<FOCUS>`: "A tweak should change only what the request asked for. Look hardest for an existing behavior of this feature that changed as a side effect (another role, another page that uses the same component or query, existing data)."
- `<STOP>`: "the PR does something other than what the request and plan asked"
- `<RECHECK>`: re-run the Step 7 specs and lint (still no `bin/ci`)

## Step 10: Hand off

Start the dev server for review, then open the worktree:

```bash
cd "$WT"
WORKTREE_PORT="$(grep -E '^PORT=' .env | cut -d= -f2)"
BASE_URL="https://localhost:${WORKTREE_PORT}"
if ! curl -sk -o /dev/null "$BASE_URL"; then
  mkdir -p log && nohup bin/dev </dev/null >log/dev-server.log 2>&1 & disown
  for i in $(seq 1 30); do curl -sk -o /dev/null "$BASE_URL" && break; sleep 1; done
fi
open -n -a "Visual Studio Code" "$WT"
```

Finish with five lines: the PR link (say "draft" if Step 9 stopped it), the review URL (the page the change is on, if there is one), what was verified (specs, regression set, lint, review), the cold review (comment link, tag counts, what each `verify` check found), and anything under "Also noticed" that isn't in the review comment. When the comment holds anything beyond `verify` lines, end with: "Next: `/settle-pr-review <PR>` to decide on the review." The worktree stays, and `/worktree-sweep` cleans it up later.

## Guardrails

- Production is read-only here: `bin/prod-read`/`bin/prod-sql` only. Writes are the user's, via the recipe.
- No PHI in questions, the plan, commits, or the PR: ids and counts only.
- One tweak per run. Other problems you notice go under "Also noticed", not into this PR.
