---
name: build-feature-remote
description: Kick off /build-feature as a one-shot cloud routine on Opus, given a PRD path — for builds you don't want to babysit locally
argument-hint: <path-to-prd.md>
---

# Build Feature Remote: Run /build-feature in the Cloud

Creates a one-time cloud routine (via the `RemoteTrigger` API) that runs the `/build-feature`
pipeline against a PRD, entirely in Anthropic's cloud infrastructure on the Opus model. This
skill only *launches* the remote run — it does not execute the pipeline itself and does not
block waiting for it to finish.

## Step 1: Resolve the PRD

Read the PRD at `${1}`.

If `${1}` is empty or not provided, fall back to the most recent PRD:
```bash
ls -t .claude/prds/*.md 2>/dev/null | head -1
```
If no PRD is found, tell the user and stop (suggest `/prd`).

From the PRD extract:
- **Feature slug** — declared in the header (`*Feature slug: `feature-slug`*`) if present. Use
  it verbatim as `FEATURE_NAME`. Otherwise kebab-case the filename.
- **Feature name / executive summary** — for the routine name and remote prompt context.

## Step 2: Make sure the PRD exists on `origin/main`

The cloud routine clones your repository (`https://github.com/<owner>/<repo>`) fresh — it will not see any local
uncommitted or unpushed files. Check the PRD's status:

```bash
git status --porcelain -- "${PRD_PATH}"
git log origin/main..HEAD -- "${PRD_PATH}"
```

- If the file is untracked, has uncommitted changes, or has commits that haven't reached
  `origin`, put it on its own docs branch and push that branch — **never push to `main`**:
  ```bash
  git switch -c "docs/prd-${FEATURE_NAME}"        # or `git switch` to it if it already exists
  git add "${PRD_PATH}"
  git commit -m "docs: add PRD for cloud build (${FEATURE_NAME})"
  git push -u origin "docs/prd-${FEATURE_NAME}"
  git switch -                                     # back to where the user was
  ```
  The cloud run branches its feature branch off `docs/prd-${FEATURE_NAME}`, so the PRD
  commit ships inside the feature PR and gets reviewed with it.
- If the PRD is already on `origin/main`, push nothing and tell the cloud run to branch off `main`.
- If the push is rejected, stop and tell the user rather than forcing anything (**never force-push**).
- Tell the user what you committed/pushed, if anything.

**Acceptance-criteria contract:** check whether `.claude/acceptance-criteria/${FEATURE_NAME}.md`
exists locally. If it does, run the same status check on it and commit/push it alongside the
PRD on the same docs branch (same docs-only commit is fine: `docs: add PRD + acceptance criteria for cloud build
(${FEATURE_NAME})`) — the remote `/build-feature` gates on this file, so a reviewed contract
left unpushed would be silently regenerated unreviewed. If it does not exist, note to the user
that the remote `/build-feature` will generate it (`/acceptance-criteria`) and review it
(`/review-acceptance-criteria`) itself before planning.

## Step 3: Compose the remote prompt

The cloud agent starts with zero conversation context, so the prompt must be fully
self-contained:

```
Run the /build-feature skill against the PRD at ${PRD_PATH}.
Invoke it as the slash command: /build-feature ${PRD_PATH}

Context (read before starting): this is the application's Rails 8 codebase.
Read CLAUDE.md and the full PRD at ${PRD_PATH} first, then follow /build-feature's own
pipeline and autonomous-execution policy end to end.

You are running unattended in a headless cloud environment:
- No local machine access.
- No Playwright/browser MCP connector is available here. If a pipeline phase needs
  browser-based verification (e.g. /execute-qa, /system-test-expert, /fix-system-test),
  skip only that phase, clearly note in the PR description that browser verification was
  skipped, and continue rather than aborting the pipeline. Fall back to the non-browser
  test suite (bin/ci, rspec) wherever possible instead.
- Start from the PRD's branch: `git fetch origin docs/prd-${FEATURE_NAME} && git switch -c
  feature/${FEATURE_NAME} origin/docs/prd-${FEATURE_NAME}` (or off origin/main if Step 2
  pushed nothing). Never commit or push directly to main.
- Carry the pipeline all the way through to opening a pull request against main on
  github.com/<owner>/<repo>. Nobody is watching, so don't wait for confirmation: where the
  pipeline would normally ask, take the recommended option and record it, and record
  unresolved issues in the PR's Known Issues section per /build-feature's own
  error-handling policy. The run's guards still apply: the PR is the only output, nothing
  is merged, and nothing touches production.

At the end, report what was built, what passed, what was skipped, and the PR URL.
```

## Step 4: Create the one-time cloud routine

Load the tool if needed: `ToolSearch select:RemoteTrigger`.

Get the current time (do not guess):
```bash
date -u +%Y-%m-%dT%H:%M:%SZ
```
Set `run_once_at` to ~2 minutes after that, as an RFC3339 UTC timestamp.

Generate a fresh lowercase v4 UUID for `events[].data.uuid`.

Call `RemoteTrigger`:
```json
{
  "action": "create",
  "body": {
    "name": "build-feature: ${FEATURE_NAME}",
    "run_once_at": "<computed timestamp>",
    "job_config": {
      "ccr": {
        "environment_id": "<your-environment-id>",
        "session_context": {
          "model": "<model-id>",
          "sources": [{"git_repository": {"url": "https://github.com/<owner>/<repo>"}}],
          "allowed_tools": ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "Skill", "Task", "Agent", "Workflow", "WebFetch"]
        },
        "events": [{"data": {
          "uuid": "<fresh uuid>",
          "session_id": "",
          "type": "user",
          "parent_tool_use_id": null,
          "message": {"content": "<composed prompt from Step 3>", "role": "user"}
        }}]
      }
    }
  }
}
```

`<your-environment-id>` is the id of the cloud environment you set up for this repo (list
yours with `RemoteTrigger` `action: "list"` and ask the user if there is more than one).
`<model-id>` is the most capable model available to you; a long unattended pipeline is
where it pays for itself.

`Task`, `Agent`, and `Workflow` are included in `allowed_tools` because `/build-feature`
launches its own sub-agents internally (nine sequential phase agents sharing one worktree — the
first is worktree-isolated, the rest work in that same worktree — plus Sonnet implementation workers
launched by the implement/review/trace agents).

## Step 5: Report back

Relay the created routine's ID and link: `https://claude.ai/code/routines/{id}`. Tell the user:
- It will fire in ~2 minutes
- No browser-based QA/system-test verification will run remotely (no Playwright MCP
  connected) — those phases will be skipped and flagged in the eventual PR
- They can check progress at the link above, or ask to run `RemoteTrigger get` on the routine

Do not poll or wait for it to complete — this skill's job ends once the routine is created.
