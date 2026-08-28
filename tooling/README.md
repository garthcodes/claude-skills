# tooling/

Helper scripts and a hook that several skills assume exist. They're small and generic — copy them in, then adjust the placeholders.

## `bin/` — worktree port + URL helpers

| Script | What it does | Used by |
|---|---|---|
| `bin/dev-url` | Prints the base URL of *this checkout's* dev server. Port precedence: `$PORT` > `PORT=` in `.env` > `3000`. Set `DEV_URL_HOST` / `DEV_URL_SCHEME` if your dev server lives at a custom host (e.g. `https://myapp.localhost`). | every Playwright-driving skill (`/bug-hunt`, `/execute-qa`, `/qa-tester`, `/full-qa`, …) |
| `bin/worktree-port` | Allocates a free dev-server port (3010–3099) for a pipeline worktree under `.claude/worktrees/` and writes `PORT=<n>` into its `.env`. A port is free when no other worktree's `.env` claims it and nothing is listening on it. | `/build-feature`, `/fix-honeybadger`, `/worktree` |
| `bin/worktree-sweep` | Removes pipeline worktrees whose PR is merged or closed: stops the server on the worktree's port, drops its `DATABASE_SUFFIX` databases, `git worktree remove`s it. Never touches open-PR, no-PR, dirty, or unregistered worktrees. `--dry-run` prints the verdicts only. Needs an authenticated `gh`. The database name prefix is read from `config/database.yml` (override with `APP_DB_PREFIX`). | `/worktree-sweep`, `/build-feature` (runs it first) |

Install:

```bash
cp tooling/bin/* /path/to/your-project/bin/
```

`bin/dev` must honor `PORT=` from `.env` for the worktree port to take effect (e.g. `export $(grep -s '^PORT=' .env)` before starting the server, or have Procfile.dev use `-p ${PORT:-3000}`). `DATABASE_SUFFIX` is the convention `/build-feature` uses to give each worktree its own databases — see that skill for the `config/database.yml` snippet.

## `hooks/` — production guard

`claude-hook-prod-guard.py` is a Claude Code **PreToolUse** hook for the `Bash` tool. Any command that targets production — `fly`/`flyctl` without an explicit staging target, `--app <prod-app>`, `bin/deploy` without `staging`, mutating `gcloud`/`gsutil`, a `production_reset` rake namespace — is turned into an explicit **ask** permission prompt, overriding any allowlist. Staging-targeted commands pass through. On any internal error it fails closed (asks).

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
