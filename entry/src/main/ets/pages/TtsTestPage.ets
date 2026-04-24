import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { AudioService, SoundKeys } from '../services/AudioService';

/**
 * TtsTestPage — standalone diagnostic page for CoreSpeechKit TTS on real
 * hardware (spec §15 V0.2 debugging). Lives outside BattlePage so we can
 * isolate whether "no audio" is a TTS problem, an audio-routing problem,
 * or a volume problem.
 *
 * The page owns its own engine (no PronunciationService) so every raw
 * lifecycle event is surfaced in the UI: `createEngine` resolve/reject,
 * and `SpeakListener.onStart / onComplete / onError / onEvent` with the
 * requestId each fires for. A separate "Play bundled SFX" button plays
 * one of the game's OGG sounds via AVPlayer so the tester can compare
 * whether the device can produce *any* audio vs. specifically TTS.
 *
 * Not wired into the shipping flow — reached only from the debug 🧪 button
 * on HomePage. Safe to keep in debug + release builds; costs nothing
 * until opened.
 */
@Entry
@Component
struct TtsTestPage {
  @State private engineStatus: string = 'idle';
  @State private lastEvent: string = '(none)';
  @State private lastError: string = '(none)';
  @State private eventCount: number = 0;
  @State private audioReady: boolean = false;

  private engine?: textToSpeech.TextToSpeechEngine;
  private initStarted: boolean = false;
  private counter: number = 0;
  private audio: AudioService = new AudioService();

  aboutToAppear(): void {
    this.initEngine();
    this.preloadSfx();
  }

  aboutToDisappear(): void {
    const eng: textToSpeech.TextToSpeechEngine | undefined = this.engine;
    this.engine = undefined;
    if (eng !== undefined) {
      try {
        eng.stop();
        eng.shutdown();
      } catch (err) {
        console.error(`TtsTestPage: shutdown failed: ${JSON.stringify(err as BusinessError)}`);
      }
    }
    this.audio.dispose().catch((err: BusinessError): void => {
      console.error(`TtsTestPage: audio.dispose failed: ${JSON.stringify(err)}`);
    });
  }

  private initEngine(): void {
    if (this.initStarted) {
      return;
    }
    this.initStarted = true;
    this.engineStatus = 'creating (zh-CN, person=0, online=1)...';
    const params: textToSpeech.CreateEngineParams = {
      language: 'zh-CN',
      person: 0,
      online: 1,
    };
    textToSpeech.createEngine(params)
      .then((eng: textToSpeech.TextToSpeechEngine): void => {
        this.engine = eng;
        this.engineStatus = 'ready (zh-CN)';
        this.attachListener(eng);
      })
      .catch((err: BusinessError): void => {
        this.engineStatus = 'create FAILED';
        this.lastError = JSON.stringify(err);
        console.error(`TtsTestPage: createEngine failed: ${JSON.stringify(err)}`);
      });
  }

  private attachListener(eng: textToSpeech.TextToSpeechEngine): void {
    // SpeakListener gives us the real signal of whether PCM is flowing
    // to the audio renderer. If onStart fires but onComplete never does
    // on a clean run, audio focus was yanked mid-utterance. If onError
    // fires, the message's errorCode is the definitive reason.
    const listener: textToSpeech.SpeakListener = {
      onStart: (requestId: string, response: textToSpeech.StartResponse): void => {
        this.eventCount += 1;
        this.lastEvent = `onStart ${requestId}`;
        console.info(`TtsTestPage: onStart ${requestId} ${JSON.stringify(response)}`);
      },
      onComplete: (requestId: string, response: textToSpeech.CompleteResponse): void => {
        this.eventCount += 1;
        this.lastEvent = `onComplete ${requestId} type=${response.type}`;
        console.info(`TtsTestPage: onComplete ${requestId} ${JSON.stringify(response)}`);
      },
      onStop: (requestId: string, response: textToSpeech.StopResponse): void => {
        this.eventCount += 1;
        this.lastEvent = `onStop ${requestId}`;
        console.info(`TtsTestPage: onStop ${requestId} ${JSON.stringify(response)}`);
      },
      onError: (requestId: string, errorCode: number, errorMessage: string): void => {
        this.eventCount += 1;
        this.lastEvent = `onError ${requestId}`;
        this.lastError = `code=${errorCode} msg=${errorMessage}`;
        console.error(`TtsTestPage: onError ${requestId} code=${errorCode} msg=${errorMessage}`);
      },
      onData: (requestId: string, audio: ArrayBuffer, response: textToSpeech.SynthesisResponse): void => {
        // Fires every time a PCM buffer is delivered. If this never
        // fires on a zh-CN utterance, the engine is silently failing.
        this.eventCount += 1;
        this.lastEvent = `onData ${requestId} bytes=${audio.byteLength}`;
      },
    };
    try {
      eng.setListener(listener);
    } catch (err) {
      this.lastError = `setListener failed: ${JSON.stringify(err as BusinessError)}`;
    }
  }

  private preloadSfx(): void {
    const ctx: common.UIAbilityContext =
      getContext(this) as common.UIAbilityContext;
    this.audio.preload(ctx, [SoundKeys.HIT_NORMAL])
      .then((): void => {
        this.audioReady = this.audio.isPlayable(SoundKeys.HIT_NORMAL);
      })
      .catch((err: Error): void => {
        console.error(`TtsTestPage: SFX preload failed: ${err.message}`);
      });
  }

  private speak(text: string, label: string, soundChannel?: number): void {
    // soundChannel values match AudioKit StreamUsage:
    //   1 = STREAM_USAGE_MEDIA (same volume slider as game SFX / music)
    //   3 = STREAM_USAGE_VOICE_ASSISTANT (default; separate volume slider,
    //       often set low on tablets → inaudible by default).
    // We expose both so the tester can A/B verify which stream the
    // device actually routes through. Fix will pin to MEDIA.
    const eng: textToSpeech.TextToSpeechEngine | undefined = this.engine;
    if (eng === undefined) {
      this.lastError = `speak("${label}"): engine not ready (${this.engineStatus})`;
      return;
    }
    try {
      eng.stop();
      this.counter += 1;
      const rid: string = `ttstest_${this.counter}`;
      const extra: Record<string, Object> = {};
      if (soundChannel !== undefined) {
        extra['soundChannel'] = soundChannel;
        extra['playType'] = 1;
      }
      const params: textToSpeech.SpeakParams = {
        requestId: rid,
        extraParams: soundChannel !== undefined ? extra : undefined,
      };
      eng.speak(text, params);
      const channelTag: string =
        soundChannel === undefined ? 'default' : `chan=${soundChannel}`;
      this.lastEvent = `speak("${text}") rid=${rid} ${channelTag}`;
    } catch (err) {
      this.lastError = `speak failed: ${JSON.stringify(err as BusinessError)}`;
      console.error(`TtsTestPage: speak failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  private playSfx(): void {
    if (!this.audioReady) {
      this.lastError = `SFX not ready`;
      return;
    }
    this.audio.play(SoundKeys.HIT_NORMAL);
    this.lastEvent = 'played SFX hit_normal';
  }

  build(): void {
    Column({ space: 14 }) {
      Text('TTS Diagnostic')
        .id('TtsTestTitle')
        .fontSize(28)
        .fontWeight(FontWeight.Bold);

      Text(`Engine: ${this.engineStatus}`)
        .id('TtsTestEngineStatus')
        .fontSize(18)
        .fontColor('#333333');

      Text(`Last event: ${this.lastEvent}`)
        .id('TtsTestLastEvent')
        .fontSize(16)
        .fontColor('#555555');

      Text(`Event count: ${this.eventCount}`)
        .id('TtsTestEventCount')
        .fontSize(16)
        .fontColor('#555555');

      Text(`Last error: ${this.lastError}`)
        .id('TtsTestLastError')
        .fontSize(14)
        .fontColor('#C0392B')
        .width('90%')
        .textAlign(TextAlign.Center);

      Button('中文 · 你好 (默认: VOICE_ASSISTANT)')
        .id('TtsTestSpeakZhDefault')
        .fontSize(18)
        .width(360)
        .height(60)
        .backgroundColor('#2A9D8F')
        .fontColor('#FFFFFF')
        .onClick((): void => this.speak('你好，这是一段测试。', 'zh-default'));

      Button('中文 · 你好 (MEDIA channel)')
        .id('TtsTestSpeakZhMedia')
        .fontSize(18)
        .width(360)
        .height(60)
        .backgroundColor('#1D7874')
        .fontColor('#FFFFFF')
        .onClick((): void => this.speak('你好，这是一段测试。', 'zh-media', 1));

      Button('English · chair (MEDIA channel)')
        .id('TtsTestSpeakEn')
        .fontSize(18)
        .width(360)
        .height(60)
        .backgroundColor('#E76F51')
        .fontColor('#FFFFFF')
        .onClick((): void => this.speak('chair', 'en-chair', 1));

      Button(`Play bundled SFX (hit_normal) ${this.audioReady ? '' : '[loading...]'}`)
        .id('TtsTestPlaySfx')
        .fontSize(18)
        .width(360)
        .height(56)
        .backgroundColor('#457B9D')
        .fontColor('#FFFFFF')
        .enabled(this.audioReady)
        .onClick((): void => this.playSfx());

      Button('Back')
        .id('TtsTestBack')
        .fontSize(18)
        .width(160)
        .height(48)
        .margin({ top: 8 })
        .onClick((): void => {
          router.back();
        });
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}
