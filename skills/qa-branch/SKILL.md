---
name: qa-branch
description: QA the current branch by hand, in your own Chrome — reads the PR, seeds the data the feature needs, signs in as the right role, opens a tab in your browser at the feature, then walks you through one scenario at a time while you watch and react
argument-hint: '[optional: extra focus, e.g. "just the calendar icon" or "as coordinator"] [--no-seed]'
---

# QA Branch (guided walkthrough in the user's Chrome)

You are a senior QA engineer pairing with the developer on **their** screen. The
developer wants to *see* the branch's feature working in their real Chrome window
without doing any of the setup themselves. You do the boring part — find the PR,
figure out what data the feature needs, put that data in the local database,
sign in as the right user, open the tab on the right page — and then you step
through the feature one scenario at a time, telling them what to look at and
waiting for their verdict before moving on.

**You do not fix anything during the walkthrough.** You note; they decide.
**The user is watching.** Keep narration to one or two sentences per step.

Extra focus / flags from the user: `$ARGUMENTS`

---

## Step 0 — Resolve where "this branch" is running

Do this before anything else. This checkout may be the main repo (port 3001) or a
worktree with its own port and its own database (`PORT=` / `DATABASE_SUFFIX=` in
`.env`). QA'ing the wrong port means QA'ing the wrong branch.

```bash
BRANCH="$(git branch --show-current)"
BASE_URL="$(bin/dev-url)"                 # $PORT > PORT= in .env > 3001
PORT="${BASE_URL##*:}"
grep -E '^(PORT|DATABASE_SUFFIX)=' .env 2>/dev/null
lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t
```

- If `lsof` prints a pid, the server is up. Confirm it is **this** checkout's server:
  `lsof -p <pid> | grep cwd` must show this directory. If it is a different
  checkout on the same port, stop and tell the user — do not QA someone else's branch.
- If nothing is listening: `nohup bin/dev > log/dev-server.out 2>&1 &` then poll
  `curl -ksf -o /dev/null "$BASE_URL/up"` every 2 s for up to 90 s. If it never
  comes up, show the tail of `log/dev-server.out` and stop.
- If `DATABASE_SUFFIX` is set and `bin/rails runner 'puts Client.count'` prints `0`,
  the worktree DB is empty. Seed it with the mini profile (~10 s):
  ```bash
  bin/rails db:seed:mini 2>&1 | tail -3    # ends "Seeds Complete (mini, Ns)"
  ```
  then restart the server (Puma caches connections).

Print one line: `Branch <name> → <BASE_URL> (db <app>_development<suffix>)`.

## Step 1 — Read the PR (or the diff if there is no PR)

```bash
gh pr view --json number,title,url,body,files 2>/dev/null
```

- **PR exists**: use its title, body, and file list as the spec. The body's
  Summary / Test plan sections tell you what the author thinks changed.
- **No PR**: fall back to `git log main..HEAD --oneline` and
  `git diff main...HEAD --stat`, and treat the commit messages as the summary.

Also look for the branch's planning artifacts — they name the scenarios for you:
```bash
ls .claude/acceptance-criteria/ .claude/prds/ .claude/qa/ 2>/dev/null | grep -i "<slug words from the branch/PR title>"
```
If an acceptance-criteria file matches, its Given/When/Then rows become scenarios
directly (Step 3). Do not invent scenarios that contradict it.

## Step 2 — Work out the entry point, the role, and the data

Read only the files in the diff plus what they touch. Answer, concretely:

| Question | Where to look |
|---|---|
| Which **page(s)** show the change? | changed views/components → the controller that renders them → `config/routes.rb` for the path |
| Which **role** must be signed in? | the Pundit policy for that controller; pick the *least* privileged role that can see it, and note any role that must *not* |
| What **record state** makes the change visible? | model scopes/predicates the diff adds or reads (e.g. `intake_forms_state == :complete`), service preconditions, feature flags in `.env` |
| Is any of this **client-portal**? | routes under `/forms/*` or `/clients/*` → needs an access-token URL, not a login |

Then find or make the data. Prefer **finding** an existing record over creating one —
seeded data is realistic and the user knows it. Use `bin/rails runner` (never the
console, never anything pointed at production):

```bash
bin/rails runner '
  org = Organization.find_by(subdomain: "<org-subdomain>")          # never Organization.first
  ActsAsTenant.with_tenant(org) do
    # e.g. Client.joins(...).where(...).first  — print id + name + the URL you will open
  end
'
```

Rules for this step:
- Wrap everything in `ActsAsTenant.with_tenant(org)`.
- If you must **create** data, create the minimum, tag it so it can be found later
  (`first_name: "QA"`, `last_name: "<branch-short>"`), and record the ids in the
  session notes (Step 6). If the user passed `--no-seed`, only find, never create.
- Clear the blockers that intercept every click for therapist users before opening
  the browser: pending CPT confirmations, unresolved diagnosis selection, outcome
  popups (`update_columns(cpt_code:, cpt_code_confirmed_at:)`,
  `diagnosis_selected_at:`, `outcome_popup_deferred_until: 1.day.from_now`), then
  `Rails.cache.clear` — the checks are cached for 30 s.
- For **each role** you will use, mint a magic-link token instead of submitting the
  form (`Passwordless::MagicLinksController` just looks up `users.magic_link_token`,
  valid 20 min):
  ```ruby
  u = User.find_by!(email: "therapist@example.com")
  u.update_columns(magic_link_token: "qa-<branch-short>-<role>", magic_link_sent_at: Time.current)
  ```
  Login URL: `$BASE_URL/passwordless/users/magic_link?token=qa-<branch-short>-<role>`

Seeded users you can rely on: `admin@example.com`, `therapist@example.com`,
`coordinator@example.com`, `supervisor@example.com` (supervisor + therapist;
the co-signer for `therapist@example.com`), `manager@example.com` (manager),
`billing@example.com` (biller), `platform-admin@example.com` (platform_admin,
platform subdomain). These are placeholders — list whatever your `db/seeds`
actually creates. Client-portal pages take a
form-assignment `access_token`, not a login: `testclient@example.com` always has
pending assignments with valid tokens.

## Step 3 — Build the scenario list (before opening the browser)

Write `.claude/qa/branch-walkthroughs/<branch>-<YYYYMMDD-HHMM>.md` with:

```markdown
# QA walkthrough — <branch> (PR #<n>: <title>)
Base URL: <url>   Role(s): <emails>   Data: <ids you found/created>

## Scenarios
| # | Scenario | Role | URL | Expect | Result |
|---|---|---|---|---|---|
| 1 | <one line, from the PR summary / AC row> | therapist | /staff/... | <what the user should see> | |
```

Ordering, so the user sees the point of the branch first:
1. The **headline change** from the PR summary, on the primary page, happy path.
2. Each other changed surface (a component used in three places = three rows).
3. The **before/negative** case — the same page with a record that should *not*
   show the new behavior (proves it isn't just always-on).
4. One **forbidden-role** check if the diff touches a policy.
5. Anything the acceptance-criteria file has that the above missed.

Cap it at ~8 rows unless the user's `$ARGUMENTS` asks for more. Show the table
in chat and ask: **"Start with #1?"** — one question, wait for the answer.

## Step 4 — Open the tab in the user's Chrome

Use **claude-in-chrome** (not Playwright, not Selenium) — the whole point is that
the tab appears in the user's own browser. Load the tools in one call:

`ToolSearch` → `select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__tabs_create_mcp,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__find,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__read_console_messages,mcp__claude-in-chrome__read_network_requests,mcp__claude-in-chrome__javascript_tool`

1. `tabs_context_mcp` first, then `tabs_create_mcp` — **always a new tab**, never
   reuse one of the user's existing tabs.
2. Navigate to the magic-link URL from Step 2. If it lands on `/users/sign_in`
   with "invalid or has expired", the token was minted >20 min ago — re-mint and retry once.
3. Navigate to scenario #1's URL. Take a screenshot so *you* can see what the user sees.
4. Read the console once after the page loads; a JS error here is finding #0
   regardless of scenario.

Known claude-in-chrome quirks (from previous hunts): the window won't shrink below
~1224 px, so skip mobile viewports unless asked; screenshots can lag the DOM by a
beat — re-screenshot before concluding something is missing; Turbo link clicks are
occasionally swallowed — fall back to `javascript_tool` with `el.click()` or
`form.requestSubmit()`; `data-turbo-confirm` dialogs would block the extension —
never click one, tell the user to click it, or bypass with
`Turbo.config.forms.confirm = () => Promise.resolve(true)` only if they agree.

## Step 5 — Walk through, one scenario at a time

For each row, in order:

1. **Navigate** (or tell the user which link to click — if the feature adds
   navigation, let them find it; not being able to is a finding).
2. **Say what to look at**, one sentence: *"#3 — appointment drawer for QA Sign
   should say 'Forms complete', not 'incomplete'."*
3. **Check the boring things yourself** while they look: console errors,
   4xx/5xx in the network log, that the DB record still has the state you set
   (`bin/rails runner`) if the scenario wrote anything.
4. **Wait for the user.** Accept: `next` / `ok` (pass), `bug` or any description
   (record it — ask for one clarifying detail at most), `skip`, `again` (re-run
   the same scenario, e.g. after they poke at it), `as <email>` (re-login as that
   user via a freshly minted token and re-run), `done` (jump to Step 6).
5. Record the result in the table immediately — don't batch.

Never advance without a reply. Never run two scenarios in one turn. If the user
goes off-script ("what happens if I delete the policy?"), do the thing they
asked, note the outcome under an `Ad hoc` row, and then return to the next scenario.

**Re-authenticating as a different role**: navigate the same tab to
`/users/sign_out` first, then the new token URL. Do not open a second tab for a
second user — sessions share cookies.

## Step 6 — Wrap up

When the table is complete or the user says `done`:

1. Fill the `Result` column (`pass` / `bug: <one line>` / `skip` / `observation: <one line>`).
2. Append a `## Findings` section — bugs first, then observations, each with the
   scenario number, the URL, the role, and a screenshot path if you took one
   (`save to .claude/qa/branch-walkthroughs/<branch>-<stamp>-<n>.png`).
3. Append `## Cleanup` with a runner snippet that soft-deletes anything you
   **created** in Step 2 (never anything you merely found). Do not run it unless
   the user asks — they may want the data for a second look.
4. Leave the tab open and signed in. Print the file path and a three-line summary:
   scenarios run / passed / bugs. If there are bugs, offer `/bug-hunt-fix` once;
   don't launch it.

---

## Rules

- **Local only.** Everything targets `$BASE_URL` from Step 0 and the local
  database. Never `fly`, never staging, never anything with production data.
- **The user drives the verdicts.** You observe, they judge. Don't declare a
  scenario passed because the code says it should.
- **One question per message** while walking through.
- **Never hand-edit `db/schema.rb`**, never run the full `db:seed` (use `db:seed:mini`), never hard-delete
  SoftDeletable records in cleanup — use `#soft_delete`.
- If claude-in-chrome is unavailable (no tools after ToolSearch, or the extension
  doesn't answer twice), stop and say so — do not silently fall back to a headless
  browser the user can't see. Offer `/bug-hunt` as the headless alternative.
