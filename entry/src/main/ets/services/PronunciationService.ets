import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@ohos.base';

/**
 * PronunciationService — thin wrapper around HarmonyOS CoreSpeechKit TTS
 * (spec §7.3 V0.2). Lives across a whole BattlePage instance so the
 * engine is created once and reused for every `speak(word)` call.
 *
 * Lifecycle:
 *   - `init()` creates the TTS engine asynchronously. On success
 *     `isAvailable` becomes true and `speak(word)` routes to the
 *     engine. On failure (e.g. CoreSpeechKit absent on this device,
 *     no network for the first init) `isAvailable` stays false and
 *     every subsequent `speak(word)` is a silent no-op.
 *   - `speak(word)` always cancels any in-flight utterance before
 *     starting the new one so rapid taps can't queue up overlapping
 *     voices.
 *   - `dispose()` shuts the engine down when BattlePage tears down.
 *
 * Error model: every failure path logs and silently degrades. Never
 * throws out of `speak`; BattlePage does not gate battle flow on TTS.
 */

/**
 * Engine-creation parameter shape. Duplicated inline (not an import
 * from @kit.CoreSpeechKit) because the kit's CreateEngineParams type
 * doesn't expose all four fields as a named type we can reference
 * cleanly from ArkTS strict mode.
 */
export class PronunciationInitParams {
  language: string = 'en-US';
  person: number = 0;
  /** Online-only voice disables offline fallback; 0 = default (on-device if available). */
  online: number = 1;
}

export class PronunciationService {
  private engine?: textToSpeech.TextToSpeechEngine;
  private initStarted: boolean = false;
  private initialized: boolean = false;
  private disposed: boolean = false;
  private utteranceCounter: number = 0;

  /**
   * Start engine creation. Resolves once the engine is ready (or the
   * attempt has failed). Safe to call multiple times — subsequent
   * invocations return the pending / resolved promise from the first.
   */
  private initPromise?: Promise<void>;
  init(params?: PronunciationInitParams): Promise<void> {
    if (this.initPromise !== undefined) {
      return this.initPromise;
    }
    this.initStarted = true;
    const effective: PronunciationInitParams =
      params !== undefined ? params : new PronunciationInitParams();
    this.initPromise = this.createEngine(effective);
    return this.initPromise;
  }

  private async createEngine(params: PronunciationInitParams): Promise<void> {
    try {
      const createParams: textToSpeech.CreateEngineParams = {
        language: params.language,
        person: params.person,
        online: params.online,
      };
      const engine: textToSpeech.TextToSpeechEngine =
        await textToSpeech.createEngine(createParams);
      if (this.disposed) {
        // Rare race: dispose() was called while createEngine was in flight.
        engine.shutdown();
        return;
      }
      this.engine = engine;
      this.initialized = true;
    } catch (err) {
      console.error(`PronunciationService.init failed: ${JSON.stringify(err as BusinessError)}`);
      this.initialized = false;
    }
  }

  /** True once createEngine resolved successfully (and we're not disposed). */
  get isAvailable(): boolean {
    return this.initialized && !this.disposed && this.engine !== undefined;
  }

  /** Has init been kicked off yet? Useful for UI gating before first resolve. */
  get isInitStarted(): boolean {
    return this.initStarted;
  }

  /**
   * Speak a word. Cancels any in-flight utterance first so rapid
   * taps replace, not queue. Never throws — per-call errors are
   * logged and swallowed.
   */
  speak(word: string): void {
    if (!this.isAvailable) {
      return;
    }
    const engine: textToSpeech.TextToSpeechEngine | undefined = this.engine;
    if (engine === undefined) {
      return;
    }
    const trimmed: string = word.trim();
    if (trimmed.length === 0) {
      return;
    }
    try {
      engine.stop();
      this.utteranceCounter += 1;
      const speakParams: textToSpeech.SpeakParams = {
        requestId: `wordmagic_${this.utteranceCounter}`,
      };
      engine.speak(trimmed, speakParams);
    } catch (err) {
      console.error(`PronunciationService.speak("${word}") failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  /** Shut the engine down. Idempotent — subsequent speak() is a no-op. */
  dispose(): void {
    this.disposed = true;
    const engine: textToSpeech.TextToSpeechEngine | undefined = this.engine;
    this.engine = undefined;
    this.initialized = false;
    if (engine !== undefined) {
      try {
        engine.stop();
        engine.shutdown();
      } catch (err) {
        console.error(`PronunciationService.dispose failed: ${JSON.stringify(err as BusinessError)}`);
      }
    }
  }
}

/**
 * Pure gating helper — exported so unit tests can cover the
 * auto-play decision tree without mocking TTS. BattlePage should
 * auto-play a word when:
 *   1. autoSpeak is enabled in GameConfig.
 *   2. The TTS service reports isAvailable.
 *   3. We are NOT currently inside the feedback window (`isRevealing`
 *      === true would mean crit/hurt audio is playing; overlapping
 *      TTS with that would muddle the soundscape).
 */
export function shouldAutoSpeak(autoSpeakEnabled: boolean, ttsAvailable: boolean, isRevealing: boolean): boolean {
  if (!autoSpeakEnabled) {
    return false;
  }
  if (!ttsAvailable) {
    return false;
  }
  if (isRevealing) {
    return false;
  }
  return true;
}
