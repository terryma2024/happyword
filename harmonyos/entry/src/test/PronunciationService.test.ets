import { describe, it, expect } from '@ohos/hypium';
import { QuestionKind } from '../main/ets/models/Question';
import { shouldAutoSpeak, buildSpeakText } from '../main/ets/services/PronunciationService';

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
    it('buildSpeakText returns the full sentence for cloze', 0, () => {
      expect(buildSpeakText(QuestionKind.SentenceCloze, 'The ____ sat on the mat', 'cat'))
        .assertEqual('The cat sat on the mat');
    });
    it('buildSpeakText returns the word for non-cloze kinds', 0, () => {
      expect(buildSpeakText(QuestionKind.Choice, '', 'cat')).assertEqual('cat');
    });
    it('buildSpeakText falls back to the word when the template is empty', 0, () => {
      expect(buildSpeakText(QuestionKind.SentenceCloze, '', 'cat')).assertEqual('cat');
    });
  });
}
