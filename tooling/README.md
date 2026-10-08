# tooling/

Helper scripts and a hook that several skills assume exist. They're small and generic — copy them in, then adjust the placeholders.

## `bin/` — worktree port + URL helpers

| Script | What it does | Used by |
|---|---|---|
| `bin/dev-url` | Prints the base URL of *this checkout's* dev server. Port precedence: `$PORT` > `PORT=` in `.env` > `3000`. Set `DEV_URL_HOST` / `DEV_URL_SCHEME` if your dev server lives at a custom host (e.g. `https://myapp.localhost`). | every Playwright-driving skill (`/bug-hunt`, `/execute-qa`, `/qa-tester`, `/full-qa`, …) |
| `bin/worktree-port` | Allocates a free dev-server port (3010–3099) for a worktree — a pipeline one under `.claude/worktrees/` or a sibling `../<app>-*` — and writes `PORT=<n>` into its `.env`. A port is free when no other worktree's `.env` claims it and nothing is listening on it. | `/build-feature`, `/fix-honeybadger`, `/worktree` |
| `bin/worktree-sweep` | Removes the repo's worktrees that hold nothing worth keeping — pipeline `.claude/worktrees/*` and sibling `../<app>-*` alike, plus stray dirs left under `.claude/worktrees/`. A worktree is **kept** when it has uncommitted changes (outside `.claude/`, `tmp/`, `log/`), unpushed non-merge commits, an open PR, a running Claude Code session inside it, or no PR and changes in the last 24 h; a stray dir is kept when anything in it changed in the last 24 h. Each removed one gets its dev server stopped (matched by the process's working directory), its `DATABASE_SUFFIX` databases dropped by exact name (never a name another worktree's suffix also produces, so sweeping `_issue_5` can't touch `_issue_52`), and `git worktree remove --force` (locked worktrees are reported, not forced). `--all` removes every worktree with no checks; `--dry-run` prints the keep/remove decision and changes nothing. Branches are never deleted. The database name prefix is read from `config/database.yml` (override with `APP_DB_PREFIX`). Needs `gh` for the open-PR rule. Run by hand only. | `/worktree-sweep` (suggested by `/build-feature` when the port range is full) |

Install:

```bash
cp tooling/bin/* /path/to/your-project/bin/
```

`bin/dev` must honor `PORT=` from `.env` for the worktree port to take effect (e.g. `export $(grep -s '^PORT=' .env)` before starting the server, or have Procfile.dev use `-p ${PORT:-3000}`). `DATABASE_SUFFIX` is the convention `/build-feature` uses to give each worktree its own databases — see that skill for the `config/database.yml` snippet.

## `hooks/` — production guard

`claude-hook-prod-guard.py` is a Claude Code **PreToolUse** hook for the `Bash` tool. Any command that targets production — `fly`/`flyctl`/`flyadmin` without an explicit staging target for that invocation, `--app <prod-app>`, `bin/deploy` without `staging`, mutating `gcloud`/`gsutil` or `gcloud secrets versions access`, a `production_reset` rake namespace — is turned into an explicit **ask** permission prompt, overriding any allowlist. It reads the command the way the shell will run it: line continuations are joined and quotes and escapes are removed first (`"fly"`, `fl''y`, `fl\<newline>y`), the word is found whatever punctuation surrounds it (`/opt/homebrew/bin/fly`, `$'fly'`, `{fly,}`), `bash -c` / `eval` payloads count, and `&`, `$(…)`, backticks and subshells start a new command, so `fly status -a <app>-staging & fly deploy` still asks. Staging-targeted commands pass through. On any internal error it fails closed.

**Unattended runs get `deny`, not `ask`.** With `HB_AUTOFIX=1` or `CLAUDE_UNATTENDED=1` in the environment there is nobody to answer a prompt, so the hook blocks the command outright. Set one of them in whatever launches headless sessions (`claude -p`, cloud routines).

**It's a tripwire, not the security boundary.** The hook reads command text, so it can't see a binary name held in a variable (`$F deploy` asks only because `F=fly` appears in the same command) or a script written in an earlier tool call and run later. The boundary is credentials: the agent's own Fly, database and cloud credentials should be read-only, with production writes run by a person (see `skills/devops-expert`). The hook's job is to stop honest mistakes and make every production action a visible decision.

Read-only text commands (`grep`, `rg`, `cat`, `echo`, …) that mention `fly` are not paused, so searching docs doesn't prompt. `git` and `gh` count as text only for subcommands that can't run a command (`git commit`/`log`/`show`/`diff`/`grep`/`status`/`tag`; `gh pr|issue create|edit|comment|review|view|list`) with no global option before them, so opening a PR whose body quotes a deploy command doesn't prompt but `git -c core.sshCommand=…` or `gh alias set --shell` does. None of these exemptions apply when the command writes a file, or when any part of it runs a shell, interpreter or command-runner (`| sh`, `| xargs`, `| tee`, `env`, `sudo`, …), because then the printed text may be executed. The body of an inert `cat > file.md <<'EOF'` heredoc (quoted delimiter, written to a document file the same command doesn't run) is not scanned either; a heredoc written to a script, or piped to a shell, is.

The ops skills (`devops-expert`, `feature-qa`, `fix-honeybadger`, `sync-user-docs`) refer to this hook behind their "never act on production automatically" rule.

Test it: `python3 -m unittest tooling/hooks/test_prod_guard.py`. The test file lists every command shape the hook must pause and every ordinary one it must let through; add a case when you change a pattern.

Install:

1. Copy the file to your repo root and set `PROD_APP` at the top to your production Fly app name (staging is assumed to be `<PROD_APP>-staging`). Adjust the regexes if your deploy tooling differs.
2. `chmod +x claude-hook-prod-guard.py`
3. Register it in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "./claude-hook-prod-guard.py" }
        ]
      }
    ]
  }
}
```
