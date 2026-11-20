---
description: Hunt for bugs in the Hotwire Native app — Claude drives the <App> Dev build on the Android emulator (taps, typing, screenshots) or the iOS Simulator, and reads inside the WebView through the dev-only debug beacon
argument-hint: "[--ios] <feature-description>"
---

# Native Bug Hunt

The `/bug-hunt` equivalent for the Hotwire Native app (`native/ios`, `native/android`). You
test the **<App> Dev** build against this checkout's `bin/dev` and document bugs. **You do NOT fix bugs — you only find and report them.**

## Feature to Test
$ARGUMENTS

## Why this skill works the way it does

The shells are ours, so both platforms run locally: the Android `development` flavor in the
emulator (`/android-emulator`) and the iOS `<App> Dev` scheme in the Simulator (`/ios-simulator`),
each pointed straight at `bin/dev` — no tunnel. A person can inspect the Android debug WebView
from `chrome://inspect`, but Claude can't drive devtools, so it reads the page through the
dev-only debug beacon instead:

| Need | Tool |
|---|---|
| Tap, type, keys, screenshots (Android) | `nd` → `adb` |
| Tap, type, screenshots, native chrome (iOS) | `axe` (see `/ios-simulator` step 5) |
| Native chrome: bottom navigation, toolbar title and bridge buttons, menus, dialogs (Android) | `nd native` → `uiautomator dump` |
| DOM, element positions, JavaScript in the live page (**Android and iOS**) | `nd eval` / `nd tap` / `nd layout` → the debug beacon (`lib/dev/native_debug_middleware.rb` + `app/javascript/native_debug.js`, development only) |
| What the page told the shell (bridge components) | `nd eval` on `document.documentElement.dataset.bridgeComponents` and the `[data-controller~="bridge--…"]` elements |
| Console errors, JS errors, layout snapshots on every page load | `nd log` → `log/native_debug.log` |
| Requests and status codes | `nd log` → `log/development.log` |

`ND=.claude/skills/native-bug-hunt/scripts/nd`. Run `$ND` with no arguments for usage.

Only staff messaging renders natively (`NativeMode::NATIVE_STAFF_PATHS` in
`app/controllers/concerns/native_mode.rb`); any other page shows the **Open in browser** screen.
Plan scope with that in mind.

## Start with the scripted shell pass

`bin/native-qa` does the whole Android setup and shell checklist unattended (boot, `adb reverse`,
build and install <App> Dev, sign-in, bridge components, tabs, toolbar buttons and menu, badge,
push registration, sheets, external-browser routing, relaunch) and writes
`docs/bug-reports/native-qa-<timestamp>/REPORT.md`. Run it yourself (it exposes nothing beyond
this machine), or use the newest `docs/bug-reports/native-qa-*/REPORT.md` if one is from today. Triage it first: every FAIL
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
   start `bin/dev` as `/bug-hunt` does. The Dev build loads `https://<org-subdomain>.<dev-host>:<port>`, so the
   `<org-subdomain>` subdomain picks the organization — `DEFAULT_ORG_SUBDOMAIN` is not needed.
2. **Beacon loaded:** the server must have started after the beacon was added (it lives in
   `config/environments/development.rb`). If `nd eval` later times out, ask the user before
   restarting with `bin/rails restart`.
3. **Android (default):** run `/android-emulator development`. It boots the emulator, runs
   `adb reverse tcp:<port> tcp:<port>`, builds and installs `com.example.app.dev`
   (`./gradlew installDevelopmentDebug -PdevBaseUrl="$BASE_URL"`) and launches it. Add
   `--no-build` when only server code changed since the last install.
4. **iOS (`--ios`):** run `/ios-simulator development`. It trusts the mkcert root CA in the
   Simulator, builds the `<App> Dev` scheme with `APP_BASE_URL="$BASE_URL"`, installs and launches
   `com.example.app.dev`. Drive it with `axe`; the beacon (`nd eval`, `nd layout`,
   `nd log`) works the same, but `nd tap`, `nd native`, `nd shot` and `nd relaunch` are
   Android-only — use `axe` and `xcrun simctl terminate/launch` instead.

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
$ND tapxy <x> <y>                               # the dev "Sign in now" shortcut
```
Expect `/staff/conversations` with the native bottom navigation. On sign-in the `session` bridge
component reports a new identity and the shell resets every tab to its start page — a brief
reload is expected, a blank screen is not.

iOS: the same steps with `axe` (screenshot, tap, type); confirm with `$ND log` that
`/passwordless/users/magic_link → /staff/conversations 200` went through.

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

- `axe screenshot` → Read the PNG; `axe tap -x -y` in points (screenshot pixels ÷ 3 on iPhone 17);
  `axe describe-ui` for the tab bar, navigation-bar buttons and menus.
- For web elements, find the box with
  `$ND eval 'return __nativeDebug.rects("<selector>")'` (CSS px = points), offset by the WebView's
  top (below the navigation bar), then `axe tap`.
- After every action: wait about 3 s, `$ND eval 'return location.pathname'`, screenshot.
- `$ND log` entries from the Simulator show `platform: ios`.

## Per-Screen Checklist

For every in-scope screen:

1. **Visual:** screenshot. Look for overlaps, clipping, content under the navbar or status bar,
   and dark-mode contrast.
2. **Hidden controls:** `$ND layout`, then `offscreenInteractive`. Anything listed is cut off by
   the viewport with no scroller to reach it (for example a composer pushed below the fold). Check it
   again with the keyboard open, since `innerHeight` changes.
3. **Native chrome (bridge components):** `$ND native` (iOS: `axe describe-ui`). Check:
   - the toolbar / navigation-bar title matches the page `<title>`;
   - the `button` component's New message button and the `menu` component's More menu (with
     **Sign out**) appear on the screens that render them, and tapping them does what the hidden
     page element does;
   - the `badge` component's count (`data-bridge--badge-count-value`) matches the Messages tab
     badge (and the app-icon badge on iOS), hidden at 0;
   - the right tab is selected;
   - `push-registration`: after sign-in, `log/development.log` shows `POST "/native/push_devices"`
     when the build can get a token (Android with `google-services.json`; never the iOS
     Simulator dev build).
4. **Errors:** `$ND log` for JS and console errors on this URL, and non-2xx/3xx requests.
5. **Interactions:** tap every control on the page. Submit forms with valid and invalid input.
   Check that `/new`, `/edit` and `/members/edit` open as sheets (path configuration `context:
   modal`) and that a success page's back button skips the form.
6. **Navigation:** back button, switching tabs and back again (the page keeps its state), and a
   non-native page: the path configuration marks it `external_browser`, so the shell opens it in
   the system browser (`$ND focus` shows the browser package); the server's **Open in browser**
   screen is only the fallback.
7. **Persistence:** `$ND relaunch` and confirm you're still signed in (90-day native remember
   cookie).

## Native Bug Types

Besides the `/bug-hunt` types, use:
- **Native Layout:** content cut off by the viewport, keyboard covering the composer
- **Native Bridge:** toolbar button, menu, badge, session reset or push registration missing or
  wrong (page side in `app/javascript/controllers/bridge/`, shell side in
  `native/*/…/BridgeComponents` / `bridge/`)
- **Native Navigation:** blank screen, wrong tab after a redirect, a push where a sheet was
  expected, a broken back stack, an off-scope page rendered in the app

## Reports

Use `/bug-hunt`'s **Severity Definitions**, **Step 6** and **Step 7** (per-bug template, INDEX
template, directory layout) unchanged, except:
- Session directory: `docs/bug-reports/native-{feature-name}-{YYYYMMDD-HHMMSS}/`.
- **Environment** block in each bug:
  ```
  - **Platform:** Android emulator (Medium_Phone_API_36.0) | iOS Simulator (device name)
  - **App:** <App> Dev (com.example.app.dev), branch <git branch> @ <short sha>
  - **URL:** [path]
  - **User:** [test user email]
  - **Viewport:** [innerHeight from nd layout] CSS px @ devicePixelRatio [n]
  ```
- **Console Errors:** paste the relevant `nd log` beacon lines.
- INDEX **Tester:** `Claude Code (native, Android emulator)` or `Claude Code (native, iOS Simulator)`.

## Wrap-Up

- Report the session directory and the severity counts.
- Leave `log/native_debug.log` in place (it's gitignored with the rest of `log/`).
