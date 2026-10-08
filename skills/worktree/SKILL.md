---
name: worktree
description: Create a git worktree and open it in a new VSCode window
argument-hint: <worktree-name>
allowed-tools: Bash(git worktree:*), Bash(git branch:*), Bash(git status:*), Bash(open:*), Bash(ls:*), Bash(pwd:*), Bash(cp:*), Bash(mkdir:*), Bash(echo:*), Bash(grep:*), Bash(tr:*), Bash(cut:*), Bash(cd:*), Bash(bin/rails:*), Bash(dropdb:*)
---

# Git Worktree Creation and VSCode Integration

Create a new git worktree named "$1" and open it in a new VSCode window.

Throughout this skill, `<main-repo>` means the absolute path of the main repository checkout
(the directory this skill is run from), and `<app>` means your application's database name
prefix (whatever `config/database.yml` uses, e.g. `myapp` for `myapp_development` /
`myapp_test`).

## Prerequisites Validation

First, validate the environment:
1. Verify we're in a git repository
2. Check that the worktree name "$1" is provided and valid
3. Confirm the worktree doesn't already exist

## Worktree Creation Strategy

Create the worktree using the following approach:
1. **Location**: Create worktree in a sibling directory: `../<repo>-$1` (e.g. if the repo
   directory is `myapp`, use `../myapp-$1`)
2. **Branch**: Create a new branch named `$1` for the worktree
3. **Base Branch**: Use the current main branch (`main`) as the base

## Execution Steps

1. **Validate the worktree name**:
   - Ensure "$1" is not empty
   - If empty, prompt user to provide a worktree name
   - Validate it follows git branch naming conventions (no spaces, special characters)

2. **Check current repository status**:
   - Verify we're in a git repository
   - Get the current working directory
   - Confirm the main branch exists

3. **Create the git worktree**:
   ```bash
   git worktree add ../<repo>-$1 -b $1 main
   ```
   This creates:
   - A new directory at `../<repo>-$1`
   - A new branch named `$1` based on `main`
   - Checks out the new branch in the worktree

4. **Verify worktree creation**:
   - List all worktrees to confirm creation
   - Verify the new directory exists

5. **Copy SSL certificates** (if your dev server uses local HTTPS):
   - The development server may require SSL certificates that are in `.gitignore`
   - Copy from the main repository to the new worktree:
   ```bash
   cp -r <main-repo>/config/certs ../<repo>-$1/config/
   ```
   - This enables `bin/dev` to start with HTTPS support

6. **Copy environment file**:
   - The `.env` file contains required environment variables (API keys, etc.) and is in `.gitignore`
   - Copy from the main repository to the new worktree:
   ```bash
   cp <main-repo>/.env ../<repo>-$1/.env
   ```
   - This ensures all environment variables are available in the new worktree

7. **Create isolated databases**:
   - The worktree must NOT share `<app>_development` / `<app>_test` with the main repo —
     migrations run in the worktree would otherwise mutate the shared dev database.
     Have `config/database.yml` append `ENV["DATABASE_SUFFIX"]` to both database names
     (an unset var must be a no-op); setting it in the worktree's `.env` means every command
     run there (`bin/rails`, `rspec`, `bin/dev`) picks it up automatically via
     dotenv/foreman. The main repo (where the var is unset) is unaffected.
   - Sanitize "$1" into a Postgres-safe suffix (hyphens → underscores, lowercase alphanumerics
     and underscores only, max 30 chars), append it to the worktree's `.env`, and create the
     databases (run from inside the worktree directory):
   ```bash
   DB_SUFFIX="_$(echo "$1" | tr '-' '_' | tr -cd 'a-z0-9_' | cut -c1-30)"
   # printf's leading newline matters: .env may not end in one, and a glued-on line is ignored
   printf '\nDATABASE_SUFFIX=%s\n' "$DB_SUFFIX" >> ../<repo>-$1/.env

   cd ../<repo>-$1
   grep -E '^DATABASE_SUFFIX=' .env || { echo "DATABASE_SUFFIX not on its own line — fix .env" >&2; exit 1; }
   bin/rails db:create db:schema:load   # <app>_development${DB_SUFFIX} + <app>_test${DB_SUFFIX}
   bin/rails db:seed                    # use a small seed profile here if your app has one
   ```
   - Verify: `bin/rails runner 'puts ActiveRecord::Base.connection_db_config.database'` run in
     the worktree should print the suffixed name, NOT `<app>_development`

8. **Open in VSCode**:
   - Use the `open` command to launch VSCode with the new worktree
   - Command: `open -a "Visual Studio Code" ../<repo>-$1`
   - This opens a new VSCode window with the worktree directory

## Error Handling

Handle common issues:
- **Missing worktree name**: Prompt user to provide a name
- **Invalid branch name**: Suggest a valid alternative
- **Worktree already exists**: List existing worktrees and suggest alternatives
- **Git errors**: Display clear error messages and suggested fixes
- **SSL certs not found**: If `<main-repo>/config/certs` doesn't exist, warn the user they'll need to generate certificates with mkcert (or skip this step if the project doesn't use local HTTPS)
- **.env not found**: If `<main-repo>/.env` doesn't exist, warn the user they'll need to create it with the required environment variables
- **Database setup fails** (`db:schema:load` / `db:seed` errors): Try `bundle install` in the worktree and retry once. If it still fails, warn the user — do NOT remove the `DATABASE_SUFFIX` line from `.env` as a workaround; working against the shared `<app>_development` database is not acceptable
- **VSCode not found**: Provide instructions for opening the directory manually

## Success Confirmation

After successful creation:
1. Confirm the worktree was created at `../<repo>-$1`
2. Confirm the branch `$1` was created
3. Confirm SSL certificates were copied
4. Confirm `.env` file was copied (including the `DATABASE_SUFFIX` line)
5. Confirm the isolated databases were created (report their names)
6. Confirm VSCode opened with the new worktree
7. Provide instructions for:
   - Switching between worktrees
   - Removing the worktree when done — drop the isolated databases FIRST (while the
     worktree's `.env` still exists), then remove the worktree:
     ```bash
     cd ../<repo>-$1 && bin/rails db:drop   # drops <app>_development${DB_SUFFIX} and <app>_test${DB_SUFFIX}
     cd <main-repo> && git worktree remove ../<repo>-$1
     ```
     (If the worktree was already removed, drop leftovers with `dropdb <name>` —
     find them with `psql -lqt | grep <app>_`)
   - Listing all worktrees: `git worktree list`

## Important Notes

- **PRD-only work**: to run `/prd` then `/build-feature`, use `/prd-worktree` instead — it skips
  every step below except creating the worktree and opening VSCode, and `/build-feature` removes it
  once a PR opens
- **Worktree isolation**: Each worktree is independent with its own working directory
- **Database isolation**: Each worktree gets its own `<app>_development_*` / `<app>_test_*`
  databases via `DATABASE_SUFFIX` in its `.env`. The main repo is unaffected (the var is unset
  there, and `config/database.yml` treats that as a no-op). Remember to `bin/rails db:drop`
  from the worktree before removing it
- **Shared git history**: All worktrees share the same git repository and history
- **Branch management**: Each worktree should have its own branch to avoid conflicts
- **Cleanup**: Remember to remove worktrees when done to keep your workspace clean
- **Claude Code compatibility**: Claude Code works seamlessly in worktrees
- **Dev server port**: Sibling worktrees serve on the default port like the main checkout, which
  collides with it. To run one alongside it, assign a port with
  `bin/worktree-port --assign .env` (writes `PORT=<n>` in the 3010–3099 range; `bin/dev`
  honors it, and `bin/dev-url` reports the resulting base URL for the QA/bug-hunt skills).
  `/worktree-sweep` removes these `../<app>-*` worktrees too once nothing in them is worth keeping

## Example Usage

```bash
/worktree feature-payments
/worktree bugfix-auth
/worktree experiment-ui
```

Execute the worktree creation workflow now, ensuring all steps are completed successfully.
