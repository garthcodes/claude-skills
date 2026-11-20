---
description: Fix a bug found by /native-bug-hunt in the Hotwire Native app and verify the fix in the <App> Dev build on the Android emulator and/or the iOS Simulator using the nd helper, axe and the dev-only debug beacon. Use whenever the user hands over a docs/bug-reports/native-*/BUG-*.md file, or asks to fix a native-app, Hotwire Native, emulator, simulator or iPhone-app bug.
argument-hint: <path-to-native-bug-file.md>
---

# Native Bug Hunt Fix

Fix one bug from a `/native-bug-hunt` report and prove it's fixed **inside the native app**, not
just in a browser. This is `/bug-hunt-fix` for the Hotwire Native app; follow that skill's phases
(analysis → plan → implement → verify → document). This file covers what changes because the bug
lives in a WebView wrapped in native chrome.

## Bug File
$ARGUMENTS

## Tools

`ND=.claude/skills/native-bug-hunt/scripts/nd` (run it with no arguments for usage). It drives the
Android emulator through adb and talks to the dev-only debug beacon
(`lib/dev/native_debug_middleware.rb` + `app/javascript/native_debug.js`), which works in the iOS
Simulator too (drive iOS taps and screenshots with `axe`, see `/ios-simulator`):

| Need | Command |
|---|---|
| Run JavaScript in the live page, read state or measurements | `$ND eval 'return …'` (helpers: `__nativeDebug.rects(sel)`, `.dom(sel)`, `.layout()`) |
| Controls cut off by the viewport, viewport height | `$ND layout` |
| Tap by CSS selector, or native chrome by device pixels | `$ND tap '<sel>' [n]` / `$ND tapxy X Y` (bounds from `$ND native`) |
| Type, keys, screenshot | `$ND type`, `$ND key escape\|back\|enter`, `$ND shot <png>` |
| Toolbar, bottom navigation, badges, menus, dialogs | `$ND native` (iOS: `axe describe-ui`) |
| Which app is in front (external-browser routing) | `$ND focus` |
| JS and console errors, layout history, request statuses | `$ND log [n]` |
| Reload the app from scratch | `$ND relaunch` |

## Phase 1: Understand and Reproduce Before Touching Code

1. **Read the bug file.** Note the **Platform** (Android emulator or iOS Simulator), app build, user, path,
   reproduction steps, screenshots and any `nd log` or `nd layout` output quoted in it.
2. **Set up the app** using the **Prerequisites** and **Sign In** sections of
   `.claude/skills/native-bug-hunt/SKILL.md`: base URL, then `/android-emulator development`
   and/or `/ios-simulator development` (<App> Dev against `bin/dev`, no tunnel), sign in as the
   report's user.
3. **Reproduce it on the reported platform** by following the report's steps through the app's UI
   (tabs, list rows, navbar buttons), the way a user would.
   - Record the evidence you'll compare against later: `$ND layout` numbers, `$ND native` output,
     the offending `$ND log` lines, and a screenshot. Save screenshots to `tmp/native_debug/fix/`,
     never to `docs/bug-reports/`.
   - For an **iOS** report, reproduce in the Simulator with `axe`, reading `$ND log` / `$ND eval`
     after each action. A bug seen only on a physical iPhone (push, keyboard, camera) needs the
     user: ask for one action per message.
   - Also try the **other platform** (both run locally). Knowing
     whether the bug is on both platforms or only one narrows the cause a lot: shared CSS and HTML
     versus platform-specific WebView behavior.
4. **If you can't reproduce it,** stop and tell the user what you saw, with the evidence. Don't fix
   a bug you can't observe; you would have no way to verify the fix.

## Phase 2: Root Cause

Investigate as in `/bug-hunt-fix` Steps 2–3. Native bugs usually come from one of these places:

- **Native-only markup:** the `native_app?` branches, especially the layout
  (`app/views/layouts/application.html.erb`),
  `app/components/staff_messaging/conversation_shell_component.*` (`native:` flag), and
  `app/views/staff/conversations/_native_navbar.html.erb`.
- **Bridge components:** page side in `app/javascript/controllers/bridge/*_controller.js`
  (`session`, `push-registration`, `badge`, `button`, `menu`), rendered as hidden
  `data-controller="bridge--…"` elements by the layout and `_native_navbar`. A component only
  loads when the shell lists it in the User-Agent (`bridge-components: [...]`), so a mistyped
  name fails silently — compare `document.documentElement.dataset.bridgeComponents` with the
  elements on the page. Shell side: `native/ios/<App>/BridgeComponents/`,
  `native/android/app/src/main/java/com/example/app/bridge/`.
- **Viewport:** the WebView sits between the shell's navigation bar and tab bar, so there are no
  safe-area insets to pad; the viewport height still changes when the keyboard opens. `h-dvh` /
  `100vh` behave differently from a desktop browser. Compare `$ND layout` numbers rather than
  guessing.
- **Which paths render natively:** `NativeMode::NATIVE_STAFF_PATHS` in
  `app/controllers/concerns/native_mode.rb`. Anything else shows **Open in browser**.
- **Path configuration:** `app/models/native_path_configuration.rb` (served at
  `/native/path_configuration/:platform`; the shells bundle copies that must match — see
  `native/README.md`). It decides default vs modal (sheet), `external_browser`, and
  `replace_root`. The shells fetch the remote copy on launch, so relaunch after changing it.
- **Navigation and redirects:** the navigator pushes and pops screens and presents modal paths as
  sheets; tabs (Messages, Channels, Search) are fixed in the shells. The request sequence in
  `$ND log` shows redirect bounces (e.g. `sign_in 302 → /staff/conversations`).

**When the page is taller than the screen** (`scrollHeight > innerHeight`, controls pushed below
the viewport), find out which element adds the height before blaming the shell. Measure the chain down from
`main`:
`$ND eval 'return Array.from(document.querySelector("main").children).map(c => [c.tagName, c.className.toString().slice(0, 50), c.getBoundingClientRect().height])'`.
If the children don't add up to the parent's height, the gap is usually an empty **line box**: an
`inline-block` element (like `button_to`'s form) takes a full `line-height` line even when its
contents are hidden. In the first real run (under the earlier shell) this was the whole bug, and
its 24 px happened to equal the Android safe area, which made insets look guilty.

Use `$ND eval` to test a hypothesis in the live page before writing code, e.g. apply a candidate
style and re-measure:
`$ND eval 'const s = document.querySelector("main > div"); s.classList.replace("h-dvh", "h-full"); return __nativeDebug.layout().offscreenInteractive'`.
Changes made this way last only until the next page load, so they're safe to experiment with.

## Phase 3: Plan and Implement

Follow `/bug-hunt-fix` Steps 4–6: a minimal, targeted change that follows repo conventions, then
`bin/standardrb --fix`. Use `/frontend-expert` for real front-end work (new markup, component,
Stimulus or JS changes); a one-line wrapper or class change doesn't need it.

Native-specific rules:
- **Don't break the web.** Most native markup shares a component with the browser version. Keep
  the fix inside the `native_app?` / `native:` branch unless the web has the same bug, and say
  which you chose.
- **Tailwind only**, with theme colors.
- **Bridge contract:** a change to a bridge message (event name or data keys) must match the
  shell code on both platforms; shell changes need a rebuild and an app release, so prefer a
  server-side fix. Never edit the bundled path-configuration JSON by hand — regenerate it.

## Phase 4: Verify in the App

1. **Load the new code in the app.** Run `$ND relaunch` (iOS: `xcrun simctl terminate` +
   `launch`). Shell (Swift/Kotlin) changes need a rebuild: rerun `/android-emulator` or
   `/ios-simulator` without `--no-build`. `bin/dev` rebuilds Tailwind
   automatically. Ruby or config changes in `config/` need `bin/rails restart`; ask the user
   before restarting the server they're running.
2. **Repeat the reproduction steps** through the UI on the reported platform, then capture the
   same evidence as in Phase 1. The **before and after numbers** are the proof, for example
   "Send button bottom 790 → 706 in a 722 px viewport; `offscreenInteractive` empty".
3. **Check the related states:**
   - with the keyboard open (tap the field and re-run `$ND layout`)
   - after a tab switch and back
   - after `$ND relaunch`
   - on the other platform, if it was affected
4. **No new errors:** `$ND log` shows no new JS or console errors and no failing requests.
5. **Web regression:** check the same page in a desktop browser (Playwright, as in `/bug-hunt-fix`
   Step 10). If the change affected web markup, check that the web layout is unchanged.
6. **Regression test when it's expressible in a browser:** add a scenario to
   `spec/system/staff/native_app_spec.rb` (`native: true`: Playwright WebKit at iPhone size with the
   Hotwire Native User-Agent and a fake bridge adapter, `spec/support/native_app_helpers.rb`).
   Page overflow is testable there, e.g. `expect_every_control_reachable`, and so are bridge
   messages (`wait_for_native_bridge_message`, `reply_to_native_bridge`). Browser specs can't
   reproduce the shell's own chrome or keyboard, so for those write down the manual `nd layout`
   check in the bug file instead of a weak test.
   **Prove the test catches the bug:** set just the fix aside, run the new example and see it fail,
   then restore the fix. The stash stack is shared between worktrees, so use a tagged stash:
   `git stash push -m <tag> -- <fixed files>`, then `git stash apply <sha>` and drop that entry.
7. Run the specs you touched, then `bin/standardrb`.

If verification fails, go back to Phase 2 with what you measured; don't stack guesses.

## Phase 5: Document and Clean Up

Append to the bug file. This is the only edit allowed in `docs/bug-reports/`:

```markdown
---

## Fix Applied

**Date:** [date]
**Status:** VERIFIED FIXED | FIXED — ONE PLATFORM UNVERIFIED | NOT FIXED

### Root Cause
[One or two sentences]

### Changes Made
- [file]: [what changed]

### Verification
| Check | Android emulator | iOS Simulator |
|---|---|---|
| Reproduced before fix | ✅ [evidence] | ✅ / not tested |
| Fixed after relaunch | ✅ [before → after numbers] | ✅ / not tested |
| Keyboard open / tab switch / relaunch | ✅ | … |
| No new JS/console errors or failed requests (`nd log`) | ✅ | … |
| Web page unchanged (Playwright) | ✅ | n/a |
| Bridge messages (if bridge touched) | ✅ [`nd eval` evidence] | ✅ / not tested |
| Regression test | [spec:line, or "manual check: …" and why] | |
```

Mark a platform "not tested" honestly. A bug verified on only one of the two affected platforms is
**FIXED — ONE PLATFORM UNVERIFIED**; one that only reproduces on a physical device stays so until
the user confirms it there.

Clean up:
- Delete `tmp/native_debug/fix/` and any Playwright screenshots.
- Close the browser if you opened it.
- Don't commit, matching `/bug-hunt-fix` and `/fix-bug-index`.
