# Cocos Battle Scene — Android Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route the Android client's battle to the shared Cocos scene (shipped on iOS/HarmonyOS in V1.1.0), with native `BattleUi` kept as a switchable/automatic fallback — emulator-only development.

**Architecture:** The Cocos Creator 3.8.8 `android` build output is vendored into the existing `android/app` module (engine Java layer + thin CMake adapter compiling the engine from the Creator-bundle source + generated assets). Battle runs in a separate `CocosBattleActivity` (CocosActivity subclass). Hand-written Kotlin adds contract codecs, a `CocosBattleBridge` adapter around the **functional** `BattleEngine` (adapter owns the `BattleState`), a route decision with preference/fallback, and a Compose config switch. Spec: `docs/superpowers/specs/2026-06-12-cocos-battle-scene-android-design.md`.

**Tech Stack:** Kotlin / Jetpack Compose, Gradle + CMake/NDK, Cocos Creator 3.8.8 (`android` platform), JUnit, arm64 AVD (`Pixel_9_API_36_1_Play` exists; `adb` at `~/Library/Android/sdk/platform-tools/adb`, `emulator` binary under `~/Library/Android/sdk/emulator/`).

**Reference implementations (in-repo, read before porting):**
- HarmonyOS plan (structure twin): `docs/superpowers/plans/2026-06-11-cocos-battle-scene-harmonyos.md`
- ArkTS adapter + tests (sequencing source of truth): `harmonyos/entry/src/main/ets/services/CocosBattleBridge.ets`, `harmonyos/entry/src/test/CocosBattleBridge.test.ets`
- ArkTS codecs: `harmonyos/entry/src/main/ets/services/CocosBridgeMessages.ets`; scene codecs: `cocos/assets/scripts/bridge/messages.ts`
- Build scripts: `tools/cocos/build-harmonyos.sh` (pattern), `cocos/README.md` (all embed recipes + gotchas)
- Contract: `shared/fixtures/cocos-battle-bridge/*.json` (19 files) + `shared/contracts/cocos-battle-bridge/`
- Android engine Java layer source: `/Applications/Cocos/Creator/3.8.8/CocosCreator.app/Contents/Resources/resources/3d/engine/native/cocos/platform/android/java/src/com/cocos/lib/` (incl. `JsbBridgeWrapper.java`)

**Key platform facts:**
- `android/app`: minSdk 26, compile/target 36; navigation in `ui/navigation/WordMagicGameApp.kt` (`AppRoute.Battle -> BattleScreen(...)` at ~line 1000; battle snapshot state in rememberSaveable ~lines 471-473).
- `core/BattleEngine.kt` is FUNCTIONAL: `initialState(): BattleState`, `submitAnswerWithOutcome(state, answer): BattleAnswerOutcome`, `applySpellLetterPenalty(state)/spellLetterPenaltyOutcome(state)`, `resultFor(state): SessionResult`. The adapter owns and threads the state. Read `ui/battle/BattleUi.kt` for how the native screen constructs the engine (question source, config) and settles results.
- Engine prebuilt externals exist for arm64-v8a (and x86 etc.) — build only `arm64-v8a`.

---

## Phase 0 — Embed spike (go/no-go, emulator)

### Task 0.1: build-android.sh + first CLI build + inventory

**Files:**
- Create: `tools/cocos/build-android.sh`

- [ ] **Step 1: Write the script** (clone `tools/cocos/build-harmonyos.sh`'s skeleton — quit editor, CLI build, output verification, NO vendor step yet):

```bash
#!/bin/bash
# Headless Cocos build for the Android embed.
# Produces cocos/build/android/ (gradle template project + data).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CREATOR="/Applications/Cocos/Creator/3.8.8/CocosCreator.app/Contents/MacOS/CocosCreator"

echo "==> quitting Cocos Creator (CLI build requires exclusive project lock)"
osascript -e 'tell application "CocosCreator" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  pgrep -x CocosCreator >/dev/null || break
  sleep 1
done

echo "==> building platform=android"
"$CREATOR" --project "$ROOT/cocos" --build "platform=android" || true
[ -d "$ROOT/cocos/build/android" ] || {
  echo "build output missing; tail of log:" >&2
  tail -40 "$ROOT/cocos/temp/logs/project.log" >&2 || true
  exit 1
}
find "$ROOT/cocos/build/android" -name main.js -path "*data*" | grep -q . || {
  echo "data bundle missing; tail of log:" >&2
  tail -40 "$ROOT/cocos/temp/logs/project.log" >&2
  exit 1
}
echo "==> done; output at cocos/build/android/"
```

- [ ] **Step 2: Run it.** `chmod +x tools/cocos/build-android.sh && tools/cocos/build-android.sh`. If the build fails on missing Android SDK/NDK config: the editor stores program paths in `cocos/settings/v2/packages/program.json` (or global `~/.CocosCreator/profiles/v2/packages/program.json`) — point androidSdk/androidNdk at `~/Library/Android/sdk` and an installed NDK (`ls ~/Library/Android/sdk/ndk/`); if no NDK is installed, install one via `sdkmanager` (find it under `~/Library/Android/sdk/cmdline-tools/*/bin/`). Record every config step. The android platform may also need build params (package name `cool.happyword.wordmagic.cocos` or similar throwaway — it's a template project we never ship) in `cocos/settings/v2/packages/builder.json`; model on how the harmonyos-next/ios entries look if the CLI complains.

- [ ] **Step 3: Inventory the output** (for Task 0.2): where the generated gradle project is, where `com/cocos/lib/*.java` lands, the data/assets dir, the generated `app/build.gradle` native config (externalNativeBuild block, abiFilters, ndkVersion), `AndroidManifest.xml` of the template (activity declaration, orientation, configChanges, metadata), and the CMakeLists chain entry (`-DRES_DIR`, `COMMON_DIR` equivalents).

- [ ] **Step 4: Commit** (script + any cocos/settings changes; build output stays gitignored under `cocos/build/`):

```bash
git add tools/cocos/build-android.sh cocos/settings
git commit -m "Add headless Cocos build script for android"
```
End every commit message in this plan with:

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

### Task 0.2: Vendor engine into android/app + CocosBattleActivity renders on emulator

**Files:**
- Create: `android/app/src/main/cpp/cocos/CMakeLists.txt` (thin adapter)
- Create: `android/app/src/main/java/com/cocos/lib/**` (vendored, via script)
- Create: `android/app/src/main/java/cool/happyword/wordmagic/cocos/CocosBattleActivity.kt`
- Modify: `android/app/build.gradle.kts` (externalNativeBuild, abiFilters, ndkVersion, packaging)
- Modify: `android/app/src/main/AndroidManifest.xml` (activity declaration)
- Modify: `android/app/.gitignore` or root `.gitignore` (assets/cocos generated)
- Modify: `tools/cocos/build-android.sh` (vendor step)

- [ ] **Step 1: Vendor step in the script** (mirror build-harmonyos.sh's `vendor_into_harmonyos`): rsync engine Java layer → `android/app/src/main/java/com/cocos/lib/` (`--delete`, committed), data bundle → `android/app/src/main/assets/cocos/` (gitignored — confirm the asset path CocosActivity expects: read the template's assets layout and `CocosHelper`/native FileUtils-android for the search root; if the engine insists on assets-root `data/` naming, follow the engine, adjust the gitignore entry accordingly, and record it). Scripted sed fix-ups only with grep assertions (BSD sed comment), e.g. if any vendored java hardcodes the template package.
- [ ] **Step 2: CMake adapter** at `android/app/src/main/cpp/cocos/CMakeLists.txt`, modeled line-for-line on `harmonyos/entry/src/main/cpp/CMakeLists.txt` (read it): derive `RES_DIR`/`COMMON_DIR` absolute paths from `CMAKE_CURRENT_LIST_DIR` (RES_DIR → `cocos/build/android`, COMMON_DIR → the generated project's common chain — the android template's equivalent; the generated `proj` dir contains the CMake entry to replicate), `CACHE STRING ... FORCE` (CMP0126 trap comment), fail-fast if `cocos/build/android` missing. NO engine patch (Android needs none).
- [ ] **Step 3: gradle wiring** in `android/app/build.gradle.kts`:

```kotlin
android {
    // inside defaultConfig:
    ndk { abiFilters += "arm64-v8a" }
    externalNativeBuild { cmake { arguments += listOf("-DANDROID_STL=c++_static") } } // match template args exactly
    // top level android block:
    externalNativeBuild { cmake { path = file("src/main/cpp/cocos/CMakeLists.txt") } }
    ndkVersion = "<from template/installed>"
}
```
Copy the EXACT cmake arguments/version from the generated template gradle (inventory from 0.1) — do not guess.
- [ ] **Step 4: CocosBattleActivity** — subclass `com.cocos.lib.CocosActivity`, landscape; manifest entry copied from the template's activity declaration (orientation, configChanges, exported=false, theme). Minimal first version: just renders the scene (the scene's battle/ready goes unanswered — expected).
- [ ] **Step 5: temporary dev entry** — debug-only: in the app's existing debug/dev menu (find it: `grep -rn "DevMenu\|Developer" android/app/src/main/java | head`), add a "CocosLab" button that `startActivity(Intent(ctx, CocosBattleActivity::class.java))`. If no dev menu exists, use a debug-only long-press on the Home version label or an `adb shell am start -n cool.happyword.wordmagic/.cocos.CocosBattleActivity` direct launch (activity exported=false still launchable via am as debuggable) — record the chosen mechanism.
- [ ] **Step 6: Build + emulator render check.** Start emulator if needed (`~/Library/Android/sdk/emulator/emulator -avd Pixel_9_API_36_1_Play -no-snapshot-save &` then `adb wait-for-device`), `cd android && ./gradlew :app:assembleDebug` (first native build compiles the whole engine — expect minutes), `adb install -r app/build/outputs/apk/debug/app-debug.apk`, launch the activity, `adb exec-out screencap -p > /tmp/android_spike.png`, VIEW it (Read tool): battle scene default state (cards + Battle top bar). On crash: `adb logcat -d | grep -E "cocos|FATAL|AndroidRuntime" | tail -40`.
- [ ] **Step 7: Commit** (logical commits; include .so size + first-build duration in the message).

### Task 0.3: Bridge ping/pong + re-entry check (go/no-go)

**Files:**
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/cocos/CocosBattleActivity.kt` (probe hooks, marked temporary)

- [ ] **Step 1: Ping/pong probe.** In the activity (after engine init), register:

```kotlin
val wrapper = JsbBridgeWrapper.getInstance()
wrapper.addScriptEventListener("wmBattleToNative") { json ->
    Log.i("WMBridge", "scene->kotlin $json")
}
// after scene boot (first battle/ready logged), send a probe init:
wrapper.dispatchEventToScript("wmBattleToScript", PROBE_INIT_JSON) // playerMaxHp 7 distinctive
```
Verify on emulator: logcat shows the organic `battle/ready`; after sending init with playerMaxHp 7, screenshot shows HP 7/7 (same proof scheme as the HOS spike). Send `battle/ping`, expect `battle/pong` logged.
- [ ] **Step 2: Re-entry check.** finish() the activity (add a temporary back/finish button or `adb shell input keyevent KEYCODE_BACK`), relaunch it, repeat 3×: must not crash; scene must render and answer a new init each time. Watch logcat for surface/EGL errors. KNOWN RISK: `CocosActivity` may re-run engine init on second launch — if it crashes or double-boots, apply the iOS isBooted pattern: a process-level singleton guard (boot once; later launches reuse; scene reset via battle/init per contract rule 3). Document whichever behavior is observed in cocos/README.md (Android embed section started here).
- [ ] **Step 3: Commit.** This is the feature go/no-go — record the verdict + evidence paths in the commit body.

---

## Phase 1 — Kotlin bridge + routing

### Task 1.1: Contract codecs + 19-fixtures gate

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/cocos/CocosBridgeMessages.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/cocos/CocosBridgeMessagesTest.kt`

- [ ] **Step 1: Failing test.** JVM tests can read repo files directly — locate fixtures via a path walk:

```kotlin
private fun fixturesDir(): File {
    var dir = File(System.getProperty("user.dir"))
    while (!File(dir, "shared/fixtures/cocos-battle-bridge").isDirectory) {
        dir = dir.parentFile ?: error("fixtures dir not found above ${System.getProperty("user.dir")}")
    }
    return File(dir, "shared/fixtures/cocos-battle-bridge")
}

@Test fun decodesOrRoundTripsEveryFixture() {
    val files = fixturesDir().listFiles { f -> f.extension == "json" }!!.sortedBy { it.name }
    assertEquals(19, files.size)
    var processed = 0
    for (f in files) { /* decode scene->native kinds; round-trip native->scene via encoders with key-order-insensitive JSON compare (use org.json or kotlinx.serialization JsonElement equality) */ processed++ }
    assertEquals(files.size, processed)
}
```
Plus focused per-type tests asserting real fixture values (port the case list from `harmonyos/entry/src/test/CocosBridgeMessages.test.ets`). Check what JSON library the app already uses (`grep -rn "kotlinx.serialization\|org.json\|moshi\|gson" android/app/build.gradle.kts android/app/src/main/java | head`) and use THAT.
- [ ] **Step 2: Run to fail:** `cd android && ./gradlew :app:testDebugUnitTest --tests "*CocosBridgeMessages*"`.
- [ ] **Step 3: Implement** `CocosBridgeMessages.kt`: port `CocosBridgeMessages.ets` (envelope `{v:1,type,payload}`, 13 type strings byte-identical, null on any invalid input incl. JSON `null`/`true`, encoders for 7 native→scene types, sealed-class decode for 6 scene→native kinds).
- [ ] **Step 4: Green; full `./gradlew test` still green; commit.**

### Task 1.2: CocosBattleBridge adapter + sequencing tests

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/cocos/CocosBattleBridge.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/cocos/CocosBattleBridgeTest.kt`

- [ ] **Step 1: Seams** (tests need no engine/activity):

```kotlin
interface CocosTransport {
    fun send(json: String)
    fun setHandler(handler: (String) -> Unit)
}
class CocosBattleBridge(
    private val engine: BattleEngine,          // functional — bridge OWNS the BattleState
    initialState: BattleState,
    private val transport: CocosTransport,
    private val callbacks: Callbacks,           // onFinish(SessionResult), playSfx(key), speakWord(word), autoSpeakWord(word, kind), onReady()
    private val scheduler: (delayMs: Long, fn: () -> Unit) -> Cancellable = mainHandlerScheduler,
    private val catalogIndexProvider: (BattleState) -> Int = { it.monsterIndex },
)
```
Adapter state: `private var state: BattleState`, `disposed`, `holdActive`, `finishNotified`, boss-intro bookkeeping (lastBossIntroMonsterIndex + seen catalog set). `dispose()` cancels scheduled closures and inerts handler/sends.
- [ ] **Step 2: Failing tests** — port `CocosBattleBridge.test.ets` case-for-case (FakeTransport + FakeScheduler capturing (delay, fn); engine seeded deterministically — read how `android/app/src/test/.../core/` BattleEngine tests construct question sources). Cases: ready→init+state+question+bossIntro; correct submit→animation(forward)+state then question@650; wrong submit→backward; medium step-advance (if Android engine has the two-step kind — check `submitAnswerWithOutcome` semantics); spellWrongTap penalty; speakAnswer→hook only; escape→finish-once; end→battle/end+finish-once not twice; re-entry second ready → full reset triplet; dispose makes scheduled closures no-ops; duplicate submit during hold dropped (exactly one engine submit).
- [ ] **Step 3: Implement** mirroring the ArkTS adapter's tables, adapted to the functional engine (every engine call returns a new state — assign it). Audio cue moments per native `BattleUi.kt`/`AndroidBattleAudioMixer` (read first; same rule as HOS: native-platform behavior wins where iOS differs).
- [ ] **Step 4: Green; commit.**

### Task 1.3: Preference + route decision + entry points

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/cocos/CocosBattlePreference.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/cocos/CocosBattlePreferenceTest.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/ui/navigation/WordMagicGameApp.kt` (battle entry branch ~line 1000 + wherever navigation to AppRoute.Battle is triggered — grep `AppRoute.Battle`)

- [ ] **Step 1: Failing tests** for the pure decision (identical table to iOS/HOS):

```kotlin
@Test fun decisionTable() {
    assertEquals(BattleRoute.COCOS,  decideBattleRoute(runtimeAvailable = true,  prefEnabled = true,  fallbackActive = false, forceNative = false))
    assertEquals(BattleRoute.NATIVE, decideBattleRoute(true,  false, false, false))
    assertEquals(BattleRoute.NATIVE, decideBattleRoute(false, true,  false, false))
    assertEquals(BattleRoute.NATIVE, decideBattleRoute(true,  true,  true,  false))
    assertEquals(BattleRoute.NATIVE, decideBattleRoute(true,  true,  false, true))
}
```
Plus default-ON semantics for the raw preference mapping (absent → true).
- [ ] **Step 2: Implement**: persistence follows the app's existing config storage (grep how GameConfig persists — SharedPreferences/DataStore; same file), key `battle.useCocosScene`, default true; process-scoped `fallbackActive` (object-level @Volatile var); `forceNative` settable by tests/instrumentation (object var + instrumentation-args read if androidTest needs it — check how existing androidTest launches and inject same-process like the HOS testsuite() did).
- [ ] **Step 3: Route sites.** Where the app navigates to `AppRoute.Battle`: branch — Cocos route launches `CocosBattleActivity` via context.startActivity (battle params passed how BattleScreen receives them today: read the existing flow; the activity/bridge constructs the engine the same way BattleScreen does); native route keeps existing navigation. Keep AppRoute.Battle = native path (fallback target).
- [ ] **Step 4: androidTest guard.** Existing UI tests that drive battles must stay native: set the forced-native flag in the test runner setup (find the shared test base/rule; mirror HOS List.test.ets injection). Verify the androidTest target compiles: `./gradlew :app:assembleDebugAndroidTest`.
- [ ] **Step 5: Green (unit) + commit.**

### Task 1.4: Config switch + activity lifecycle/fallback/result flow

**Files:**
- Modify: config/settings Compose screen (find it: `grep -rn "设置\|Config" android/app/src/main/java/cool/happyword/wordmagic/ui --include="*.kt" -l | head`)
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/cocos/CocosBattleActivity.kt`

- [ ] **Step 1: Config switch row** 「Cocos 战斗场景」 in the battle/audio settings group (reuse the existing switch-row composable; testTag `ConfigCocosBattleSwitch`), bound to CocosBattlePreference (default ON), visible always on Android (runtime is always linked).
- [ ] **Step 2: Activity live wiring**: construct engine + initial state exactly as BattleScreen does (extract a shared factory ONLY if the construction can't be called as-is — zero-behavior extraction allowed, mirror the HOS BattleSessionFactory precedent); wrap JsbBridgeWrapper in a real CocosTransport (GL-thread callback → main thread hop); CocosBattleBridge with audio/TTS hooks per BattleUi parity; 5 s ready watchdog → fallback (set flag, finish activity, navigate native — the Compose side observes the fallback flag or activity result and re-routes); countdown owner (1 s tick → engine tick semantics — read how BattleUi ticks the timer with the functional engine, mirror it + `sendStateTick`); finish flow → settle results the same way BattleUi does (reuse its settlement code path; extraction allowed) → activity result back to Compose → existing result screen; onDestroy → bridge.dispose() + listener removal.
- [ ] **Step 3: Re-entry per Task 0.3 verdict** (singleton guard if needed).
- [ ] **Step 4: Emulator smoke**: switch ON → Cocos battle plays a question; OFF → native BattleUi; ready-timeout simulated (temporarily rename assets dir in a local build) → auto-fallback. Screenshots viewed.
- [ ] **Step 5: `./gradlew test` green; commit.**

---

## Phase 2 — Verification + docs

### Task 2.1: Emulator full parity pass [gate]

- [ ] Burn through the parity list on the AVD (drive via adb input taps from screenshot coordinates): all 5 question kinds (record which appear; ~10 answers budget), combo-3 crit overlay, wrong-answer hurt, boss intro bubble (right after battle start), escape → result settlement, battle re-entry ×3, config switch both ways, fallback path, backgrounding (home key mid-battle + return). Screenshots (≤400KB, `sips`) → `docs/features/2026-06-12-cocos-battle-android/screenshots/`. Audio evidence via logcat (mixer/TTS lines).
- [ ] Run full gates: `./gradlew test`, `./gradlew :app:assembleDebug`, androidTest compile (`assembleDebugAndroidTest`); if an emulator-runnable UI suite exists, run it (forced-native).
- [ ] Fix-forward loop for deviations; commit per fix.

### Task 2.2: Docs + cleanup

**Files:**
- Modify: `cocos/README.md` (Android embed section: recipe, CocosActivity hosting, re-entry verdict, emulator notes, gotchas)
- Create: `docs/features/2026-06-12-cocos-battle-android/README.md` + `50-parity-checklist.md` (model on `docs/features/2026-06-11-cocos-battle-harmonyos/`)
- Modify: `CLAUDE.md` (Commands → Cocos bullet: add Android embed line — build-android.sh; vendored `com/cocos/lib` + cpp adapter exempt from hand-edit)
- Modify: remove/keep dev entry per Task 0.2 mechanism (keep if it mirrors the other platforms' DevMenu CocosLab; remove probe artifacts from 0.3)

- [ ] Write docs; parity checklist from Task 2.1 evidence (honest statuses; "physical-device smoke pending store release" row).
- [ ] Final gate run; push branch; hand to user for merge decision.

---

## Self-review notes

- Spec coverage: §1→0.2/1.2/1.3/1.4; §2→0.1/0.2/0.3; §3→1.1-1.4; §4→2.1/2.2. Emulator-only baked into every verification step; re-entry risk isolated in 0.3 with a named fallback playbook (iOS isBooted pattern).
- Functional-engine divergence is called out in the header and Task 1.2 seams (adapter owns BattleState) — the one structural difference vs the Swift/ArkTS adapters.
- Names used consistently: `CocosTransport {send,setHandler}`, `decideBattleRoute(runtimeAvailable, prefEnabled, fallbackActive, forceNative)`, key `battle.useCocosScene` — same as the other platforms.
