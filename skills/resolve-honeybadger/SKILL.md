---
name: resolve-honeybadger
description: Mark Honeybadger faults resolved once the PRs that fixed them are merged AND deployed to production, and reopen the issue (label fix-didnt-work) when a fault fires again after its fix went live. Scans recently merged PRs and closed GitHub issues (default yesterday + today) for the fault ids they fix, checks each fix is in the live production revision, checks in Honeybadger that the fault is still unresolved and hasn't fired since the fix merged, then resolves them through the Honeybadger API with the token from the macOS Keychain (macOS only). Use whenever the user says "/resolve-honeybadger", "mark the honeybadger errors resolved", "resolve the HB faults we fixed today", "clean up Honeybadger after the merges", "close out the fixed faults", or asks which Honeybadger faults can be resolved now — even if they don't name PRs or issues.
argument-hint: [days back | YYYY-MM-DD]
---

# Resolve Fixed Honeybadger Faults

**Setup (once):** `HB_PROJECT_ID` = your production Honeybadger project id; `APP_URL` = your production app's https URL (its public sign-in page must render `<meta name="honeybadger-revision" content="<git sha>">`); optionally `HB_KEYCHAIN_SERVICE` (default `honeybadger-token`). The scripts use the macOS Keychain, so this skill is macOS-only as written.

`/fix-honeybadger`, `/resolve-issue` and the autofix cloud runs produce PRs whose descriptions end with "Resolve fault #N in Honeybadger once this is in production". This skill does that chore for every recent merge in one pass.

A fault is resolved only when all of these are true. Resolving early hides nothing (Honeybadger reopens a resolved fault on its next notice), but it would mean a reopen notification in the middle of the day for something that was never fixed:

1. A merged PR **fixes** it: the PR's title or branch names the fault, its body opens a line with "Fixes Honeybadger fault #N" or has a "Resolve … fault N" to-do, or it closes an issue titled `HB #N: …` (or `Follow-up to HB #N: …`). If an id only appears in passing (docs-sync PRs listing old branches, tooling PRs quoting ids, issues closed as `NOT_PLANNED` duplicates), it's a mention, not a fix.
2. That fix is **in production**: its merge commit is an ancestor of the revision production is running.
3. In Honeybadger the fault is **unresolved, not ignored**, and its `last_notice_at` is **before the fix merged**.

## Arguments

- None: since yesterday (yesterday + today).
- A number `N`: the last N days (`--since` = today − N).
- A date `YYYY-MM-DD`: since that date.

## Step 1: Find fixed faults

```bash
python3 .claude/skills/resolve-honeybadger/scripts/find_fixed_faults.py --since <YYYY-MM-DD>
```

The script fetches origin, reads production's revision from `$APP_URL`'s public sign-in page (`<meta name="honeybadger-revision">`), lists merged PRs and closed issues with `gh`, and prints JSON:

- `faults[]`: `fault_id`, `fixes[]` (`pr`, `title`, `merged_at`, `role` primary/follow-up, `deployed`, `via`), `ready`.
- `ready` is true when a **primary** fix is deployed. Follow-up PRs (hardening filed after the main fix) don't block: the main fix stopped the error. They're only used when a fault has no primary fix.
- `deployed: null` means the merge commit isn't known locally or the revision couldn't be read. Treat that as not deployed and say why.
- `mentions_only`: ids found only in passing. List them in the report and never resolve them on this evidence alone.

## Step 2: Check each candidate in Honeybadger

For every fault in `faults[]`, call `mcp__honeybadger__get_fault(project_id: $HB_PROJECT_ID, fault_id: …)` (in parallel). Sort each one into a bucket:

| Bucket | Condition |
|---|---|
| **resolve** | `ready`, `resolved: false`, `ignored: false`, `last_notice_at` < earliest primary fix's `merged_at` |
| **already resolved** | `resolved: true` or `ignored: true` |
| **waiting for deploy** | not `ready`. Name the undeployed PR(s) |
| **fired after the fix** | `last_notice_at` ≥ the fix's `merged_at`. Don't resolve. Step 2b splits it: before the fix went live (wait), or after (**fix didn't work**) |
| **not found** | `get_fault` errors (wrong project, deleted). Report it |

### Step 2b: Did the fix fail, or just not ship yet?

For every **fired after the fix** fault whose primary fix is `deployed`, find when that fix first reached production:

```bash
python3 .claude/skills/resolve-honeybadger/scripts/fix_deployed_at.py --since <earliest merged_at date> <merge_sha> <merge_sha> …
```

It reads Honeybadger's production deploy list (your deploy script reports each deploy with its revision) with the same Keychain token as `resolve_faults.sh`, and prints `{merge_sha: first deploy time | null}`. Then:

- `last_notice_at` **before** that deploy time: it fired between merge and deploy. Leave it unresolved; the next run resolves it if it stays quiet.
- `last_notice_at` **after** that deploy time: **the fix didn't work.** Reopen its issue so it gets built again:

```bash
gh label create fix-didnt-work --color B60205 --description "Fault fired again after its fix reached production" --force
gh issue list --state all --search "HB #<id> in:title" --json number,state,title   # the fault's issue; else the fix PR's closing issue
gh issue reopen <issue>      # only if closed
gh issue edit <issue> --add-label fix-didnt-work
gh issue comment <issue> --body "HB #<id> fired at <last_notice_at>, after PR #<pr> reached production at <deploy time>. The fix didn't stop it. Next: /fix-honeybadger <id> (or queue this issue with the autofix-queue label)."
```

  No issue at all (a fast fix with no issue): file one with `/fix-honeybadger`'s issue template, titled `HB #<id>: …`, with the same comment text in its body and the same label.
- `null` (no recorded deploy contains it, or the commit isn't fetched): don't decide; report it under "fired after the fix" with the reason.

Comparing against the merge time is deliberately conservative. A notice that landed after the merge but before the deploy holds the fault for one more run. That's cheaper than resolving something still broken.

## Step 3: Resolve

Run the bundled script with every id in the **resolve** bucket:

```bash
.claude/skills/resolve-honeybadger/scripts/resolve_faults.sh <id> <id> …
```

It reads the token from the Keychain item `$HB_KEYCHAIN_SERVICE` (default `honeybadger-token`), passes it to `curl` on stdin rather than the command line, PUTs `{"fault":{"resolved":true}}` to each fault, and ends with `RESULT: resolved=N failed=M`. Only that script touches the token. Never print it, `echo` it, or look for it anywhere else (env files, MCP config, shell profiles). If the tool call is blocked by a permission check, stop and hand the user the exact command to run as `! <command>`. Don't try another way to get the token.

- **Exit 3 (no Keychain item):** tell the user to create it once, in a regular Terminal window outside Claude Code. A `!` command can't answer the password prompt, so the item silently isn't saved. The command is `security add-generic-password -U -a "$USER" -s honeybadger-token -w`, with nothing after `-w`; it prompts for the token twice, so the token never enters shell history or the conversation. The token is the personal auth token under Honeybadger → Profile → Authentication, not the `hbp_` project key. Then re-run.
- **`FAILED 401/403`:** the token is wrong or lacks access. Same fix, with `-U` overwriting the item.
- **`FAILED 404`:** the fault isn't in that project. Report it; don't retry.

The Honeybadger MCP has no write tools, so it can't do this step.

## Step 4: Report

One short table, then the leftovers. Example:

```
Resolved 5 faults (production at a9c06b57d1ac):

| Fault | Error | Fixed by |
|---|---|---|
| 100000201 | EmailProvider::ThrottledError 420 | #41 (+ follow-ups #44, #46 not deployed yet) |
| …

Waiting for deploy (resolve on the next run): 100000202 (#48), 100000203 (#47)
Already resolved: 100000204
Fix didn't work (issue reopened, fix-didnt-work): 100000205 → #42 (fired 10/06/2026 14:02, fix live 10/05/2026 18:40)
Fired before the fix went live (resolve next run): 100000206
Mentions only, not touched: 100000207, 100000208 (issues #50/#51 closed as duplicates of open #52)
```

Use links where they help: `https://app.honeybadger.io/projects/<project-id>/faults/<id>`. Keep the error column to the class plus a few words; fault messages can contain user data, so don't paste them whole.

If anything is waiting for a deploy, end with one line saying a re-run after the next production deploy will pick those up.
