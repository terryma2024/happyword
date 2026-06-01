import { VoiceLabLane } from '../AudioLabTypes';
import { PronunciationService } from '../../services/PronunciationService';

export class RealVoiceLabLane implements VoiceLabLane {
  private readonly service: PronunciationService = new PronunciationService();
  private pendingWord: string = '';
  private initPromise?: Promise<void>;
  private initFinished: boolean = false;
  private disposed: boolean = false;

  init(): Promise<void> {
    if (this.initPromise !== undefined) {
      return this.initPromise;
    }
    this.initPromise = this.service.init().then((): void => {
      this.initFinished = true;
      this.flushPendingWord();
    });
    return this.initPromise;
  }

  speak(word: string): void {
    if (this.disposed) {
      return;
    }
    if (!this.service.isAvailable) {
      this.pendingWord = word;
      this.init().catch((err: Error): void => {
        console.error(`RealVoiceLabLane deferred init failed: ${JSON.stringify(err)}`);
      });
      return;
    }
    this.service.speak(word);
  }

  isAvailable(): boolean {
    return !this.disposed && (!this.initFinished || this.service.isAvailable);
  }

  dispose(): void {
    this.disposed = true;
    this.pendingWord = '';
    this.service.dispose();
  }

  private flushPendingWord(): void {
    if (!this.service.isAvailable || this.pendingWord.trim().length === 0) {
      return;
    }
    const word: string = this.pendingWord;
    this.pendingWord = '';
    this.service.speak(word);
  }
}
