# Cocos battle scene — HarmonyOS integration (design)

Date: 2026-06-11
Branch: `cocos-battle-harmonyos`
Status: approved by user (sections reviewed 2026-06-11)

## Goal

Bring the Cocos battle scene shipped on iOS in V1.1.0 to the HarmonyOS NEXT
client. The ArkTS app keeps all battle logic; the shared `cocos/` scene and the
`shared/contracts/cocos-battle-bridge/` contract are reused as-is. New work is
limited to: engine embedding, an ArkTS bridge, routing with native fallback,
and an adaptive resolution policy for tablet aspect ratios.

Decisions fixed during brainstorming:

- Real device: **MatePad Air** (hdc). **Emulator-first**: the Phase 0 spike
  targets the DevEco emulator (Mac arm64) before device verification; if the
  emulator cannot run the engine, the spike falls back to the device and the
  emulator permanently uses the native battle (routing handles this).
- Routing/fallback **fully mirrors iOS**: config-page switch (default ON),
  auto-fallback on boot failure / ready timeout, UI automation forces native.
- **ArkTS-only rule exemption (user-approved)**: the vendored Cocos engine
  (generated C++ glue, prebuilt `.so`, CMakeLists) does not count against the
  "HarmonyOS feature work is ArkTS only" rule. All hand-written code stays
  ArkTS. Engine C++ is vendored, never hand-edited.
- Milestone: **dev-complete** (all question kinds + effects + fallback verified
  on device, merged to main). AppGallery release is separate work.
- Approach A (user-approved): engine artifacts vendored into the existing
  `entry` module, mirroring the official `harmonyos-next` build template
  structure. A separate native HAR module was considered and rejected for
  spike risk; revisit only if the in-entry C++ build proves unacceptable.

## 1. Architecture and module boundaries

```
harmonyos/entry
├── src/main/cpp/                     # vendored: Cocos glue + prebuilt .so + CMakeLists (never hand-edited)
├── src/main/resources/rawfile/cocos/ # scene data assets (generated, synced by script)
└── src/main/ets/
    ├── pages/CocosBattlePage.ets         # XComponent host page + engine lifecycle (pause/resume/dispose)
    ├── services/CocosBattleBridge.ets    # contract codecs + BattleEngine.ets adapter
    └── services/CocosBattlePreference.ets# switch preference (default ON) + route decision
```

- **Zero logic migration**: `BattleEngine.ets` and sibling services are
  untouched; the bridge only translates, exactly like iOS
  `CocosBattleBridge.swift`.
- **Shared scene**: one `cocos/` project serves both platforms. This feature
  adds only the adaptive resolution policy (and HOS-conditional branches if
  the spike uncovers any).
- **Contract unchanged**: schema + 19 fixtures stay the acceptance basis.
- Native `BattlePage.ets` remains the fallback presentation.

## 2. Embedding and build chain (emulator-first)

Generation and extraction:

1. Cocos Creator CLI build `platform=harmonyos-next` →
   `cocos/build/harmonyos-next/` (a complete DevEco template project).
2. Extract into `harmonyos/entry`:
   - `src/main/cpp/` — engine entry (XComponent NAPI registration, prebuilt
     engine libs, CMakeLists);
   - scene data assets → `rawfile/cocos/`;
   - the template's ArkTS launch page is **reference only** (XComponent
     id/type/libraryname conventions, worker startup); our host page is
     hand-written.
3. `entry/build-profile.json5` gains `externalNativeOptions` (CMakeLists path,
   abiFilters) — a Hvigor project-file change, explained here per project rule.

Tooling (mirrors `tools/cocos/build-ios.sh`):

- New `tools/cocos/build-harmonyos.sh`: quit editor → Creator CLI build →
  rsync engine artifacts/data into entry → prompt for hvigor build.
- Generated artifacts are committed directly (HOS ships a single arm64 `.so`
  set). If size proves unacceptable at spike time, switch to LFS or a fetch
  script — decide with real numbers.

Emulator-first go/no-go:

- Phase 0 verifies on the **DevEco emulator** (Mac arm64): XComponent renders
  the scene and the bridge answers ping/pong.
- Emulator failure → retry the same spike on MatePad Air; only a device
  failure is a no-go for the feature.
- Findings land in a new HarmonyOS section of `cocos/README.md`, structured
  like the iOS embed recipe.

Build discipline: HAP builds keep **0 `ArkTS:WARN`** and pass CodeLinter for
our ArkTS code; vendored C++ is outside both gates.

## 3. Bridge and routing (ArkTS side)

Message channel:

- Scene side unchanged: events `wmBattleToScript` / `wmBattleToNative`,
  `{v:1,type,payload}` envelopes (`native.jsbBridgeWrapper` also exists on the
  openharmony platform).
- On HOS the engine runs in a **worker thread**; the exact ArkTS bridge API is
  locked during the Phase 0 spike from the template. `CocosBattleBridge.ets`
  hides the thread marshalling behind a synchronous-style
  `start()/send()/onMessage` surface.

Engine adapter (mirrors iOS `CocosBattleBridge.swift`):

- `battle/ready` → `battle/init` (full-reset semantics) + `battle/state` +
  `battle/question` + first-monster `battle/bossIntro`.
- `battle/submit` → judge → `battle/animation` + `battle/state` +
  `battle/question`, with the same 650 ms feedback hold.
- `battle/spellWrongTap`, escape, and result routing follow the iOS sequence;
  audio stays native (`BattleAudioMixer` reacts to bridge events).
- Acceptance: ArkTS codecs decode all 19 shared fixtures in local tests.

Routing and fallback (same behavior table as iOS):

| Condition | Result |
| --- | --- |
| Preference ON (default) and runtime available | Cocos battle |
| Config switch OFF | native BattlePage |
| Engine boot failure / ready timeout (5 s) | auto-fallback + in-process fallback flag |
| ohosTest UI automation | forced native via launch parameter (parity with iOS `-UITestForceNativeBattle`) |
| Battle re-entry | engine singleton reused; `battle/init` resets the scene |

The config-page switch row reuses the existing ConfigPage switch style.

## 4. Adaptive resolution (tablet + phone)

In `BattleSceneController`, replace the hard-coded policy with a pure decision
function shared by both platforms:

```
screen aspect ≥ design aspect (1565/720 ≈ 2.17) → FIXED_HEIGHT (status quo, iPhone unchanged)
screen aspect < design aspect                   → FIXED_WIDTH (MatePad 3:2: full content, background fills the extra vertical space)
```

- The decision (and the top-bar anchoring offset under FIXED_WIDTH) are pure
  TS functions with vitest coverage (phone / tablet / square boundaries).
- The background layer already draws at 2× design size, covering extensions.
- One iPhone regression pass confirms no visual change on the wide path.

## 5. Testing and verification

| Layer | Content |
| --- | --- |
| vitest (`cocos/`) | resolution decision function; existing 45 tests stay green |
| ArkTS local tests | codecs vs 19 fixtures; routing decision table; adapter message sequence (mirrors iOS routing/bridge test sets) |
| Emulator | Phase 0 spike (render + ping/pong) → post-integration smoke (switch toggle, fallback path) |
| MatePad device | all 5 question kinds + combo crit / hurt effects + boss bubble + escape/result + battle re-entry; hdc screenshots archived |
| Build gates | HAP 0 `ArkTS:WARN`; CodeLinter; `ohosTest` UI suite green on the forced-native path |
| Docs | `cocos/README.md` HarmonyOS embed section; feature folder parity checklist per SOP |

## Phases

| Phase | Scope | Gate |
| --- | --- | --- |
| 0 | Embed spike: CLI build, vendor into entry, XComponent renders, bridge ping/pong (emulator → device) | go/no-go |
| 1 | ArkTS bridge + routing: codecs, adapter, preference + fallback, config switch | fixtures + routing tests green |
| 2 | Device verification + adaptive resolution + docs: full play parity on MatePad, README/parity checklist | all gates green, merge to main |
