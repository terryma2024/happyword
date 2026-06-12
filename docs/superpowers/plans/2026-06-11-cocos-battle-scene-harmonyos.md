# Cocos Battle Scene — HarmonyOS Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route the HarmonyOS client's battle to the shared Cocos scene (shipped on iOS in V1.1.0), with the native `BattlePage` kept as a switchable/automatic fallback.

**Architecture:** The Cocos Creator 3.8.8 `harmonyos-next` build output is vendored into the existing `harmonyos/entry` module (C++ glue + prebuilt libs + template ArkTS plumbing, never hand-edited). Hand-written ArkTS adds a bridge (contract codecs + `BattleEngine.ets` adapter), a route decision with preference/fallback, an XComponent host page, and a config switch. The scene gains an adaptive resolution policy for 3:2 tablets. Spec: `docs/superpowers/specs/2026-06-11-cocos-battle-scene-harmonyos-design.md`.

**Tech Stack:** ArkTS / ArkUI, Hvigor, Cocos Creator 3.8.8 (`harmonyos-next` platform), Hypium local tests, vitest (cocos/), DevEco emulator first then MatePad Air (hdc).

**Reference implementations (read before porting):**
- iOS adapter: `ios/WordMagicGame/Features/CoreLoop/CocosBattleBridge.swift`
- iOS codecs: `ios/WordMagicGame/Core/CocosBattleBridgeMessage.swift`
- Scene-side codecs (port source of truth): `cocos/assets/scripts/bridge/messages.ts`
- Contract: `shared/contracts/cocos-battle-bridge/` (schema + `fixtures/*.json`, 19 files)
- Routing precedent: `ios/WordMagicGame/App/AppCoordinator.swift` (`shouldUseCocosBattleView`)
- Build commands / device rules: `.cursor/ohos-dev-commands.md`

**Key engine facts (verified against the installed editor):**
- Template: `/Applications/Cocos/Creator/3.8.8/CocosCreator.app/Contents/Resources/resources/3d/engine/templates/harmonyos-next/` — a full DevEco project; its `entry/src/main/ets/` ships required plumbing (`cocos/WorkerManager.ets`, `workers/cocos_worker.ets`, `common/*`, `components/*`, `pages/index.ets` shows the XComponent conventions).
- OpenHarmony has **no `jsbBridgeWrapper` native backend**. Scene→ArkTS exists as `JavaScriptArkTsBridge` (`native/cocos/bindings/manual/JavaScriptArkTsBridge.cpp`: invokes a static method on an ArkTS module class by path, async or sync). The reverse direction candidates are probed in Task 0.3.
- Engine runs in an ArkTS **worker**; all bridge traffic crosses threads.

---

## Phase 0 — Embed spike (go/no-go, emulator first)

### Task 0.1: Headless HarmonyOS build script + first CLI build

**Files:**
- Create: `tools/cocos/build-harmonyos.sh`

- [ ] **Step 1: Write the script** (mirror `tools/cocos/build-ios.sh`'s structure: quit editor → CLI build; no lib re-compile step is needed on HOS — prebuilts are arm64 only):

```bash
#!/bin/bash
# Headless Cocos build for the HarmonyOS embed.
# Produces cocos/build/harmonyos-next/ (DevEco template project + data).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CREATOR="/Applications/Cocos/Creator/3.8.8/CocosCreator.app/Contents/MacOS/CocosCreator"

echo "==> quitting Cocos Creator (CLI build requires exclusive project lock)"
osascript -e 'tell application "CocosCreator" to quit' 2>/dev/null || true
for _ in $(seq 1 20); do pgrep -x CocosCreator >/dev/null || break; sleep 1; done

echo "==> building platform=harmonyos-next"
"$CREATOR" --project "$ROOT/cocos" --build "platform=harmonyos-next" || {
  echo "build failed; see cocos/temp/logs/project.log" >&2; exit 1; }

echo "==> done; output at cocos/build/harmonyos-next/"
```

- [ ] **Step 2: Make executable and run it**

Run: `chmod +x tools/cocos/build-harmonyos.sh && tools/cocos/build-harmonyos.sh`
Expected: exit 0; `cocos/build/harmonyos-next/` contains a DevEco project (`entry/`, `build-profile.json5`, …). If the platform is missing from the project, first open the editor once so it registers the `harmonyos-next` build target (Project → Build), mirroring how the iOS target was added; document any editor-side one-time step in the commit message.

- [ ] **Step 3: Inventory the output** (informs Task 0.2; record in the task notes):

Run: `find cocos/build/harmonyos-next -maxdepth 4 -type d | head -30 && du -sh cocos/build/harmonyos-next/entry/libs 2>/dev/null || true`
Note where these live: generated `entry/src/main/cpp` (CMakeLists + glue), prebuilt `.so` location, data/assets directory, worker declarations in the generated `entry/build-profile.json5`, and `module.json5` deltas vs the template.

- [ ] **Step 4: Commit**

```bash
git add tools/cocos/build-harmonyos.sh
git commit -m "Add headless Cocos build script for harmonyos-next"
```

### Task 0.2: Vendor engine into entry + XComponent host renders on emulator

**Files:**
- Create: `harmonyos/entry/src/main/cpp/**` (vendored from build output)
- Create: `harmonyos/entry/src/main/ets/cocosvendor/**` (template ArkTS plumbing: `WorkerManager`, `common/*`, worker script, `components/*` as needed)
- Create: `harmonyos/entry/src/main/ets/pages/CocosBattlePage.ets`
- Modify: `harmonyos/entry/build-profile.json5` (externalNativeOptions + worker entry)
- Modify: `harmonyos/entry/src/main/module.json5` (only if the generated project shows required additions, e.g. permissions/metadata)
- Modify: `harmonyos/entry/src/main/resources/base/profile/main_pages.json` (register `pages/CocosBattlePage`)
- Modify: `tools/cocos/build-harmonyos.sh` (append rsync of cpp/, data → rawfile/cocos/, vendor ets)

- [ ] **Step 1: Extend the build script with the vendor step** (paths from Task 0.1's inventory; shape):

```bash
echo "==> vendoring engine artifacts into harmonyos/entry"
OUT="$ROOT/cocos/build/harmonyos-next"
DEST="$ROOT/harmonyos/entry"
rsync -a --delete "$OUT/entry/src/main/cpp/"  "$DEST/src/main/cpp/"
rsync -a --delete <generated-data-dir>/        "$DEST/src/main/resources/rawfile/cocos/"
# Template ArkTS plumbing is copied ONCE (committed, not --delete-synced):
# WorkerManager.ets, common/*, workers/cocos_worker.ets, libcocos type decls.
```

- [ ] **Step 2: Wire the native build into our entry module.** In `harmonyos/entry/build-profile.json5` add (adjust to the generated project's exact values):

```json5
buildOption: {
  externalNativeOptions: {
    path: './src/main/cpp/CMakeLists.txt',
    arguments: '',
    cppFlags: '',
    abiFilters: ['arm64-v8a'],
  },
  arkOptions: {
    // copy the worker list verbatim from the generated entry/build-profile.json5
  },
},
```

- [ ] **Step 3: Write the host page.** `CocosBattlePage.ets` — minimal first version, copying the XComponent conventions from the template's `pages/index.ets` (same `id`/`type`/`libraryname`, same WorkerManager startup), plus a back button. No bridge yet.

- [ ] **Step 4: Temporary dev entry.** Add a `CocosLab` button to the existing DevMenu page (same pattern as the iOS DevMenu CocosLab) that `router.pushUrl({ url: 'pages/CocosBattlePage' })`. (Removed in Task 2.3.)

- [ ] **Step 5: Build the HAP**

Run: `cd harmonyos && hvigorw assembleHap`
Expected: success, **0 `ArkTS:WARN`** from OUR files (vendored template warnings: if any appear, scope the warning gate per `.cursor/ohos-dev-commands.md` and record the decision in `cocos/README.md`).

- [ ] **Step 6: Emulator boot.** Start the DevEco emulator, install, open DevMenu → CocosLab.

Expected: the Battle scene renders (default state: cards + “Battle” top bar — the scene boots and its `battle/ready` goes unanswered, which is fine).
If the emulator fails on the engine `.so` (loader/arch errors): capture the log, retry the same steps on MatePad Air (`hdc list targets`, install per `.cursor/ohos-dev-commands.md`). Emulator-fail+device-pass = record “Cocos HOS is device-only” in `cocos/README.md` and routing treats the emulator as runtime-unavailable.

- [ ] **Step 7: Commit** (include `.so` sizes in the message; if total vendored size is >100 MB reconsider committing libs — flag to the user before proceeding).

```bash
git add harmonyos tools/cocos/build-harmonyos.sh
git commit -m "Vendor Cocos harmonyos-next engine into entry; XComponent host renders"
```

### Task 0.3: Bridge ping/pong spike (go/no-go)

**Files:**
- Create: `cocos/assets/scripts/bridge/transport.ts` (scene-side transport abstraction)
- Modify: `cocos/assets/scripts/bridge/BridgeClient.ts` (use transport)
- Modify: `harmonyos/entry/src/main/ets/pages/CocosBattlePage.ets` (probe hooks)

- [ ] **Step 1: Scene-side transport interface.** Extract from `BridgeClient.ts` so iOS keeps `native.jsbBridgeWrapper` and HOS gets its own implementation:

```ts
// transport.ts — pure interface + iOS impl + HOS impl(s)
export interface BridgeTransport {
    send(json: string): void;
    onReceive(handler: (json: string) => void): void;
    readonly available: boolean;
}
```

`BridgeClient` picks the first available transport. Existing iOS behavior must not change (run `npm test` + rely on Phase 2 iOS regression).

- [ ] **Step 2: Probe scene→ArkTS.** Candidates, in order:
  1. `native.bridge.sendToNative('wmBattleToNative', json)` — if the string bridge exists on openharmony in 3.8.8.
  2. `jsb.reflection` / ArkTS-bridge call (`JavaScriptArkTsBridge`): invoke a static method on a hand-written ArkTS class, e.g. `entry/src/main/ets/services/CocosBridgeReceiver.ets`:

```typescript
export class CocosBridgeReceiver {
  static onScriptMessage(json: string): string {
    // hop to main thread; emitter wired in Task 1.2
    return '';
  }
}
```

- [ ] **Step 3: Probe ArkTS→scene.** Candidates, in order:
  1. `native.bridge.onNative` fed by an ArkTS `sendToScript` equivalent (if the string bridge exists).
  2. Worker port: post from the UI thread to `cocos_worker` (template `WorkerManager` / `WorkerPort` API) and surface to the scene VM via the worker’s engine glue — inspect how the template delivers editbox/webview events to script for the exact call.

- [ ] **Step 4: Ping/pong.** Scene answers `{"v":1,"type":"battle/ready"...}` to any `battle/init`; ArkTS probe button sends init and logs the reply. Verify on emulator (or device per Task 0.2 outcome).

Expected: round-trip JSON both directions logged. **This is the feature go/no-go.** Record the chosen mechanism + thread-hopping rules in `cocos/README.md` (HarmonyOS section) before continuing.

- [ ] **Step 5: Commit**

```bash
git add cocos harmonyos
git commit -m "HOS bridge spike: scene<->ArkTS round-trip via <chosen mechanism>"
```

---

## Phase 1 — ArkTS bridge + routing

### Task 1.1: Contract codecs in ArkTS + fixtures gate

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/CocosBridgeMessages.ets`
- Create: `tools/cocos/gen-harmony-fixtures.sh`
- Create: `harmonyos/entry/src/test/CocosBridgeFixtures.ets` (generated, committed)
- Test: `harmonyos/entry/src/test/CocosBridgeMessages.test.ets`

- [ ] **Step 1: Generate fixtures module.** Script embeds every `shared/contracts/cocos-battle-bridge/fixtures/*.json` as exported const strings (ArkTS local tests cannot read repo files at runtime):

```bash
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/harmonyos/entry/src/test/CocosBridgeFixtures.ets"
{
  echo "// GENERATED by tools/cocos/gen-harmony-fixtures.sh — do not edit."
  echo "export const FIXTURES: Map<string, string> = new Map<string, string>(["
  for f in "$ROOT"/shared/contracts/cocos-battle-bridge/fixtures/*.json; do
    name="$(basename "$f" .json)"
    json="$(python3 -c 'import json,sys;print(json.dumps(json.dumps(json.load(open(sys.argv[1])))))' "$f")"
    echo "  ['$name', $json],"
  done
  echo "]);"
} > "$OUT"
echo "wrote $OUT"
```

- [ ] **Step 2: Write the failing test.** Port the assertion set from `cocos/tests/messages.test.ts` (same fixture names, same field expectations). Skeleton:

```typescript
import { describe, expect, it } from '@ohos/hypium';
import { decodeOutbound, encodeInbound } from '../main/ets/services/CocosBridgeMessages';
import { FIXTURES } from './CocosBridgeFixtures';

export default function cocosBridgeMessagesTest() {
  describe('CocosBridgeMessages', () => {
    it('decodes_every_fixture', 0, () => {
      FIXTURES.forEach((json: string, name: string) => {
        const msg = decodeOutbound(json) ?? decodeInboundForTest(json, name);
        expect(msg !== null).assertTrue();
      });
    });
    // + one focused test per message type asserting payload fields,
    //   mirroring cocos/tests/messages.test.ts cases.
  });
}
```

- [ ] **Step 3: Run to verify it fails** — per `.cursor/ohos-dev-commands.md` local-test command. Expected: FAIL (module missing).

- [ ] **Step 4: Implement `CocosBridgeMessages.ets`.** Direct port of `cocos/assets/scripts/bridge/messages.ts` types + encode/decode (ArkTS strict: explicit classes, no `any`, no destructuring). Same envelope `{v:1,type,payload}`, same type names.

- [ ] **Step 5: Run tests until green.** Register the suite in the local test list (`harmonyos/entry/src/test/List.test.ets`).

- [ ] **Step 6: Commit**

```bash
git add harmonyos tools/cocos/gen-harmony-fixtures.sh
git commit -m "ArkTS bridge codecs decode all 19 shared fixtures"
```

### Task 1.2: CocosBattleBridge adapter (BattleEngine ↔ scene)

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/CocosBattleBridge.ets`
- Test: `harmonyos/entry/src/test/CocosBattleBridge.test.ets`

- [ ] **Step 1: Define the transport seam** (so tests need no engine):

```typescript
export interface CocosTransport {
  send(json: string): void;
  setHandler(handler: (json: string) => void): void;
  present(): boolean;   // show engine window/page resources
  dismiss(): void;
}
```

- [ ] **Step 2: Write failing tests with a FakeTransport + real BattleEngine** (seeded rng), porting the iOS test set `ios/WordMagicGameTests/Core/CocosBattleBridgeTests.swift` case-for-case:
  - ready → init + state + question (+ bossIntro for monster 1)
  - correct submit → animation(forward) + state + question after 650 ms hold
  - wrong submit → animation(backward) + state, same question retained semantics as native
  - spellWrongTap → penalty state
  - battle end → finish routing callback fired once
  - re-entry: second `start()` on a booted transport re-sends init (full reset)

- [ ] **Step 3: Run to verify failure.**

- [ ] **Step 4: Implement the adapter.** Mirror `CocosBattleBridge.swift` translation tables 1:1 (message construction via Task 1.1 codecs; timings: 650 ms feedback hold, boss intro on first sight of each catalog index). Audio: invoke `BattleAudioMixer` exactly where `BattlePage.ets` does today (search its submit/finish handlers and reuse the same calls).

- [ ] **Step 5: Tests green → commit**

```bash
git add harmonyos
git commit -m "ArkTS CocosBattleBridge drives BattleEngine over the bridge contract"
```

### Task 1.3: Preference + route decision + entry points

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/CocosBattlePreference.ets`
- Test: `harmonyos/entry/src/test/CocosBattlePreference.test.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/HomePage.ets:469,542` (battle pushUrl sites)
- Modify: `harmonyos/entry/src/main/ets/pages/ResultPage.ets:190` (retry route)
- Modify: `harmonyos/entry/src/main/ets/entryability/EntryAbility.ets` (read `forceNativeBattle` want param → AppStorage)

- [ ] **Step 1: Failing tests for the decision table** (mirror `CocosBattleRoutingTests.swift`):

```typescript
// decision(runtimeAvailable, prefEnabled, fallbackActive, forceNative) -> 'cocos' | 'native'
expect(decideBattleRoute(true,  true,  false, false)).assertEqual('cocos');
expect(decideBattleRoute(true,  false, false, false)).assertEqual('native');
expect(decideBattleRoute(false, true,  false, false)).assertEqual('native');
expect(decideBattleRoute(true,  true,  true,  false)).assertEqual('native');
expect(decideBattleRoute(true,  true,  false, true )).assertEqual('native');
```

- [ ] **Step 2: Implement.** Preference persisted via the same storage util ConfigPage uses (`@ohos.data.preferences` wrapper already in the codebase — follow `GameConfig` persistence); default **true**. `fallbackActive` is a process-scoped AppStorage flag. `runtimeAvailable` = vendored lib loadable && (emulator allowed per Task 0.2 outcome).

- [ ] **Step 3: Route sites.** Replace the three literal `'pages/BattlePage'` battle-entry URLs with `battleRouteUrl()` from the new service. ResultPage retry keeps its `isTodayAdventure` branch.

- [ ] **Step 4: ohosTest forced-native.** `EntryAbility` reads `want.parameters?.forceNativeBattle === 'true'` → `AppStorage.setOrCreate('forceNativeBattle', true)`. Update the UI-test launch helper (locate the `startAbility` call in `harmonyos/entry/src/ohosTest/ets/test/` utils / `scripts/run_ui_tests.sh`) to pass the parameter so `BattleFlow.ui.test.ets` & co. stay on the native page.

- [ ] **Step 5: Tests green; run the full local suite; commit**

```bash
git add harmonyos scripts
git commit -m "Battle route decision with Cocos preference, fallback flag, forced-native tests"
```

### Task 1.4: Config page switch row

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/ConfigPage.ets` (after the audio switches, ~line 766)

- [ ] **Step 1: Add a「战斗画面」group** reusing the existing `audioSwitch`-style row (`Toggle({type: ToggleType.Switch})`, id `ConfigCocosBattleSwitch`, label `Cocos 战斗场景`), bound to `CocosBattlePreference`. Render the group only when the runtime is available (mirror iOS: hidden where it can do nothing).

- [ ] **Step 2: Build gate.** `hvigorw assembleHap` → 0 `ArkTS:WARN`; CodeLinter clean.

- [ ] **Step 3: Commit**

```bash
git add harmonyos
git commit -m "Config switch: Cocos battle scene (default on)"
```

### Task 1.5: CocosBattlePage lifecycle + fallback wiring

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/CocosBattlePage.ets`

- [ ] **Step 1: Wire the real transport** (Task 0.3 mechanism) into `CocosBattleBridge`; construct `BattleEngine` exactly as `BattlePage.ets:607` does (same `IQuestionSource`, same `BattleConfig` from GameConfig).

- [ ] **Step 2: Lifecycle:** `onPageShow` → bridge.start(); `onPageHide` → pause engine; back/escape → confirm dialog parity with native page; battle end → route to `pages/ResultPage` with the same params the native page passes (copy from `BattlePage.ets` finish handler).

- [ ] **Step 3: Ready timeout fallback:** if no `battle/ready` within 5 s of page show → set fallback flag, `router.replaceUrl({url:'pages/BattlePage'})`.

- [ ] **Step 4: Emulator smoke:** switch ON → Cocos battle plays a question end-to-end; switch OFF → native page; kill switch ON + simulate boot failure (temporarily rename lib in a local build) → auto-fallback lands on native. Record results.

- [ ] **Step 5: Commit**

```bash
git add harmonyos
git commit -m "CocosBattlePage drives live battles with fallback and result routing"
```

---

## Phase 2 — Adaptive resolution, device verification, docs

### Task 2.1: Adaptive resolution policy (shared scene)

**Files:**
- Create: `cocos/assets/scripts/ui/resolutionPolicy.ts` (pure)
- Modify: `cocos/assets/scripts/BattleSceneController.ts` (use it)
- Test: `cocos/tests/resolutionPolicy.test.ts`

- [ ] **Step 1: Failing vitest:**

```ts
import { describe, expect, it } from 'vitest';
import { choosePolicy } from '../assets/scripts/ui/resolutionPolicy';

describe('choosePolicy', () => {
    it('keeps FIXED_HEIGHT on wide phones', () => {
        expect(choosePolicy(2622, 1206, 1565, 720)).toBe('fixedHeight'); // iPhone 16 Pro
    });
    it('uses FIXED_WIDTH on 3:2 tablets', () => {
        expect(choosePolicy(2800, 1840, 1565, 720)).toBe('fixedWidth'); // MatePad Air
    });
    it('treats the exact design aspect as FIXED_HEIGHT', () => {
        expect(choosePolicy(1565, 720, 1565, 720)).toBe('fixedHeight');
    });
});
```

- [ ] **Step 2: Implement** (`screenW/screenH >= designW/designH ? 'fixedHeight' : 'fixedWidth'`), map to `ResolutionPolicy` in the controller via `screen.windowSize`. Keep the top bar anchored to the visible top: under `fixedWidth`, offset `topStatusY` by `(visibleHeight - designHeight) / 2` — expose that as a second pure function with its own test.

- [ ] **Step 3: vitest green (existing 45 + new), iPhone visual regression once in browser preview** (per `cocos/README.md` preview SOP — frame unchanged on 2.17:1).

- [ ] **Step 4: Commit**

```bash
git add cocos
git commit -m "Scene picks FIXED_WIDTH on squarer screens; tablet-safe top bar"
```

### Task 2.2: MatePad device verification [MANUAL gate]

- [ ] **Step 1: Rebuild chain:** `tools/cocos/build-harmonyos.sh` → `hvigorw assembleHap` → `hdc install …entry-default-signed.hap` (paths per `.cursor/ohos-dev-commands.md`).
- [ ] **Step 2: Full parity pass on MatePad Air** (mirror the iOS V1.1.0 checklist): all 5 question kinds, combo-3 crit overlay, hurt circle, boss intro bubble, spell pool penalty, escape + result + retry re-entry, config switch both ways, audio (BGM/SFX/TTS) on the Cocos path. `hdc shell snapshot_display` screenshots archived under the feature folder.
- [ ] **Step 3: Layout check:** no clipped cards on 3:2; top bar anchored; record one screenshot in the parity table.
- [ ] **Step 4: iPhone regression:** one battle on iOS device (scene shared) — visuals unchanged.
- [ ] **Step 5: Fix-forward loop:** any deviation → smallest fix → re-run the relevant gate; commit per fix.

### Task 2.3: Docs, gates, cleanup

**Files:**
- Modify: `cocos/README.md` (HarmonyOS embed section: recipe, bridge mechanism, emulator verdict, gotchas)
- Create: `docs/features/2026-06-11-cocos-battle-harmonyos/50-parity-checklist.md` (+ folder README per SOP templates)
- Modify: `CLAUDE.md` (one line: vendored Cocos engine C++ exemption to the ArkTS-only rule; HOS build script pointer)
- Modify: DevMenu (remove the temporary CocosLab entry from Task 0.2 — routing + config switch supersede it)

- [ ] **Step 1: Write docs;** parity checklist filled from Task 2.2 evidence.
- [ ] **Step 2: Final gates:** `cd harmonyos && hvigorw assembleHap` (0 `ArkTS:WARN`) → `codelinter -c ./code-linter.json5 . --fix` → full local test suite → `scripts/run_ui_tests.sh` (forced-native) → `cd cocos && npm test`.
- [ ] **Step 3: Commit, push branch, hand to user for merge decision**

```bash
git add -A
git commit -m "HarmonyOS Cocos battle: docs, parity checklist, gate run"
git push
```

---

## Self-review notes

- Spec coverage: §1→Tasks 0.2/1.2/1.3; §2→0.1/0.2/0.3; §3→1.1–1.5; §4→2.1; §5→2.2/2.3. Emulator-first is embedded in 0.2/0.3; device-only fallback path defined.
- Engine-dependent unknowns are isolated to Tasks 0.2 (worker/abi specifics from generated output) and 0.3 (bridge mechanism) with explicit decision-recording steps; every later task consumes their recorded outcome rather than assuming one.
- Type seams used consistently: `BridgeTransport` (scene), `CocosTransport` (ArkTS), `decideBattleRoute` signature shared between 1.3 tests and route sites.
