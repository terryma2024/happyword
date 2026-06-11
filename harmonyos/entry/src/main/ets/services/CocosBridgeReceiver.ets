/**
 * CocosBridgeReceiver — scene -> ArkTS half of the Cocos battle bridge
 * (V1.1.0 Task 0.3).
 *
 * The Cocos scene calls native.reflection.callStaticMethod(
 *   'entry/src/main/ets/services/CocosBridgeReceiver', 'onSceneMessage',
 *   json, false). The engine's JavaScriptArkTsBridge resolves that through
 * the 'executeMethodAsync' threadsafe function CocosEngineHost registered on
 * the UI thread: the engine napi-loads THIS module by the path above
 * (napi_load_module_with_info) and calls the exported function below with
 * (paramStr, callback).
 *
 * Hard requirements:
 *  - The module path string in the scene transport
 *    (cocos/assets/scripts/bridge/transport.ts) must match this file's path.
 *  - This file must be listed in buildOption.arkOptions.runtimeOnly.sources
 *    of harmonyos/entry/build-profile.json5, or napi_load_module_with_info
 *    cannot resolve it at runtime.
 *  - done() MUST be invoked: the engine blocks the Cocos game thread on an
 *    internal promise until the callback fires. Call it first so the game
 *    loop resumes before any app-side message handling runs.
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cocosEngineHost } from './CocosEngineHost';

export function onSceneMessage(json: string, done: (result: string) => void): void {
  // Unblock the engine's game thread immediately; the dispatch below runs on
  // the UI thread and must not gate the scene's frame loop.
  // IMPORTANT: done() is called BEFORE dispatch. A throw before done() would
  // permanently hang the game thread (it blocks on an internal promise). An
  // escaping exception after done() leaves a pending napi exception on the UI
  // thread — the try/catch below prevents that.
  done('ok');
  try {
    cocosEngineHost().dispatchSceneMessage(json);
  } catch (err) {
    hilog.error(0x0000, 'WMBridge',
      'dispatchSceneMessage threw (pending napi exception avoided): %{public}s',
      (err instanceof Error) ? err.message : JSON.stringify(err as object));
  }
}
