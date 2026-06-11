# V1.1.0 Cocos Battle Scene (iOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the iOS battle screen with an embedded Cocos Creator 3.8 scene driven over a JSON bridge by the existing Swift `BattleEngine`, with the SwiftUI `BattleView` kept as a debug fallback.

**Architecture:** Swift keeps all battle/learning logic, the countdown timer, and audio. A new `CocosBattleBridge` translates engine state/outcomes into versioned JSON messages over `JsbBridgeWrapper`; the Cocos scene (TypeScript, nodes built programmatically) is presentation + input only. Contract schemas/fixtures live in `shared/`, decoded by both XCTest and vitest.

**Tech Stack:** Cocos Creator 3.8 + TypeScript, vitest, Swift/SwiftUI, XcodeGen, JsbBridgeWrapper.

**Spec:** `docs/superpowers/specs/2026-06-10-cocos-battle-scene-ios-design.md`

**Environment constraints:** Phases 0 and the editor/device steps require a local machine with Xcode, XcodeGen, and Cocos Creator 3.8.x (Cocos Dashboard). Cloud agents cannot run these; steps are marked **[MANUAL]** where the Cocos Creator editor or a simulator/device is required.

**Source files you will mirror (read them before Phase 2/3 work):**

- `ios/WordMagicGame/Core/BattleEngine.swift` — logic (do not modify)
- `ios/WordMagicGame/Core/Question.swift` — question model
- `ios/WordMagicGame/Core/BattleAnimationEvent.swift` — animation event semantics
- `ios/WordMagicGame/Features/CoreLoop/BattleView.swift` — behavior reference for every renderer
- `ios/WordMagicGame/App/AppCoordinator.swift:281-505` — battle lifecycle

---

## Phase 0 — Embed spike (go/no-go gate)

### Task 0.1: Environment check

**Files:** none (verification only)

- [ ] **Step 1: Verify required tooling**

```bash
xcodebuild -version                  # expect Xcode 16+
xcodegen --version                   # expect 2.45+
ls /Applications/Cocos/Creator/      # expect a 3.8.x directory (e.g. 3.8.6)
node --version && npm --version     # expect node 18+
```

- [ ] **Step 2: If Cocos Creator 3.8.x is missing, stop and ask the user to install it** via Cocos Dashboard (https://www.cocos.com/en/creator-download). Do not continue this phase without it.

### Task 0.2: Create the Cocos Creator project under `cocos/`

**Files:**
- Create: `cocos/` (Cocos Creator empty-2D project root, editor-generated)
- Create: `cocos/.gitignore`
- Create: `cocos/README.md`

- [ ] **Step 1 [MANUAL]: Create the project in Cocos Dashboard** — New Project → template **Empty (2D)** → project name `WordMagicBattle` → location such that the project root is exactly `cocos/` in this repo. Editor version 3.8.x. Open once so `assets/`, `settings/`, `package.json`, `tsconfig.json` are generated.

- [ ] **Step 2: Add `cocos/.gitignore`**

```gitignore
build/
library/
temp/
local/
profiles/
native/engine/common/
node_modules/
```

- [ ] **Step 3: Add `cocos/README.md`**

```markdown
# WordMagicBattle (Cocos Creator 3.8)

Battle presentation layer for WordMagicGame. Logic stays in the native clients;
this project renders the battle scene and reports user input over the JSB bridge.
Contract: `shared/contracts/cocos-battle-bridge/`.

## Requirements
- Cocos Creator 3.8.x (Cocos Dashboard)
- node 18+ (`npm install` for tests)

## Commands
- Unit tests (pure TS, no editor): `npm test`
- iOS build: open in Cocos Creator → Project → Build → platform iOS,
  output `build/ios` (gitignored). See "iOS embed" below.

## iOS embed
(filled in by the Phase 0 spike — keep updated)
```

- [ ] **Step 4: Commit**

```bash
git add cocos/ && git commit -m "Add Cocos Creator 3.8 project skeleton for battle scene"
```

### Task 0.3: Bridge probe script (ping/pong)

**Files:**
- Create: `cocos/assets/scripts/bridge/BridgeProbe.ts`
- Create: `cocos/assets/scenes/Battle.scene` **[MANUAL]** (editor: New Scene named `Battle`, add a Canvas, attach `BridgeProbe` to the Canvas node, set it as the launch scene in Project Settings)

- [ ] **Step 1: Write `BridgeProbe.ts`**

```typescript
import { _decorator, Component, Label, native, sys } from 'cc';
const { ccclass } = _decorator;

const TO_SCRIPT = 'wmBattleToScript';
const TO_NATIVE = 'wmBattleToNative';

@ccclass('BridgeProbe')
export class BridgeProbe extends Component {
    onLoad() {
        if (!sys.isNative) return;
        native.jsbBridgeWrapper.addNativeEventListener(TO_SCRIPT, (json: string) => {
            const msg = JSON.parse(json);
            if (msg.type === 'battle/ping') {
                native.jsbBridgeWrapper.dispatchEventToNative(
                    TO_NATIVE,
                    JSON.stringify({ v: 1, type: 'battle/pong', payload: { echo: msg.payload.echo } })
                );
            }
        });
        native.jsbBridgeWrapper.dispatchEventToNative(
            TO_NATIVE,
            JSON.stringify({ v: 1, type: 'battle/ready', payload: {} })
        );
    }
}
```

- [ ] **Step 2 [MANUAL]: Verify the scene compiles in the editor** (no red errors in the editor console).

- [ ] **Step 3: Commit**

```bash
git add cocos/assets && git commit -m "Add bridge probe script and Battle scene shell"
```

### Task 0.4 [MANUAL]: First iOS native build from Cocos Creator

**Files:** none committed (`cocos/build/` and `cocos/native/engine/common/` are gitignored; commit only `cocos/native/engine/ios/` if you customize it)

- [ ] **Step 1:** In Cocos Creator: Project → Build → Platform **iOS**, Bundle Identifier `com.terryma.wordmagicbattle`, output `build/ios`. Run Build then Make once to confirm the toolchain works.
- [ ] **Step 2:** Record in `cocos/README.md` ("iOS embed" section): the generated Xcode project path (`cocos/build/ios/proj/*.xcodeproj`), the library targets produced, where `JsbBridgeWrapper.h` lives in the generated tree, and the name of the generated view-controller / app-delegate classes.
- [ ] **Step 3: Commit the README update.**

### Task 0.5: Embed spike — Cocos view + ping/pong inside WordMagicGame

This is the riskiest task in the project. Goal: the existing app shows the Cocos scene in a hosted view controller and completes a `battle/ping` → `battle/pong` round-trip. Wiring details below are the best-known candidate; the executor adapts to what Task 0.4 actually generated and **documents the final recipe in `cocos/README.md`**.

**Files:**
- Create: `ios/WordMagicGame/CocosRuntime/WMCocosRuntimeShim.h`
- Create: `ios/WordMagicGame/CocosRuntime/WMCocosRuntimeShim.mm`
- Create: `ios/WordMagicGame/CocosRuntime/WordMagicGame-Bridging-Header.h`
- Modify: `ios/project.yml` (link Cocos libs + data bundle, set `SWIFT_OBJC_BRIDGING_HEADER`, add `COCOS_BATTLE_RUNTIME` Swift flag)
- Modify: `ios/WordMagicGame/Features/Settings/ConfigView.swift` (temporary DevMenu "CocosLab" button; replaced in Phase 2)

- [ ] **Step 1: Write the ObjC++ shim** (single integration point for all later phases)

```objc
// WMCocosRuntimeShim.h
#import <UIKit/UIKit.h>

typedef void (^WMScriptMessageHandler)(NSString *_Nonnull json);

@interface WMCocosRuntimeShim : NSObject
+ (instancetype _Nonnull)shared;
@property (class, readonly) BOOL isLinked;
- (UIViewController *_Nullable)makeViewController;
- (void)sendToScript:(NSString *_Nonnull)json;
- (void)setScriptHandler:(WMScriptMessageHandler _Nullable)handler;
- (void)shutdown;
@end
```

```objc
// WMCocosRuntimeShim.mm — adapt includes/classes to the Task 0.4 findings
#import "WMCocosRuntimeShim.h"
#import "JsbBridgeWrapper.h"   // from the generated cocos native tree

static NSString *const kToScript = @"wmBattleToScript";
static NSString *const kToNative = @"wmBattleToNative";

@implementation WMCocosRuntimeShim {
    WMScriptMessageHandler _handler;
}
+ (instancetype)shared { static WMCocosRuntimeShim *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [WMCocosRuntimeShim new]; }); return s; }
+ (BOOL)isLinked { return YES; }
- (UIViewController *)makeViewController {
    // Instantiate the generated Cocos ViewController and start the engine
    // exactly as the generated AppDelegate does (spike resolves the calls).
}
- (void)sendToScript:(NSString *)json {
    [[JsbBridgeWrapper sharedInstance] triggerEventToScript:kToScript arg:json];
}
- (void)setScriptHandler:(WMScriptMessageHandler)handler {
    _handler = [handler copy];
    __weak typeof(self) weakSelf = self;
    [[JsbBridgeWrapper sharedInstance] addScriptEventListener:kToNative
        callback:^(NSString *arg) {
            typeof(self) self = weakSelf;
            if (self && self->_handler) {
                dispatch_async(dispatch_get_main_queue(), ^{ self->_handler(arg); });
            }
        }];
}
- (void)shutdown { /* pause/end the cocos director per the generated lifecycle API */ }
@end
```

- [ ] **Step 2: Wire `ios/project.yml`** — add to the `WordMagicGame` target: the shim sources, header search paths into the cocos generated tree, the cocos static libraries (via `projectReferences` to the generated `.xcodeproj`, or direct `.a` paths if simpler), the cocos `data/` bundle as a resource, and:

```yaml
settings:
  base:
    SWIFT_OBJC_BRIDGING_HEADER: WordMagicGame/CocosRuntime/WordMagicGame-Bridging-Header.h
    OTHER_SWIFT_FLAGS: "$(inherited) -DCOCOS_BATTLE_RUNTIME"
```

- [ ] **Step 3: Add a temporary `CocosLab` button to `DevMenuView`** (`ios/WordMagicGame/Features/Settings/ConfigView.swift:554-564`, next to the existing `devToolButton` entries) that presents `WMCocosRuntimeShim.shared.makeViewController()` full-screen, sends `{"v":1,"type":"battle/ping","payload":{"echo":"hi"}}`, and shows a toast when `battle/pong` with `echo == "hi"` arrives.

- [ ] **Step 4 [MANUAL]: Verify on simulator** — `cd ios && xcodegen generate`, build & run, open DevMenu → CocosLab, confirm: scene renders, pong toast appears, no crash on dismiss → re-enter.

- [ ] **Step 5: Go/no-go.** Document the working recipe (exact libs, header paths, lifecycle calls) in `cocos/README.md`. If the embed cannot be made to work after honest effort, STOP — escalate to the user and propose the WKWebView fallback (same bridge contract) before any further phase.

- [ ] **Step 6: Commit**

```bash
git add ios/ cocos/README.md && git commit -m "Spike: embed Cocos runtime in iOS app with JSB ping/pong"
```

---

## Phase 1 — Cocos project foundations (no editor required except where marked)

### Task 1.1: vitest infrastructure + bridge message codecs (TS)

**Files:**
- Modify: `cocos/package.json` (add devDeps + test script)
- Create: `cocos/vitest.config.ts`
- Create: `cocos/assets/scripts/bridge/messages.ts` (pure TS — **must not import `cc`**)
- Test: `cocos/tests/messages.test.ts`

- [ ] **Step 1: Add vitest**

```bash
cd cocos && npm install --save-dev vitest typescript
```

In `cocos/package.json` add: `"scripts": { "test": "vitest run" }`.

`cocos/vitest.config.ts`:

```typescript
import { defineConfig } from 'vitest/config';
export default defineConfig({ test: { include: ['tests/**/*.test.ts'] } });
```

- [ ] **Step 2: Write the failing test** (fixtures arrive in Task 2.1; until then test against inline JSON — keep these cases, Task 2.1 adds fixture-file cases)

```typescript
// cocos/tests/messages.test.ts
import { describe, expect, it } from 'vitest';
import { parseNativeMessage, serializeScriptMessage } from '../assets/scripts/bridge/messages';

describe('parseNativeMessage', () => {
    it('parses a battle/state envelope', () => {
        const json = JSON.stringify({
            v: 1, type: 'battle/state', payload: {
                playerHp: 9, playerMaxHp: 10, monsterHp: 1, monsterMaxHp: 1,
                monsterIndex: 1, monstersTotal: 2, remainingSeconds: 297,
                comboCount: 2, status: 'playing',
                monster: { catalogIndex: 3, imageKey: 'CharacterSnowGoblin', name: 'Snow Goblin', levelLabel: 'L1', bonus: false },
            },
        });
        const msg = parseNativeMessage(json);
        expect(msg?.type).toBe('battle/state');
        if (msg?.type === 'battle/state') expect(msg.payload.playerHp).toBe(9);
    });
    it('returns null for unknown type or wrong version', () => {
        expect(parseNativeMessage('{"v":1,"type":"nope","payload":{}}')).toBeNull();
        expect(parseNativeMessage('{"v":2,"type":"battle/state","payload":{}}')).toBeNull();
        expect(parseNativeMessage('not json')).toBeNull();
    });
});

describe('serializeScriptMessage', () => {
    it('wraps submitOption in a v1 envelope', () => {
        const json = serializeScriptMessage({ type: 'battle/submitOption', payload: { option: 'apple' } });
        expect(JSON.parse(json)).toEqual({ v: 1, type: 'battle/submitOption', payload: { option: 'apple' } });
    });
});
```

- [ ] **Step 3: Run to verify failure** — `cd cocos && npm test` → FAIL (module not found).

- [ ] **Step 4: Implement `messages.ts`** — define the payload interfaces exactly mirroring the Swift names used in Task 2.2:

```typescript
export interface MonsterArtPayload { catalogIndex: number; imageKey: string; name: string; levelLabel: string; bonus: boolean; }
export interface BattleInitPayload {
    playerMaxHp: number; monsterMaxHp: number; monstersTotal: number; startingSeconds: number;
    playerArt: { idle: string; fight: string; hurt: string };
}
export interface BattleStatePayload {
    playerHp: number; playerMaxHp: number; monsterHp: number; monsterMaxHp: number;
    monsterIndex: number; monstersTotal: number; remainingSeconds: number;
    comboCount: number; status: 'ready' | 'playing' | 'won' | 'lost'; monster: MonsterArtPayload;
}
export interface BattleQuestionPayload {
    wordId: string; kind: 'choice' | 'fill-letter' | 'fill-letter-medium' | 'spell' | 'sentence-cloze';
    promptZh: string; answer: string; options: string[];
    letterTemplate: string; missingIndex: number; letterOptions: string[]; letterAnswer: string;
    letterTemplateBase: string; missingIndices: number[]; letterOptionsSteps: string[][];
    letterAnswers: string[]; currentStep: number;
    spellLetters: string[]; spellRevealedMask: boolean[]; spellPool: string[];
    sentenceTemplate: string; sentenceZh: string;
}
export interface BattleAnimationPayload {
    projectileDirection: 'forward' | 'backward'; projectileIntensity: number; projectileLabel: string;
    playerMotion: 'idle' | 'nudge' | 'hurt' | 'cast' | 'zoom';
    monsterMotion: 'idle' | 'nudge' | 'hurt' | 'cast' | 'zoom';
    feedbackText: string; showsCritOverlay: boolean; damageLabel: string;
    playsMonsterDefeatCue: boolean; correct: boolean; comboTriggered: boolean; battleEnded: boolean;
}
export interface BattleBossIntroPayload { monsterIndex: number; name: string; introLineEn: string; introLineZh: string; }
export interface BattleEndPayload { status: 'won' | 'lost'; }

export type NativeToScriptMessage =
    | { type: 'battle/init'; payload: BattleInitPayload }
    | { type: 'battle/state'; payload: BattleStatePayload }
    | { type: 'battle/question'; payload: BattleQuestionPayload }
    | { type: 'battle/animation'; payload: BattleAnimationPayload }
    | { type: 'battle/bossIntro'; payload: BattleBossIntroPayload }
    | { type: 'battle/end'; payload: BattleEndPayload }
    | { type: 'battle/ping'; payload: { echo: string } };

export type ScriptToNativeMessage =
    | { type: 'battle/ready'; payload: Record<string, never> }
    | { type: 'battle/submitOption'; payload: { option: string } }
    | { type: 'battle/spellWrongTap'; payload: Record<string, never> }
    | { type: 'battle/speakAnswer'; payload: Record<string, never> }
    | { type: 'battle/escape'; payload: Record<string, never> }
    | { type: 'battle/pong'; payload: { echo: string } };

const NATIVE_TYPES = new Set([
    'battle/init', 'battle/state', 'battle/question', 'battle/animation',
    'battle/bossIntro', 'battle/end', 'battle/ping',
]);

export function parseNativeMessage(json: string): NativeToScriptMessage | null {
    try {
        const raw = JSON.parse(json);
        if (raw?.v !== 1 || typeof raw.type !== 'string' || !NATIVE_TYPES.has(raw.type)) {
            console.warn(`[bridge] ignoring message: ${String(raw?.type)}`);
            return null;
        }
        return { type: raw.type, payload: raw.payload } as NativeToScriptMessage;
    } catch {
        console.warn('[bridge] ignoring non-JSON message');
        return null;
    }
}

export function serializeScriptMessage(msg: ScriptToNativeMessage): string {
    return JSON.stringify({ v: 1, type: msg.type, payload: msg.payload });
}
```

- [ ] **Step 5: Run tests** — `cd cocos && npm test` → PASS.
- [ ] **Step 6: Commit** — `git add cocos && git commit -m "Add TS bridge message codecs with vitest"`

### Task 1.2: Port `LetterTemplateLayout` to TS

**Files:**
- Create: `cocos/assets/scripts/ui/letterTemplate.ts` (pure TS, no `cc` import)
- Test: `cocos/tests/letterTemplate.test.ts`

Reference: `ios/WordMagicGame/Features/CoreLoop/BattleView.swift:8-68` — port `LetterTemplateSlot`, `LetterTemplateLayout.slots(from:missingIndex:pendingIndex:)` (note: consecutive spaces collapse into ONE space slot keeping the run's first index), and `metrics(forGlyphCount:)` (thresholds ≤6 / ≤9 / ≤12 / else with the exact numbers in the Swift source).

- [ ] **Step 1: Write the failing tests**

```typescript
// cocos/tests/letterTemplate.test.ts
import { describe, expect, it } from 'vitest';
import { metricsForGlyphCount, slotsFromTemplate } from '../assets/scripts/ui/letterTemplate';

describe('slotsFromTemplate', () => {
    it('maps glyphs with original indices and missing flag', () => {
        const slots = slotsFromTemplate('app_e', 3);
        expect(slots.map(s => s.glyph)).toEqual(['a', 'p', 'p', '_', 'e']);
        expect(slots[3]).toMatchObject({ isMissing: true, originalIndex: 3 });
    });
    it('collapses a run of spaces into one slot', () => {
        const slots = slotsFromTemplate('ice  cream', 4);
        expect(slots.map(s => s.glyph)).toEqual(['i', 'c', 'e', ' ', 'c', 'r', 'e', 'a', 'm']);
        expect(slots[3].originalIndex).toBe(3);
    });
    it('marks pending index', () => {
        const slots = slotsFromTemplate('app_e', 3, 3);
        expect(slots[3].isPending).toBe(true);
    });
});

describe('metricsForGlyphCount', () => {
    it('matches Swift thresholds', () => {
        expect(metricsForGlyphCount(6)).toEqual({ width: 16, height: 44, gap: 3, filledFontSize: 30, placeholderFontSize: 26 });
        expect(metricsForGlyphCount(9).height).toBe(40);
        expect(metricsForGlyphCount(12).height).toBe(36);
        expect(metricsForGlyphCount(13).height).toBe(32);
    });
});
```

- [ ] **Step 2: Run to verify failure** — `cd cocos && npm test` → FAIL.
- [ ] **Step 3: Implement the port faithfully from the Swift source.**
- [ ] **Step 4: Run tests** → PASS.
- [ ] **Step 5: Commit** — `git add cocos && git commit -m "Port letter template layout to TS"`

### Task 1.3: Art sync script

**Files:**
- Create: `tools/cocos/sync-art.sh`
- Create (generated): `cocos/assets/resources/art/characters/*.png`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# One-way sync: iOS asset catalog -> cocos battle art. Never edit outputs by hand.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/ios/WordMagicGame/Resources/Assets.xcassets"
DST="$ROOT/cocos/assets/resources/art/characters"
mkdir -p "$DST"
for dir in "$SRC"/Character*.imageset; do
    name="$(basename "$dir" .imageset)"
    png="$(find "$dir" -name '*.png' | sort | tail -1)"   # largest scale wins
    [ -n "$png" ] && cp "$png" "$DST/$name.png"
done
echo "Synced $(ls "$DST" | wc -l | tr -d ' ') character textures"
```

- [ ] **Step 2: Run it** — `chmod +x tools/cocos/sync-art.sh && tools/cocos/sync-art.sh` → expect `Synced N character textures` with N > 30 (catalog has 100 monsters + magician poses; verify `CharacterMagician.png`, `CharacterMagicianFight.png`, `CharacterMagicianBeaten.png` exist in the output).
- [ ] **Step 3: Commit** — `git add tools/cocos cocos/assets/resources && git commit -m "Add cocos art sync script and synced battle textures"`

### Task 1.4: Static battle layout (programmatic node tree)

**Files:**
- Create: `cocos/assets/scripts/BattleSceneController.ts` (cc component; orchestrator)
- Create: `cocos/assets/scripts/ui/TopStatusBar.ts`
- Create: `cocos/assets/scripts/ui/FighterCard.ts`
- Create: `cocos/assets/scripts/ui/QuestionPanel.ts`
- Create: `cocos/assets/scripts/ui/AnswerRow.ts`
- Modify: `cocos/assets/scenes/Battle.scene` **[MANUAL]** — attach `BattleSceneController` to the Canvas (replacing `BridgeProbe` attachment; keep BridgeProbe file for reference until Phase 2 deletes it)

Layout parity reference: `assets/screenshots/ios/latest-simulator/feature-ios-battle.png` and `BattleView.swift:126-260`. Landscape design resolution 1280×720 (set in editor project settings, Fit Height). Structure to build programmatically (each `ui/*.ts` exposes `build(parent: Node): Node` plus update methods used in later phases):

- **TopStatusBar** (top strip): left `Combo: N`, center title `Battle`, right `Countdown M:SS` + `Escape` capsule button.
- **FighterCard** (×2, left player / right monster, width ≈ 168pt scaled): rounded card (player tint pale blue, monster pale pink), sprite (player `CharacterMagician`, monster from state), name, subtitle (`Player` / `Monster i / total`), `HP x / y` label, green HP bar, level badge (monster), gold `Bonus` capsule (hidden by default).
- **QuestionPanel** (center, flexible): prompt label `苹果` + speaker button placeholder + feedback line `Choose the right spell`.
- **AnswerRow** (bottom): three purple capsule buttons with placeholder texts.

Use solid-color `Sprite` + `Graphics` rounded rects for cards/capsules; load textures with `resources.load('art/characters/CharacterMagician/spriteFrame', SpriteFrame)`.

- [ ] **Step 1: Implement the five files** with static placeholder data matching the screenshot (player 10/10 HP, monster `Snow Goblin` 1/1, `Monster 1 / 2`, options orange/blueberry/apple, `Countdown 4:57`, `Combo: 0`).
- [ ] **Step 2 [MANUAL]: Verify in Cocos Creator preview (browser preview is fine)** — side-by-side with the screenshot: three columns, top status, answer row present.
- [ ] **Step 3: Commit** — `git add cocos/assets && git commit -m "Build static battle layout in Cocos scene"`

---

## Phase 2 — Bridge contract + Swift integration

### Task 2.1: Contract schema + fixtures in `shared/`

**Files:**
- Create: `shared/contracts/cocos-battle-bridge/README.md` (protocol doc: envelope `{v:1,type,payload}`, channels `wmBattleToScript` / `wmBattleToNative`, unknown-type rule, additive-within-v1 rule)
- Create: `shared/contracts/cocos-battle-bridge/battle-bridge.schema.json` (JSON Schema draft-07, `oneOf` per message type, payload shapes exactly as Task 1.1 interfaces)
- Create fixtures under `shared/fixtures/cocos-battle-bridge/`: `init.json`, `state.json`, `question-choice.json`, `question-fill-letter.json`, `question-fill-letter-medium.json`, `question-spell.json`, `question-sentence-cloze.json`, `animation-correct.json`, `animation-wrong.json`, `animation-combo.json`, `boss-intro.json`, `end.json`, `ready.json`, `submit-option.json`, `spell-wrong-tap.json`, `speak-answer.json`, `escape.json`

Fixture content rules: realistic values from the existing app (e.g. `question-choice.json` uses 苹果/apple/orange/blueberry; `question-spell.json` has `spellLetters` of length 5 with `spellRevealedMask[0] == true`). Every Question fixture fills **all** fields of `BattleQuestionPayload` (empty arrays/strings where unused by the kind).

- [ ] **Step 1: Write README, schema, and all 17 fixtures.**
- [ ] **Step 2: Extend `cocos/tests/messages.test.ts`** — add a test that reads every fixture in `../../shared/fixtures/cocos-battle-bridge/` with `fs.readdirSync`, asserts native-direction files parse via `parseNativeMessage` (non-null) and script-direction files (`ready`, `submit-option`, `spell-wrong-tap`, `speak-answer`, `escape`) round-trip through `serializeScriptMessage` equal to the file content (`JSON.parse` deep-equal).
- [ ] **Step 3: Run** — `cd cocos && npm test` → PASS (fix codecs/fixtures until both agree).
- [ ] **Step 4: Commit** — `git add shared cocos/tests && git commit -m "Add cocos battle bridge contract schema and fixtures"`

### Task 2.2: Swift bridge messages + fixture-driven tests

**Files:**
- Create: `ios/WordMagicGame/Core/CocosBattleBridgeMessage.swift`
- Test: `ios/WordMagicGameTests/Core/CocosBattleBridgeMessageTests.swift`

- [ ] **Step 1: Write the failing test** (loads fixtures from the repo via `#filePath`)

```swift
import XCTest
@testable import WordMagicGame

final class CocosBattleBridgeMessageTests: XCTestCase {
    private static let fixturesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Core
        .deletingLastPathComponent()  // WordMagicGameTests
        .deletingLastPathComponent()  // ios
        .appendingPathComponent("shared/fixtures/cocos-battle-bridge")

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixturesURL.appendingPathComponent(name))
    }

    func testDecodesEveryScriptToNativeFixture() throws {
        for name in ["ready.json", "submit-option.json", "spell-wrong-tap.json", "speak-answer.json", "escape.json"] {
            let message = try CocosBridgeInbound.decode(from: fixture(name))
            XCTAssertNotNil(message, name)
        }
    }

    func testSubmitOptionCarriesOption() throws {
        guard case .submitOption(let option) = try CocosBridgeInbound.decode(from: fixture("submit-option.json")) else {
            return XCTFail("expected submitOption")
        }
        XCTAssertEqual(option, "apple")
    }

    func testEncodedStateMatchesFixture() throws {
        let payload = BattleStatePayload(
            playerHp: 9, playerMaxHp: 10, monsterHp: 1, monsterMaxHp: 1,
            monsterIndex: 1, monstersTotal: 2, remainingSeconds: 297, comboCount: 2,
            status: "playing",
            monster: MonsterArtPayload(catalogIndex: 3, imageKey: "CharacterSnowGoblin",
                                       name: "Snow Goblin", levelLabel: "L1", bonus: false)
        )
        let encoded = try CocosBridgeOutbound.state(payload).encodedJSON()
        let expected = try JSONSerialization.jsonObject(with: fixture("state.json")) as! NSDictionary
        let actual = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as! NSDictionary
        XCTAssertEqual(actual, expected)
    }

    func testUnknownTypeDecodesToNil() throws {
        let data = Data(#"{"v":1,"type":"battle/unknown","payload":{}}"#.utf8)
        XCTAssertNil(try CocosBridgeInbound.decode(from: data))
    }
}
```

(Adjust `state.json` fixture values in Task 2.1 to these exact numbers so the test is deterministic.)

- [ ] **Step 2: Run to verify failure**

```bash
cd ios && xcodegen generate && xcodebuild -project WordMagicGame.xcodeproj -scheme WordMagicGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:WordMagicGameTests/CocosBattleBridgeMessageTests
```

Expected: FAIL (types not defined).

- [ ] **Step 3: Implement `CocosBattleBridgeMessage.swift`**

```swift
import Foundation

struct MonsterArtPayload: Codable, Equatable {
    var catalogIndex: Int; var imageKey: String; var name: String; var levelLabel: String; var bonus: Bool
}

struct PlayerArtPayload: Codable, Equatable { var idle: String; var fight: String; var hurt: String }

struct BattleInitPayload: Codable, Equatable {
    var playerMaxHp: Int; var monsterMaxHp: Int; var monstersTotal: Int
    var startingSeconds: Int; var playerArt: PlayerArtPayload
}

struct BattleStatePayload: Codable, Equatable {
    var playerHp: Int; var playerMaxHp: Int; var monsterHp: Int; var monsterMaxHp: Int
    var monsterIndex: Int; var monstersTotal: Int; var remainingSeconds: Int
    var comboCount: Int; var status: String; var monster: MonsterArtPayload
}

struct BattleQuestionPayload: Codable, Equatable {
    var wordId: String; var kind: String; var promptZh: String; var answer: String; var options: [String]
    var letterTemplate: String; var missingIndex: Int; var letterOptions: [String]; var letterAnswer: String
    var letterTemplateBase: String; var missingIndices: [Int]; var letterOptionsSteps: [[String]]
    var letterAnswers: [String]; var currentStep: Int
    var spellLetters: [String]; var spellRevealedMask: [Bool]; var spellPool: [String]
    var sentenceTemplate: String; var sentenceZh: String

    init(question: Question) {
        wordId = question.wordId; kind = question.kind.rawValue
        promptZh = question.promptZh; answer = question.answer; options = question.options
        letterTemplate = question.letterTemplate; missingIndex = question.missingIndex
        letterOptions = question.letterOptions; letterAnswer = question.letterAnswer
        letterTemplateBase = question.letterTemplateBase; missingIndices = question.missingIndices
        letterOptionsSteps = question.letterOptionsSteps; letterAnswers = question.letterAnswers
        currentStep = question.currentStep
        spellLetters = question.spellLetters; spellRevealedMask = question.spellRevealedMask
        spellPool = question.spellPool
        sentenceTemplate = question.sentenceTemplate; sentenceZh = question.sentenceZh
    }
}

struct BattleAnimationPayload: Codable, Equatable {
    var projectileDirection: String; var projectileIntensity: Int; var projectileLabel: String
    var playerMotion: String; var monsterMotion: String
    var feedbackText: String; var showsCritOverlay: Bool; var damageLabel: String
    var playsMonsterDefeatCue: Bool; var correct: Bool; var comboTriggered: Bool; var battleEnded: Bool
}

struct BattleBossIntroPayload: Codable, Equatable {
    var monsterIndex: Int; var name: String; var introLineEn: String; var introLineZh: String
}

struct BattleEndPayload: Codable, Equatable { var status: String }

enum CocosBridgeOutbound {
    case initialize(BattleInitPayload)
    case state(BattleStatePayload)
    case question(BattleQuestionPayload)
    case animation(BattleAnimationPayload)
    case bossIntro(BattleBossIntroPayload)
    case end(BattleEndPayload)
    case ping(echo: String)

    private var typeName: String {
        switch self {
        case .initialize: "battle/init"
        case .state: "battle/state"
        case .question: "battle/question"
        case .animation: "battle/animation"
        case .bossIntro: "battle/bossIntro"
        case .end: "battle/end"
        case .ping: "battle/ping"
        }
    }

    func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadData: Data
        switch self {
        case .initialize(let p): payloadData = try encoder.encode(p)
        case .state(let p): payloadData = try encoder.encode(p)
        case .question(let p): payloadData = try encoder.encode(p)
        case .animation(let p): payloadData = try encoder.encode(p)
        case .bossIntro(let p): payloadData = try encoder.encode(p)
        case .end(let p): payloadData = try encoder.encode(p)
        case .ping(let echo): payloadData = try encoder.encode(["echo": echo])
        }
        let payload = try JSONSerialization.jsonObject(with: payloadData)
        let envelope: [String: Any] = ["v": 1, "type": typeName, "payload": payload]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

enum CocosBridgeInbound: Equatable {
    case ready
    case submitOption(String)
    case spellWrongTap
    case speakAnswer
    case escape
    case pong(echo: String)

    private struct Header: Decodable { var v: Int; var type: String }
    private struct OptionPayload: Decodable { var option: String }
    private struct EchoPayload: Decodable { var echo: String }
    private struct Envelope<P: Decodable>: Decodable { var payload: P }

    static func decode(from data: Data) throws -> CocosBridgeInbound? {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.v == 1 else { return nil }
        switch header.type {
        case "battle/ready": return .ready
        case "battle/submitOption":
            return .submitOption(try decoder.decode(Envelope<OptionPayload>.self, from: data).payload.option)
        case "battle/spellWrongTap": return .spellWrongTap
        case "battle/speakAnswer": return .speakAnswer
        case "battle/escape": return .escape
        case "battle/pong":
            return .pong(echo: try decoder.decode(Envelope<EchoPayload>.self, from: data).payload.echo)
        default: return nil
        }
    }
}
```

- [ ] **Step 4: Run the test** → PASS.
- [ ] **Step 5: Commit** — `git add ios shared && git commit -m "Add Swift cocos bridge message codecs with fixture tests"`

### Task 2.3: `CocosRuntime` abstraction + `CocosBattleBridge`

**Files:**
- Create: `ios/WordMagicGame/Features/CoreLoop/CocosRuntime.swift`
- Create: `ios/WordMagicGame/Features/CoreLoop/CocosBattleBridge.swift`
- Create: `ios/WordMagicGame/Core/BattleSfx.swift` (extract the private `sfxCue(for:)` mapping from `BattleView.swift` into `enum BattleSfx { static func cue(for event: BattleAnimationEvent) -> BattleSfxCue }`; update `BattleView` to call it — behavior unchanged)
- Create: `ios/WordMagicGame/CocosRuntime/ShimCocosRuntime.swift` (the Swift `CocosRuntime` conformance wrapping the ObjC shim — the factory below references it, so it must land in this task; whole file inside `#if COCOS_BATTLE_RUNTIME`):

```swift
#if COCOS_BATTLE_RUNTIME
import UIKit

final class ShimCocosRuntime: CocosRuntime {
    func makeViewController() -> UIViewController? { WMCocosRuntimeShim.shared().makeViewController() }
    func send(json: String) { WMCocosRuntimeShim.shared().send(toScript: json) }
    func setScriptMessageHandler(_ handler: @escaping (String) -> Void) {
        WMCocosRuntimeShim.shared().setScriptHandler(handler)
    }
    func shutdown() { WMCocosRuntimeShim.shared().shutdown() }
}
#endif
```

- Test: `ios/WordMagicGameTests/Core/CocosBattleBridgeTests.swift`

- [ ] **Step 1: Define the runtime protocol**

```swift
import UIKit

protocol CocosRuntime: AnyObject {
    func makeViewController() -> UIViewController?
    func send(json: String)
    func setScriptMessageHandler(_ handler: @escaping (String) -> Void)
    func shutdown()
}

enum CocosRuntimeFactory {
    /// Installed by the COCOS_BATTLE_RUNTIME integration (Task 2.5); nil when the engine is not linked.
    static var make: () -> CocosRuntime? = {
        #if COCOS_BATTLE_RUNTIME
        ShimCocosRuntime()
        #else
        nil
        #endif
    }
}
```

- [ ] **Step 2: Write failing tests with a `MockCocosRuntime`** (records sent JSON strings; lets the test inject script messages). Cover:
  - on `battle/ready`: bridge sends `battle/init`, `battle/state`, `battle/question` (in that order) and `bridge.isReady == true`.
  - on `battle/submitOption` with the correct option: coordinator's engine state advances (`totalAnswers + 1`), bridge sends `battle/animation` (with `correct == true`) then `battle/state` then `battle/question`.
  - on `battle/submitOption` ending the battle (1-monster config): bridge sends `battle/end` and after ~0.65 s the coordinator route is `.result` (use `XCTestExpectation` with 2 s timeout).
  - on `battle/spellWrongTap`: engine player HP −1, bridge sends animation (from `BattleAnimationEvent.spellWrongTapPenalty`) + state.
  - on `battle/escape`: coordinator route becomes `.result`.
  - unknown inbound type: nothing sent, no crash.

  Build the coordinator the same way existing battle tests do (see `ios/WordMagicGameTests/Core/` battle/engine test setup for the fixture word pack pattern and reuse it).

- [ ] **Step 3: Run tests** → FAIL (bridge not defined).

- [ ] **Step 4: Implement `CocosBattleBridge`**

```swift
import Foundation

@MainActor
final class CocosBattleBridge {
    private weak var coordinator: AppCoordinator?
    private let runtime: CocosRuntime
    private(set) var isReady = false
    private let feedbackHoldNs: UInt64 = 650_000_000  // mirrors BattleView clearFeedbackAfterDelay

    init(coordinator: AppCoordinator, runtime: CocosRuntime) {
        self.coordinator = coordinator
        self.runtime = runtime
        runtime.setScriptMessageHandler { [weak self] json in
            Task { @MainActor in self?.handleScriptMessage(json) }
        }
    }

    func handleScriptMessage(_ json: String) {
        guard let message = try? CocosBridgeInbound.decode(from: Data(json.utf8)) else { return }
        switch message {
        case .ready: handleReady()
        case .submitOption(let option): handleSubmit(option)
        case .spellWrongTap: handleSpellWrongTap()
        case .speakAnswer: coordinator?.speakCurrentBattleAnswer()
        case .escape: coordinator?.escapeBattle()
        case .pong: break
        }
    }

    func sendStateAndQuestion() { sendState(); sendQuestion() }

    // handleReady(): isReady = true; send init (from engine state + GameConfig fields
    //   + PlayerArtPayload(idle: "CharacterMagician", fight: "CharacterMagicianFight", hurt: "CharacterMagicianBeaten"));
    //   sendStateAndQuestion(); maybeSendBossIntro(); coordinator?.autoSpeakCurrentBattleAnswer(isRevealing: false)
    // handleSubmit(option): mirrors BattleView.handleOptionTap (BattleView.swift:709-726):
    //   capture word = engine.state.currentQuestion?.answer ?? "";
    //   let outcome = coordinator.submitBattleOptionForAnimation(option); guard non-nil;
    //   let event = BattleAnimationEvent(outcome: outcome, word: word);
    //   coordinator.playBattleSfx(BattleSfx.cue(for: event));
    //   if event.playsMonsterDefeatCue { coordinator.playBattleSfx(.monsterDefeat) }
    //   send(.animation(payload-from-event-and-outcome)); sendState();
    //   if outcome.battleEnded { send(.end(...)); Task { sleep(feedbackHoldNs); coordinator.finishBattle() } }
    //   else { sendQuestion(); maybeSendBossIntro(); coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false) }
    // handleSpellWrongTap(): let damage = engine.applySpellLetterPenalty();
    //   send animation from BattleAnimationEvent.spellWrongTapPenalty(damage:); sendState();
    //   if engine.state.status == .lost { send(.end); Task { sleep; coordinator.finishBattle() } }
    // sendState(): builds BattleStatePayload from engine.state + MonsterCodex.entry(catalogIndex1Based:)
    //   (imageKey/name) + level.battleLabel + state.currentMonsterBonus.
    // maybeSendBossIntro(): replicate the trigger conditions in BattleView.swift:1143-1175
    //   (same MonsterCodex entry dialogue source, once per catalog index per battle).
    // All sends: runtime.send(json: try outbound.encodedJSON()) — wrap in try? with a log on failure.
}
```

The comment block above is the behavioral spec — implement each method fully; no comment placeholders may remain in the committed file.

- [ ] **Step 5: Run tests** → PASS. Also run the full unit suite to catch the `BattleView`/`BattleSfx` refactor: same `xcodebuild test` command, `-only-testing:WordMagicGameTests`.
- [ ] **Step 6: Commit** — `git add ios && git commit -m "Add CocosBattleBridge translating engine state to bridge messages"`

### Task 2.4: `CocosBattleView` hosting + routing + DevMenu toggle

**Files:**
- Create: `ios/WordMagicGame/Features/CoreLoop/CocosBattleView.swift`
- Modify: `ios/WordMagicGame/App/ContentView.swift:19-22` (battle case)
- Modify: `ios/WordMagicGame/App/AppCoordinator.swift` (add `@Published var cocosBattleFallbackActive = false`, reset in `startBattle()`/`startReviewBattle()`; add `var shouldUseCocosBattleView: Bool`)
- Modify: `ios/WordMagicGame/Features/Settings/ConfigView.swift` (DevMenu: replace the Task 0.5 CocosLab button with a `Toggle("Use native BattleView", isOn:)` bound to `@AppStorage("dev.useNativeBattleView")`, accessibilityIdentifier `DevMenuNativeBattleToggle`)
- Test: `ios/WordMagicGameTests/Core/CocosBattleRoutingTests.swift`

- [ ] **Step 1: Routing rule (write failing tests first)** — `shouldUseCocosBattleView` is true only when ALL hold: a runtime can be made (`CocosRuntimeFactory.make() != nil` — cache the probe, do not build a runtime per check), `cocosBattleFallbackActive == false`, launch arguments do not contain `-UITestForceNativeBattle`, and NOT (debug developer tools visible && `UserDefaults dev.useNativeBattleView == true`). Tests cover each clause (inject `ProcessInfo` arguments via an init parameter defaulting to `ProcessInfo.processInfo.arguments`).

- [ ] **Step 2: Implement `CocosBattleView`**

```swift
import SwiftUI

struct CocosBattleView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var engine: BattleEngine
    @State private var bridge: CocosBattleBridge?
    @State private var runtimeVC: UIViewController?
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let runtimeVC {
                CocosHostingView(viewController: runtimeVC)
                    .ignoresSafeArea()
                    .accessibilityIdentifier("CocosBattleSurface")
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .onAppear(perform: startRuntime)
        .onDisappear(perform: stopRuntime)
        .onReceive(countdownTimer) { _ in
            guard engine.state.status == .playing else { return }
            coordinator.tickBattleCountdown()
            bridge?.sendStateAndQuestion()
        }
        .task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if bridge?.isReady != true {
                stopRuntime()
                coordinator.cocosBattleFallbackActive = true  // ContentView re-renders native BattleView
            }
        }
    }

    private func startRuntime() {
        guard let runtime = CocosRuntimeFactory.make() else {
            coordinator.cocosBattleFallbackActive = true
            return
        }
        bridge = CocosBattleBridge(coordinator: coordinator, runtime: runtime)
        runtimeVC = runtime.makeViewController()
    }

    private func stopRuntime() { /* runtime.shutdown(), clear bridge/vc */ }
}

private struct CocosHostingView: UIViewControllerRepresentable {
    let viewController: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { viewController }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}
```

(Keep a strong `runtime` reference in the view state alongside `bridge`; the snippet omits it for brevity — store both.)

- [ ] **Step 3: Wire `ContentView`**

```swift
case .battle:
    if let engine = coordinator.battleEngine {
        if coordinator.shouldUseCocosBattleView {
            CocosBattleView(coordinator: coordinator, engine: engine)
        } else {
            BattleView(coordinator: coordinator, engine: engine)
        }
    }
```

- [ ] **Step 4: Run unit tests** (`-only-testing:WordMagicGameTests`) → PASS. Without the cocos runtime linked locally this still exercises routing (factory returns nil → native path + fallback flag).
- [ ] **Step 5: Commit** — `git add ios && git commit -m "Route battle to Cocos view with debug fallback toggle"`

### Task 2.5: Live state in the Cocos scene (TS bridge client + controller wiring)

**Files:**
- Create: `cocos/assets/scripts/bridge/BridgeClient.ts` (the only TS file allowed to import `native` from `cc` for bridging)
- Modify: `cocos/assets/scripts/BattleSceneController.ts`
- Delete: `cocos/assets/scripts/bridge/BridgeProbe.ts`
- Test: extend `cocos/tests/` with `controllerState.test.ts` for any pure mapping helpers you extract (e.g. `formatCountdown(seconds) -> "4:57"`, HP ratio clamping) — write tests first for those helpers.

- [ ] **Step 1: Implement `BridgeClient.ts`**

```typescript
import { native, sys } from 'cc';
import { NativeToScriptMessage, ScriptToNativeMessage, parseNativeMessage, serializeScriptMessage } from './messages';

const TO_SCRIPT = 'wmBattleToScript';
const TO_NATIVE = 'wmBattleToNative';

export class BridgeClient {
    onMessage: ((msg: NativeToScriptMessage) => void) | null = null;

    start() {
        if (!sys.isNative) return;
        native.jsbBridgeWrapper.addNativeEventListener(TO_SCRIPT, (json: string) => {
            const msg = parseNativeMessage(json);
            if (msg && this.onMessage) this.onMessage(msg);
        });
        this.send({ type: 'battle/ready', payload: {} });
    }

    send(msg: ScriptToNativeMessage) {
        if (!sys.isNative) return;
        native.jsbBridgeWrapper.dispatchEventToNative(TO_NATIVE, serializeScriptMessage(msg));
    }
}
```

- [ ] **Step 2: Wire `BattleSceneController`** — on load: build static layout (Task 1.4), `bridgeClient.start()`, route messages: `battle/init` stores config + player art; `battle/state` updates HP labels/bars, combo, countdown (`formatCountdown`), monster sprite/name/level/bonus badge, monster subtitle `Monster i / total`; `battle/question` renders prompt text only for now (full renderers are Phase 3); `battle/end` disables input. Tap on Escape capsule → `send({type:'battle/escape',payload:{}})`; tap on speaker → `battle/speakAnswer`.
- [ ] **Step 3: Run TS tests** — `cd cocos && npm test` → PASS.
- [ ] **Step 4 [MANUAL]: Device/simulator verification** — rebuild cocos iOS (editor Build), `cd ios && xcodegen generate`, run app, start a battle: Cocos scene shows live HP/timer/monster, Escape returns to native Result page, DevMenu toggle switches back to native BattleView.
- [ ] **Step 5: Commit** — `git add cocos && git commit -m "Drive Cocos battle scene from live bridge state"`

---

## Phase 3 — Question renderers + combat animations (Cocos TS)

Each task: write pure-logic helpers test-first in `cocos/tests/`, build nodes in the listed component, then **[MANUAL]** verify in simulator against the matching screenshot, then commit. Behavior source of truth is `BattleView.swift` — read the cited lines before coding; replicate timings exactly (feedback hold 650 ms, impact delay 340 ms).

### Task 3.1: Choice + sentence-cloze renderers

**Files:** Modify `cocos/assets/scripts/ui/QuestionPanel.ts`, `cocos/assets/scripts/ui/AnswerRow.ts`; test `cocos/tests/answerFeedback.test.ts`

Behavior (BattleView.swift:709-765 and the questionPanel/answerRow sections; screenshots `battle-choice.png`, `sentence-cloze-battle.png`): three option capsules; on tap send `battle/submitOption`; lock input until the next `battle/question` arrives; while locked show feedback — selected capsule green `rgb(46,191,97)` when correct / red when wrong, others gray; feedback line text from `battle/animation.feedbackText`, gold when `comboTriggered`, green when correct, red otherwise; restore `Choose the right spell` + purple capsules when the new question renders (scene delays the swap 650 ms after the animation message — buffer the incoming question). Sentence-cloze additionally shows `sentenceTemplate` (with `____` blank) above `sentenceZh`.

- [ ] **Step 1:** Read the cited `BattleView.swift` sections; write failing vitest tests for a pure `answerFeedback.ts` helper (capsule color per option given selected/correct/locked state; feedback line color).
- [ ] **Step 2:** Run `cd cocos && npm test` → FAIL, implement the helper, → PASS.
- [ ] **Step 3:** Wire the renderers into `QuestionPanel.ts` / `AnswerRow.ts` using the helper.
- [ ] **Step 4 [MANUAL]:** Simulator check vs screenshots (choice + sentence-cloze battles).
- [ ] **Step 5:** Commit — `git add cocos && git commit -m "Add choice and sentence-cloze renderers to Cocos battle scene"`

### Task 3.2: Fill-letter renderers (single + medium)

**Files:** Modify `cocos/assets/scripts/ui/QuestionPanel.ts`; reuse `letterTemplate.ts`; test `cocos/tests/fillLetterView.test.ts`

Behavior (BattleView questionPanel fill-letter sections; screenshots `battle-fill-letter.png`, `battle-fill-letter-medium.png`): render `letterTemplate` slots via `slotsFromTemplate` (missing slot shows `_` placeholder style, metrics from `metricsForGlyphCount`); options are `letterOptions`. Medium: template comes from `letterTemplateBase`, current missing index is `missingIndices[currentStep]`, options `letterOptionsSteps[currentStep]`; a correct step-0 answer arrives as a new `battle/question` with `currentStep == 1` and the revealed letter already substituted in `letterTemplateBase` (engine handles it — scene just re-renders, no damage animation because the Swift bridge sends NO animation message for `advancedStep` outcomes, only state+question; replicate by not flashing feedback when no animation message preceded the question). **Bridge prerequisite:** confirm `CocosBattleBridge.handleSubmit` (Task 2.3) skips the animation send when `outcome.advancedStep == true` — add a unit test there if missing.

- [ ] **Step 1:** Write failing vitest tests for a pure `fillLetterView.ts` helper (slot list + active missing index + option list derivation for both kinds, including the medium `currentStep` switch).
- [ ] **Step 2:** Run `cd cocos && npm test` → FAIL, implement, → PASS.
- [ ] **Step 3:** Wire both renderers into `QuestionPanel.ts` (template row uses `metricsForGlyphCount` sizing).
- [ ] **Step 4 [MANUAL]:** Simulator check vs both fill-letter screenshots, including a medium two-step answer.
- [ ] **Step 5:** Commit — `git add cocos ios && git commit -m "Add fill-letter renderers to Cocos battle scene"`

### Task 3.3: Spell renderer

**Files:** Modify `cocos/assets/scripts/ui/QuestionPanel.ts`; test `cocos/tests/spellView.test.ts`

Behavior (BattleView spell sections — slots `spellSlots`, `spellConsumedIndices`, `spellShakingPoolIndex`; screenshot `battle-spell.png`): show `spellLetters` slots with `spellRevealedMask` (first letter always revealed), letter pool from `spellPool`. Tapping the next correct pool letter fills the next hidden slot locally and marks the pool index consumed; when the word completes, send `battle/submitOption` with `payload.option = answer` (mirrors native: spell submits the full answer). Tapping a wrong pool letter: shake that pool button (tween ±6 px, 3 cycles, ~0.3 s) and send `battle/spellWrongTap`.

- [ ] **Step 1:** Write failing vitest tests for a pure `spellView.ts` helper (next-expected-letter, consumed indices, wrong-tap detection, completion) using a 5-letter fixture word.
- [ ] **Step 2:** Run `cd cocos && npm test` → FAIL, implement, → PASS.
- [ ] **Step 3:** Wire the renderer into `QuestionPanel.ts` (slots + pool buttons + shake tween + bridge sends).
- [ ] **Step 4 [MANUAL]:** Simulator check vs `battle-spell.png`, including a wrong tap (player HP −1, shake, no question change).
- [ ] **Step 5:** Commit — `git add cocos && git commit -m "Add spell renderer to Cocos battle scene"`

### Task 3.4: Combat animations

**Files:** Create `cocos/assets/scripts/ui/ProjectileLayer.ts`, `cocos/assets/scripts/ui/FloaterLayer.ts`, `cocos/assets/scripts/ui/CritOverlay.ts`; modify `BattleSceneController.ts`, `FighterCard.ts`

Behavior on `battle/animation` (BattleView.swift:767-840 `triggerAnimation`, `MagicProjectileOverlay`, `DamageFloaterLabel.swift`): projectile sprite/label flies player→monster (`forward`) or monster→player (`backward`); player motions — `nudge` (small forward lunge tween), `hurt` (delayed 340 ms: red flash + hurt texture `CharacterMagicianBeaten` + `-N` floater on player side), `cast` (scale-up + glow); monster motions — `hurt` (340 ms delay: flash + floater), `zoom` (scale punch) + crit overlay when `showsCritOverlay` (full-screen gold burst with `damageLabel`, mirrors `CritSpectacleOverlay`); max 4 stacked floaters per side, 6 px vertical stagger. Player sprite swaps idle/fight/hurt textures from `battle/init.playerArt`. Use `tween()`; pool floater nodes (create 4, reuse).

- [ ] **Step 1:** Read the cited Swift animation code; write failing vitest tests for a pure `animationPlan.ts` helper mapping a `BattleAnimationPayload` to a declarative step list (`[{target, effect, delayMs}]`).
- [ ] **Step 2:** Run `cd cocos && npm test` → FAIL, implement, → PASS.
- [ ] **Step 3:** Implement `ProjectileLayer.ts`, `FloaterLayer.ts`, `CritOverlay.ts`; drive them from the plan steps in `BattleSceneController.ts`.
- [ ] **Step 4 [MANUAL]:** Simulator check — correct hit, wrong answer, combo crit (3 in a row), monster defeat transition.
- [ ] **Step 5:** Commit — `git add cocos && git commit -m "Add combat animations to Cocos battle scene"`

### Task 3.5: Boss intro + monster transitions

**Files:** Create `cocos/assets/scripts/ui/BossIntroBubble.ts`; modify `BattleSceneController.ts`, `FighterCard.ts`

Behavior: on `battle/bossIntro` show the dialogue bubble at 65% width / 20% height position (`BattleBossIntroLayoutSpec`, BattleView.swift:3-6) with name + EN line + ZH line, auto-dismiss matching native timing (BattleView.swift:1160-1175) and dismiss early if the monster index moves on; on monster defeat (state change with `monsterIndex` increment) play a brief fade-out/fade-in on the monster card; `bonus` flag toggles the gold `Bonus` capsule.

- [ ] **Step 1:** Read BattleView.swift:1096-1175 for bubble layout/timing; implement `BossIntroBubble.ts` and the monster-card transition in `FighterCard.ts` / `BattleSceneController.ts`.
- [ ] **Step 2:** Run `cd cocos && npm test` → PASS (no regressions).
- [ ] **Step 3 [MANUAL]:** Simulator check — boss encounter shows bubble once per catalog index, bonus monster shows gold capsule.
- [ ] **Step 4:** Commit — `git add cocos && git commit -m "Add boss intro and monster transitions to Cocos battle scene"`

---

## Phase 4 — Hardening, automation, docs

### Task 4.1: UI automation guardrails

**Files:**
- Modify: `ios/WordMagicGameUITests/` battle flow tests — add `-UITestForceNativeBattle` to `app.launchArguments` in the shared launch helper (find it with `grep -rn "launchArguments" ios/WordMagicGameUITests/`)
- Create: `ios/WordMagicGameUITests/CocosBattleSmokeTests.swift` — launches WITHOUT the force-native flag, starts a battle, asserts `app.otherElements["CocosBattleSurface"].waitForExistence(timeout: 10)`; skip (`XCTSkip`) when the runtime is not linked (probe via launch environment `COCOS_RUNTIME_LINKED` set from a `#if COCOS_BATTLE_RUNTIME` check exposed through `app.launchEnvironment`).

- [ ] Run the full UI suite on simulator; existing battle tests must pass unchanged on the native path.
- [ ] Commit.

### Task 4.2: Fallback + logging hardening

**Files:** Modify `CocosBattleView.swift`, `CocosBattleBridge.swift`, `AppCoordinator.swift`; test `ios/WordMagicGameTests/Core/CocosBattleRoutingTests.swift`

- [ ] Auto-fallback (runtime nil / ready-timeout) logs via `os.Logger(subsystem: "com.terryma.wordmagicgame", category: "cocosBattle")` and shows the existing toast mechanism (`coordinator.showToast`) only in debug builds.
- [ ] `cocosBattleFallbackActive` resets on every `startBattle()`/`startReviewBattle()` so one bad session doesn't permanently disable Cocos. Unit test: set flag → start battle → flag false.
- [ ] Bridge encode failures log and drop (never crash). Unit test with a mock runtime that records nothing when given an unencodable state (construct via a question containing an invalid UTF-8 surrogate is impractical — instead test that `handleScriptMessage` with garbage input is a no-op).
- [ ] Commit.

### Task 4.3: Parity pass + documentation

**Files:**
- Modify: `docs/WordMagicGame_roadmap.md` §20 (status: iOS integration landed, scope + fallback note)
- Create: `docs/features/2026-06-10-cocos-battle-scene-v1-1-0/README.md` — short entry: iOS-first (user-approved SOP deviation), links to spec/plan, Harmony/Android follow-up to be SOP-managed; parity checklist table for the 5 question types + animations vs `assets/screenshots/`
- Modify: `CLAUDE.md` — add cocos commands (`cd cocos && npm test`; build via Cocos Creator editor; art sync `tools/cocos/sync-art.sh`) and the rule that `cocos/assets/resources/art/` is generated (edit sources in iOS asset catalog, then re-run sync)
- Modify: `cocos/README.md` — final embed recipe, troubleshooting

- [ ] **[MANUAL] Screenshot parity run:** play one battle per question type plus a boss encounter on simulator; capture and compare against `assets/screenshots/harmonyos/battle-*.png` and `assets/screenshots/ios/latest-simulator/feature-ios-battle.png`; record pass/deviation per row in the feature README checklist.
- [ ] Full verification: `cd cocos && npm test` (0 fail) → `cd ios && xcodegen generate && xcodebuild ... test` (full scheme, 0 fail).
- [ ] Commit docs; final commit message `Cocos battle scene v1.1.0: iOS integration complete`.

---

## Self-review notes

- Spec coverage: architecture/bridge (Tasks 2.1-2.5), cocos project + layout (0.2-1.4), 5 question types (3.1-3.3), animations + boss intro (3.4-3.5), fallback/toggle (2.4, 4.2), tests (1.1, 1.2, 2.2, 2.3, 4.1), screenshot parity + docs (4.3), spike gate (0.5).
- Risk: Task 0.5 is the documented go/no-go; nothing after Phase 0 starts until it lands.
- Type names are kept identical across TS (`messages.ts`) and Swift (`CocosBattleBridgeMessage.swift`); fixtures are the cross-check.
