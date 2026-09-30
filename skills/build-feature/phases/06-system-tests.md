# C1 — System tests

## Inputs

- Bootstrap per `_shared.md`. From the state file: Known Issues so far (a documented gap must not
  become a "failing" test you thrash on).

**Parallel:** you are the **lead** of the C1 ‖ C2 pair (`_shared.md` → Parallel pairs). C2 is
running browser QA against the dev server right now and holds its bug fixes and commits until you
check your Phase Log box — check it as your very last action. You use the test DB, C2 the dev DB;
commit only your own paths.

## Steps

Now that the implementation is reviewed and hardened, add browser-layer regression coverage. System
tests were deliberately excluded from `/plan`, `/tickets`, and `/code` — **this phase owns them**,
planned against the final code rather than the pre-review design.

### Step S1: Plan the system tests

Invoke `/plan-system-tests` with no argument (branch mode — it analyzes `git diff main...HEAD` and
reads the contract: `browser` / `browser+spec` Must rows are the journeys, `guard` rows become
negative assertions, and every scenario carries a `Verifies:` line):

```
/plan-system-tests
```

The scenario plan is saved to `tmp/test-plans/<feature-slug>-YYYYMMDD.md`.

### Step S2: Implement the tests

```
/system-test-expert tmp/test-plans/<feature-slug>-*.md
```

It implements every SC/EC scenario under `spec/system/`, runs each spec file as it goes, and
stability-checks the new suite 3 consecutive times. It reports any scenario it could not get passing
rather than thrashing on it. Run `bin/rails tailwindcss:build` first if the worktree has never built
CSS (system specs need it).

### Step S2b: Run the existing system specs this branch is expected to break

Never run the whole `spec/system` suite here (`bin/ci` in C4 does). Run only the existing system spec
files named in the state file's Known Issues as expected to go red, plus any existing
`spec/system/**` file that exercises a controller, component, or view this branch changed
(`git diff --name-only origin/main...HEAD`). Failures join Step S3. Repair fixtures to the new rules;
where an assertion encodes behavior the contract deliberately changed, update it to the AC and cite
the AC in a comment — never weaken an assertion that guards unchanged behavior.

### Step S3: Fix failures and flakes

If `system-test-expert` reports failing or flaky specs:

```
/fix-system-test <failing spec paths>
```

(pipeline mode — it reads the test plan's handoff notes, budgets 3 fix attempts per test, and
verifies with `CI=true` so rspec-retry can't mask flakiness). **Maximum 2 rounds.** Still failing:
- Mark that spec `pending("<reason> — see PR Known Issues")` so the suite (and later `bin/ci`) stays
  green while the gap remains visible
- Record it under "Known Issues (System Tests)" with the failure output and root-cause hypothesis
- If `/fix-system-test` determined the **application code** is at fault and fixed it, keep that fix
  and note it — an app bug caught here is the phase working as intended

### Step S4: Commit

```bash
git add spec/system/... <app files fixed>      # be specific
git commit -m "$(cat <<'MSG'
test: add system tests for ${FEATURE_NAME}

Browser-layer coverage implemented from the /plan-system-tests scenario plan.

Co-Authored-By: [your standard Claude Code co-author line]
MSG
)"
```

## CHECKPOINT

Update the state file: Phase Log C1 checked; Artifacts with the test plan path and the system-tests
commit hash; Results with scenarios implemented (spec paths), pass/flaky/pending counts, app bugs
found and fixed; Known Issues (System Tests).

## RETURN

```
C1 DONE
COMMIT: <hash>
SYSTEM TESTS: <n> scenarios in <k> files — passing <n>, pending <n>
APP BUGS FIXED: <none | list>
```
