---
name: native-bug-hunt-fix
description: Fix a bug found by /native-bug-hunt in the Ruby Native app and verify the fix on the Android emulator (and on the iPhone, with the user tapping) using the nd helper and dev-only debug beacon. Use whenever the user hands over a docs/bug-reports/native-*/BUG-*.md file, or asks to fix a native-app, Ruby Native, emulator or iPhone-app bug.
argument-hint: <path-to-native-bug-file.md>
---

# Native Bug Hunt Fix

Fix one bug from a `/native-bug-hunt` report and prove it's fixed **inside the native app**, not
just in a browser. This is `/bug-hunt-fix` for the Ruby Native app; follow that skill's phases
(analysis → plan → implement → verify → document). This file covers what changes because the bug
lives in a WebView wrapped in native chrome.

## Bug File
$ARGUMENTS

## Tools

`ND=.claude/skills/native-bug-hunt/scripts/nd` (run it with no arguments for usage). It drives the
Android emulator through adb and talks to the dev-only debug beacon
(`lib/dev/native_debug_middleware.rb` + `app/javascript/native_debug.js`), which works on the
iPhone too:

| Need | Command |
|---|---|
| Run JavaScript in the live page, read state or measurements | `$ND eval 'return …'` (helpers: `__nativeDebug.rects(sel)`, `.dom(sel)`, `.layout()`) |
| Controls cut off by the viewport, safe-area insets, viewport height | `$ND layout` |
| Tap by CSS selector, or native chrome by device pixels | `$ND tap '<sel>' [n]` / `$ND tapxy X Y` (bounds from `$ND native`) |
| Type, keys, screenshot | `$ND type`, `$ND key escape\|back\|enter`, `$ND shot <png>` |
| Navbar, tab bar, badges, dialogs | `$ND native` |
| JS and console errors, layout history, request statuses | `$ND log [n]` |
| Reload the app from scratch | `$ND relaunch` |

## Phase 1: Understand and Reproduce Before Touching Code

1. **Read the bug file.** Note the **Platform** (Android or iPhone), app version, user, path,
   reproduction steps, screenshots and any `nd log` or `nd layout` output quoted in it.
2. **Set up the app** using the **Prerequisites** and **Sign In** sections of
   `.claude/skills/native-bug-hunt/SKILL.md`: base URL, `DEFAULT_ORG_SUBDOMAIN=<org-subdomain>`, emulator and
   app installed, **the user starts the tunnel** (Claude can't), `nd url`, sign in as the report's
   user.
3. **Reproduce it on the reported platform** by following the report's steps through the app's UI
   (tabs, list rows, navbar buttons), the way a user would.
   - Record the evidence you'll compare against later: `$ND layout` numbers, `$ND native` output,
     the offending `$ND log` lines, and a screenshot. Save screenshots to `tmp/native_debug/fix/`,
     never to `docs/bug-reports/`.
   - For an **iPhone** report, ask the user for one action per message and read `$ND log` /
     `$ND eval` after each one.
   - Also try the **other platform** when you can (Android is always available to you). Knowing
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
- **Native signals:** hidden `data-native-*` elements rendered through the ruby_native helpers.
  A mistyped or duplicated signal fails silently. Run
  `bundle exec ruby_native check --paths=app/views,app/components`.
- **Insets and viewport:** the gem stylesheet (`stylesheet_link_tag :ruby_native`) sets
  `--ruby-native-safe-area-*` and the `native-inset*` classes; the app sets the viewport height,
  which changes when the keyboard opens. `h-dvh` / `100vh` interact with the native tab bar and
  navbar differently from a browser. Compare `$ND layout` numbers rather than guessing.
- **Which paths render natively:** `NativeMode::NATIVE_STAFF_PATHS` in
  `app/controllers/concerns/native_mode.rb`. Anything else shows **Open in browser**.
- **App config:** `config/ruby_native.yml` (tabs, advanced mode, appearance, linked paths). The app
  reads it on launch.
- **Navigation and redirects:** in advanced mode the app pushes and pops screens, presents
  `/new` and `/edit` as sheets, and switches tabs for links that belong to another tab. The
  request sequence in `$ND log` shows redirect bounces (e.g. `sign_in 302 → /staff/conversations`).

**When the page is taller than the screen** (`scrollHeight > innerHeight`, controls under the tab
bar), find out which element adds the height before blaming insets. Measure the chain down from
`main`:
`$ND eval 'return Array.from(document.querySelector("main").children).map(c => [c.tagName, c.className.toString().slice(0, 50), c.getBoundingClientRect().height])'`.
If the children don't add up to the parent's height, the gap is usually an empty **line box**: an
`inline-block` element (like `button_to`'s form) takes a full `line-height` line even when its
contents are hidden. In the first real run this was the whole bug, and its 24 px happened to equal
the Android safe area, which made insets look guilty.

Use `$ND eval` to test a hypothesis in the live page before writing code, e.g. apply a candidate
style and re-measure:
`$ND eval 'const s = document.querySelector(".native-inset-bottom"); s.classList.replace("h-dvh", "h-full"); return __nativeDebug.layout().offscreenInteractive'`.
Changes made this way last only until the next page load, so they're safe to experiment with.

## Phase 3: Plan and Implement

Follow `/bug-hunt-fix` Steps 4–6: a minimal, targeted change that follows repo conventions, then
`bin/standardrb --fix`. Use `/frontend-expert` for real front-end work (new markup, component,
Stimulus or JS changes); a one-line wrapper or class change doesn't need it.

Native-specific rules:
- **Don't break the web.** Most native markup shares a component with the browser version. Keep
  the fix inside the `native_app?` / `native:` branch unless the web has the same bug, and say
  which you chose.
- **Tailwind only**, with theme colors. The gem's `native-inset*` classes and CSS variables are
  the sanctioned way to handle safe areas.
- If you touched signals, rerun `ruby_native check`.

## Phase 4: Verify in the App

1. **Load the new code in the app.** The WebView caches pages and assets, so run `$ND relaunch`
   (on iOS, ask the user to swipe the app away and reopen it). `bin/dev` rebuilds Tailwind
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
   `spec/system/staff/native_app_spec.rb` using its `enter_native_app` helper (Ruby Native user
   agent under Playwright). Page overflow is testable there, e.g.
   `document.documentElement.scrollHeight - window.innerHeight <= 0`. Browser specs can't reproduce
   the native tab bar or safe-area insets, so for pure inset bugs, write down the manual `nd layout`
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
**Status:** VERIFIED FIXED | FIXED — iOS UNVERIFIED | NOT FIXED

### Root Cause
[One or two sentences]

### Changes Made
- [file]: [what changed]

### Verification
| Check | Android emulator | iPhone |
|---|---|---|
| Reproduced before fix | ✅ [evidence] | ✅ / not tested |
| Fixed after relaunch | ✅ [before → after numbers] | ✅ / not tested |
| Keyboard open / tab switch / relaunch | ✅ | … |
| No new JS/console errors or failed requests (`nd log`) | ✅ | … |
| Web page unchanged (Playwright) | ✅ | n/a |
| `ruby_native check` (if signals touched) | ✅ | n/a |
| Regression test | [spec:line, or "manual check: …" and why] | |
```

Mark a platform "not tested" honestly. An iPhone-reported bug verified only on Android is
**FIXED — iOS UNVERIFIED** until the user confirms it on the phone.

Clean up:
- Delete `tmp/native_debug/fix/` and any Playwright screenshots.
- Close the browser if you opened it.
- Remind the user they can stop the tunnel.
- Don't commit, matching `/bug-hunt-fix` and `/fix-bug-index`.
