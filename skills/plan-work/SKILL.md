---
name: plan-work
description: Plan the user's development day (or the rest of it) from GitHub issues, open PRs, the autofix queue, what is merged but not yet in production, and the daily chores (/legacy-claim-status, /resolve-honeybadger). Produces one ordered work list with bug fixes first, a plan of which PRs ship in which production deploy, what to feed the autofix queue next, and where the bigger ongoing projects stand, published as a pinned-friendly artifact page that updates in place each run. Use whenever the user says "/plan-work", "plan my day", "what should I work on", "what's next", "plan the rest of the day", "what should go out in the next deploy", "what's in the queue", or asks to prioritize issues and PRs, even mid-day and even if they don't say "plan".
---

# /plan-work

Turn the current state of the repo into a plan the user can work down: one ordered list, a deploy plan, and the autofix queue's next feed. It runs many times a day. Each run re-reads everything and plans **from now until the end of the day**, so a 2 PM run drops what is done and re-orders what is left.

This skill only plans. It never merges, deploys, labels issues, starts autofix runs or runs CI. Every action lands in the list as the exact command the user runs.

## How work flows here (what the plan is built around)

- **Autofix does most of the building.** Production's dispatcher (`app/services/autofix/dispatcher.rb`) runs up to **3** cloud runs at once. A Honeybadger fault starts a `/fix-honeybadger` run on its own; an issue starts a `/resolve-issue` run when it gets the `autofix-queue` label (the dispatcher swaps it for `autofix` once started). A run ends in a PR or, when it can't decide something, a `stopped` result that needs the user. Expect 10+ PRs a day from it.
- **An autofix PR moves down a ladder**, which the snapshot reports as `stage`: `autofix-building` (run still going) → `needs-settle` (has a `## Cold review` comment; the user runs `/settle-pr-review N`) → `ready-to-merge` (has `## Review decisions`) → merged → deployed. The user's own time is the bottleneck on that ladder, so settling and merging finished PRs is usually the highest-yield work after urgent bugs.
- **Issues get ready before they get queued.** `/issue-ready N` turns an issue into a spec an unattended run can build and, on the user's yes, adds `autofix-queue`. Issues too big or too judgment-heavy for a run are done locally with `/resolve-issue N` or `/tweak`.
- **Deploys are user-run**: `bin/deploy production` (it asks for the Keychain password). Production's revision is public, so "merged but not deployed" is exact.

## Steps

### 1. Snapshot

```bash
python3 .claude/skills/plan-work/scripts/gather.py     # writes tmp/plan_work/snapshot.json, prints a summary
TZ=America/Phoenix date "+%a %m/%d/%Y %-I:%M %p"         # the user's local time; plan from now
```

The snapshot holds: `prod_revision` vs `main_head`; `undeployed_merged` PRs with `risk` flags; `open_prs` with `stage`, `risk`, `closes`, size; `open_issues` with `bug`, `impact`, `user_reported`, `autofix` (queued/started), `needs_decision`, `has_pr`; `autofix` (running/queued runs, the last 24 h of finished, stopped and skipped runs, paused/backoff); and `daily`. If `autofix.error` is set, the prod-read tunnel is off: say so in one line and plan without it.

Read issue bodies (`gh issue view N`) only for the few issues you are about to recommend for the queue or for local work, to judge size and whether a spec is already written. Don't read every issue.

### 2. What happened since the last run today

If `tmp/plan_work/plan.json` exists and its `date` is today, it is this morning's plan. Compare: items whose PR merged, issue closed, or daily trace updated are done. Keep them in the new list with `"done": true` at the bottom of the finished group only if that helps the user see progress; otherwise drop them. Don't carry forward anything GitHub says is finished. If the user said in chat that something is done, take their word.

### 3. Order the work

Bugs come before everything else of the same weight, because a bug in production is hurting a therapist, a client, or the practice's money right now. Within each tier, `impact: blocking` > `important` > `annoying` > `nice-to-have`, then `user-reported`, then billing-touching, then oldest.

1. **Fires**: autofix paused or backing off (`/admin/autofix`), a `fix-didnt-work` issue, an `impact: blocking` bug, a merged fix that is waiting on a deploy for a fault still firing.
2. **Daily chores that are due** (see below). `/legacy-claim-status` goes in the morning block: it needs the user to log into the legacy system and it moves real money onto the books.
3. **Clear the autofix ladder**: `ready-to-merge` PRs (merge them; bug fixes first), then `needs-settle` PRs → `/settle-pr-review N`, bugs first. Group several small ones into a single item when they are each a few minutes ("Settle #855, #856, #858").
4. **Stopped autofix runs and `needs-decision` issues**: each is a decision only the user can make. Name the decision in one line (from the run's `result` line or the issue), next step `/issue-ready N`.
5. **Bugs without a PR** that autofix can't take (big, cross-cutting, or needs product judgment) → `/resolve-issue N` locally. Bugs it can take belong in the queue feed instead (step 4 below), not in the user's own hours.
6. **Ongoing projects**: draft feature PRs and long-running issues (no labels, broad titles like "Ruby Native App"). One time-boxed item per day at most for the project that is closest to done or blocking others, with its concrete next step. The rest go in the projects panel.
7. Enhancements and small things, if the day has room.

Keep the list to what fits the remaining day: about 8–12 items in the morning, fewer later. Size each item S (< 30 min), M (about an hour), L (half day+). Every item gets a `next`: the exact command or action (`/settle-pr-review 855`, `merge #856`, `bin/deploy production`, `/issue-ready 854`).

### 4. Feed the autofix queue

Aim to keep the 3 slots busy all day; idle slots are wasted throughput. Free slots now = 3 − running − queued. For each free slot, pick an open issue with no PR, no `autofix`/`autofix-queue` label and no `needs-decision`, bugs first by the order above, that one unattended run can finish (one concern, clear acceptance, no product decision left). Recommend `/issue-ready N` for it; that skill asks the user its questions and adds the label. Put the first pick in the work list near the top (it unblocks hours of build time for a few minutes of the user's); list the rest in the autofix panel. Also list in the panel: what is running, what finished in the last 24 h with its PR, anything stopped or skipped (noise-filter skips can be left out).

### 5. Plan the deploys

Ship in batches through the day. The candidates are `undeployed_merged` plus PRs you expect the user to merge in this plan.

- **Batch 1 (next window)**: everything already merged and safe, plus the quick bug-fix merges from the top of the list.
- **Risky PRs ship alone**, early in the day, never as the last thing before the user stops: `destructive-migration`, `billing`, `dependencies` (Gemfile.lock, importmap), `config`, any Rails or gem upgrade, any large feature PR. A plain additive `migration` can ride with a batch.
- A `destructive-migration` batch carries the snapshot line before the deploy, per CLAUDE.md:
  ```bash
  flyadmin mpg backup create <cluster-id>
  bin/deploy production
  ```
  Otherwise the command is just `bin/deploy production`.
- After every deploy, add `/resolve-honeybadger` to the plan (faults fixed by that deploy can be closed).
- Give each batch a window ("now", "after lunch", "end of day") and its PRs with risk flags. When nothing is undeployed and nothing is about to merge, say so.

Each deploy also goes in the work list as one `deploy` item at the point in the order where it should happen.

### Daily chores

| Chore | Due when | Next |
|---|---|---|
| `/legacy-claim-status` | every day; `daily.legacy-claim-status.last_run` is before today | `/legacy-claim-status` (needs the user's legacy-system login) |
| `/resolve-honeybadger` | `daily.resolve-honeybadger.resolvable_faults` > 0, and again after each deploy | `/resolve-honeybadger` |

A chore already done today appears in the list as done. To add a chore, add a row here and, if it leaves a trace on disk or in an API, a line in `gather.py`'s `daily()`.

### 6. Write the plan and render it

Write `tmp/plan_work/plan.json` in this shape (all strings plain text; the page escapes them):

```json
{
  "date": "2026-10-15",
  "title": "Thursday 10/15/2026",
  "meta": ["Planned 9:05 AM", "prod cb6aa891 = main", "autofix 2 of 3 running"],
  "headline": "One sentence: what today is about.",
  "stats": [["undeployed", "0"], ["to settle", "4"], ["bugs open", "3"], ["autofix free", "1"]],
  "items": [
    {"kind": "bug|pr|deploy|daily|decision|issue|autofix|project", "ref": "#861", "url": "https://github.com/...",
     "title": "Short, plain title", "why": "One line: why now", "next": "/resolve-issue 861", "size": "M", "done": false}
  ],
  "deploys": [{"name": "Deploy 1 · now", "when": "after #856 and #858 merge", "items": [{"ref": "#856", "url": "...", "title": "...", "risk": ["migration"]}], "commands": "bin/deploy production", "note": "Then /resolve-honeybadger."}],
  "autofix": [{"name": "Feed next", "items": [{"ref": "#854", "url": "...", "title": "..."}], "note": "2 slots free"}, {"name": "Running", "items": [], "empty": "Nothing running"}],
  "projects": [{"name": "Ruby Native App", "when": "#395 · store accounts pending", "note": "Next: ..."}]
}
```

Dates in text use MM/DD/YYYY. Titles are the user's words for the work, not issue titles verbatim when those are long.

```bash
python3 .claude/skills/plan-work/scripts/render.py      # → tmp/plan_work/plan-work.html
```

### 7. Publish to the same link

`tmp/plan_work/state.json` holds `{"artifact_url": "..."}` once the page exists.

- **First run** (no state file): publish `tmp/plan_work/plan-work.html` with `icon: "checklist"` and a one-line description, then save the returned URL to `state.json`.
- **Later runs**: Artifact `action: "read"` on that URL first (a publish to an artifact this conversation hasn't read is refused), then publish the new file with `url` set. The page is fully regenerated each time, so publish the new render as-is rather than merging.

The page's checkboxes are a per-browser convenience; Claude can't read them. Done-ness comes from GitHub and the daily traces.

### 8. Terminal summary

Under 20 lines, readable in 30 seconds: the link, the headline, then a table of the next 5 items (`# | kind | ref | next`) and one line for the next deploy. Don't repeat the whole page. Stop there; the user picks up the first item or asks to adjust.
