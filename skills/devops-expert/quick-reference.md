# DevOps Quick Reference

Placeholders: `<app-name>` = Fly.io production app, `<app-name>-staging` = staging app, `<fly-org>` / `<fly-org>-staging` = Fly.io orgs, `app.example.com` / `staging.example.com` = production / staging hosts.

> **Production safety**: nearly every command on this sheet targets the live production app (`<app-name>`). None of them may run without explicit user approval — the `claude-hook-prod-guard.py` hook pauses each one for an approval prompt. Approval of one command is not approval of the next.

## Two Environments, Two Config Files

Both environments run `RAILS_ENV=production`. The difference is the Fly.io config file:
- **Production**: `fly.toml` → `<app-name>` app in `<fly-org>` org
- **Staging**: `fly.staging.toml` → `<app-name>-staging` app in `<fly-org>-staging` org

## Most-Used Commands

```bash
# Status check
fly status --app <app-name>
fly logs --app <app-name>
fly machine list --app <app-name>

# Deploy (wrapper bakes git SHA into image + notifies the error tracker)
bin/deploy production
bin/deploy staging

# What revision is deployed?
fly ssh console --app <app-name> -C "cat /rails/REVISION"

# Rollback
fly releases --app <app-name>
fly releases rollback --app <app-name>

# SSH / Console
fly ssh console --app <app-name>
fly ssh console --app <app-name> -C "bin/rails console"

# Secrets
fly secrets list --app <app-name>
fly secrets set KEY=value --app <app-name>

# Scale
fly scale show --app <app-name>
fly scale count web=2 worker=1 --app <app-name>

# Database
fly mpg list --org <fly-org>
fly mpg connect <cluster-id>
fly mpg snapshot list <cluster-id>

# Domains
fly certs list --app <app-name>
fly certs show <domain> --app <app-name>
fly ips list --app <app-name>

# DNS verification
dig app.example.com CNAME +short
dig example.net A +short
curl -I https://app.example.com/up
```

## App/Org Mapping

| What | Production | Staging |
|------|-----------|---------|
| Org | `<fly-org>` | `<fly-org>-staging` |
| App | `<app-name>` | `<app-name>-staging` |
| Domain | `app.example.com` | `staging.example.com` |
| Region | `sjc` | `sjc` |
| GitHub Secret | `FLY_API_TOKEN_PRODUCTION` | `FLY_API_TOKEN_STAGING` |

## Emergency Procedures

**App down**: `fly status` > `fly logs` > `fly releases rollback`
**Database issue**: `fly mpg status <id>` > `fly mpg snapshot list <id>` > restore
**Bad deploy**: `fly releases rollback --app <app-name>`
**OOM**: Scale up VM memory in `fly.toml` > `fly deploy`
**SSL broken**: `fly certs show <domain>` > check DNS > re-add cert if needed
