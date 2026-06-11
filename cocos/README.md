# WordMagicBattle (Cocos Creator 3.8)

Battle presentation layer for WordMagicGame. Logic stays in the native clients;
this project renders the battle scene and reports user input over the JSB bridge.
Contract: `shared/contracts/cocos-battle-bridge/`.

## Requirements
- Cocos Creator 3.8.x (Cocos Dashboard); editor binary at
  `/Applications/Cocos/Creator/3.8.8/CocosCreator.app`
- node 18+ (`npm install` for tests)
- For device deploys: Xcode, XcodeGen, cmake (brew), an unlocked iPhone

## Architecture rules (do not break these)

1. **The scene is presentation + input ONLY.** Question generation, answer
   judging, HP/combo/reward math, timers, audio, and learning records all live
   in the native host (`ios/WordMagicGame/Core/BattleEngine.swift` etc.). If a
   change needs game logic, it belongs in Swift + the bridge contract, not here.
2. **The bridge contract is the only interface.** Envelope
   `{v:1, type, payload}` over `JsbBridgeWrapper` events `wmBattleToScript` /
   `wmBattleToNative`. Schema + fixtures: `shared/contracts/cocos-battle-bridge/`.
   Both ends decode every fixture in their test suites
   (`cocos/tests/messages.test.ts`, `WordMagicGameTests/CocosBattleBridgeMessageTests`)
   — change the contract by changing fixtures first, then both codecs.
3. **`battle/init` is a full scene reset** (sent on first ready AND on
   re-entry — the engine boots once per process and the scene never reloads).
4. **Visual source of truth is the native BattleView**
   (`ios/WordMagicGame/Features/CoreLoop/BattleView.swift`). When styling,
   read the exact native values (fonts in pt, colors as RGB) and convert:
   **design space = native points × 1.5** (design resolution 1280×720,
   `ResolutionPolicy.FIXED_HEIGHT` — fitWidth crops vertically on tall phones).

## Code layout conventions

- `assets/scripts/BattleSceneController.ts` — orchestrator (cc component on Canvas).
- `assets/scripts/bridge/` — `messages.ts` (codecs, **pure TS**),
  `BridgeClient.ts` (the only file that touches `native.jsbBridgeWrapper`),
  `previewFakeHost.ts` (browser stand-in for the native host).
- `assets/scripts/ui/` — components (`FighterCard`, `QuestionPanel`,
  `AnswerRow`, `SpellPool`, `TopStatusBar`, `BossIntroBubble`, `effects.ts`)
  plus **pure** helpers (`theme.ts`, `format.ts`, `letterTemplate.ts`,
  `spellView.ts`, `answerFeedback.ts`, `animationPlan.ts`).
- **Pure modules must not import `cc`** — that is what makes them
  vitest-testable headless. Put every branchy decision (colors, slot layouts,
  option lists, animation step plans) in a pure module with tests; keep cc
  components as thin appliers.
- All UI is built **programmatically** (`nodeFactory.ts`); the `.scene` file is
  just a Canvas with the controller attached. The editor generates `.meta`
  files for new assets on its next focus — **commit them**.
- Write failing vitest tests first for pure logic (`npm test`), then implement.

## Engine gotchas (web/TS side — each cost real debugging time)

- **`UIOpacity` does NOT affect `Graphics` nodes.** Fading Graphics requires
  baking alpha into fill/stroke colors and redrawing per frame — use
  `animateGraphicsAlpha` in `nodeFactory.ts`. `UIOpacity` works fine on
  `Label`/`Sprite`.
- **`Sprite.SizeMode.CUSTOM` stretches the texture** to the content size.
  For character art use `loadCharacterSprite` (fits inside a box preserving
  `spriteFrame.originalSize` aspect) or art gets visibly squashed.
- **Long `Label` text clips by default.** For native
  `minimumScaleFactor`-style behavior set `label.overflow = Label.Overflow.SHRINK`
  plus an explicit `UITransform` content size.
- **`label.color` mutation needs reassignment** (`label.color = c.clone()`)
  or the renderer may not pick up the change.
- The page's **game loop freezes when the browser window is hidden**
  (see Preview SOP below) — Framerate 0 is almost never a code bug.
- `tsconfig` extends the Creator-generated base; `tsc --noEmit` reports a
  moduleResolution deprecation from that base — the editor compile is
  authoritative, vitest covers the pure modules.

## Commands
- Unit tests (pure TS, no editor): `npm test`
- **Headless iOS build (preferred for device deploys)**: `tools/cocos/build-ios.sh`
  — quits the editor, runs the Creator CLI build (data + Xcode project), and
  rebuilds the arm64 device engine libs. Then rebuild the host app in `ios/`.
- Editor build (alternative): Project → Build → iOS, output `build/ios`
  (gitignored). Editor builds reset the engine libs to x86_64-simulator;
  rerun the cmake arm64 steps afterwards.
- Art sync: `tools/cocos/sync-art.sh` (see Art pipeline).

## Iteration loop A — browser preview (fast, use this for UI/effects work)

1. Keep ONE editor instance open:
   `open -na "/Applications/Cocos/Creator/3.8.8/CocosCreator.app" --args --project <repo>/cocos`.
   `tools/cocos/build-ios.sh` QUITS the editor — device deploys end preview
   sessions; relaunch afterwards.
2. Preview URL: http://localhost:7456/ (probe with curl until 200; cold start
   takes ~45s). The FIRST page load after an editor start compiles scripts
   (black screen 10–30s) — reload once.
3. **The page's game loop freezes whenever its browser window is hidden:
   minimized, fully occluded, or on another macOS Space**
   (`document.visibilityState === "hidden"`, requestAnimationFrame stops).
   Symptoms: profiler shows Framerate 0 and fake-host data never applies.
   Keep the preview window visible on the active Space; don't fullscreen the
   editor over it. Diagnose with injected JS:
   `({v: document.visibilityState, f: cc.director.getTotalFrames()})`.
4. After editing scripts: focus the editor once (recompiles on focus,
   `osascript -e 'tell application "CocosCreator" to activate'`), wait ~8s,
   reload the preview page. If the preview server dies (curl 000,
   `lsof -iTCP:7456` empty), quit + relaunch the editor and wait out the cold
   start.
5. The preview runs `PreviewFakeHost` (no JSB bridge): cycles all five
   question kinds as you answer, simulates the 3-streak combo burst, and shows
   the monster intro bubble at startup. Extend the fake host whenever a new
   scene behavior needs preview-side verification.

## Iteration loop B — device verification (ground truth)

Fully scripted; no human interaction needed beyond an unlocked, connected phone:

```sh
tools/cocos/build-ios.sh                       # cocos data + arm64 engine libs
cd ios && xcodegen generate
xcodebuild -project WordMagicGame.xcodeproj -scheme WordMagicGame \
  -destination 'platform=iOS,id=<udid>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <devicectl-id> <DerivedData>/WordMagicGame.app
xcodebuild test ... -only-testing:WordMagicGameUITests/CocosBattleScreenshotUITests \
  -resultBundlePath /tmp/battle.xcresult     # starts a real battle, screenshots
xcrun xcresulttool export attachments --path /tmp/battle.xcresult --output-path /tmp/out
```

- The screenshot test takes a burst (1s/1.5s/2s/3s/7s) — early frames catch
  the monster-intro bubble window (~1.05s after scene ready).
- Headless bridge repro without UI: launch with `-- -CocosLabAutoRun` via
  `devicectl device process launch --console` (live NSLog stream).
- Device crash logs: `xcrun devicectl device copy from --domain-type
  systemCrashLogs --source / --destination <dir>` then parse the `.ips` JSON.

## Art pipeline

- Character art SOURCES are SVGs in the iOS asset catalog
  (`ios/WordMagicGame/Resources/Assets.xcassets/Character*.imageset`).
- `tools/cocos/sync-art.sh` rasterizes them to 512px PNGs under
  `assets/resources/art/characters/` via `rsvg-convert` (brew librsvg).
- The outputs are **generated** — never hand-edit; edit the SVG source and
  re-run the sync. Textures load at runtime via
  `resources.load('art/characters/<Key>/spriteFrame')`.

## iOS embed (Phase 0 spike recipe — keep updated)

The host app (`ios/WordMagicGame`) embeds the Cocos runtime directly; there is
no separate Cocos app. Verified with Cocos Creator 3.8.8 + Xcode 26.4.

### Platform support
- **Device (arm64)**: fully supported — this is the only path that links the engine.
- **Simulator**: NOT supported. Cocos 3.8 prebuilt externals (v8 etc.) ship
  x86_64-sim + arm64-device slices only; the generated project sets
  `EXCLUDED_ARCHS=arm64` for simulator. The host shim
  (`ios/WordMagicGame/CocosRuntime/WMCocosRuntimeShim.mm`) compiles to a stub on
  simulator (`isLinked == NO`) and the app falls back to the native BattleView.
  Simulator UI automation therefore always exercises the native battle.

### Build steps (local machine)
1. Cocos build (headless `tools/cocos/build-ios.sh` or editor Build). Generates
   `build/ios/ios/proj` (CMake/Xcode project), `build/ios/ios/data` (runtime
   assets), and `native/engine/` glue.
2. Device engine libs (editor/CLI Make only builds x86_64-simulator):
   ```sh
   CMAKE=/Applications/Cocos/Creator/3.8.8/CocosCreator.app/Contents/Resources/tools/cmake/bin/cmake
   $CMAKE --build cocos/build/ios/ios/proj --config Release --target cocos_engine  -- -quiet -sdk iphoneos -arch arm64
   $CMAKE --build cocos/build/ios/ios/proj --config Release --target boost_container -- -quiet -sdk iphoneos -arch arm64
   ```
   Note: the CMake Xcode project regenerates itself on the first build after a
   CMakeLists change (ZERO_CHECK); if a flag change seems ignored, run the build
   twice.
3. Host app: `cd ios && xcodegen generate` — `ios/project.yml` carries all the
   integration (engine/header paths, device-only `OTHER_LDFLAGS[sdk=iphoneos*]`
   incl. `-Wl,-ld_classic`, the `Copy Cocos Data` script phase that rsyncs
   `build/ios/ios/data/` into the app bundle root, bridging header).

### How the runtime boots (WMCocosRuntimeShim)
- The engine resolves its render surface via
  `UIApplication.delegate.window.rootViewController.view` (SystemWindow.mm), so
  the shim creates a dedicated `UIWindow` (root VC = engine Metal `View`),
  assigns it to the host `AppDelegate.window`, then drives
  `AppDelegateBridge application:didFinishLaunchingWithOptions:`.
- Engine boot is once-per-process; battles after the first show/hide the window
  and pause/resume via `applicationWillResignActive` / `DidBecomeActive`.
- Engine compile defines are mirrored in
  `ios/WordMagicGame/CocosRuntime/WMCocosEnginePrelude.h`; include it before any
  engine header.

### Known quirks (native side — each caused a real crash or dead feature)
- `native/engine/ios/CMakeLists.txt` adds `-Wno-invalid-specialization`
  (Xcode 26 clang rejects enoki's std-trait specializations on the arm64 path).
- `JsbBridgeWrapper addScriptEventListener:` (MRC) **takes ownership** of the
  listener — it calls `[listener release]` internally. ARC callers must hand it
  an extra retain (`CFRetain`) or the block is over-released and the first
  `triggerEvent` jumps through a dangling pointer (see WMCocosRuntimeShim.mm).
- The actual `UIApplication.delegate` is SwiftUI's internal class; reach the
  `@UIApplicationDelegateAdaptor`'s `window` property with `performSelector:`
  (message forwarding) — KVC `setValue:forKey:` throws `NSUnknownKeyException`.
- A `UIWindow` created without attaching a `UIWindowScene` never becomes
  visible in scene-based apps; the shim attaches the foreground scene.
- ObjC++ blocks: use explicit types instead of `typeof(self)` (C++ mode).
- Register the script listener BEFORE engine boot; `battle/ready` can fire
  during startup.
- Spike verification: DevMenu → CocosLab runs a ping/pong round-trip and
  dismisses the Cocos window on success. Headless repro: launch with
  `-CocosLabAutoRun`. Automated check: `CocosLabSpikeUITests` (device only;
  auto-skips on simulator).

## Visual parity workflow (how the scene was matched to native)

1. Read the native implementation for exact values (`BattleView.swift`,
   `MessageBubble.swift`) — fonts/sizes in pt (×1.5 → design px), colors as
   `Color(red:green:blue:)` (×255 → hex).
2. Compare against `assets/screenshots/` and user-provided screenshots.
3. For motion/effects: ask for a screen recording of the native page, extract
   frames (`ffmpeg -i rec.mov -vf "fps=8,scale=700:-1" /tmp/f%03d.png`), and
   diff the animation phases frame by frame (timings like the 340ms impact
   delay and 650ms feedback hold came from `BattleView.swift` constants).
4. Verify in preview interactively (fake host), then on device via the
   screenshot test before pushing.
