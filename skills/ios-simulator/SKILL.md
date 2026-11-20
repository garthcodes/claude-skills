---
name: ios-simulator
description: Boot an iOS simulator, build the Hotwire Native iOS shell (native/ios), install it and launch it — the "<App> Dev" build against this checkout's local `bin/dev` server by default, or the store "<App>" build against production for a quick look. Use when the user wants to open, run or test the iOS app on a simulator, including the on-device cache probe.
argument-hint: "[development|production] [device name, default \"iPhone 17\"] [--no-build]"
allowed-tools: Bash(xcrun simctl:*), Bash(xcodebuild:*), Bash(xcodegen:*), Bash(open:*), Bash(ls:*), Bash(find:*), Bash(grep:*), Bash(curl:*), Bash(mkcert:*), Bash(bin/dev-url:*), Bash(axe:*)
---

# Open the iOS app in a simulator

Arguments: `$ARGUMENTS`

- **Build** — `development` (default) or `production`.
- **Device** — any name from `xcrun simctl list devices available`; default `iPhone 17`.
- **`--no-build`** — skip the build and relaunch whatever is already installed.

| Build         | Scheme     | Configuration | App bundle     | Bundle ID                     | Server                                    |
|---------------|------------|---------------|----------------|-------------------------------|-------------------------------------------|
| `development` | `<App> Dev` | `Debug-Dev`   | `<App> Dev.app` | `com.example.app.dev` | this checkout's `bin/dev` (`bin/dev-url`) |
| `production`  | `<App>`    | `Debug`       | `<App>.app`     | `com.example.app`     | `https://<app-host>`          |

There is no staging build. Run every command from the repo root of the current checkout. Stop and report at the first failing step — do not work around it.

## 1. Preflight

1. `native/ios/project.yml` must exist. If not, this checkout has no iOS shell — say so and stop.
2. `xcrun simctl list runtimes` must list an iOS runtime. If none, tell the user to run `xcodebuild -downloadPlatform iOS` (large download, their call) and stop.
3. Confirm the device name appears in `xcrun simctl list devices available`. If it does not, list the available iPhones and ask which to use.
4. **development**: `BASE_URL=$(bin/dev-url)`, then `curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/up"` must print `200`. If not, tell the user to start `bin/dev` in this checkout and stop — never start it yourself.
5. **production**: warn in one line that the app talks to **live production**; proceed only if the user asked for production explicitly, and never sign in for them.

## 2. Boot the simulator

```bash
xcrun simctl boot "<device>" 2>/dev/null || true   # "already booted" is fine
xcrun simctl bootstatus "<device>" -b
open -a Simulator 2>/dev/null || true             # optional window for the user; AXe works headless
```

**development** only — trust the mkcert root CA that signs the `bin/dev` certificate (idempotent). The simulator shares the Mac's network, so `<org-subdomain>.<dev-host>` reaches `bin/dev` directly — no tunnel:

```bash
xcrun simctl keychain "<device>" add-root-cert "$(mkcert -CAROOT)/rootCA.pem"
```

## 3. Build (skip with `--no-build`)

If `native/ios/project.yml` is newer than `native/ios/<App>.xcodeproj/project.pbxproj`, run `(cd native/ios && xcodegen generate)` first. It regenerates `<App>/Info.plist` from `project.yml`'s `info.properties` — expected.

```bash
xcodebuild -project native/ios/<App>.xcodeproj -scheme "<scheme>" -configuration "<configuration>" \
  -destination 'platform=iOS Simulator,name=<device>' \
  -derivedDataPath native/ios/build build -quiet \
  APP_BASE_URL="$BASE_URL"          # development only; omit for production
```

`native/ios/build/` is gitignored. `IDELogStore … LogStoreManifest.plist` lines on a fresh build folder are noise. On a real failure, show the `error:` lines and stop.

## 4. Install and launch

```bash
xcrun simctl install "<device>" "native/ios/build/Build/Products/<configuration>-iphonesimulator/<app bundle>"
xcrun simctl launch "<device>" <bundle-id>
```

The first development load takes several seconds (importmap serves every controller unbundled). The app asks for notification permission once signed in (the `push-registration` bridge component); the simulator gets no APNs token from a dev build, so nothing is registered.

## 5. Drive the app (AXe)

`axe` (`brew install cameroncooke/axe/axe`, needs Xcode 26.6+) taps and types in the simulator without Accessibility permissions. Get the UDID from `axe list-simulators` or `xcrun simctl list devices booted`.

```bash
axe screenshot --udid <udid> --output <scratchpad>/screen.png     # then Read the PNG
axe tap -x <pt-x> -y <pt-y> --udid <udid>                         # coordinates in POINTS
axe type 'therapist@example.com' --udid <udid>
axe tap --label Allow --udid <udid>                               # native alerts / chrome only
axe describe-ui --udid <udid>                                     # tab bar, nav bar buttons, menus
```

- The WebView's HTML is not in `axe describe-ui`; locate web elements from the screenshot, or use the debug beacon (`.claude/skills/native-bug-hunt/scripts/nd eval|tap|layout|log` — it answers the simulator too). Points = screenshot pixels ÷ 3 on iPhone 17 (1206×2622 px ↔ 402×874 pt).
- Native chrome (tabs Messages / Channels / Search, the New message button, the More menu with Sign out) is in `axe describe-ui`.
- Re-screenshot after typing — the keyboard scrolls the page and moves the next target.
- Local dev accounts: `therapist@example.com`, `admin@example.com`. In development the sign-in page shows a **Sign in now** shortcut after **Send Magic Link**, so no email is needed. Sign in only against development — never production.

## 6. Report

Tell the user, in a few lines:
- which device is up, and which build is running against which server;
- sign in inside the app with the **sign-in code** or dev's **Sign in now** (a magic link tapped in the simulator's Mail/Safari does not open the Dev build — Universal Links point at the production host);
- after a server-side change, pull to refresh or relaunch; rebuild only after Swift / `project.yml` changes (`--no-build` otherwise). A path-configuration change also needs the bundled copy regenerated (`native/README.md`);
- handy follow-ups (`-a` is required: WebKit's cache files are binary, and the shell's `grep` wrapper skips binaries without it — control with `grep -rla '<org-subdomain>.<dev-host>'`, which must match):

```bash
xcrun simctl terminate "<device>" <bundle-id>                                  # force-quit
xcrun simctl get_app_container "<device>" <bundle-id> data                      # app data dir
grep -rla 'cache-probe-7f3a' "$(xcrun simctl get_app_container "<device>" <bundle-id> data)"  # cache probe — must print nothing
xcrun simctl shutdown "<device>"                                                # done
```
