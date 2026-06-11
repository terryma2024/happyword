# Cocos battle scene (V1.1.0) — iOS first

> **SOP deviation (user-approved):** this feature is iOS-first, not
> Harmony-first. The `cocos/` project and the bridge contract
> (`shared/contracts/cocos-battle-bridge/`) are the future shared
> presentation assets; HarmonyOS / Android adoption will be planned as
> separate SOP-managed work once the iOS integration stabilizes.

- Design spec: [`docs/superpowers/specs/2026-06-10-cocos-battle-scene-ios-design.md`](../../superpowers/specs/2026-06-10-cocos-battle-scene-ios-design.md)
- Implementation plan: [`docs/superpowers/plans/2026-06-10-cocos-battle-scene-ios.md`](../../superpowers/plans/2026-06-10-cocos-battle-scene-ios.md)
- Embed recipe + build commands: [`cocos/README.md`](../../../cocos/README.md)

## Status

| Phase | Result |
| --- | --- |
| 0 — embed spike | GO — engine embedded, JSB ping/pong verified on device |
| 1 — cocos project + static layout | done (vitest infra, letter template port, art sync, 1:1 layout) |
| 2 — bridge contract + Swift integration | done (fixtures, codecs both ends, CocosBattleBridge, routing + fallback) |
| 3 — question renderers + animations | done (all 5 kinds, projectile/floaters/crit/boss intro), device-verified |
| 4 — hardening + docs | tests green (sim suite native-fallback, device smoke), docs updated |

## Parity checklist (vs native BattleView / `assets/screenshots`)

| Surface | Status |
| --- | --- |
| choice | verified (preview interactive + device) |
| fill-letter | verified (device screenshot, template slots) |
| fill-letter-medium | verified (preview interactive, two-step) |
| spell | verified (preview interactive: pool consume/shake/penalty/submit) |
| sentence-cloze | verified (preview interactive) |
| combat animations | verified (preview: projectile/feedback colors/floaters; device play) |
| boss intro bubble | implemented; verify on device during play-test |
| escape / result routing | verified on device |
| audio (BGM/SFX/TTS) | native-side unchanged; spot-check during play-test |

## Notes

- Cocos battle is **device-only**; simulator builds always use the native
  BattleView (Cocos 3.8 ships no arm64-simulator prebuilts).
- Native `BattleView` remains the debug fallback (DevMenu toggle
  `dev.useNativeBattleView`, `-UITestForceNativeBattle` launch argument,
  automatic fallback on runtime failure / ready timeout).
