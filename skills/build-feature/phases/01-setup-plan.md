# A1 — Setup & plan

## Inputs

- You were launched WITHOUT `isolation`: you create the pipeline worktree yourself, under
  `${PRIMARY_DIR}/.claude/worktrees/` — never inside `MAIN_DIR` when that is a sibling worktree
  (a nested worktree would be deleted along with it, and `bin/worktree-port` can't see it).
- Identity values from the coordinator prompt (`FEATURE_NAME`, `MAIN_DIR`, `PRIMARY_DIR`, `PRD`,
  `AC_PATH`, `AC_REVIEW`, `IMPLEMENT_MODEL`). The Bootstrap in `_shared.md` does not apply to you
  (there is no state file yet) — you create it.

## Steps

### Step 1: Worktree setup

Create the worktree on `feature/${FEATURE_NAME}`, based on the launching checkout's `HEAD`:

```bash
WORKTREE_PATH="${PRIMARY_DIR}/.claude/worktrees/${FEATURE_NAME}"
BASE="$(git -C "${MAIN_DIR}" rev-parse HEAD)"
git -C "${PRIMARY_DIR}" worktree prune
git -C "${PRIMARY_DIR}" worktree add "${WORKTREE_PATH}" -b "feature/${FEATURE_NAME}" "${BASE}"
cd "${WORKTREE_PATH}"   # run EVERY later command from here
```

If `worktree add` fails because the path or branch already exists: when there is no
`${WORKTREE_PATH}/.claude/pipeline-state.md` and `git log ${BASE}..feature/${FEATURE_NAME}` is
empty, it is a leftover from an A1 that died — `git -C "${PRIMARY_DIR}" worktree remove --force
"${WORKTREE_PATH}"` (if registered), drop its `<app>_*<suffix>` databases if its `.env` had a
`DATABASE_SUFFIX`, `git -C "${PRIMARY_DIR}" branch -D "feature/${FEATURE_NAME}"`, and retry once.
Otherwise the branch holds real work — stop and RETURN that (never delete it).

```bash
# Copy gitignored files needed for development — always from the PRIMARY checkout
# (a /prd-worktree launching checkout has neither)
# (skip the certs line if your dev setup doesn't use local HTTPS)
cp -r "${PRIMARY_DIR}/config/certs" ./config/
cp "${PRIMARY_DIR}/.env" ./.env
sed -i '' '/^DATABASE_SUFFIX=/d;/^PORT=/d' .env   # never inherit another checkout's
```

**Isolate this pipeline's databases.** The worktree must NOT share `<app>_development` / `<app>_test`
with the main repo. `config/database.yml` appends `ENV["DATABASE_SUFFIX"]` to both database names;
setting it in the worktree's `.env` means every command run here picks it up via dotenv.

```bash
DB_SUFFIX="_$(echo "${FEATURE_NAME}" | tr '-' '_' | tr -cd 'a-z0-9_' | cut -c1-30)"
# printf's leading newline matters: .env may not end in one, and a glued-on line is ignored
printf '\nDATABASE_SUFFIX=%s\n' "$DB_SUFFIX" >> .env

# Fresh dev + test databases, then the mini seed (~10 s: every named QA user, ~50 clients,
# one claim per status, portal test client). Ends with "Seeds Complete (mini, Ns)".
dropdb --if-exists "<app>_development${DB_SUFFIX}"; dropdb --if-exists "<app>_test${DB_SUFFIX}"
bin/rails db:create 2>&1 | tail -2
bin/rails db:schema:load 2>&1 | tail -5     # loads both <app>_development${DB_SUFFIX} and <app>_test${DB_SUFFIX}
bin/rails db:seed:mini 2>&1 | tail -3
```

Never point the worktree at the shared database, and never use `db:prepare` (it runs the full seed).

**Assign this worktree's dev server port** (each pipeline worktree serves on its own port):

```bash
WORKTREE_PORT="$(bin/worktree-port --assign .env)"   # lowest free port in 3010–3099
echo "WORKTREE_PORT=${WORKTREE_PORT}"
```

If the script exits 1 (range exhausted) → return with its message (Error Handling: Port range exhausted).

Verify setup:
```bash
git branch --show-current       # feature/${FEATURE_NAME}
ls config/certs/ .env
grep -E '^(DATABASE_SUFFIX|PORT)=' .env
bin/rails runner 'puts ActiveRecord::Base.connection_db_config.database'   # <app>_development${DB_SUFFIX}
```

If the printed database name has no suffix, STOP and fix `.env` before proceeding — running against
the shared dev database is not acceptable.

### Step 2: Commit the PRD and the contract

Copy both from `MAIN_DIR` if they are not already in this checkout (they usually aren't committed to
`main` yet), then commit so the PR carries permanent traceability from code back to requirements and
to the contract it was verified against (C4's cleanup deliberately preserves `.claude/prds/` and
`.claude/acceptance-criteria/<slug>.md`):

```bash
mkdir -p .claude/prds .claude/acceptance-criteria
[ -f "${PRD}" ]     || cp "${MAIN_DIR}/${PRD}" "${PRD}"
[ -f "${AC_PATH}" ] || cp "${MAIN_DIR}/${AC_PATH}" "${AC_PATH}"
grep -q 'Review status: PASS' "${AC_PATH}" || echo "WARNING: contract is not PASS-stamped"
git add "${PRD}" "${AC_PATH}"
git diff --cached --quiet || git commit -m "$(cat <<'MSG'
docs: add PRD and acceptance-criteria contract for ${FEATURE_NAME}

Co-Authored-By: [your standard Claude Code co-author line]
MSG
)"
```

If the contract is not PASS-stamped, stop and return that (the coordinator was supposed to gate on it).

### Step 3: Create the implementation plan

Invoke `/plan` with the **contract** path (it follows the contract's `*PRD:*` link and reads both):

```
/plan .claude/acceptance-criteria/${FEATURE_NAME}.md — system tests are EXCLUDED (QA is done via Playwright). The contract is what the PR is gated on: every AC-n row must map to at least one plan step and appear by ID in the plan's Success Criteria; every plan step must cite the AC(s) it serves or be marked `infra`; the guard rows must become an explicit "Not Building" list. Build exactly what the PRD and contract say — nothing more, nothing less. UI copy is labels, values, headings, button verbs, and validation errors only — every other string goes in `### Copy` with its AC or a one-line reason (CLAUDE.md "UI Copy Discipline").
```

The plan is saved to `.claude/implementation-plan-*.md`.

**Verify**:
- The plan MUST NOT include any system tests (`/plan` honors the exclusion, but check). If system
  tests slipped in, remove those sections.
- **Contract coverage**: every `AC-n` ID from the contract appears in the plan's Success Criteria
  with a plan step; the plan has a "Not Building" list naming every `guard` AC. Any AC with no step →
  add the step now. Any step citing no AC and not marked `infra` → remove it (the earliest and
  cheapest place to stop an extra).

## CHECKPOINT

Create `.claude/pipeline-state.md` with the full schema from `_shared.md`: Identity (all values,
`WORKTREE_PATH` from `pwd`, `PRIMARY_DIR`, `WORKTREE_PORT` from `.env`, `DB_SUFFIX`, `IMPLEMENT_MODEL`), Phase Log
with A1 checked, Artifacts with the exact implementation-plan path, Results with the contract
coverage counts (ACs covered / total, guards in "Not Building").

## RETURN

```
A1 DONE
WORKTREE_PATH: <absolute path>
BRANCH: feature/<slug>   PORT: <n>   DB_SUFFIX: <suffix>
PLAN: <path>
CONTRACT COVERAGE: <x>/<y> ACs have a step; <g> guards in Not Building
APPROACH: <3–5 lines>
ISSUES: <none | one line each>
```
