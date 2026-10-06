# tooling/

Helper scripts and a hook that several skills assume exist. They're small and generic — copy them in, then adjust the placeholders.

## `bin/` — worktree port + URL helpers

| Script | What it does | Used by |
|---|---|---|
| `bin/dev-url` | Prints the base URL of *this checkout's* dev server. Port precedence: `$PORT` > `PORT=` in `.env` > `3000`. Set `DEV_URL_HOST` / `DEV_URL_SCHEME` if your dev server lives at a custom host (e.g. `https://myapp.localhost`). | every Playwright-driving skill (`/bug-hunt`, `/execute-qa`, `/qa-tester`, `/full-qa`, …) |
| `bin/worktree-port` | Allocates a free dev-server port (3010–3099) for a worktree — a pipeline one under `.claude/worktrees/` or a sibling `../<app>-*` — and writes `PORT=<n>` into its `.env`. A port is free when no other worktree's `.env` claims it and nothing is listening on it. | `/build-feature`, `/fix-honeybadger`, `/worktree` |
| `bin/worktree-sweep` | Removes the repo's worktrees that hold nothing worth keeping — pipeline `.claude/worktrees/*` and sibling `../<app>-*` alike, plus stray dirs left under `.claude/worktrees/`. A worktree is **kept** when it has uncommitted changes (outside `.claude/`, `tmp/`, `log/`), unpushed non-merge commits, an open PR, a running Claude Code session inside it, or no PR and changes in the last 24 h. Each removed one gets its dev server stopped (matched by the process's working directory), its `DATABASE_SUFFIX` databases dropped, and `git worktree remove --force`. `--all` removes every worktree with no checks; `--dry-run` prints the keep/remove decision only. Branches are never deleted. The database name prefix is read from `config/database.yml` (override with `APP_DB_PREFIX`). Needs `gh` for the open-PR rule. Run by hand only. | `/worktree-sweep` (suggested by `/build-feature` when the port range is full) |

Install:

```bash
cp tooling/bin/* /path/to/your-project/bin/
```

`bin/dev` must honor `PORT=` from `.env` for the worktree port to take effect (e.g. `export $(grep -s '^PORT=' .env)` before starting the server, or have Procfile.dev use `-p ${PORT:-3000}`). `DATABASE_SUFFIX` is the convention `/build-feature` uses to give each worktree its own databases — see that skill for the `config/database.yml` snippet.

## `hooks/` — production guard

`claude-hook-prod-guard.py` is a Claude Code **PreToolUse** hook for the `Bash` tool. Any command that targets production — `fly`/`flyctl` without an explicit staging target, `--app <prod-app>`, `bin/deploy` without `staging`, mutating `gcloud`/`gsutil`, a `production_reset` rake namespace — is turned into an explicit **ask** permission prompt, overriding any allowlist. Staging-targeted commands pass through. On any internal error it fails closed (asks). The body of an inert `cat > file <<'EOF'` heredoc (quoted delimiter, output to a file) is not scanned, so writing a plan or PR body that quotes a deploy command doesn't prompt; every other heredoc stays guarded.

The ops skills (`devops-expert`, `feature-qa`, `impact-assessment`, `fix-honeybadger`, `sync-user-docs`) refer to this hook as the enforcement layer behind their "never act on production automatically" rule.

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
