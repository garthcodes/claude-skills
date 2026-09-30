# B3 — Security review & requirements trace

## Inputs

- Bootstrap per `_shared.md`. From the state file: commit hashes, SKIPPED tickets, deferred fixes.

**Parallel:** you are the **follower** of the B2 ‖ B3 pair (`_shared.md` → Parallel pairs). B2 is
reviewing and fixing the same branch right now. Order of work:
1. **Read-only, immediately:** Step 1's `/security-review` and Step 2's first `/trace-requirements`
   run — collect findings and the trace report; write nothing tracked, commit nothing.
2. **Wait for B2's Phase Log box** (the poll in `_shared.md`).
3. Re-check every security finding and trace gap against the new HEAD (B2 may have fixed or moved
   it). If B2 changed any `app/` file and your first trace was FULLY TRACED, re-run
   `/trace-requirements` once now.
4. Then do the fix cycles (Step 1 fixes, Step 2 worker), Step 3 (contract diff check — always after
   B2, since B2's fixes change the diff), commits, and the state file.

## Steps

### Step 1: Security review (HIPAA)

Run `/security-review` against the branch changes (`feature/${FEATURE_NAME}` vs. `main`):

```
/security-review
```

`/security-review` reads the git state of the session's launch checkout (`${MAIN_DIR}`, usually a
clean `main`), not the worktree — invoked bare it reviews an empty diff. Pass the scope explicitly:
`/security-review the diff of ${WORKTREE_PATH} — run git -C ${WORKTREE_PATH} diff origin/main...HEAD`.
If its report still shows no changed files, review `git -C ${WORKTREE_PATH} diff origin/main...HEAD`
yourself against the checklist below and say so in the RETURN block.

Brakeman (in `bin/ci`) does static Rails checks, but this is a HIPAA app — pay particular attention
to findings Brakeman won't catch:
- PHI (names, DOBs, diagnoses, clinical content) passed into `Honeybadger.notify` context hashes or
  written to log lines (CLAUDE.md legislates both)
- Controller actions missing Pundit `authorize`/policy-scope calls
- Mass-assignment gaps in strong params on new endpoints

Handle findings with **one fix cycle**:
1. Fix every Critical and High finding (directly — these are small, judgment-heavy edits; use a
   worker only if a fix spans several files).
2. Medium/Low: fix the quick ones; record the rest under "Known Issues (Security)" with a one-line
   justification each.
3. Run the specs for touched files, then commit (skip if no changes):

```bash
git add <specific files>
git diff --cached --quiet || git commit -m "$(cat <<'MSG'
fix: address security review findings for ${FEATURE_NAME}

Co-Authored-By: [your standard Claude Code co-author line]
MSG
)"
```

A Critical/High finding that cannot be fixed in one cycle → "Known Issues (Security)" marked
**UNRESOLVED — blocker for merge**. Do NOT ask the user; proceed.

### Step 2: Requirements traceability gate

The plan reviews critiqued the *plan* and `/full-review` critiqued *code quality* — this gate
verifies the code implements the *PRD*. A dropped requirement survives both and is expensive to
discover in QA.

```
/trace-requirements
```

It maps every FR and Definition of Done item to code/spec evidence in `git diff main...HEAD`,
statically traces every AC row, checks every `guard` AC against the diff, and saves
`.claude/requirement-traces/trace-*.md` with a verdict: `FULLY TRACED | GAPS FOUND | SIGNIFICANT GAPS`.

**FULLY TRACED** → Step 3.

**GAPS FOUND / SIGNIFICANT GAPS** → exactly ONE fix cycle:
1. Launch a worker (recipe in `_shared.md`, non-`/code` variant) with the report's **Gaps &
   Recommended Actions** section pasted verbatim — every MISSING and PARTIAL item, written as
   executable tickets. Same constraints as B1: NO system tests, NO feature specs; unit/controller/
   component/policy specs for each fix.
2. If the report flags **Out of Scope violations** or a **violated guard AC**, remove that code
   yourself — the PRD's "Do NOT Build" list and the contract's guard rows are hard boundaries.
   Merely-untraceable changes (review-fix hardening etc.) need no action; Step 3 re-examines them.
3. Verify the worker's return, run the touched specs, commit:

```bash
git add <specific files>
git commit -m "$(cat <<'MSG'
feat: close requirements-trace gaps for ${FEATURE_NAME}

Implements PRD requirements found MISSING/PARTIAL by /trace-requirements.

Co-Authored-By: [your standard Claude Code co-author line]
MSG
)"
```

4. Re-run `/trace-requirements` once to confirm.

Whatever is still not IMPLEMENTED goes under "Known Issues (Requirements Trace)" — one line per
FR/DoD item with status and why. No second fix cycle, no asking.

### Step 3: Contract diff check (Step 7.6 — one pass, static, no fix cycle)

`/trace-requirements` asks "is every requirement in the code?"; this asks the opposite: **"is
everything in the code required?"**

1. `git diff main...HEAD --stat` and `--name-only`. List every *user-visible or structural surface*
   the branch adds: routes, models and migrations/columns, navigation or menu entries,
   controllers/actions, mailer actions, jobs, Stimulus controllers, new ViewComponents, rake tasks,
   settings/flags.
2. For each, name the `AC-n` (or `FR-n`) that requires it. Specs, factories, and pure refactors of
   touched code need no justification.
3. Anything with no AC/FR is an extra. Remove it if self-contained (and its specs), commit as
   `refactor: remove out-of-contract <thing> from ${FEATURE_NAME}`; if removing it would break
   contract behavior, keep it and record it under `## Scope Drift` with a one-line reason.
4. Anything that contradicts a `guard` AC → remove, no exceptions.
5. **Copy surfaces** (CLAUDE.md "UI Copy Discipline"). List every non-label string the branch adds
   to UI files, added lines only:

   ```bash
   git diff -U0 main...HEAD -- 'app/views/**' 'app/components/**' \
     | grep -E '^(\+\+\+ b/|\+[^+])' \
     | grep -E '^\+\+\+ b/|help_text:|hint:|TooltipComponent|HelpBubbleComponent|AlertBoxComponent\.new\((\s*\)|.*variant: :info|\s*title:)|(PageHeaderComponent|FormSectionComponent)\.new\(.*description:|^\+\s+description: "|^\+\s*<p[ >][^%]*[A-Za-z]{4}' \
     | awk '/^\+\+\+ b\//{f=substr($0,7); next} {print f ": " $0}'
   # second pass — a sentence on its own line in a template
   git diff -U0 main...HEAD -- 'app/views/**/*.html.erb' 'app/components/**/*.html.erb' \
     | grep -E '^\+\s+[A-Z][a-z]+ [a-z]+ [a-z]+'
   ```

   Every hit is one of: (i) a label / heading / column header / button verb / value / validation
   error → fine; (ii) listed in the plan's `### Copy` (= the tickets' `Copy (allowed)` lines) →
   keep; (iii) an always-allowed category (AC-named text, consent / legal / billing-disclosure /
   clinical-compliance, client-portal `reassurance`, error messaging per
   `docs/ERROR_MESSAGING_GUIDE.md`) → keep; (iv) anything else → **remove it** (and any spec
   asserting it), commit as `refactor: remove unrequested UI copy from ${FEATURE_NAME}`. Known
   false positives — mark them and move on: `description:` as a component initializer parameter or
   `description: some_variable`; `AlertBoxComponent` with `variant: :danger | :warning | :success`;
   `hint:` / `help_text:` on an *existing* component whose call site this branch didn't add. Do not
   touch copy on lines the branch did not add.

Write the surface → AC table into the state file under `## Scope Drift` (kept items only need
listing; removed items get the commit hash), followed by the copy-surface hit → disposition table.

## CHECKPOINT

Update the state file: Phase Log B3 checked; Artifacts with the trace report path; Results with
security findings by severity (fixed vs. recorded, commit hash), trace verdict (final) with FR
counts (implemented/partial/missing, Must vs. Should), DoD and static AC trace counts (incl. guard
checks), gaps fixed (FR IDs + commit hash) and remaining; `## Scope Drift` tables; Known Issues.

## RETURN

```
B3 DONE
COMMITS: <hashes or none>
SECURITY: Critical <n> High <n> fixed; recorded <n>; UNRESOLVED: <none | list>
TRACE: <verdict> — FRs <x>/<y> (Must <x>/<y>), DoD <x>/<y>, guards <x>/<y> clean; gaps remaining: <none | list>
SCOPE DRIFT: <n> surfaces kept with reason, <n> removed, <n> copy strings removed
```
