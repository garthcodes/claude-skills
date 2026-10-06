---
description: Hunt for bugs in the Ruby Native app — Claude drives the Android emulator (taps, typing, screenshots) and reads inside the WebView through the dev-only debug beacon; iOS runs with the user tapping
argument-hint: "[--ios] <feature-description>"
---

# Native Bug Hunt

The `/bug-hunt` equivalent for the Ruby Native app. You test the native app against the
local dev server and document bugs. **You do NOT fix bugs — you only find and report them.**

## Feature to Test
$ARGUMENTS

## Why this skill works the way it does

Ruby Native has no agent or automation mode, and the preview app's WebView **cannot be inspected**
on either platform (no Safari Web Inspector, no Chrome DevTools socket). Instead:

| Need | Tool |
|---|---|
| Tap, type, keys, screenshots (Android) | `nd` → `adb` |
| Native chrome: tab bar, navbar title and buttons, dialogs, some WebView controls | `nd native` → `uiautomator dump` |
| DOM, element positions, JavaScript in the live page (**Android and iPhone**) | `nd eval` / `nd tap` / `nd layout` → the debug beacon (`lib/dev/native_debug_middleware.rb` + `app/javascript/native_debug.js`, development only) |
| Console errors, JS errors, layout snapshots on every page load | `nd log` → `log/native_debug.log` |
| Requests and status codes | `nd log` → `log/development.log` |

`ND=.claude/skills/native-bug-hunt/scripts/nd`. Run `$ND` with no arguments for usage.

Only staff messaging renders natively (`NativeMode::NATIVE_STAFF_PATHS` in
`app/controllers/concerns/native_mode.rb`); any other page shows the **Open in browser** screen.
Plan scope with that in mind.

## Start with the scripted shell pass

`bin/native-qa` does the whole Android setup and shell checklist unattended (boot, tunnel, Paste
URL, sign-in, tabs, badge, navbar, sheets, cross-tab links, Open in browser, relaunch) and writes
`docs/bug-reports/native-qa-<timestamp>/REPORT.md`. Ask the user to run it in their own terminal
(it starts the tunnel, which auto mode blocks for Claude) and paste the report path, or use the
newest `docs/bug-reports/native-qa-*/REPORT.md` if one is from today. Triage it first: every FAIL
row is a bug to write up with its screenshot (Type per **Native Bug Types** below); a WARN row is
something the script could not decide — check it by hand in the per-screen pass. Then hunt the
feature below the same way, driving the emulator yourself for anything the script does not cover.

## Scope Determination

Follow **Scope Determination** (Mode A / Mode B) in `.claude/skills/bug-hunt/SKILL.md` exactly,
ignoring `--ios` when reading `$ARGUMENTS`. In Mode B, only native-reachable pages from the diff are
in scope.

## Prerequisites

Do these in order. Stop and tell the user when one needs them.

1. **Base URL:** `BASE_URL="$(bin/dev-url)"`, and the server answers
   (`curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL/users/sign_in"` → 200). If it doesn't,
   start `bin/dev` as `/bug-hunt` does.
2. **Default org:** `grep -q '^DEFAULT_ORG_SUBDOMAIN=<org-subdomain>' .env`. If it's missing, stop: the user
   must add it and restart the server. Without it the tunnel host's random subdomain is read as an
   organization and every page 404s.
3. **Beacon loaded:** the server must have started after the beacon was added (it lives in
   `config/environments/development.rb`). If `nd eval` later times out, ask the user before
   restarting with `bin/rails restart`.
4. **Android:**
   - `adb devices` lists an emulator; if not, start `~/Library/Android/sdk/emulator/emulator -avd
     Medium_Phone_API_36.0` in the background and wait for `sys.boot_completed`.
   - `adb shell pm list packages | grep com.rubynative.demo`. If it's missing, the user must sign
     the emulator into Google Play and install Ruby Native
     (`https://play.google.com/store/apps/details?id=com.rubynative.demo`).
5. **iOS (`--ios`):** the user needs Ruby Native from TestFlight
   (`https://testflight.apple.com/join/fP6YgsyX`) on a physical iPhone. The Simulator can't run it.
6. **Tunnel — the user starts it.** Auto mode blocks Claude from opening an ingress tunnel. Ask
   the user to run, in their own terminal:
   ```bash
   bundle exec ruby_native preview --url <BASE_URL>
   ```
   and paste the `https://….trycloudflare.com` URL. Remind them their dev server is public until
   they press Ctrl+C.
7. **Connect the app:**
   - Android: `$ND url <tunnel-url>`, then tap **Paste URL**, using its bounds from `$ND native`
     (`$ND tapxy X Y`). Mac `pbcopy` does not reach the emulator.
   - iOS: the user copies the URL on the Mac and taps **Paste URL**; Universal Clipboard carries it.
8. **Static pass:** `bundle exec ruby_native check --paths=app/views,app/components`. Every error
   or warning is a bug (Type: Native Signal).

## Sign In

Test users are the table in `/bug-hunt` Step 4 (staff roles only; the native app has no client
portal). Default: `therapist@example.com`.

Android: the beacon only answers **signed-in** users, so `nd tap` and `nd eval` don't work on
the sign-in page. Use `nd native` (the form fields show up in `uiautomator`) and `tapxy` with the
centre of each element's bounds:
```bash
$ND native | grep -E "Email|Send Magic Link"    # bounds like [126, 682, 952, 737]
$ND tapxy <x> <y>                               # the Email field
$ND type 'therapist@example.com'
$ND key escape
$ND tapxy <x> <y>                               # Send Magic Link
$ND native | grep "Sign in now"
$ND tapxy <x> <y>                               # the Staging Login "Sign in now" shortcut
```
A new tunnel URL means a new host, so the app will be signed out. If the app shows **Preview
tunnel stopped**, run `$ND url <new-url>`, tap **SWITCH SERVER**, then **Paste URL**.
Expect `/staff/conversations` with the native tab bar. If the page is **blank**, that is a known
Android bug (a redirect bounce after sign-in): record it or confirm it's still reported, then use
`$ND relaunch`.

iOS: tell the user the same steps and watch `$ND log` for
`magic_link → /staff/conversations 200`.

## Driving (Android)

- **Find, then tap:** list candidates with
  `$ND eval 'return __nativeDebug.rects("<selector>").map((e, i) => i + " " + e.text)'`,
  then `$ND tap '<selector>' <n>`. Selector taps are exact; use `tapxy` only for native chrome
  (bounds from `$ND native`).
- **After every action:**
  - wait about 3 s
  - `$ND eval 'return location.pathname'`
  - `$ND shot <session>/screenshots/step-NN.png`, then Read the PNG (1080×2400 device px)
- **Keyboard:** `$ND key escape` hides it; `$ND key back` is the system back button.
- **Arbitrary checks:** `$ND eval` with any JavaScript that ends in `return`, e.g.
  `return document.querySelector("textarea").value`. The helpers are `__nativeDebug.rects(sel)`,
  `.dom(sel)` and `.layout()`.

## Driving (iOS, `--ios`)

You can't tap the phone. Walk the user through **one action per message**. After each one:
`$ND log` (the phone reports `platform: ios`), `$ND eval` for state and measurements (the beacon
works on the iPhone), and ask for a screenshot when a visual matters. Save user screenshots into
the session's `screenshots/`.

## Per-Screen Checklist

For every in-scope screen:

1. **Visual:** screenshot. Look for overlaps, clipping, content under the navbar or status bar,
   and dark-mode contrast.
2. **Hidden controls:** `$ND layout`, then `offscreenInteractive`. Anything listed is cut off by
   the viewport with no scroller to reach it (for example a composer under the tab bar). Check it
   again with the keyboard open, since `innerHeight` changes.
3. **Native chrome:** `$ND native`. Check the navbar title matches the page, the navbar buttons
   (new message, ⋮ menu) and their actions, the tab badge counts, and that the right tab is
   selected.
4. **Errors:** `$ND log` for JS and console errors on this URL, and non-2xx/3xx requests.
5. **Interactions:** tap every control on the page. Submit forms with valid and invalid input.
   Check that `/new` and `/edit` open as sheets (advanced mode) and that a success page's back
   button skips the form.
6. **Navigation:** back button, switching tabs and back again (the page keeps its state), links to
   another tab's page (the app should switch tabs), and a non-native page (should show **Open in
   browser**).
7. **Persistence:** `$ND relaunch` and confirm you're still signed in (90-day native remember
   cookie).

## Native Bug Types

Besides the `/bug-hunt` types, use:
- **Native Layout:** hidden behind the tab bar or navbar, safe-area gaps
- **Native Signal:** navbar, tabs, badge or buttons missing or wrong; `ruby_native check` findings
- **Native Navigation:** blank screen, wrong tab after a redirect, a push where a sheet was
  expected, a broken back stack

## Reports

Use `/bug-hunt`'s **Severity Definitions**, **Step 6** and **Step 7** (per-bug template, INDEX
template, directory layout) unchanged, except:
- Session directory: `docs/bug-reports/native-{feature-name}-{YYYYMMDD-HHMMSS}/`.
- **Environment** block in each bug:
  ```
  - **Platform:** Android emulator (Medium_Phone_API_36.0) | iPhone (model from the user)
  - **App:** Ruby Native preview app <version shown on its start screen>
  - **URL:** [path]
  - **User:** [test user email]
  - **Viewport:** [innerHeight from nd layout] CSS px @ devicePixelRatio [n]
  ```
- **Console Errors:** paste the relevant `nd log` beacon lines.
- INDEX **Tester:** `Claude Code (native, Android-driven)` or `Claude Code (native, iOS user-driven)`.

## Wrap-Up

- Report the session directory and the severity counts.
- Remind the user to stop the tunnel (Ctrl+C).
- Leave `log/native_debug.log` in place (it's gitignored with the rest of `log/`).
