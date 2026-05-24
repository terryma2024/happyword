import { describe, it, expect } from '@ohos/hypium';
import { QuestionKind } from '../main/ets/models/Question';
import { shouldAutoSpeak } from '../main/ets/services/PronunciationService';

export default function pronunciationServiceTest(): void {
  describe('PronunciationService', () => {
    it('allows normal choice questions to auto speak when enabled and available', 0, () => {
      expect(shouldAutoSpeak(true, true, false, QuestionKind.Choice)).assertTrue();
    });

    it('blocks sentence cloze questions from auto speak', 0, () => {
      expect(shouldAutoSpeak(true, true, false, QuestionKind.SentenceCloze)).assertFalse();
    });

    it('still blocks auto speak during reveal windows', 0, () => {
      expect(shouldAutoSpeak(true, true, true, QuestionKind.Choice)).assertFalse();
    });
  });
}
