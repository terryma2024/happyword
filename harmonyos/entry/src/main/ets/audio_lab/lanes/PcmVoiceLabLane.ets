import audio from '@ohos.multimedia.audio';
import { BusinessError } from '@ohos.base';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { VoiceLabLane } from '../AudioLabTypes';

export class PcmVoiceChunkQueue {
  private chunks: ArrayBuffer[] = [];
  private firstOffset: number = 0;

  enqueue(chunk: ArrayBuffer): void {
    if (chunk.byteLength > 0) {
      this.chunks.push(chunk);
    }
  }

  clear(): void {
    this.chunks = [];
    this.firstOffset = 0;
  }

  hasData(): boolean {
    return this.chunks.length > 0;
  }

  fill(target: ArrayBuffer): number {
    const out: Uint8Array = new Uint8Array(target);
    for (let i = 0; i < out.length; i++) {
      out[i] = 0;
    }
    let copied: number = 0;
    while (copied < out.length && this.chunks.length > 0) {
      const chunk: ArrayBuffer = this.chunks[0];
      const src: Uint8Array = new Uint8Array(chunk);
      const remainingInChunk: number = src.length - this.firstOffset;
      const remainingOut: number = out.length - copied;
      const take: number = Math.min(remainingInChunk, remainingOut);
      for (let i = 0; i < take; i++) {
        out[copied + i] = src[this.firstOffset + i];
      }
      copied += take;
      this.firstOffset += take;
      if (this.firstOffset >= src.length) {
        this.chunks.shift();
        this.firstOffset = 0;
      }
    }
    return copied;
  }
}

class PcmVoiceFormat {
  sampleRate: audio.AudioSamplingRate = audio.AudioSamplingRate.SAMPLE_RATE_24000;
  channels: audio.AudioChannel = audio.AudioChannel.CHANNEL_1;
  sampleFormat: audio.AudioSampleFormat = audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE;
}

export class PcmVoiceLabLane implements VoiceLabLane {
  private engine?: textToSpeech.TextToSpeechEngine;
  private renderer?: audio.AudioRenderer;
  private initialized: boolean = false;
  private disposed: boolean = false;
  private requestCounter: number = 0;
  private currentRequestId: string = '';
  private readonly queue: PcmVoiceChunkQueue = new PcmVoiceChunkQueue();
  private readonly writeDataCallback = (data: ArrayBuffer): audio.AudioDataCallbackResult => {
    this.queue.fill(data);
    return audio.AudioDataCallbackResult.VALID;
  };

  async init(): Promise<void> {
    if (this.initialized || this.disposed) {
      return;
    }
    try {
      const createParams: textToSpeech.CreateEngineParams = {
        language: 'zh-CN',
        person: 0,
        online: 1,
      };
      const engine: textToSpeech.TextToSpeechEngine = await textToSpeech.createEngine(createParams);
      if (this.disposed) {
        engine.shutdown();
        return;
      }
      engine.setListener({
        onStart: (requestId: string, response: textToSpeech.StartResponse): void => {
          this.handleStart(requestId, response);
        },
        onComplete: (requestId: string, response: textToSpeech.CompleteResponse): void => {
          this.handleComplete(requestId, response);
        },
        onStop: (_requestId: string, _response: textToSpeech.StopResponse): void => {},
        onError: (requestId: string, errorCode: number, errorMessage: string): void => {
          console.error(`PcmVoiceLabLane TTS error ${requestId}: ${errorCode} ${errorMessage}`);
        },
        onData: (requestId: string, chunk: ArrayBuffer, response: textToSpeech.SynthesisResponse): void => {
          this.handleData(requestId, chunk, response);
        },
      });
      this.engine = engine;
      this.initialized = true;
    } catch (err) {
      this.initialized = false;
      console.error(`PcmVoiceLabLane.init failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  speak(word: string): void {
    if (!this.isAvailable()) {
      return;
    }
    const trimmed: string = word.trim();
    const engine: textToSpeech.TextToSpeechEngine | undefined = this.engine;
    if (trimmed.length === 0 || engine === undefined) {
      return;
    }
    try {
      engine.stop();
      this.queue.clear();
      this.requestCounter += 1;
      this.currentRequestId = `audio_lab_pcm_${this.requestCounter}`;
      const extra: Record<string, Object> = {
        'queueMode': 0,
        'speed': 1,
        'volume': 1,
        'pitch': 1,
        'soundChannel': 1,
        'playType': 0,
      };
      const speakParams: textToSpeech.SpeakParams = {
        requestId: this.currentRequestId,
        extraParams: extra,
      };
      engine.speak(trimmed, speakParams);
    } catch (err) {
      console.error(`PcmVoiceLabLane.speak("${word}") failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  isAvailable(): boolean {
    return this.initialized && !this.disposed && this.engine !== undefined;
  }

  dispose(): void {
    this.disposed = true;
    this.initialized = false;
    this.queue.clear();
    const engine: textToSpeech.TextToSpeechEngine | undefined = this.engine;
    this.engine = undefined;
    if (engine !== undefined) {
      try {
        engine.stop();
        engine.shutdown();
      } catch (err) {
        console.error(`PcmVoiceLabLane.dispose engine failed: ${JSON.stringify(err as BusinessError)}`);
      }
    }
    this.releaseRenderer().catch((err: BusinessError): void => {
      console.error(`PcmVoiceLabLane.dispose renderer failed: ${JSON.stringify(err)}`);
    });
  }

  private handleStart(requestId: string, response: textToSpeech.StartResponse): void {
    if (requestId !== this.currentRequestId || this.disposed) {
      return;
    }
    const audioType: string = response.audioType.toLowerCase();
    if (audioType.length > 0 && audioType.indexOf('pcm') < 0) {
      console.error(`PcmVoiceLabLane unsupported audioType=${response.audioType}`);
      return;
    }
    this.recreateRenderer(response).catch((err: BusinessError): void => {
      console.error(`PcmVoiceLabLane renderer create failed: ${JSON.stringify(err)}`);
    });
  }

  private handleData(
    requestId: string,
    chunk: ArrayBuffer,
    response: textToSpeech.SynthesisResponse,
  ): void {
    if (requestId !== this.currentRequestId || this.disposed) {
      return;
    }
    const audioType: string = response.audioType.toLowerCase();
    if (audioType.length > 0 && audioType.indexOf('pcm') < 0) {
      return;
    }
    this.queue.enqueue(chunk);
  }

  private handleComplete(requestId: string, response: textToSpeech.CompleteResponse): void {
    if (requestId !== this.currentRequestId || this.disposed) {
      return;
    }
    if (response.type === 1) {
      this.releaseRenderer().catch((err: BusinessError): void => {
        console.error(`PcmVoiceLabLane complete release failed: ${JSON.stringify(err)}`);
      });
    }
  }

  private async recreateRenderer(response: textToSpeech.StartResponse): Promise<void> {
    await this.releaseRenderer();
    if (this.disposed) {
      return;
    }
    const format: PcmVoiceFormat = this.formatFromResponse(response);
    const rendererOptions: audio.AudioRendererOptions = {
      streamInfo: {
        samplingRate: format.sampleRate,
        channels: format.channels,
        sampleFormat: format.sampleFormat,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
      },
      rendererInfo: {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0,
      },
    };
    const nextRenderer: audio.AudioRenderer = await audio.createAudioRenderer(rendererOptions);
    try {
      nextRenderer.on('writeData', this.writeDataCallback);
      nextRenderer.setInterruptModeSync(audio.InterruptMode.SHARE_MODE);
    } catch (err) {
      console.warn(`PcmVoiceLabLane renderer setup warning: ${JSON.stringify(err as BusinessError)}`);
    }
    await nextRenderer.setVolume(1);
    await nextRenderer.start();
    this.renderer = nextRenderer;
  }

  private async releaseRenderer(): Promise<void> {
    const renderer: audio.AudioRenderer | undefined = this.renderer;
    this.renderer = undefined;
    if (renderer === undefined) {
      return;
    }
    try {
      renderer.off('writeData', this.writeDataCallback);
      await renderer.stop();
    } catch (err) {
      console.warn(`PcmVoiceLabLane renderer stop failed: ${JSON.stringify(err as BusinessError)}`);
    }
    await renderer.release();
  }

  private formatFromResponse(response: textToSpeech.StartResponse): PcmVoiceFormat {
    const format: PcmVoiceFormat = new PcmVoiceFormat();
    format.sampleRate = this.sampleRateOf(response.sampleRate);
    format.channels = response.audioChannel === 2 ? audio.AudioChannel.CHANNEL_2 : audio.AudioChannel.CHANNEL_1;
    format.sampleFormat = this.sampleFormatOf(response.sampleBit);
    return format;
  }

  private sampleRateOf(value: number): audio.AudioSamplingRate {
    if (value === 8000) {
      return audio.AudioSamplingRate.SAMPLE_RATE_8000;
    }
    if (value === 11025) {
      return audio.AudioSamplingRate.SAMPLE_RATE_11025;
    }
    if (value === 12000) {
      return audio.AudioSamplingRate.SAMPLE_RATE_12000;
    }
    if (value === 16000) {
      return audio.AudioSamplingRate.SAMPLE_RATE_16000;
    }
    if (value === 22050) {
      return audio.AudioSamplingRate.SAMPLE_RATE_22050;
    }
    if (value === 32000) {
      return audio.AudioSamplingRate.SAMPLE_RATE_32000;
    }
    if (value === 44100) {
      return audio.AudioSamplingRate.SAMPLE_RATE_44100;
    }
    if (value === 48000) {
      return audio.AudioSamplingRate.SAMPLE_RATE_48000;
    }
    return audio.AudioSamplingRate.SAMPLE_RATE_24000;
  }

  private sampleFormatOf(sampleBit: number): audio.AudioSampleFormat {
    if (sampleBit === 8) {
      return audio.AudioSampleFormat.SAMPLE_FORMAT_U8;
    }
    if (sampleBit === 24) {
      return audio.AudioSampleFormat.SAMPLE_FORMAT_S24LE;
    }
    if (sampleBit === 32) {
      return audio.AudioSampleFormat.SAMPLE_FORMAT_S32LE;
    }
    return audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE;
  }
}
