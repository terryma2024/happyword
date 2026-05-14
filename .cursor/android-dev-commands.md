# Android dev commands manifest (source of truth)

> For the per-feature lifecycle (HarmonyOS-first design, stabilization gate, parallel iOS/Android replication, parity checklist), see [`docs/sop/00-three-platform-feature-sop.md`](../docs/sop/00-three-platform-feature-sop.md). This manifest only owns Android commands.

Read this file before running Android build, test, install, emulator, screenshot,
or logcat commands. It is the Android companion to `.cursor/ohos-dev-commands.md`
for HarmonyOS.

- **last_verified_android_studio:** (fill when confirmed)
- **repo_root:** repository root (`<repo-root>`)
- **android_project_root:** `android/` (where `settings.gradle.kts`, `gradlew`,
  `local.properties`, and `app/build.gradle.kts` live)
- **package:** `cool.happyword.wordmagic`
- **main_activity:** `cool.happyword.wordmagic/.MainActivity`
- **stack:** Kotlin / Jetpack Compose / Gradle Android Plugin

## Conventions

- Run Gradle commands from **android_project_root** (`android/`) using the
  checked-in wrapper: `./gradlew ...`.
- Prefer debug builds unless a task explicitly asks for release behavior.
- Use Android Studio for emulator/device management when convenient, but record
  the equivalent shell commands here after discovering them.
- Keep native Android work under `android/`. Do not add shared client runtime
  under `shared/`; only consume contracts/fixtures from there when needed.
- For feature work and bugfixes, follow the applicable Superpowers workflow
  before implementation. For behavior changes, write/update tests first.
- If multiple devices are attached, pass `-s <serial>` to **`adb` only** — do
  **not** append `-s <serial>` after `./gradlew` (Gradle treats extra tokens as
  task names; see **Targeting `installDebug`** under §2 Build).
- Generated build output under `android/.gradle/`, `android/app/build/`, and
  local IDE state must not be treated as source changes.

**Phase order (autofix loop):** unit test/compile -> assemble -> emulator UI
test -> install -> manual screenshot/logcat verification.

---

## 1) Environment — `android-env-check`

| Step | Command | Success signal |
|------|---------|----------------|
| Check Java | `cd android && ./gradlew -version` | Shows JVM 17+ and Gradle version |
| Check Android SDK | `cd android && ./gradlew :app:tasks --all` | Gradle configures without SDK errors |
| List emulators/devices | `$ANDROID_HOME/platform-tools/adb devices` | At least one `device` row when an emulator/device is ready |
| Show emulator resolution | `$ANDROID_HOME/platform-tools/adb -s <serial> shell wm size` | Prints physical size |

**JDK:** use Android Studio's bundled JBR 17 when possible. If local Gradle
cannot find Java, add this local-only entry to `android/local.properties`:

```properties
org.gradle.java.home=/Applications/Android Studio.app/Contents/jbr/Contents/Home
```

Do not commit machine-specific absolute SDK/JDK paths unless they are already
intentionally tracked for the local worktree.

---

## 2) Build — `android-build`

| Step | Command | Success signal |
|------|---------|----------------|
| Compile + unit tests | `cd android && ./gradlew testDebugUnitTest` | `BUILD SUCCESSFUL`; Kotlin compiles; JVM tests pass |
| Assemble debug APK | `cd android && ./gradlew assembleDebug` | APK under `android/app/build/outputs/apk/debug/app-debug.apk` |
| Install debug APK | `cd android && ./gradlew installDebug` (or `:app:installDebug`) | Installs on the selected device; see **Targeting `installDebug`** below when more than one device is online |
| Launch app | `$ANDROID_HOME/platform-tools/adb -s <serial> shell am start -n cool.happyword.wordmagic/.MainActivity` | Activity starts on target |

**Targeting `installDebug` to one emulator (Gradle pitfall):**

- **Wrong:** `./gradlew :app:installDebug -s emulator-5556` — Gradle does **not**
  accept `adb`'s `-s` flag here. Extra words are interpreted as **Gradle task
  names**, which fails with `Task 'emulator-5556' not found in root project ...`.
- **Right:** set the serial for the whole command environment, then run Gradle:
  `export ANDROID_SERIAL=emulator-5556` (zsh/bash) then
  `cd android && ./gradlew :app:installDebug`. The Android Gradle Plugin uses the
  same device selection as `adb` when `ANDROID_SERIAL` is set.
- If **exactly one** `device` row appears in `adb devices`, plain
  `./gradlew installDebug` is enough (no `ANDROID_SERIAL` needed).

**Working directory:** `android/` for Gradle; any directory for `adb`.

**Compile warnings:** Kotlin warnings should be treated as actionable when they
come from files touched in the current task. Do not leave new warnings in files
you changed.

---

## 3) Unit tests — `android-unit-test`

**Scope:** `android/app/src/test/**` JVM tests. No emulator required.

| Command | Success signal |
|---------|----------------|
| `cd android && ./gradlew testDebugUnitTest` | Exit 0; report under `android/app/build/reports/tests/testDebugUnitTest/` |

Current core tests cover `BattleEngine`, `GameConfig`, app metadata, and parent
PIN behavior. Add tests here for state-machine, scoring, option ordering, and
other non-UI logic.

**TDD rule:** for a bugfix, write or update a failing test first, verify it
fails for the expected reason, then implement the fix.

---

## 4) Emulator / device — `android-emulator-manage`

| Step | Command | Success signal |
|------|---------|----------------|
| List devices | `$ANDROID_HOME/platform-tools/adb devices` | Online emulator row such as `emulator-5556 device` |
| Handle multiple devices (`adb`) | `$ANDROID_HOME/platform-tools/adb -s <serial> ...` | Command targets the intended device |
| Install via Gradle when multiple devices | `export ANDROID_SERIAL=<serial> && cd android && ./gradlew :app:installDebug` | Same as §2 — **never** `./gradlew ... -s <serial>` |
| Start app | `$ANDROID_HOME/platform-tools/adb -s <serial> shell am start -n cool.happyword.wordmagic/.MainActivity` | App visible |
| Force-stop app | `$ANDROID_HOME/platform-tools/adb -s <serial> shell am force-stop cool.happyword.wordmagic` | Exit 0 |

**Common device state issue:** an old emulator may appear as `offline`. Do not
target it. Use the online serial from `adb devices`, or restart the emulator
from Android Studio.

**Current manual convention:** when `adb` reports more than one device/emulator,
prefer the online AVD serial. Use **`export ANDROID_SERIAL=<serial>`** before
`./gradlew installDebug` / `connectedDebugAndroidTest`, and pass **`-s <serial>`**
only on **`adb`** shell commands (e.g. `am start`, `logcat`, `input`).

**Reuse existing emulators (preferred):**

- Prefer **already running** emulators from `adb devices` (look for
  `emulator-#### device`). Set `ANDROID_SERIAL` to that serial for Gradle install /
  UI tests instead of launching another VM.
- **Do not** start a second emulator from the **same AVD** unless you intentionally
  run **every** concurrent instance with **`-read-only`**. Otherwise the emulator
  exits with *Another emulator instance is running* / *run all emulators with
  -read-only flag*. For normal install-and-try flows, **reuse the existing window**.
- To push one built APK to **two devices that are already online** (two serials,
  or emulator + physical), run **`assembleDebug` once**, then
  `adb -s <serial> install -r app/build/outputs/apk/debug/app-debug.apk` per target
  — still never `./gradlew … -s <serial>`.

---

## 5) Instrumented UI tests — `android-ui-test`

**Scope:** `android/app/src/androidTest/**` using Compose UI test.

| Command | Success signal |
|---------|----------------|
| `cd android && ./gradlew connectedDebugAndroidTest` | `BUILD SUCCESSFUL`, console shows tests finished on target |

Current smoke tests cover:

- Home renders and battle can be opened.
- Battle page uses English labels and countdown.
- Battle advances to the next word after answering.

When option order is randomized, UI tests must click by visible answer text
when they care about correctness. Do not assume `BattleAnswer_0` is the correct
answer.

---

## 6) Manual QA commands — `android-manual-qa`

**Human confirmation handoff:** when the user asks to manually confirm the
Android build, leave the emulator/device online and keep the app installed
after verification. Do not run `adb emu kill`, wipe emulator data, or uninstall
the app unless the user explicitly asks for cleanup.

| Goal | Command |
|------|---------|
| Tap screen | `$ANDROID_HOME/platform-tools/adb -s <serial> shell input tap <x> <y>` |
| Dump UI hierarchy | `$ANDROID_HOME/platform-tools/adb -s <serial> shell uiautomator dump /sdcard/window.xml` |
| Read UI hierarchy | `$ANDROID_HOME/platform-tools/adb -s <serial> exec-out cat /sdcard/window.xml` |
| Screenshot to file | `$ANDROID_HOME/platform-tools/adb -s <serial> exec-out screencap -p > assets/screenshots/android/<name>.png` |
| Device-side delayed screenshot | `$ANDROID_HOME/platform-tools/adb -s <serial> shell "input tap <x> <y> && sleep 0.2 && screencap -p /sdcard/frame.png"` then `adb -s <serial> exec-out cat /sdcard/frame.png > assets/screenshots/android/<name>.png` |
| Clear logcat | `$ANDROID_HOME/platform-tools/adb -s <serial> logcat -c` |
| Read filtered logcat | `$ANDROID_HOME/platform-tools/adb -s <serial> logcat -d \| rg -i "WordMagic|TextToSpeech|MediaPlayer|AndroidRuntime|Exception"` |

**Screenshot policy for UI replica work:** after significant visual changes,
install and screenshot on the Android emulator. Compare against the relevant
HarmonyOS screenshot under `assets/screenshots/harmonyos/` and refine until the
layout and style are close enough for the current milestone.

### Parity-scout pointer

For finding Android gaps vs HarmonyOS `main`, run via the `parity-scout` skill. CLI cheat-sheet: [`tools/parity_scout/README.md`](../tools/parity_scout/README.md). Skill: [`.cursor/skills/parity-scout/SKILL.md`](skills/parity-scout/SKILL.md).

---

## 7) Battle page debug notes — `android-battle-debug`

Battle is currently native Compose, not a Cocos scene. Keep visual/gameplay
logic small and local until a later Cocos battle-layer migration is explicitly
planned.

Important behavior to preserve:

- Battle page is fixed landscape.
- Parent/admin pages are fixed portrait.
- Battle UI labels are English.
- Home adventure card uses English region names.
- Answer options are randomized per question; tests must not rely on fixed
  option positions.
- TTS should pronounce the current English word on question switch and speaker
  tap.
- Battle effects follow four outcome paths:
  - normal correct: green selected button, forward projectile, mage fight pose,
    monster hit flash, `hit_normal`
  - wrong: red selected button, reveal correct answer, reverse projectile,
    mage beaten pose, `answer_wrong` + `player_hurt`
  - combo burst: every third consecutive correct answer deals 2 damage, gold
    projectile, crit overlay, `hit_crit`
  - monster defeat: normal/crit hit first, then `monster_defeat` if battle
    continues

### TTS debugging

Android uses platform `TextToSpeech`, but emulator playback can be muted if the
Google TTS service tries to play audio as a background service. The current app
therefore uses:

1. `TextToSpeech.synthesizeToFile(...)` to create a temporary WAV in app cache.
2. App-local `MediaPlayer` to play that WAV through the same audible path as
   battle SFX.

Useful checks:

| Check | Command |
|-------|---------|
| Installed TTS packages | `$ANDROID_HOME/platform-tools/adb -s <serial> shell pm list packages \| rg -i "tts|speech|googlequicksearch|pico"` |
| Default TTS engine | `$ANDROID_HOME/platform-tools/adb -s <serial> shell settings get secure tts_default_synth` |
| TTS/audio logs | `$ANDROID_HOME/platform-tools/adb -s <serial> logcat -d \| rg -i "WordMagicTTS|GoogleTTSServiceImpl|TextToSpeech|AudioHardening|MediaPlayer|TTS dispatch"` |

If logs show synthesis success but no sound, check emulator media volume and
host audio first. If logs show `WordMagicTTS` errors, fix the synthesis path.

---

## 8) Assets — `android-assets`

Android runtime assets live under:

- SVG characters: `android/app/src/main/res/raw/character_*.svg`
- Battle SFX: `android/app/src/main/res/raw/*.ogg`
- App/icons: `android/app/src/main/res/drawable/`

Reuse HarmonyOS assets when replicating:

- Harmony source assets: `harmonyos/entry/src/main/resources/rawfile/`
- Design/source backups: `assets/`

**Asset retention policy:** never delete SVG/PNG/audio/font/source assets just
because runtime code stopped referencing them. Move retired resource files under
`assets/<category>/` and add a short README entry when needed.

---

## 9) Failure artifacts — `android-log-analyzer`

Read in this order:

1. Last 200-400 lines of the failing Gradle command.
2. Unit test reports: `android/app/build/reports/tests/testDebugUnitTest/`.
3. Instrumented test reports/results under `android/app/build/reports/androidTests/`
   and `android/app/build/outputs/androidTest-results/`.
4. Device logs after reproduction:
   `$ANDROID_HOME/platform-tools/adb -s <serial> logcat -d`.
5. UI hierarchy if a tap or Compose node cannot be found:
   `uiautomator dump` + `exec-out cat`.
6. Screenshot under `assets/screenshots/android/` for visual regressions.

When a failure depends on a particular emulator/device, record:

- serial from `adb devices`
- `wm size`
- API level / AVD name if visible in Gradle output
- exact command used to reproduce

---

## 10) Release readiness checklist — `android-ready`

Before claiming an Android change is complete:

- `cd android && ./gradlew testDebugUnitTest`
- `cd android && ./gradlew connectedDebugAndroidTest` for UI-visible changes
- `cd android && ./gradlew assembleDebug` or an equivalent command that proves
  the APK builds
- `cd android && ./gradlew installDebug` when user needs to manually try it
- screenshot/logcat evidence for visual/audio/device-specific work

Do not claim completion from code inspection alone.

---

## 11) Local growth verification — `android-local-growth`

After touching PackManager, Wishlist, RedemptionHistory, MonsterCodex,
TodayPlan, LearningReport, local pack state, coins, or learning stats:

- `cd android && ./gradlew testDebugUnitTest`
- `cd android && ./gradlew assembleDebug`
- `cd android && ./gradlew connectedDebugAndroidTest`
- `cd android && ./gradlew installDebug`

Screenshot refresh command sequence:

```sh
cd android && ./gradlew installDebug installDebugAndroidTest
$ANDROID_HOME/platform-tools/adb shell am instrument -w \
  -e class cool.happyword.wordmagic.AndroidScreenScreenshotTest \
  cool.happyword.wordmagic.test/androidx.test.runner.AndroidJUnitRunner
cd ..
for f in local-growth-home.png pack-manager.png wishlist.png \
  redemption-history.png monster-codex.png today-plan.png learning-report.png \
  scan-binding.png bound-device-info.png config-landscape.png \
  parent-pin-portrait.png parent-admin.png lesson-review-portrait.png \
  dev-menu-debug.png bypass-secret-debug.png result.png; do
  $ANDROID_HOME/platform-tools/adb exec-out run-as cool.happyword.wordmagic \
    cat files/screenshots/$f > assets/screenshots/android/$f
done
```

Compare refreshed Android screenshots with the HarmonyOS references named in
`docs/superpowers/specs/2026-05-11-android-replica-phase2-local-growth-pack-design.md`.

---

## 12) Cloud/binding verification — `android-cloud-binding`

After touching ScanBinding, BoundDeviceInfo, cloud credentials, pack sync, or
word-stats sync:

- `cd android && ./gradlew testDebugUnitTest`
- `cd android && ./gradlew assembleDebug`
- `cd android && ./gradlew connectedDebugAndroidTest`

The screenshot test also captures:

- `assets/screenshots/android/scan-binding.png`
- `assets/screenshots/android/bound-device-info.png`

Cloud integration rules:

- Child play must continue when sync fails.
- Device token must stay out of normal SharedPreferences.
- Unbind clears cloud credentials but keeps local packs, coins, and learning
  progress.

---

## 13) Debug routing verification — `android-debug-routing`

After touching DevMenu, BypassSecret, preview manifest, backend URL provider, or
debug-only **home version label** (triple-tap) entry:

- `cd android && ./gradlew testDebugUnitTest`
- `cd android && ./gradlew assembleDebug`
- `cd android && ./gradlew connectedDebugAndroidTest`

Release gating rule:

- Debug builds may show **`HomeVersionLabel`** (version line) and DevMenu when triple-tapped.
- Release builds must not show DevMenu, BypassSecret, preview bypass entry, or
  mock routing UI.

---

## 14) Release hardening — `android-release-hardening`

After touching screenshot parity gates, release/debug visibility, offline
fallbacks, fixture/contract mapping, or Android release-readiness docs:

- `cd android && ./gradlew testDebugUnitTest`
- `cd android && ./gradlew assembleDebug`
- `cd android && ./gradlew connectedDebugAndroidTest`
- `cd android && ./gradlew assembleRelease`

Phase 5 policy checks:

- `BuildGate.showDeveloperTools(false)` must hide debug-only developer surfaces
  (e.g. `HomeVersionLabel`, DevMenu entry points) in release-style paths.
- Production routing must not attach `x-vercel-protection-bypass`, even if a
  debug device has a local secret saved.
- Failed global/family pack sync must keep bundled packs playable.
- Failed word-stats sync must not block Result or local learning progress.
- Shared fixtures under `shared/fixtures/` must pass
  `SharedFixtureCompatibilityTest`.
- Screenshot baselines live under `assets/screenshots/android/`; keep HarmonyOS
  reference images unchanged.
- Release readiness checklist:
  `docs/android-replica/07-release-readiness-checklist.md`.

If `assembleRelease` fails because release signing is not configured, record
the exact signing/configuration gap in the handoff. Do not treat code
inspection as a release gate.
