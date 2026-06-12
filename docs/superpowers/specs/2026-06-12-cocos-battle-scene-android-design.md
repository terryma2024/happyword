# Cocos battle scene — Android integration (design)

Date: 2026-06-12
Branch: `cocos-battle-android`
Status: approved by user (sections reviewed 2026-06-12)

## Goal

Bring the Cocos battle scene (shipped on iOS and HarmonyOS in V1.1.0) to the
Android client (Kotlin / Jetpack Compose). Kotlin keeps all battle logic; the
shared `cocos/` scene and the `shared/contracts/cocos-battle-bridge/` contract
are reused unchanged. New work: engine embedding, a Kotlin bridge adapter,
routing with native fallback, and a config-page switch.

Decisions fixed during brainstorming (carried over from the iOS/HarmonyOS
cycles, user-confirmed):

- **Emulator-only development and verification** — the user has no Android
  device. Investigation confirmed feasibility: Cocos 3.8.8 ships prebuilt
  Android externals for ALL four ABIs (arm64-v8a / armeabi-v7a / x86 /
  x86_64), the Apple-Silicon host runs arm64 AVD images natively (same ABI as
  real devices), and `JsbBridgeWrapper` is first-class on Android. A physical
  smoke test is deferred to store-release time.
- Routing/fallback fully mirrors iOS/HOS: config switch (default ON),
  auto-fallback on boot failure / 5 s ready timeout, UI automation forces
  native, in-process fallback flag.
- Milestone: **dev-complete** (emulator-verified, merged to main). Google
  Play / store release is separate work.
- Approach A (user-approved): vendor generated artifacts into the existing
  `android/app` module + battle hosted in a **separate `CocosBattleActivity`**
  (CocosActivity subclass — the engine-blessed Android path; surface
  re-creation is natively supported, no engine patch expected). A separate
  gradle module and single-activity SurfaceView embedding were considered and
  rejected (recipe divergence / re-implementing CocosActivity plumbing).

## 1. Architecture and module boundaries

```
android/app
├── src/main/cpp/cocos/              # thin CMakeLists adapter (engine source chain from the Creator bundle; never hand-edited beyond the adapter itself)
├── src/main/java/com/cocos/lib/     # vendored engine Java layer (CocosActivity/CocosHelper/JsbBridge…; rsynced by script, never hand-edited)
├── src/main/assets/cocos/           # scene data assets (generated, gitignored, synced by script)
└── src/main/java/cool/happyword/wordmagic/
    ├── cocos/CocosBattleActivity.kt     # battle host (CocosActivity subclass, landscape)
    ├── cocos/CocosBattleBridge.kt       # contract codecs + BattleEngine.kt adapter
    └── cocos/CocosBattlePreference.kt   # switch preference (default ON) + route decision
```

- **Zero logic migration**: `core/BattleEngine.kt` and sibling services are
  untouched; the bridge only translates — same shape as the Swift and ArkTS
  adapters.
- **Scene and contract unchanged**: the shared scene's `JsbWrapperTransport`
  works natively on Android (same API as iOS) — not even a new transport is
  needed. The 19 shared fixtures remain the codec acceptance basis.
- Native `BattleUi.kt` stays as the fallback presentation. The Compose battle
  entry points route per the decision table: `startActivity(CocosBattleActivity)`
  or navigate to native BattleUi.
- Battle results flow over the bridge to Kotlin → the adapter runs the same
  settlement path BattleUi uses → the activity finishes back into the Compose
  result flow.

## 2. Embedding and build chain (emulator-only)

Generation and extraction:

1. One-time prerequisite: the Creator editor needs Android SDK/NDK paths
   configured (Preferences → Program Manager). If the CLI build fails for a
   missing SDK/NDK, the spike task configures it and records the steps.
2. `tools/cocos/build-android.sh` (mirrors `build-harmonyos.sh`): quit editor
   → Creator CLI build `platform=android` → outputs under
   `cocos/build/android/` (gradle template project + data) → rsync into
   `android/app`:
   - engine Java layer → `src/main/java/com/cocos/lib/` (committed; scripted
     sed fix-ups with grep assertions if needed);
   - data assets → `src/main/assets/cocos/` (gitignored, ~13 MB generated —
     same policy as HOS rawfile);
   - native glue is reference only — we hand-write a thin CMakeLists adapter
     (derives engine paths from `CMAKE_CURRENT_LIST_DIR`, includes the
     Creator-bundle source chain, builds `libcocos.so`). **No engine patch
     expected** — Android surface re-creation is natively supported.
3. `android/app/build.gradle.kts` additions: `externalNativeBuild { cmake }`,
   `abiFilters += "arm64-v8a"`, ndkVersion, manifest declaration of
   `CocosBattleActivity` (landscape, configChanges to avoid recreation).

Emulator verification chain (fully scriptable): arm64 AVD (`adb devices`,
`emulator -avd <name>`; the spike inventories existing AVDs or creates one
via `avdmanager`) → `./gradlew assembleDebug` → `adb install -r` →
`adb shell am start` → `adb exec-out screencap -p` screenshots.

Build discipline: existing `./gradlew test` stays green; no new lint
warnings.

**Phase 0 go/no-go**: CocosBattleActivity renders the battle scene on the
emulator + JsbBridgeWrapper ping/pong round-trips both directions + the
re-entry check (finish → second launch must not crash and must render; if the
engine singleton conflicts with activity recreation, apply the iOS
isBooted/resume pattern — a known playbook, not new design).

## 3. Bridge and routing (Kotlin side)

Message channel: `com.cocos.lib.JsbBridgeWrapper` —
`addScriptEventListener("wmBattleToNative", …)` /
`dispatchEventToScript("wmBattleToScript", json)`, same names and semantics
as iOS. Scene side needs zero changes. Thread rule: listener callbacks arrive
on the GL thread; the adapter immediately hops to the main thread
(Handler/coroutine). The iOS MRC ownership trap does not exist in the Java
layer.

Adapter (`CocosBattleBridge.kt`, mirrors the Swift/ArkTS adapters):

- ready → init + state + question + bossIntro (first catalog-index sighting);
  submit → animation + state immediately, question after the 650 ms hold;
  spellWrongTap → HP penalty; escape → immediate settlement; end →
  battle/end + finish-once callback.
- `dispose()` + `holdActive` guards ship in the first version (hard
  requirements distilled from the HOS reviews).
- Audio/TTS hooks align with native BattleUi's call points (read
  `AndroidBattleAudioMixer` for the current behavior).
- Acceptance: Kotlin codecs decode all 19 shared fixtures (JUnit,
  `./gradlew test`) + the adapter sequencing test set ported from the ArkTS
  suite (fake transport + real BattleEngine with seeded rng).

Routing and fallback (same decision table on all three platforms):

| Condition | Result |
| --- | --- |
| Preference ON (default) and runtime available | `startActivity(CocosBattleActivity)` |
| Config switch OFF | Compose navigation → native BattleUi |
| Engine boot failure / ready timeout (5 s) | auto-fallback + in-process fallback flag |
| androidTest UI automation | forced native via a test-controllable global flag (same idea as the HOS AppStorage injection) |
| Battle re-entry | per Phase 0 outcome: engine singleton reuse + init reset (iOS pattern) or activity-level recreation |

Config page gains a「战斗画面 / Cocos 战斗场景」switch row (reuse the existing
Compose settings-row style; persistence follows the existing GameConfig
storage mechanism).

## 4. Testing, verification, phases

| Layer | Content |
| --- | --- |
| JUnit | codecs vs 19 fixtures; routing decision table; adapter sequencing (fake transport + seeded BattleEngine) |
| Emulator | Phase 0 spike (render + ping/pong + re-entry) → post-integration: all 5 question kinds + combo crit + boss bubble + escape/settlement + switch both ways + fallback path; adb screenshots archived |
| Build gates | `./gradlew test` green; assembleDebug no new warnings; existing androidTest suite (forced-native) no regression |
| Docs | `cocos/README.md` Android embed section; feature folder `docs/features/2026-06-12-cocos-battle-android/` + parity checklist |

## Phases

| Phase | Scope | Gate |
| --- | --- | --- |
| 0 | Embed spike: build script, vendor into app, CocosBattleActivity renders, bridge ping/pong, re-entry check (emulator) | go/no-go |
| 1 | Kotlin bridge + routing: codecs, adapter, preference + fallback, config switch, activity lifecycle | fixtures + sequencing + routing tests green |
| 2 | Emulator full verification + docs: parity pass, README/feature folder, final gates | all gates green, merge to main |
