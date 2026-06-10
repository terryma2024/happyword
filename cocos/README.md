# WordMagicBattle (Cocos Creator 3.8)

Battle presentation layer for WordMagicGame. Logic stays in the native clients;
this project renders the battle scene and reports user input over the JSB bridge.
Contract: `shared/contracts/cocos-battle-bridge/`.

## Requirements
- Cocos Creator 3.8.x (Cocos Dashboard)
- node 18+ (`npm install` for tests)

## Commands
- Unit tests (pure TS, no editor): `npm test`
- **Headless iOS build (preferred)**: `tools/cocos/build-ios.sh` — quits the
  editor, runs the Creator CLI build (data + Xcode project), and rebuilds the
  arm64 device engine libs. Then rebuild the host app in `ios/`.
- Editor build (alternative): open in Cocos Creator → Project → Build →
  platform iOS, output `build/ios` (gitignored). Editor builds reset the
  engine libs to x86_64-simulator; rerun the cmake arm64 steps afterwards.
- Device battle screenshot check: `xcodebuild test … -only-testing:`
  `WordMagicGameUITests/CocosBattleScreenshotUITests` (device destination),
  then export attachments from the result bundle.

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

### Build steps (local machine)
1. Editor build: Cocos Creator → Project → Build (platform iOS, output
   `build/ios`, start scene `Battle`). This generates `build/ios/ios/proj`
   (CMake/Xcode project), `build/ios/ios/data` (runtime assets), and
   `native/engine/` glue.
2. Device engine libs (the editor's Make only builds x86_64-simulator):
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
- Script bridge: `JsbBridgeWrapper` events `wmBattleToScript` / `wmBattleToNative`
  with JSON envelopes (`shared/contracts/cocos-battle-bridge/`).
- Engine compile defines are mirrored in
  `ios/WordMagicGame/CocosRuntime/WMCocosEnginePrelude.h`; include it before any
  engine header.

### Known quirks
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
- Spike verification: DevMenu → CocosLab runs a ping/pong round-trip against
  the `BridgeProbe` scene script and dismisses the Cocos window on success.
  Headless repro: launch the app with `-CocosLabAutoRun`
  (`xcrun devicectl device process launch --console --device <id>
  com.terryma.wordmagicgame -- -CocosLabAutoRun`). Automated check:
  `WordMagicGameUITests/CocosLabSpikeUITests` (device destination only).
