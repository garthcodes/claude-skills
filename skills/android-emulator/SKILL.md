---
name: android-emulator
description: Start an Android emulator, build the Hotwire Native Android shell (native/android), install it and launch it — the `development` flavor ("<App> Dev") against this checkout's local `bin/dev` server by default, or the `production` flavor against production for a quick look. Use when the user wants to open, run or test the Android app on an emulator, including the file-picker check and the on-device cache probe.
argument-hint: "[development|production] [AVD name, default Medium_Phone_API_36.0] [--no-build]"
allowed-tools: Bash(adb:*), Bash(emulator:*), Bash(ls:*), Bash(grep:*), Bash(curl:*), Bash(mkcert:*), Bash(bin/dev-url:*), Bash(./gradlew:*)
---

# Open the Android app in an emulator

Arguments: `$ARGUMENTS`

- **Flavor** — `development` (default) or `production`.
- **AVD** — any name from `$ANDROID_HOME/emulator/emulator -list-avds`; default `Medium_Phone_API_36.0`.
- **`--no-build`** — skip the build and relaunch whatever is already installed.

| Flavor        | Gradle install task       | Application ID                | Server                                    |
|---------------|---------------------------|-------------------------------|-------------------------------------------|
| `development` | `installDevelopmentDebug` | `com.example.app.dev` | this checkout's `bin/dev` (`bin/dev-url`) |
| `production`  | `installProductionDebug`  | `com.example.app`     | `https://<app-host>`          |

There is no staging flavor. Run every command from the repo root of the current checkout. Stop and report at the first failing step — do not work around it. For an unattended shell checklist on top of this, the user can run `bin/native-qa`.

## 1. Preflight

1. `native/android/app/build.gradle.kts` must exist. If not, this checkout has no Android shell — say so and stop.
2. `$ANDROID_HOME` must be set and `$ANDROID_HOME/emulator/emulator -list-avds` must include the AVD. If not, list the AVDs and ask which to use.
3. **development**: `BASE_URL=$(bin/dev-url)` and `PORT=${BASE_URL##*:}`; `curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/up"` must print `200`. If not, tell the user to start `bin/dev` in this checkout and stop — never start it yourself. `mkcert -CAROOT` must point at a directory holding `rootCA.pem` (the build copies it into the development APK only).
4. **production**: warn in one line that the app talks to **live production**; proceed only if the user asked for production explicitly, and never sign in for them.

## 2. Start the emulator

Skip the launch if `adb devices` already lists an `emulator-*` in `device` state.

```bash
(nohup "$ANDROID_HOME/emulator/emulator" -avd "<avd>" >/dev/null 2>&1 &)
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done
until adb shell ping -c1 -W2 <dev-host> >/dev/null 2>&1; do sleep 2; done   # DNS up — launching earlier shows "Host Lookup"
```

**development** only — the emulator's `127.0.0.1` is the emulator itself; forward the dev port to the Mac (no tunnel; re-run after every emulator restart):

```bash
adb reverse tcp:$PORT tcp:$PORT
```

## 3. Build and install (skip the build with `--no-build`)

```bash
(cd native/android && ./gradlew <install task> -q \
  -PdevBaseUrl="$BASE_URL")      # development only; omit for production
adb shell pm grant <application-id> android.permission.POST_NOTIFICATIONS   # optional: skip the Android 13+ prompt
```

On failure, show the error lines and stop. Without a `google-services.json` (see `native/README.md`) the app builds and runs, but push registration never gets an FCM token.

## 4. Launch

```bash
adb shell am force-stop <application-id>
adb shell monkey -p <application-id> -c android.intent.category.LAUNCHER 1
```

The first development load takes several seconds (importmap serves every controller unbundled). To drive it (taps, typing, screenshots, JavaScript in the page through the debug beacon), use `.claude/skills/native-bug-hunt/scripts/nd`.

## 5. Report

Tell the user, in a few lines:
- which AVD is up, and which flavor is running against which server;
- sign in inside the emulator with the **sign-in code** or dev's **Sign in now** (a magic link opened in Chrome lands in Chrome, not the Dev build); for production never sign in for them;
- after a server-side change, pull to refresh or relaunch; rebuild only after Kotlin / Gradle changes (`--no-build` otherwise). A path-configuration change also needs the bundled copy regenerated (`native/README.md`);
- handy follow-ups:

```bash
adb shell am force-stop <application-id>                                     # force-quit
adb shell run-as <application-id> grep -rl 'cache-probe-7f3a' .              # cache probe — must print nothing (debug builds only)
adb emu kill                                                                 # shut the emulator down
```
