# Browser verification (only when a spec can't cover the fix)

Use this when the fix changes rendered HTML, a Stimulus controller or a Turbo Stream in a way a component/request spec can't prove. Faults in jobs, webhooks, services and mailers are verified with a spec plus `bin/rails runner` on the fault's inputs instead — don't open a browser for them.

The Playwright MCP browser rejects the mkcert dev certificate (`ERR_CERT_AUTHORITY_INVALID`) and `bin/dev` serves HTTPS only, so use **Selenium MCP** headless Chrome, which ignores the certificate and keeps its own profile.

## Start the worktree server and sign in

The background DB setup from Step 5 must have finished (`db:seed:mini` done) before this.

```bash
cd $WT && env -u PORT nohup bin/dev > log/hb-dev.out 2>&1 &
for i in $(seq 1 60); do
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL" 2>/dev/null)
  [ "$STATUS" = "200" ] || [ "$STATUS" = "302" ] && break; sleep 1
done
```

If it doesn't come up, check `log/hb-dev.out`, try `bundle install` once, and if still failing skip verification and say so in the PR.

Pick the user from the fault's URL: staff pages → `admin@example.com` or `therapist@example.com`; client portal → `user@example.com`; default `admin@example.com`. Mint a magic link instead of reading logs:

```bash
cd $WT && bin/rails runner 'User.find_by!(email: "admin@example.com").update_columns(magic_link_token: "hb-1", magic_link_sent_at: Time.current)'
```

Therapist users have pending CPT / unresolved-session modals that intercept clicks. If you sign in as one, clear them first with `bin/rails runner` (`update_columns(cpt_code:, cpt_code_confirmed_at:)`, `diagnosis_selected_at:`, `outcome_popup_deferred_until: 1.day.from_now`, then `Rails.cache.clear`).

```
mcp__selenium__start_browser(browser: "chrome", options: {headless: true,
  arguments: ["--ignore-certificate-errors", "--allow-insecure-localhost",
              "--window-size=1280,800", "--disable-dev-shm-usage", "--no-sandbox"]})
mcp__selenium__navigate(url: "$BASE_URL/passwordless/users/magic_link?email=admin@example.com&token=hb-1")
```

Use `--window-size=375,667` instead for client-portal faults (`window.resizeTo` does nothing in headless).

## Reproduce and confirm

1. Reach the affected area by clicking through the UI like a user (sidebar, menus, buttons). Only type URLs for the first load and the magic link.
2. Build the data the fault needs if the mini seed lacks it (FactoryBot inside `bin/rails runner`: `require "factory_bot"; FactoryBot.find_definitions; include FactoryBot::Syntax::Methods`).
3. Perform the action that raised the error, then confirm: the page renders as expected (read `accessibility://current` or `get_element_text`), no new errors in `log/development.log` (`grep -nE "Error|Exception" $WT/log/development.log | tail`), and no JS errors (`mcp__selenium__diagnostics(type: "console")`).
4. Selenium quirks: if a click is "intercepted" by a sticky header, `execute_script` with `scrollIntoView({block:'center'})` then `.click()`; a `window.confirm` needs `mcp__selenium__alert(action: "accept")`; don't pull `diagnostics(type: "network")` on a long session — it overflows.

When the fault depends on an external service the dev environment has no credentials for (Google, Stripe, Stedi), fake only that service's answer with a temporary `config/initializers/zz_hb_verify_fake.rb` that prepends onto the one service call, keyed to a test-only input (e.g. one email). Delete it before committing, confirm `git status` doesn't show it, and say in the PR that the external answer was faked.

## Clean up

```bash
lsof -ti:$PORT | xargs kill 2>/dev/null
```

Close the Selenium session (`mcp__selenium__close_session`) and delete any screenshots taken.
