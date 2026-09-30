# C3 — Acceptance gate

## Inputs

- Bootstrap per `_shared.md`. From the state file: QA plan path, QA results, Known Issues. The dev
  server from C2 is still running on `PORT=` from `.env`.

## Steps

QA exercised scenarios; this phase asks the only question that decides whether a PR is created:
**was every acceptance criterion observed to hold — including every guard?** The reviewed contract at
`${AC_PATH}` is the contract.

### Step A1: Score the criteria

```
/verify-acceptance
```

It joins the QA plan's `Verifies:` tags with `/execute-qa`'s PASS/FAIL results, runs the branch's
system specs (`CI=true`) and the specs that cover `spec` criteria, runs any `manual` criteria's
stated commands, and writes `.claude/acceptance-scorecards/scorecard-${FEATURE_NAME}-*.md` with a
verdict: `PASS | PASS WITH SHOULD GAPS | FAIL`.

### Step A2: Close gaps (max 2 cycles)

**PASS** → Step A3.

**Otherwise**, work the scorecard's **Gaps & Recommended Actions**, Must rows first:
- **UNVERIFIED — coverage gap (browser)**: add a scenario to the QA plan
  (`docs/qa-plans/${FEATURE_NAME}-*.md`) with `**Verifies:** AC-n` whose expected results assert the
  criterion's *Then* clause literally, then run `/execute-qa` on **that scenario only**; or add a
  system spec example whose description contains `(AC-n)` and get it passing.
- **UNVERIFIED — coverage gap (spec)**: write the spec that exercises the criterion (unit / service /
  controller / component / policy) and get it passing.
- **FAILED**: fix the app bug **and write a regression spec** (same rule as C2), then re-execute the
  covering scenario / spec. A fix spanning several files → worker per `_shared.md`.
- **UNVERIFIED — manual**: run the stated command against the dev DB and confirm the output; if the
  criterion names no runnable command, it stays UNVERIFIED (note it — a PRD defect to surface).
- Commit each cycle's changes:

```bash
git add <specific files>
git diff --cached --quiet || git commit -m "$(cat <<'MSG'
fix: close acceptance-criteria gaps for ${FEATURE_NAME}

Addresses non-VERIFIED rows of the /verify-acceptance scorecard.

Co-Authored-By: [your standard Claude Code co-author line]
MSG
)"
```

Then re-run `/verify-acceptance`. **Maximum 2 gap-closing cycles.** Never satisfy a criterion by
weakening a spec, deleting a scenario, or editing the contract file or the PRD — the contract was
reviewed and frozen before planning. A **FAILED guard** AC means an extra was built: remove the
offending code (and its specs) rather than arguing the guard.

### Step A3: Close the browser; leave the server running

Close the browser session (`mcp__playwright__browser_close`, or the selenium session if that was
used). Do NOT stop the dev server — it is the review server handed to the developer at the end.

Delete any screenshots created during verification (`.playwright-mcp/` or elsewhere) — **EXCEPT
`tmp/pr-screenshots/`**, which C4 publishes with the PR.

## CHECKPOINT

Update the state file's `## Acceptance` block with the **final** verdict, the scorecard path,
Must/Should/guard counts, one line per non-VERIFIED AC (ID, priority, status, reason), the gap-fix
commit hashes; Phase Log C3 checked. **C4 runs regardless of verdict** — simplification, CI, and
screenshots still happen; the verdict is applied at C4's last step.

## RETURN

```
C3 DONE
ACCEPTANCE: <PASS | PASS WITH SHOULD GAPS | FAIL> — Must <x>/<y> • Should <x>/<y> • Guards <x>/<y>
SCORECARD: <path>
NOT VERIFIED: <none | AC-n (Must|Should, status) — reason, one per line>
COMMITS: <hashes or none>
```
