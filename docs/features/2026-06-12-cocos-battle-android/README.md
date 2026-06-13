# Cocos battle scene — Android adoption (V1.1.x)

Replicates the V1.1.0 iOS-embedded Cocos battle scene
([`../2026-06-10-cocos-battle-scene-v1-1-0/`](../2026-06-10-cocos-battle-scene-v1-1-0/README.md))
on the Android client, following the HarmonyOS adoption
([`../2026-06-11-cocos-battle-harmonyos/`](../2026-06-11-cocos-battle-harmonyos/README.md)).
The Cocos project (`cocos/`) and the bridge contract
(`shared/contracts/cocos-battle-bridge/`) are shared as-is; this work embeds
the engine into `android/app` and wires the Kotlin side.

- Design spec: [`docs/superpowers/specs/2026-06-12-cocos-battle-scene-android-design.md`](../../superpowers/specs/2026-06-12-cocos-battle-scene-android-design.md)
- Implementation plan: [`docs/superpowers/plans/2026-06-12-cocos-battle-scene-android.md`](../../superpowers/plans/2026-06-12-cocos-battle-scene-android.md)
- Embed recipe + gotchas: [`cocos/README.md`](../../../cocos/README.md) → "Android embed"

## Status

| Phase | Result |
| --- | --- |
| 0 — build chain + embed + bridge spike | GO — `tools/cocos/build-android.sh` headless export, engine built from source via Gradle `externalNativeBuild` (thin CMake adapter under `app/src/main/cpp/cocos/`), Java glue vendored at `app/src/main/java/com/cocos/lib/`, `CocosBattleActivity` renders, JsbBridgeWrapper ping/pong ~10 ms |
| 0.3 — re-entry verdict | GO — Android is **native-clean**: every activity entry is a full JS reload with a fresh organic `battle/ready` (no HOS-style once-per-process latch, no engine patch needed) |
| 1.1 — Kotlin codecs | done — `CocosBridgeMessages.kt` passes all 19 shared contract fixtures |
| 1.2 — bridge adapter | done — `CocosBattleBridge` (sequencing, question hold, finish-notify guard) |
| 1.3 — routing | done — `chooseBattleRoute()` four-input decision (`runtimeAvailable` / pref default ON / process `fallbackActive` / debug `forceNativeBattle`), `ForceNativeBattleRule` keeps battle-driving androidTests native |
| 1.4 — activity + config switch | done — `CocosBattleActivity` lifecycle shell, `CocosBattleSessionHolder` in-process handoff, per-answer side-effect callback (iOS parity), back-press = escape, 游戏配置 →「Cocos 战斗场景」switch, 5 s ready watchdog + boot-failure fallback |
| 2.1 — emulator parity pass | done on **arm64 emulator** (Pixel 9, API 36, 2.24:1). All 5 question kinds verified in Cocos (forced via the 题型选择 toggles). Evidence: [`screenshots/`](screenshots/) + [`50-parity-checklist.md`](50-parity-checklist.md) |
| 2.2 — docs + gates | done (this folder, cocos/README.md "Android embed", CLAUDE.md command line) |

## Verification gates (2026-06-13, emulator `emulator-5556`, arm64)

- `cd android && ./gradlew :app:testDebugUnitTest` — 250 passed
- `cd android && ./gradlew :app:assembleDebug` — green
- `cd android && ./gradlew :app:assembleDebugAndroidTest` — green
- `cd cocos && npm test` — 57 passed (scene untouched by this work)

## Known limits / follow-ups

- **Physical-device smoke pending** — all evidence in this folder is from the
  arm64 emulator; re-run entry / re-entry / audio on a physical device when
  the store release build is cut.
- **Fallback path is code-verified only** — the boot-throw and ready-timeout
  branches latch `fallbackActive` and re-route to the native BattleScreen
  (unit-tested decision table + reviewed activity wiring), but a live
  simulation needs source hacks because the engine boots reliably on the
  emulator. See the honest row in the parity checklist.
- BGM was OFF (config default on the test profile) during the audio
  spot-check; TTS + audio-focus + AudioTrack evidence is in the checklist,
  but no audible confirmation is possible over adb.
