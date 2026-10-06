# Honeybadger → GitHub issue

One issue per fault (or per follow-up). The reader is `/resolve-issue`, which investigates on its own from the issue body and comments, so the body has to carry everything Honeybadger told you — once the issue exists nobody goes back to the fault page. The reader is also GitHub, which is outside the HIPAA boundary: ids, counts and code paths only, never names, emails, DOBs, phone numbers or clinical text, even when a notice shows them.

## Dedup first

```bash
gh issue list --state all --search "HB #<fault_id> in:title" --json number,title,state,closedAt,url
```

- **Open issue** → don't file another; note it in the report (`#N already open`). An open issue does **not** make the fault "handled": if it meets the urgent criteria it is still fixed on the fast path, and the PR says `Closes #N`. When its impact changed since filing (quiet → recurring), add a one-line comment with the new counts so the priority on the issue stays true.
- **Closed issue** and the fault has notices after `closedAt` → file a new one and reference the old (`Regression of #N`) in the first line of the body.
- **Closed issue** and no notices since → treat as fixed-but-unresolved: tell the user to resolve the fault in Honeybadger.

## Labels

`bug` and `honeybadger`. Create the second once if it's missing:

```bash
gh label list --search honeybadger --json name | grep -q honeybadger || gh label create honeybadger --color E6A700 --description "Filed from a Honeybadger fault by /fix-honeybadger"
```

## Create

Write the body to a file in the scratchpad first (a nested heredoc inside `$(cat <<EOF)` breaks on the inner code fences), then:

```bash
gh issue create --label bug --label honeybadger \
  --title "HB #<fault_id>: <ErrorClass> in <Class#method or file:line>" \
  --body-file <scratchpad>/hb-<fault_id>-issue.md
```

Body:

````markdown
**Honeybadger:** <fault URL>
**Priority:** <urgent — fix next | deferred: <one-line reason>>
**Error:** `<ErrorClass>` — <message, trimmed, no PHI>
**Impact:** <N> notices in last 7d · <total> all time · <N> affected users · first seen MM/DD/YYYY · last seen MM/DD/YYYY
**Environment:** <production|staging> · <request|job|webhook|mailer>

## Where it fails

```
app/<file>.rb:<line> in `<method>`
app/<file>.rb:<line> in `<method>`
```

Request: `<METHOD> <path with ids>` (or job: `<JobClass>` with `<argument shape>`)

## Root cause (as far as known)

<What the code assumes and what the data does instead. "Not investigated" for a triage-only filing; say what was ruled out if you looked.>

## Suggested fix

- <one line per change, with the file>
- Regression spec: <which spec file, which input>

## Why not fixed now

<Deferred faults only: low impact / stopped recurring / needs a migration / needs a product decision on X / shared pattern across N callers — one line.>

## Follow-ups discovered (optional)

- <related things noticed while reading the code, if any>
````

Variants:

- **Triage-only filing** (Step 2 sweep, no investigation yet): keep the header, "Where it fails" and "Why not fixed now"; root cause is "Not investigated"; "Suggested fix" is the obvious direction or omitted.
- **Scope-guard filing** (Step 6 found the fix is too big): include the full investigation — that's the issue's main value. Say concretely why it's big (migration, N call sites, product decision) so `/resolve-issue` plans for it.
- **Follow-up from a fix** (Step 6 or Step 9 found something adjacent): title `Follow-up to HB #<fault_id>: <what>`, reference the PR in the first line, and describe the specific pattern or finding instead of the fault block.

Record every issue URL you create; the report and the PR body list them.
