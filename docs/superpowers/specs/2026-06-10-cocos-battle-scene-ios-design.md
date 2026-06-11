# V1.1.0 Cocos Battle Scene (iOS) Design

> Date: 2026-06-10
> Owner: matianyi
> Status: Approved design, ready for implementation planning
> Roadmap anchor: `docs/WordMagicGame_roadmap.md` §20 (V1.1.0 Cocos2D 战斗美术化重构版)

## Summary

Replace the iOS battle presentation layer (SwiftUI `BattleView`) with a Cocos Creator 3.8 scene, while keeping every piece of battle/learning logic in the existing Swift core. The iOS app shell (startup, Home, Result, parent surfaces, audio, learning records) is unchanged; only the `.battle` route hosts an embedded Cocos runtime. A new Cocos Creator project lives under `cocos/` at the repo root and is the future shared presentation asset for HarmonyOS / Android.

Approved decisions:

| Decision | Choice |
| --- | --- |
| Engine | Cocos Creator 3.8 + TypeScript (roadmap V1.1.0 recommendation) |
| Logic ownership | Swift keeps `BattleEngine` / question generation / scoring; Cocos is presentation + input only |
| Integration | Native embed of Cocos runtime into `WordMagicGame.xcodeproj` + `JsbBridgeWrapper` JSON event bridge (Approach A) |
| First-version visuals | 1:1 parity with current battle screen (existing PNG art, current landscape three-column layout) |
| Question types | All 5: `choice`, `fillLetter`, `fillLetterMedium`, `spell`, `sentenceCloze` |
| Native fallback | SwiftUI `BattleView` kept, debug-only DevMenu toggle; Cocos is default |

## Goals

- Battle scene rendered by Cocos (scene graph, animations, input) with behavior identical to the current SwiftUI battle: same question flows, HP/combo/bonus/boss-intro semantics, same visible layout per `assets/screenshots/ios/latest-simulator/feature-ios-battle.png` and `assets/screenshots/harmonyos/battle-*.png`.
- Zero changes to `BattleEngine`, `BattleQuestionScheduler`, learning records, reward settlement, audio services.
- A reusable, platform-agnostic Cocos project (`cocos/`) plus a versioned bridge contract (`shared/contracts/cocos-battle-bridge/`) so HarmonyOS / Android can adopt the same scene later.

## Non-Goals

- No new art themes, skeletal animation, or particle systems in this version (later iterations per roadmap §20).
- No port of battle logic to TypeScript.
- No HarmonyOS / Android integration in this version (architecture must not block it).
- Result page, battle BGM/SFX mixing, and pronunciation stay native.

## SOP note

This is an explicitly iOS-first effort (user decision), deviating from the Harmony-first three-platform SOP. The `cocos/` project and bridge contract are designed as shared assets; Harmony/Android replication will follow as separate SOP-managed work once the iOS integration stabilizes.

## Architecture

```text
SwiftUI App (unchanged shell)
└─ AppCoordinator (unchanged: BattleEngine, countdown tick, audio, records, settlement)
   ├─ BattleView (native SwiftUI, debug fallback)
   └─ CocosBattleView (new, UIViewControllerRepresentable)
        └─ CocosViewController (Cocos Creator generated native runtime)
             ↕ JsbBridgeWrapper — JSON messages, versioned v:1
        cocos/assets/scenes/Battle.scene (TypeScript, presentation + input only)
```

- **Swift keeps the clock**: the existing countdown timer and `tickBattleCountdown()` remain in Swift; Cocos receives state snapshots.
- **Swift keeps audio**: pronunciation (`PronunciationService`), battle SFX, and BGM mixing fire from Swift in response to engine outcomes or `battle/speakAnswer` intents from Cocos.
- **New Swift component `CocosBattleBridge`**: subscribes to `BattleEngine.state` and answer outcomes, encodes bridge messages down; decodes user intents up and calls existing coordinator methods (`submitBattleOptionForAnimation`, `escapeBattle`, `applySpellLetterPenalty`, …). Battle logic call sites are reused, not duplicated.

## Bridge contract

Location: `shared/contracts/cocos-battle-bridge/` (JSON Schema + fixtures only, per `shared/` discipline). Every message is `{ "v": 1, "type": "<name>", "payload": { … } }`.

Swift → Cocos:

| Type | Payload (summary) |
| --- | --- |
| `battle/init` | player/monster max HP, monstersTotal, starting seconds, art mapping (catalog index → texture key), locale strings |
| `battle/state` | full `BattleState` snapshot: HPs, monsterIndex, catalog index, remainingSeconds, combo, bonus flag, status |
| `battle/question` | current `Question` (kind, prompt, options / letterOptions / template / steps, currentStep) |
| `battle/animation` | mirror of `BattleAnimationEvent`: projectile direction/intensity/label, player/monster motion, feedback text, crit overlay flag, damage label, defeat cue flag; plus boss-intro trigger |
| `battle/end` | end status (won/lost) — Cocos stops input; Swift routes to native ResultView |

Cocos → Swift:

| Type | Payload (summary) |
| --- | --- |
| `battle/ready` | scene loaded; Swift replies with `battle/init` + first state/question |
| `battle/submitOption` | `{ option: string }` |
| `battle/spellWrongTap` | none (spell letter-pool wrong tap, −1 HP rule) |
| `battle/speakAnswer` | request native pronunciation |
| `battle/escape` | escape button |

Rules: unknown message types are ignored with a warning log on both sides; payloads are additive within `v:1`; fixtures under `shared/fixtures/cocos-battle-bridge/` are decoded by both Swift XCTests and TS vitest to keep the two ends honest.

## `cocos/` project layout

```text
cocos/                       # Cocos Creator 3.8 project root
  assets/
    scenes/Battle.scene
    scripts/
      BattleSceneController.ts   # orchestrates state → nodes
      bridge/                    # JsbBridge client, message codecs (pure TS, unit-testable)
      ui/                        # FighterCard, QuestionPanel, AnswerRow, overlays
      model/                     # TS mirrors of bridge DTOs
    resources/art/               # PNGs synced from iOS assets (characters, monsters, icons)
  settings/  package.json  tsconfig.json
  native/engine/               # post-build customized native glue (committed where customized)
  README.md                    # build + sync + embed instructions
```

- Art is synced one-way from `ios/WordMagicGame/Resources/Assets.xcassets` via `tools/cocos/sync-art.sh`; no hand-maintained duplicates. Design-source files stay under `assets/` per the asset retention policy.
- `LetterTemplateLayout` and similar pure presentation-layout helpers are ported to TS (they are view-layer logic; the Swift originals remain for the fallback view).
- Question renderers replicate the SwiftUI behaviors: choice/sentenceCloze option buttons, fillLetter template slots + letter options, fillLetterMedium two-step reveal, spell letter pool with consumed indices, shake on wrong tap, and pending-slot rendering.

## iOS integration (Approach A)

- Cocos Creator iOS build emits a CMake-generated native project (`cocos/build/ios/proj`) plus engine libraries. The host app links the Cocos static libs and hosts the generated `CocosViewController` inside `CocosBattleView` (a `UIViewControllerRepresentable`).
- `ios/project.yml` (XcodeGen) gains the Cocos framework/library references and the cocos data bundle so regeneration never loses the linkage. Any DevEco-style project-file changes are explained in the PR per repo rules.
- Bridge transport is the official `JsbBridgeWrapper` (string event + string payload; payloads are JSON).
- **Phase 0 is a de-risking spike**: an empty Cocos scene embedded in the existing app with a bridge round-trip. Embedding a 3.8 build into an existing app is a community-validated (not officially scripted) path — the spike validates it before any feature work. If the spike fails irrecoverably, fall back to Approach B (WKWebView + web-mobile build) with the same bridge contract.

## Routing, fallback, error handling

- `ContentView` battle route chooses `CocosBattleView` (default) or native `BattleView` based on a debug-only DevMenu toggle (`useNativeBattleView`). Release builds do not expose the toggle (same policy as backend switching).
- XCUITest battle flows launch with an argument that forces the native view, preserving existing automation; a new smoke test asserts the Cocos hosting view appears.
- Runtime safety: if the Cocos runtime fails to initialize, or `battle/ready` does not arrive within 5 seconds of entering the battle route, Swift automatically falls back to the native `BattleView` for that session and logs the failure. The same `BattleEngine` instance keeps the session, so the fallback view simply renders the current state.
- Lifecycle: leaving the battle route tears down / pauses the Cocos director consistent with its embed API; re-entry re-inits via `battle/ready` handshake.

## Testing

| Layer | Coverage |
| --- | --- |
| Swift logic | Existing `BattleEngine` XCTests unchanged |
| Bridge (Swift) | New XCTests: encode/decode all message types against `shared/fixtures/cocos-battle-bridge/` |
| Bridge + layout (TS) | vitest on pure TS modules (codecs, letter-template layout, view-model mapping) — runs headless in CI, no Cocos editor |
| UI automation | Existing XCUITest battle flows forced onto native fallback; new Cocos-load smoke test |
| Visual parity | Manual screenshot comparison against `assets/screenshots/` battle set (5 question types + boss intro + combo crit) |

## Implementation phases

1. **Phase 0 — embed spike**: empty Cocos scene inside the existing app, JsbBridge round-trip, XcodeGen integration proven. Go/no-go gate for Approach A.
2. **Phase 1 — project + static layout**: `cocos/` project, Battle scene with 1:1 static layout (player card / question panel / monster card / answer row / top status), art sync script.
3. **Phase 2 — bridge + state sync**: contract schemas + fixtures, `CocosBattleBridge` (Swift), TS bridge client, live HP/timer/combo/question sync.
4. **Phase 3 — question types + animations**: all 5 renderers; projectile, hurt/nudge/cast/zoom motions, crit overlay, damage floaters, boss intro bubble, bonus badge.
5. **Phase 4 — hardening**: fallback toggle + auto-fallback, tests per matrix above, screenshot parity pass, docs (roadmap §20 status, feature folder entry noting iOS-first deviation and Harmony/Android follow-up).

## Risks

| Risk | Mitigation |
| --- | --- |
| Cocos 3.8 embed into existing iOS app is not an officially scripted path | Phase 0 spike before feature work; WKWebView fallback plan with same contract |
| XcodeGen regeneration breaks Cocos linkage | All linkage expressed in `project.yml`, verified in CI by a clean regenerate + build |
| Behavior drift between Cocos scene and native fallback | Single logic source (Swift engine); shared fixtures; screenshot parity checklist |
| Repo size growth from engine artifacts | Commit only project sources + customized `native/engine` glue; generated `cocos/build/` stays gitignored; document the local build step in `cocos/README.md` |
