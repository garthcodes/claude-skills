---
description: Sync docs/user_docs with everything deployed to production since the last sync — analyze the deployed diff, CRUD the user-doc corpus, and open a PR
argument-hint: "[optional: baseline override — a SHA or ref to diff from instead of the recorded state]"
---

# User Docs Sync

You are tasked with bringing the user-doc corpus (`docs/user_docs/`) up to date with what is actually **deployed to production**, then opening a PR with the changes.

The corpus is consumed by two audiences: end users reading it directly, and the **dashboard help assistant**, which answers staff questions *exclusively* from these files. A stale doc makes the assistant confidently wrong; a missing doc makes it say "I don't know." This skill closes that gap on a recurring basis.

**Hard scope constraint: the only files you may create, update, or delete are inside `docs/user_docs/`** (docs, the index `0_USER_DOCS_INDEX.md`, and the state file described below). Never touch application code, other docs, or config — if you find an app bug or doc-worthy code problem while reading, report it in your summary instead of fixing it.

## Input

$ARGUMENTS

No argument is required. An optional argument overrides the baseline (step 2) — e.g. a SHA or ref to diff from, useful for a first run or a re-run after a bad sync.

## Phase 1: Determine the Deployment Window

### Step 1: Find the currently deployed production SHA

Production exposes its deployed revision in a public meta tag (baked by `bin/deploy` as `GIT_COMMIT`). Read it with a plain GET — **never** use `fly` commands for this (prod-guarded, and unnecessary):

```bash
curl -s --max-time 20 "https://<app-host>/users/sign_in" \
  | grep -o '<meta name="honeybadger-revision" content="[a-f0-9]*"' \
  | grep -o '[a-f0-9]\{40\}'
```

Call this `DEPLOYED_SHA`. Then:

```bash
git fetch origin main
git merge-base --is-ancestor $DEPLOYED_SHA origin/main && echo ok
```

- If curl fails or returns no 40-char SHA: **stop** and report — do not guess a revision.
- If the SHA is not an ancestor of `origin/main` (rollback, hotfix from another branch): **stop** and report what you found. Do not sync against an unverified revision.

### Step 2: Find the baseline (last synced SHA)

The state file is `docs/user_docs/.docs-sync-state.json`:

```json
{
  "last_synced_sha": "<40-char sha>",
  "last_synced_at": "<ISO8601>",
  "synced_by_pr": "<PR url of the previous sync>"
}
```

- If the user passed a baseline argument, use that (resolve it to a SHA).
- Else if the state file exists, use its `last_synced_sha` as `BASELINE_SHA`.
- Else (first run): use the last commit that touched the corpus — `git log -1 --format=%H origin/main -- docs/user_docs/` — and say clearly in your summary and the PR body that this first-run baseline is an approximation.

If `BASELINE_SHA == DEPLOYED_SHA`, there is nothing to sync: report that and **stop** (no branch, no PR).

### Step 3: Enumerate the deployments' changes

Everything deployed to production ships from `main` (enforced by `bin/deploy` preflight), so the deployed delta is exactly the commit range on main:

```bash
# Every deployed unit of change: one line per PR merge AND per commit pushed straight to main
git log --first-parent --oneline ${BASELINE_SHA}..${DEPLOYED_SHA} origin/main

# The full file-level change surface
git diff --stat ${BASELINE_SHA}..${DEPLOYED_SHA} -- . ':!spec' ':!docs'
```

The `--first-parent` walk yields two kinds of entries, and **both must be triaged — direct pushes to main are just as deployed as merged PRs**:

- **Merge commits** (PRs) — inspect with `git show <sha> --first-parent`
- **Non-merge commits** (changes pushed straight to main, often small fixes) — inspect with `git show <sha>`

Small direct-to-main commits are easy to dismiss by their size; a one-line change (a relabeled button, a flipped policy check, a validation tweak) can still change user-visible behavior. Triage them by diff like everything else.

As a completeness check before Phase 2: every file in the `git diff --stat` output must be attributable to at least one entry you triaged. If a changed file belongs to no unit you looked at, you missed a commit — go back.

### Code-only rule (applies to every phase from here on)

**All decisions — what is relevant, what to write, what to delete — are made from code alone.** Commit messages, PR titles and bodies, PRDs, planning documents, READMEs, `docs/APP_FEATURES.md`, code comments describing intent, and the existing user docs themselves are **never** inputs to those decisions. Do not run `gh pr view` to read PR descriptions; do not open PRD or planning files. The commit list from `git log` is used only to enumerate the window and to cite *which* merge or direct commit caused a doc change in the PR body — never to determine what changed. What changed is determined exclusively by reading the diffs and the code at `DEPLOYED_SHA`. Prose about the code describes intent; only the code is the behavior.

## Phase 2: Triage for User-Facing Relevance

Classify every unit in the window — PR merges and direct-to-main commits alike — as **relevant** or **not relevant** to the corpus **by reading its diff** (`git show <sha> --first-parent` for merges, `git show <sha>` for direct commits) — never from its commit message or PR description. Relevant means a user-visible behavior changed:

- New/changed/removed screens, buttons, form fields, labels, navigation (`app/views`, `app/components`, `app/javascript`)
- New/changed routes or controller actions users can reach (`config/routes.rb`, `app/controllers`)
- Permission changes — who can do what (`app/policies`)
- Status/workflow changes, new enums or transitions (`app/models`, `app/services`)
- Emails or texts users receive (`app/mailers`, `TextMessageService`)
- Client-portal behavior changes
- Settings/configuration users can change

Not relevant (skip, but list in the PR body under "Reviewed, no doc impact"): refactors with no behavior change, test-only changes, CI/tooling, dependency bumps, performance work, logging/monitoring, admin-internal (Avo/platform) changes unless the corpus documents them, migration-only data fixes.

When unsure whether a change is user-visible, read more of the surrounding code — the answer never comes from the commit message, PR description, or any document.

## Phase 3: Ground Every Edit in Current Code

**Follow the grounding rules and writing conventions of the `user-docs` skill** — read `.claude/skills/user-docs/SKILL.md` before writing (it is the single source of truth for the doc template, frontmatter, role names, permission-table rules, and writing guidelines). The non-negotiables that apply here:

- **Code at `DEPLOYED_SHA` is the only source of truth.** Per the code-only rule, commit messages, PR bodies, PRDs, and other documentation contribute nothing to what you write. Before editing a doc, read the current code (models, controllers, views, policies, services) for that feature and verify the behavior as it exists now. Note: your working tree is at origin/main which may be *ahead* of `DEPLOYED_SHA` — if they differ, verify behavior with `git show ${DEPLOYED_SHA}:<path>` for the files you rely on, and do not document not-yet-deployed behavior.
- **Never guess.** If you cannot confirm a behavior in code, omit it and list it in your summary. Omission is safe; invention is not.
- **Verify reachability** — a behavior belongs in the docs only if it's routed, authorized, AND rendered in the UI for the roles you name.

## Phase 4: CRUD the Corpus

For each relevant change, decide the doc operation:

1. **Update** — the common case. Edit the affected section(s) of the existing doc(s): steps, field lists, permission tables, statuses, Common Questions, TLDR if the feature's essence changed. Keep edits surgical; don't rewrite healthy sections.
2. **Create** — a genuinely new feature with no home in any existing doc. Write a new `docs/user_docs/{feature-name}.md` following the full `user-docs` template (frontmatter, TLDR, permissions table, Common Questions), and add/repoint its row in `0_USER_DOCS_INDEX.md`. If the feature is small and belongs to an existing doc's workflow, prefer adding a section over creating a file.
3. **Delete** — a feature was removed from the app. Delete its doc (or section), remove/repoint its index row, and remove now-dangling cross-references from other docs (search the corpus for the filename).
4. **Index** — whenever docs are created, deleted, or regrouped, update `0_USER_DOCS_INDEX.md` rows and its Summary counts.

Also fix **collateral staleness you actually notice**: if grounding a change reveals an adjacent sentence in the same section that no longer matches the code, correct it. Do not launch a general audit of untouched docs — this skill syncs the delta.

### Step: Update the state file

Write `docs/user_docs/.docs-sync-state.json` with `last_synced_sha: DEPLOYED_SHA` and the current timestamp. After `gh pr create` returns the PR URL (Phase 5), set `synced_by_pr` to it, amend the commit, and `git push --force-with-lease`.

**The state file must be updated in every sync PR** — it is how the next run knows where this one stopped. If the window contained changes but *none* were user-facing, still create the PR with just the state-file bump so the next run doesn't re-analyze the same window; say so in the PR body.

## Phase 5: Create the PR

Work on a fresh branch; never commit to `main`:

```bash
git checkout -b docs/user-docs-sync-$(date +%Y-%m-%d) origin/main
```

If the current checkout is dirty or mid-work, do the edits in a temporary worktree instead (`git worktree add`) so the user's tree is untouched.

- Verify with `git status` that **only** `docs/user_docs/` paths changed. If anything else is modified, revert it before committing.
- Commit with a message like `docs: sync user docs with production deploys (<short-baseline>..<short-deployed>)`, ending with the standard co-author trailer.
- Push and open the PR with `gh pr create`. PR body must include:
  - The deployment window: `BASELINE_SHA` → `DEPLOYED_SHA` (short SHAs + dates)
  - **Doc changes** — each created/updated/deleted doc with a one-line reason tied to the PR/commit that caused it
  - **Reviewed, no doc impact** — every unit in the window (PR or direct commit) that needed no doc change, one line each
  - **Omitted / needs human verification** — anything you saw in the diff but could not confirm in code

## Output

When complete, report:
1. The deployment window analyzed and how many PRs/commits it contained
2. The PR URL
3. Docs created / updated / deleted (with the driving change for each)
4. Changes reviewed and skipped as not user-facing
5. Anything omitted because it could not be verified in code
