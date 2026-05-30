import { VoiceLabLane } from '../AudioLabTypes';
import { PronunciationService } from '../../services/PronunciationService';

export class RealVoiceLabLane implements VoiceLabLane {
  private readonly service: PronunciationService = new PronunciationService();

  init(): Promise<void> {
    return this.service.init();
  }

  speak(word: string): void {
    this.service.speak(word);
  }

  isAvailable(): boolean {
    return this.service.isAvailable;
  }

  dispose(): void {
    this.service.dispose();
  }
}
