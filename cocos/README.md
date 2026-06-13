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
   `{v:1, type, payload}` over a per-platform transport
   (`assets/scripts/bridge/transport.ts`): `JsbBridgeWrapper` events
   `wmBattleToScript` / `wmBattleToNative` on iOS, ArkTS reflection +
   `evalString` on HarmonyOS (see “HarmonyOS embed” below).
   Schema + fixtures: `shared/contracts/cocos-battle-bridge/`.
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
- **Graphics drawn while a node is `active = false` may never render on the
  NATIVE platform** (fine in web preview — a web/native divergence). If a
  Graphics node starts hidden and is activated later (e.g. the level badge),
  redraw its content on activation (`redrawRoundedRect`).
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
   **Automated workaround — inject a worker frame pump right after every
   `navigate`** (worker timers are exempt from visibility throttling and the
   pump drives engine boot AND the scene):
   ```js
   if (!window.__agentPump) {
     const w = new Worker(URL.createObjectURL(new Blob(
       ['setInterval(()=>postMessage(0),33)'], {type:'text/javascript'})));
     w.onmessage = () => { if (document.visibilityState==='hidden'
       && typeof cc!=='undefined' && cc.game?.step) { try{cc.game.step();}catch(e){} } };
     window.__agentPump = w;
   }
   ```
   The scene controller also installs its own pump in preview mode
   (`startHiddenTabPump`), but only after the scene loads — the injected pump
   covers engine boot too. **Pixel screenshots of a hidden window may be
   stale/black**; verify state via injected JS instead (walk the node tree and
   read `cc.Label` strings, query `cc.director.getScene()`), and reserve
   screenshots for when the window is visible.
   Quick health probe:
   `({v: document.visibilityState, f: cc.director.getTotalFrames(), s: cc.director.getScene()?.name})`.
4. After editing scripts: focus the editor once (recompiles on focus,
   `osascript -e 'tell application "CocosCreator" to activate'`), wait ~8s,
   reload the preview page. If the preview server dies (curl 000,
   `lsof -iTCP:7456` empty), quit + relaunch the editor and wait out the cold
   start.
5. The preview runs `PreviewFakeHost` (no JSB bridge): cycles all five
   question kinds as you answer, simulates the 3-streak combo burst, and shows
   the monster intro bubble at startup. Extend the fake host whenever a new
   scene behavior needs preview-side verification.
6. **Pin the preview start scene** so the preview never depends on which scene
   the editor has open (otherwise the editor logs 无法查到当前场景 JSON 数据
   and the preview loads an empty scene): set
   `cocos/profiles/v2/packages/preview.json` →
   `general.start_scene = "fbc8208b-dc3b-4c53-a87e-14a72766a372"` (Battle.scene
   uuid). The file is gitignored (editor-local prefs); edit it while the editor
   is CLOSED, then start the editor. If the page loaded before the asset DB was
   ready the scene stays null — just reload the page.

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

## HarmonyOS embed (V1.1.0 HOS Tasks 0.1–0.3 — keep updated)

The HarmonyOS app (`harmonyos/entry`) embeds the engine compiled from source
(`tools/cocos/build-harmonyos.sh` + hvigor; see that script and
`harmonyos/entry/src/main/ets/services/CocosEngineHost.ets` for the boot
recipe). Verified on the arm64 emulator (`hdc` target `127.0.0.1:5555`);
spike route: `aa start -a EntryAbility -b com.terryma.wordmagicgame --ps
cocosLab true` (debug builds only). The physical verification target is the
MatePad (`hdc` target `5FFBB25926205346`, 3:2 screen) — wake/unlock routine
and the pinned password live in `scripts/run_ui_tests.sh`
(`unlock_target_device_if_needed`); if the hdc channel reports
`Unauthorized`, confirm the RSA dialog on the tablet (requires physical
access), or fall back to the emulator.

### Bridge mechanism (Task 0.3, locked)

`native.jsbBridgeWrapper` is **null** on OPENHARMONY — the engine only
compiles `ScriptNativeBridge` for ANDROID/IOS/OSX/OHOS
(`cocos/native-binding/impl.ts` + `jsb_module_register.cpp`), so the iOS
event-bus transport cannot exist here. The scene therefore selects a
transport at runtime (`assets/scripts/bridge/transport.ts`); BridgeClient's
public API is unchanged and the contract envelope stays
`{v:1, type, payload}`.

**Scene → ArkTS** (`ArkTsReflectionTransport.send`):
`native.reflection.callStaticMethod(clsPath, method, json, false)` backed by
the engine's `JavaScriptArkTsBridge`. The engine resolves it through the
`executeMethodAsync` threadsafe function the host registered (UI thread,
`CocosEngineHost.ensureBooted`), napi-loads the ArkTS module
`entry/src/main/ets/services/CocosBridgeReceiver` **by path**
(`napi_load_module_with_info`) and calls its exported
`onSceneMessage(json, done)` on the **UI thread**.
- The receiver module path must be listed in
  `buildOption.arkOptions.runtimeOnly.sources` of
  `harmonyos/entry/build-profile.json5` or the runtime load fails.
- The engine **blocks the game thread** on an internal promise until
  `done()` is invoked — the receiver calls `done('ok')` first and only then
  dispatches into app code. Keep handlers light; never make the UI thread
  wait on the game thread inside a handler (deadlock).
- 4th `callStaticMethod` parameter `false` = async variant; `true` (sync)
  also blocks and additionally takes the return value — not needed.

**ArkTS → scene** (`CocosEngineHost.sendToScene`): libcocos.so's
`evalString(snippet)` called from the **UI thread**. The engine detects the
UI main thread (where the XComponent loaded the NAPI module) and re-schedules
the eval onto the game thread — async, no return value, thread-safe. The
scene pre-registers `globalThis.__wmBattleInbound = handler` in
`ArkTsReflectionTransport.onReceive`.
- Escaping rule: the snippet is
  `` `globalThis.__wmBattleInbound && globalThis.__wmBattleInbound(${JSON.stringify(json)})` ``
  — `JSON.stringify` of the *string* is the only escaping step needed (it
  yields a valid JS string literal).
- `evalString` silently drops calls before the game loop runs
  (`CC_CURRENT_APPLICATION()` null) — only send after the scene's organic
  `battle/ready` arrived.
- Never call `evalString` from a non-UI thread: the engine would eval on the
  calling thread instead of scheduling onto the game thread.

Round-trip measured at ~10 ms on the emulator (ping sent 14:03:35.551,
pong logged .561). The Task 0.3 probe UI (Ping button + hilog handler on
`pages/CocosBattlePage.ets`) was removed in Task 1.5 — the page now drives
live battles through `CocosBattleBridge`; for manual entry use DevMenu →
CocosLab or just start a battle with the Config switch ON.

### Known quirks (HarmonyOS side)
- Engine cmake flags: `USE_SE_JSVM ON`, `USE_SOCKET OFF`; scene
  `console.log` lands in hilog under tag `A00000/HMG_LOG`.
- Vendored template plumbing under
  `harmonyos/entry/src/main/ets/cocosvendor/` is regenerated by
  `tools/cocos/build-harmonyos.sh` — never hand-edit; extend the script's
  scripted-sed + grep-assertion pattern if a vendored tweak is unavoidable.
- **ArkTS:WARN policy for cocosvendor/ (cold builds only):** the vendored
  adapter emits warnings that only surface when its files actually recompile
  (incremental `assembleHap` looks falsely clean). Two classes are accepted
  and allowlisted in `scripts/check_arkts_warnings.sh`:
  `arkts-no-globalthis` (sys-ability-polyfill.ets + cocos_worker.ets define
  worker globals the native engine looks up via napi — ArkTS has no
  compliant substitute) and the `MessagePort.postMessage` may-throw advisory
  (WorkerPort.ts / ui_port.ts message pump — a try/catch wrapper would alter
  engine plumbing). The third class, missing-permission hints
  (GET_NETWORK_INFO / VIBRATE), is NOT accepted: fix-up 3 in
  `build-harmonyos.sh` stubs `getNetworkType` (returns -1) and `vibrate`
  (no-op) because the battle scene uses neither and the undeclared calls
  would throw error 201 at runtime anyway.
- Engine boot is once per process (`CocosEngineHost.ensureBooted` +
  `notifySurfaceLoaded` posts `onXCLoad` at most once); `battle/init` being a
  full scene reset is what makes page re-entry work.
- **Surface lifecycle (Task 1.5, emulator-verified):** the engine render loop
  is only stopped by the app-lifecycle `onHide` — the JSPAGE `onPageHide`
  relay does nothing (`napiOnPageHide` just logs). A frame racing the
  XComponent surface destroy aborts the process in `eglSwapBuffers`
  (`EGL_BAD_SURFACE`, `GLES3GPUContext.cpp:332`). `CocosEngineHost` therefore
  derives visibility from `booted && appForeground && pageActive &&
  surfaceAlive` and `CocosBattlePage` calls `pauseRendering()` before every
  `replaceUrl`.
- **Surface re-creation works via an engine patch** (stock Cocos 3.8.8 OH
  crashes on it — `onSurfaceCreatedCB` registered the re-created surface as
  a NEW `SystemWindow` id while the GFX swapchain stayed bound to the
  removed original window, and the game-thread
  `WM_XCOMPONENT_SURFACE_CREATED` handler was empty, so the first frame
  after resume swapped a dead EGLSurface and aborted at
  `GLES3GPUContext.cpp:332`). The patch is a vendored copy of
  `OpenHarmonyPlatform.cpp` at
  `harmonyos/entry/src/main/cpp/cocos-patches/` (patched blocks marked
  `WMG PATCH(surface-recreation)`); the adapter
  `harmonyos/entry/src/main/cpp/CMakeLists.txt` swaps it into the
  `cocos_engine` target sources and pins the Creator bundle original by
  SHA256, so a Creator upgrade fails the build loudly instead of silently
  dropping the patch. Mechanism — reuse of the already-working
  SURFACE_HIDE/SHOW machinery: surface destroy broadcasts
  `WindowDestroy(mainWindowId)` (swapchain releases its EGL surface) and
  KEEPS the `SystemWindow` registered; surface re-create rebinds the
  existing main window to the new native handle (`setWindowHandle`) and the
  game thread broadcasts `WindowRecreated(mainWindowId)` →
  `RenderWindow::onNativeWindowResume` → swapchain `createSurface` +
  `generateFrameBuffer`. Resume ordering is safe because the rebind message
  and the host's `onShow` relay travel through the same FIFO worker queue,
  and `CocosEngineHost` only resumes rendering from the new surface's
  `onLoad`. Net effect: EVERY battle of a process runs in Cocos
  (emulator-verified 2026-06-11: battle → escape → result → home → battle
  three times in one process — each re-entry renders, takes touch input, no
  cppcrash; backgrounding mid-battle and resuming is also clean. 再来一局 on
  a today-adventure result routes through HomePage by design, so it is the
  same re-entry path).
- **Receiver exception rule:** `CocosBridgeReceiver.onSceneMessage` calls
  `done('ok')` BEFORE dispatching into app code. A throw before `done()` would
  permanently hang the game thread (it blocks on an internal NAPI promise). A
  throw after `done()` — if unguarded — leaves a pending NAPI exception on the
  UI thread. The receiver wraps `dispatchSceneMessage` in try/catch and logs
  via `hilog.error` tag `WMBridge` to prevent that silent corruption.
- **Ready-latch replay on re-entry:** `battle/ready` fires exactly ONCE per
  process lifetime (the engine never reloads). `CocosEngineHost.sceneReady`
  latches true on first receipt. When `setSceneMessageHandler` is called on
  a subsequent page entry and `sceneReady` is already true, the host
  synchronously replays a synthetic `'{"v":1,"type":"battle/ready","payload":{}}'`
  to the new handler so the page always gets a ready signal regardless of
  whether it was present for the original event.

## Android embed (AND Tasks 0.1–2.2 — keep updated)

The Android app (`android/app`) embeds the engine compiled from source.
Build chain: `tools/cocos/build-android.sh` (headless Creator export of
scene data + the generated android proj into `cocos/build/android/`) →
Gradle `externalNativeBuild` pointing at the thin adapter
`android/app/src/main/cpp/cocos/CMakeLists.txt`, which derives RES_DIR /
COMMON_DIR from its own location and includes the Cocos common CMake chain
(engine C++ comes from the installed Creator 3.8.8 app bundle; libcocos.so
is built by Gradle, not by Creator). Engine Java glue is vendored at
`android/app/src/main/java/com/cocos/lib/` (script-only vendor — never
hand-edit).

Verified on the arm64 emulator `emulator-5556` (Pixel 9, API 36). Spike
route (debug builds export the activity):
`adb -s emulator-5556 shell am start -n cool.happyword.wordmagic/.cocos.CocosBattleActivity`.

### Activity hosting

`cool.happyword.wordmagic.cocos.CocosBattleActivity` extends the engine's
`CocosActivity` (a `GameActivity` subclass). Each `onCreate` loads the
native lib (idempotent) and calls `onCreateNative`; each `onDestroy` tears
the surface/views down. Unlike HarmonyOS there is NO once-per-process boot
guard and none is needed — see the re-entry verdict below.

### Bridge mechanism (Task 0.3, locked)

On Android `native.jsbBridgeWrapper` EXISTS, so the scene picks the
`JsbWrapperTransport` (same transport family as iOS): it listens on event
`wmBattleToScript`, sends on `wmBattleToNative`, envelope `{v:1, type,
payload}` unchanged.

**Kotlin → scene:** `JsbBridgeWrapper.getInstance()
.dispatchEventToScript("wmBattleToScript", json)`. The engine's
`Java_com_cocos_lib_JsbBridge_nativeSendToScript` marshals onto the game
thread via `performFunctionInCocosThread`, so calling from the main thread
is safe. Two gotchas (both verified on the emulator):
- The native side dereferences `ScriptNativeBridge::bridgeCxxInstance`
  without a null check, and events with no JS listener are dropped — a
  message dispatched before the scene's `BridgeClient` registers is
  **silently lost** (no crash, no pong; first boot took ~7.5 s on the
  emulator and a 4 s blind delay lost the probe). Only send after the
  scene's organic `battle/ready`; the real adapter must queue outbound
  messages until then.
- `JsbBridgeWrapper` is a **process-level singleton**: listeners survive
  activity recreation, and `addScriptEventListener` does NOT de-duplicate
  despite its javadoc. Remove your listener in `onDestroy` or each
  re-entry stacks another copy.

**Scene → Kotlin:** `JsbBridgeWrapper.addScriptEventListener
("wmBattleToNative") { json -> ... }`. Callbacks arrive on the **Cocos
game thread** (an unnamed pthread — logged as `Thread-2`, and a new
`Thread-N` after every activity recreation). Hop to the main thread before
touching UI/state.

Round-trip measured at ~10 ms on the emulator (ping 23:40:00.302 → pong
.305 logged on the game thread). `battle/init` applies as a full scene
reset (probe: playerMaxHp 7 → HP 7/7 rendered, startingSeconds 300 →
Countdown 5:00). The Task 0.3 probe has been replaced by the real adapter:
`CocosBattleBridge.kt` (sequencing, question hold, finish-notify guard)
fed by the `CocosBridgeMessages.kt` codecs (all 19 shared contract
fixtures pass in `:app:testDebugUnitTest`).

### Re-entry + backgrounding verdict (Task 0.3, emulator-verified)

- **Back → relaunch (×3): clean, no guard needed.** The process survives
  back (activity finishes, pid stays). Each `am start` creates a new
  `CocosActivity`, and the engine performs a **full JS reload per activity
  entry**: a fresh game thread spins up and the scene emits a fresh organic
  `battle/ready` every time (unlike HarmonyOS, where the engine boots once
  per process and ready must be latch-replayed). Verified 3 consecutive
  back/relaunch cycles in one process: scene renders, init applies,
  ping/pong round-trips, zero `FATAL`/`AndroidRuntime` lines, no new
  dropbox crash entries. No iOS-style `isBooted` guard was added — the
  stock `CocosActivity` lifecycle handles recreation.
- **Home → relaunch from recents: clean.** Same activity instance gets
  `onPause`/`onResume`; the JS VM keeps running (no new `battle/ready`),
  scene state is preserved and the surface re-attaches without a crash.
- Implication for the Task 1.x adapter: per-activity bridge state is
  correct on Android (register listener in `onCreate`, remove in
  `onDestroy`, wait for that entry's own `battle/ready`); do NOT port the
  HarmonyOS once-per-process latch.

### Production integration (Tasks 1.3–1.4 — routing, session handoff, lifecycle)

All under `android/app/src/main/java/cool/happyword/wordmagic/cocos/`
(hand-written Kotlin — only `com/cocos/lib/` and `cpp/cocos/` are vendored).

- **Routing** (`CocosBattlePreference.kt`): `chooseBattleRoute(context)` at
  every battle-start site. Four-input pure decision —
  `isCocosRuntimeAvailable()` && pref enabled && !`fallbackActive` &&
  !`forceNativeBattle` → COCOS, anything else → NATIVE. The preference is
  `wordmagic_cocos_battle_prefs` / `battle.useCocosScene` (string
  `"true"`/`"false"`, absent → **default ON**, iOS/HOS parity). The user
  switch is 游戏配置 → 战斗画面 →「Cocos 战斗场景」. On Android
  `libcocos.so` is always bundled, so there is no "library missing" probe:
  the process-scoped `fallbackActive` latch IS the runtime probe.
- **Fallback contract** (`CocosBattleActivity`): `super.onCreate` runs
  inside a try (engine boot throw) and a 5 s `battle/ready` watchdog is
  armed last. Either failure latches `fallbackActive`, posts
  `CocosBattleOutcome.Fallback` and finishes; the Compose side re-routes
  the SAME session into the native BattleScreen, and the rest of the
  process stays native.
- **Session handoff** (`CocosBattleSession.kt`): `CocosBattleSessionHolder`
  is a main-thread single-slot holder — the Compose route site builds the
  session (engine + initial state + config, the same construction the
  native BattleScreen uses), `publishInputs(...)` → `startActivity`; the
  activity `takeInputs()` (one-shot) in `onCreate` and `postOutcome(...)`
  just before `finish()`; WordMagicGameApp `consumeOutcome()` in an
  ON_RESUME observer and settles exactly like the native path
  (`Finished` → `finishBattleSession`, `TimedOut` → native-timeout
  equivalent, `Fallback` → native battle re-route). Intent extras are not
  an option: `BattleEngine` is not serializable and settlement parity
  needs the same engine instance on both sides.
- **Per-answer side effects**: `CocosBattleSessionInputs.onAnswerOutcome`
  carries the SAME body the native BattleScreen `onAnswer` runs (learning
  record, review mark, monster progress —
  `WordMagicGameApp.applyAnswerSideEffects`); the bridge invokes it on the
  main thread once per accepted submit with the pre-submit state. Without
  this, Cocos battles would not persist learning progress (iOS-parity
  fix, verified via `wordmagic-local-progress.xml` on the emulator).
- **Back press = escape**: `KEYCODE_BACK` is intercepted in
  `onKeyDown`/`onKeyUp` BEFORE GameActivity forwards keys to the native
  engine, and routed through `bridge.requestEscape()` (Lost settlement →
  Result), with `onBackPressed` as a defensive fallback. A bare `finish()`
  would silently abandon the battle with no outcome posted.
- **Host-owned countdown**: the functional `BattleState` carries no clock;
  the activity runs the 1 Hz tick (native `battleTimeLeft` parity) and a
  0-second tick posts `TimedOut`.
- **androidTest rule**: battle-driving instrumentation suites apply
  `ForceNativeBattleRule` (`@get:Rule`) — it sets the debug-only
  `forceNativeBattle` flag so UI tests always exercise the native
  BattleScreen regardless of the stored preference.

Emulator parity evidence (entry, all 5 question kinds, crit overlay,
re-entry, backgrounding, config OFF/ON, back-press escape, per-answer
records, audio logcat):
[`docs/features/2026-06-12-cocos-battle-android/`](../docs/features/2026-06-12-cocos-battle-android/50-parity-checklist.md).

### Emulator notes

- Rebuild loop: `cd android && ./gradlew :app:assembleDebug` (~2 min
  incremental) → `adb -s emulator-5556 install -r
  android/app/build/outputs/apk/debug/app-debug.apk`.
- Scene `console.log` lands in logcat under tag `jswrapper`; probe logs use
  tags `WMBridge` / `WMCocosBattle`.
- Crash sweep: `adb logcat -d | grep -E "FATAL|AndroidRuntime"` plus
  `adb shell dumpsys dropbox` (ignore stale `system_app_*` entries that
  predate the run).

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
