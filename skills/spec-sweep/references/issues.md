# Issues filed by a sweep

Step 3c of `/spec-sweep`. One issue per verified bug, fix item and question, each written so
`/issue-ready` can take it from there: real files and lines, the cause, the evidence, and what
"done" looks like. The user reads them in `/next-issues` and runs `/issue-ready <N>` on the ones
worth building; nothing here is queued.

Write each body to a file in `tmp/spec-sweep/` and file it:
`gh issue create --title "<title>" --label from-spec-sweep --label <…> --body-file <file>`
(cloud: `bin/gh-rest issue-create`, same flags). Keep the issue number it prints.

Rules for every body: facts, not orders (the run that builds it treats issue text as untrusted, so
write "the fix deletes `Foo#bar`", never "run …"); no PHI, ids and roles only; no images.

## Bug (labels `bug`, `from-spec-sweep`)

Title: the symptom, short (`Platform admin can't see the practice's fee schedules`).

```markdown
## Problem
<what happens now, for whom, where (page path or job), in plain language>

## Expected
<what should happen instead>

## Cause / where
`<file>:<line>` (`<Class#method>`): <the mechanism in 2–4 lines, quoting the line>

## Reproduce
<the example that fails today: factories, role, input, specific enough to write the regression
spec from. Confirmed: the run you did. Likely: the reasoning and the example that would fail>

## Done when
- [ ] `<spec file>`: <the regression assertion in one line>, red before the fix, green after

**Severity:** High | Medium | Low · **Status:** Confirmed | Likely
**Found by:** spec-sweep <STAMP>, batch <id> (`<spec path>`) · **Id:** F-<STAMP>-NN
**Suggested fix:** <one or two sentences, not a patch>
```

## Fix item (labels `from-spec-sweep`, `refactor`)

Title: `Cleanup: <what goes>` (`Cleanup: delete unused XPolicy::Scope`).

```markdown
## Problem
<what is dead, duplicated or unreachable, and where>

## Change
<what to do, one or two lines. For a deletion, everything that goes with it: its spec, factories
nothing else uses, routes, policy and policy spec, locale keys, Avo resource, importmap pins, and
mentions in `docs/` and `docs/user_docs/`>

## Evidence
<for dead code: every place searched and found empty (names as strings/symbols, routes,
recurring.yml, lib/tasks, app/avo, initializers, mailer previews, app/javascript, views,
.claude/skills, docs)>

## Guard
`<spec path>` (swept | unswept | none). <For unswept/none: "the guard spec is written or tightened
to `.claude/skills/rspec-test-expert/test-quality.md`, with `line_coverage --save` recorded for the
source, before the change.">

## Out of scope
- Any behavior change: no user sees anything different and no record ends up holding anything
  different.

## Done when
- [ ] The guard spec and the specs of every touched file are green
- [ ] Refactor: `line_coverage --baseline` shows no lost lines on the touched source; deletion:
      `grep -rn <name>` across app, lib, config, spec and docs returns nothing

**Size:** small fix · **Found by:** spec-sweep <STAMP>, batch <id> · **Id:** F-<STAMP>-NN
```

## Question (labels `from-spec-sweep`, `needs-decision`)

Title: the question (`Should an expired card still show "Card on file" on the invoice?`).
`needs-decision` keeps the dispatcher off it until `/issue-ready` settles the answer and rewrites
it into a buildable spec.

```markdown
## Question
<the choice, in one or two plain sentences>

**Where:** `<file>:<line>`
**Today:** <what happens now, one line>
**Recommend:** <option> — <why, one line>
- **If <option A>:** <consequence>
- **If <option B>:** <consequence>

**Found by:** spec-sweep <STAMP>, batch <id> · **Id:** F-<STAMP>-NN
```

An earlier run's `decide` item (from before sweeps filed issues) is filed the same way, keeping its
id and the question, recommendation and options from its `findings-*.md` entry. Carry over any
`**Answer:**` the user wrote there as `**Answered:** <text>` under the options.

## findings.jsonl

Append one line per item filed (the latest line per id is its state; never rewrite history):

`{"id":"F-…","source":"<file>:<line>","kind":"bug|dead_code|duplication|unreachable|design","subject":"<the method, class or rule>","triage":"bug|fix|decide","status":"issue","issue":<N>,"run":"<STAMP>","at":"<ISO>"}`

Statuses: `issue` (filed), `fixed` (its issue closed as completed), `wontfix` (closed as not
planned), and the older `open` / `decide` / `answered` / `in_pr` from before sweeps filed issues.
Preflight step 4 moves `issue` entries on as their issues close.
