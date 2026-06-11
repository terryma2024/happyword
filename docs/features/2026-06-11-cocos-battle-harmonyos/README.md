# Cocos battle scene — HarmonyOS adoption (V1.1.x)

Replicates the V1.1.0 iOS-embedded Cocos battle scene
([`../2026-06-10-cocos-battle-scene-v1-1-0/`](../2026-06-10-cocos-battle-scene-v1-1-0/README.md))
on the HarmonyOS client. The Cocos project (`cocos/`) and the bridge contract
(`shared/contracts/cocos-battle-bridge/`) are shared as-is; this work embeds
the engine into `harmonyos/entry` and wires the ArkTS side.

- Design spec: [`docs/superpowers/specs/2026-06-11-cocos-battle-scene-harmonyos-design.md`](../../superpowers/specs/2026-06-11-cocos-battle-scene-harmonyos-design.md)
- Implementation plan: [`docs/superpowers/plans/2026-06-11-cocos-battle-scene-harmonyos.md`](../../superpowers/plans/2026-06-11-cocos-battle-scene-harmonyos.md)
- Embed recipe + gotchas: [`cocos/README.md`](../../../cocos/README.md) → "HarmonyOS embed"

## Status

| Phase | Result |
| --- | --- |
| 0 — build chain + embed + bridge spike | GO — `tools/cocos/build-harmonyos.sh` CLI build, engine vendored into `entry`, XComponent renders, ArkTS⇄scene ping/pong ~10 ms |
| 1 — codecs, bridge adapter, routing, Config switch, page lifecycle | done (19 shared fixtures pass in ArkTS codecs; CocosBattleBridge; `battleRouteUrl()` + Config "Cocos 战斗场景" switch; CocosBattlePage fallback contract) |
| 2.1 — adaptive resolution | done (FIXED_HEIGHT policy; squarish-screen design height) |
| engine patch — surface re-creation | done — vendored `OpenHarmonyPlatform.cpp` patch (SHA256-guarded); every battle of a process runs in Cocos (previously first battle only, then native fallback) |
| 2.2 — device verification | done on **arm64 emulator** (MatePad hdc channel Unauthorized — needs a physical confirm tap; re-run there when available). Evidence: [`screenshots/`](screenshots/) + [`50-parity-checklist.md`](50-parity-checklist.md) |
| 2.3 — docs + gates | done (this folder, cocos/README.md, CLAUDE.md, `.cursor/ohos-dev-commands.md`, `scripts/check_arkts_warnings.sh` gate) |

## Verification gates (2026-06-11, emulator `127.0.0.1:5555`, arm64)

- `cd cocos && npm test` — 53 passed
- `cd harmonyos && hvigorw -p module=entry@default test --no-daemon` — green
- `cd harmonyos && hvigorw assembleHap` + `scripts/check_arkts_warnings.sh` —
  0 disallowed / 25 allowed (vendored `cocosvendor/` allowlist)
- `cd harmonyos && codelinter -c ./code-linter.json5 . --fix` — no defects
- `scripts/run_ui_tests.sh` — **skipped**: suite is pinned to the MatePad
  (`5FFBB25926205346`), whose hdc channel reported `Unauthorized` (the RSA
  confirm dialog needs a physical tap; `hdc kill && hdc start` did not clear
  it). Re-run after re-authorizing the tablet.

## Known limits / follow-ups

- **MatePad (3:2) pass pending** — all device evidence in this folder is from
  the 2.16:1 arm64 emulator. The adaptive-resolution-on-3:2 row of the parity
  checklist needs the tablet.
- Boss intro bubble not reached during emulator play (requires defeating 9
  monsters in one 5-minute battle); the scene code is shared with iOS where
  Task 3.5 verified it on device.
- Question kinds beyond choice / sentence-cloze (fill-letter,
  fill-letter-medium, spell) did not appear within the verification battles
  even with all five kinds enabled in ConfigPage — kind selection depends on
  word memory state. Renderers are shared with iOS (verified there); spot-check
  on Harmony when a progressed profile is available.
