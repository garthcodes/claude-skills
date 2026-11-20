---
name: project-new
description: Start an autofix project — a GitHub Projects board that Claude works through over many runs, one small PR at a time, instead of a pile of GitHub issues. Given a plain-text goal ("make the scheduler faster", "clean up intake notes") or an issue number that is too big for one PR, research the code, ask the user one plain-language question at a time until the goal, done-when, out of scope and decisions are settled, then (after one yes) create the board with its Status/PR/Note fields, a Brief card and the first 3–5 slice cards. The app's autofix dispatcher picks it up on its next 15-minute poll and builds the cards one by one with /project-step. Use whenever the user says "/project-new …", "start a project for …", "make this a project", "break this down and work through it over time", "turn #640 into a project", or describes ongoing improvement work that will take several PRs. For one bug or small change use /issue-ready; for a new feature built in one go use /prd → /build-feature.
argument-hint: <plain-text goal | issue number> [runner=spec-sweep]
---

# Project New

One run = one autofix board, groomed and ready. After this the user only watches the board, answers `needs-decision` issues and merges PRs.

**How a board runs** (so the Brief you write gives the runs what they need): every 15 minutes `Autofix::ProjectPoller` walks the open boards. A board with no card in Building, In review or Needs you gets its top **Todo** card built by a cloud `/project-step` run. That run sees only the Brief, the card, the repo and GitHub: no production data or logs, no Honeybadger beyond `bin/hb-api`, no questions. When Todo runs out, it plans the next cards itself from the Brief. So everything a run can't look up or decide has to be in the Brief now.

Issues stay for bugs, Honeybadger faults, small one-offs and decision questions. Never file the slices as issues.

## Step 1: Load

- **Issue number:** `gh issue view <N> --comments`. It becomes the board's starting material; Step 5 closes it with a link to the board.
- **Plain text:** write down the user's words exactly.
- `runner=spec-sweep`: a board for `/spec-sweep` (Step 4's sweep variant). Skip Steps 2–3.
- Check the board doesn't exist already: `gh project list --owner <owner> --format json --jq '.projects[] | {number, title}'`.

## Step 2: Research

Do `/issue-ready` Step 2 (code, git history, Honeybadger, `bin/prod-read` counts, CLAUDE.md rules) for the whole goal, aimed at two things:

- the **done-when**: an observable end state (a page under 300 ms, no service left on `include Callable` in `app/services/billing/`, every intake note path covered by a system spec);
- the **first slices**: each one PR's worth of change, small fixes or modest full paths, ordered so each builds on the last. Only the first 3–5 get written now: runs plan the rest as they learn.

Hand wide sweeps to an `Explore` agent and keep its conclusion.

## Step 3: Ask

Ask the user, **one question per message**, plain words with a real example from the code or data, recommended option first, about everything a run couldn't decide on its own: scope edges, behavior changes users would notice, which of two patterns to copy, anything touching money, PHI or permissions. Skip what a house rule already decides (CLAUDE.md), and say which rule. Stop asking when the Brief has no open choice left.

## Step 4: Show the board, then wait

Print the board as it will be created, and ask one question: create it (Recommended), change something, or cancel.

```
Board: <title>
Brief: <title>
  Goal: <one or two lines>
  Done when: <observable end state>
  Out of scope: <bullets>
  Decisions: <bullets, each with its source: user, CLAUDE.md rule, code>
  Runner: project-step
Cards (Todo, top first):
  1. <title> — <one line>
  2. …
```

Brief body template (stored on the card, so plain markdown):

```markdown
**Goal:** …
**Done when:** …

### Out of scope
- …

### Decisions
- … (source)

### Facts runs can't look up
- <prod counts, ids, statuses from bin/prod-read; never names, DOBs or clinical text>

Runner: project-step
```

Each slice card body follows `/issue-ready` Step 4's template, short: files, cause or pattern, decisions, acceptance. `###` headings only.

**Sweep variant** (`runner=spec-sweep`): title "Spec sweep", Brief "Brief: spec sweep" with body "Runs /spec-sweep one round per card. Its ledger on main is the state.\n\nRunner: spec-sweep", and one card "Continue spec sweep" whose body is the last sweep's queue numbers (from the open `spec-sweep-next` issue, if any).

## Step 5: Create it

Only after the yes. `gh project` uses GraphQL, which is fine locally (cloud runs can't, which is why only the app writes boards after this).

```bash
B=$(gh project create --owner <owner> --title "<title>" --format json --jq .number)
gh project link $B --owner <owner> --repo <owner>/<repo>   # shows it on the repo's Projects tab
PID=$(gh project view $B --owner <owner> --format json --jq .id)
STATUS=$(gh project field-list $B --owner <owner> --format json --jq '.fields[] | select(.name=="Status") | .id')
gh api graphql -f query='mutation($f:ID!){updateProjectV2Field(input:{fieldId:$f, singleSelectOptions:[
  {name:"Todo",color:GRAY,description:""},{name:"Building",color:YELLOW,description:""},
  {name:"In review",color:BLUE,description:""},{name:"Done",color:GREEN,description:""},
  {name:"Needs you",color:RED,description:""}]}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}' -f f=$STATUS
gh project field-create $B --owner <owner> --name PR --data-type TEXT
gh project field-create $B --owner <owner> --name Note --data-type TEXT
```

Then add the cards in order, Brief first, each with a body file, and set every slice card's Status to Todo:

```bash
ID=$(gh project item-create $B --owner <owner> --title "<title>" --body "$(cat <file>)" --format json --jq .id)
gh project item-edit --project-id $PID --id $ID --field-id $STATUS --single-select-option-id <Todo option id>
```

(`gh project field-list $B --owner <owner> --format json` gives the option ids after the mutation.) Leave the Brief's Status empty.

Check it (GitHub takes a few seconds to list new cards): `gh project item-list $B --owner <owner> --format json --jq '[.items[] | {title, status}]'` shows the Brief first and the cards in order, all Todo.

From an issue: `gh issue close <N> --comment "Moved to the project board: https://github.com/users/<owner>/projects/<B>"`. For the sweep variant, close the open `spec-sweep-next` issue the same way.

## Step 6: Report

The board link, the card count, and one line: "Autofix picks it up within 15 minutes; first card: <title>." Mention that the cloud `project` routine must be set up (`AUTOFIX_ROUTINE_ID_PROJECT` / `AUTOFIX_FIRE_TOKEN_PROJECT` in production) if this is the first board.
