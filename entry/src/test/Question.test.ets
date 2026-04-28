import { describe, it, expect } from '@ohos/hypium';
import { Question, QuestionKind } from '../main/ets/models/Question';

function makeChoice(answer: string, options: string[]): Question {
  const q: Question = new Question();
  q.kind = QuestionKind.Choice;
  q.promptZh = '苹果';
  q.answer = answer;
  q.options = options;
  q.wordId = 'fruit-apple';
  return q;
}

function makeFillLetter(): Question {
  const q: Question = new Question();
  q.kind = QuestionKind.FillLetter;
  q.promptZh = '苹果';
  q.answer = 'apple';
  q.wordId = 'fruit-apple';
  q.letterTemplate = 'a _ p l e';
  q.missingIndex = 1;
  q.letterOptions = ['p', 'b', 't'];
  q.letterAnswer = 'p';
  return q;
}

function makeFillLetterMedium(): Question {
  const q: Question = new Question();
  q.kind = QuestionKind.FillLetterMedium;
  q.promptZh = '苹果';
  q.answer = 'apple';
  q.wordId = 'fruit-apple';
  q.letterTemplateBase = 'a _ p _ e';
  q.missingIndices = [1, 3];
  q.letterOptionsSteps = [
    ['p', 'b', 't'],
    ['l', 'r', 's'],
  ];
  q.letterAnswers = ['p', 'l'];
  q.currentStep = 0;
  return q;
}

export default function questionTest() {
  describe('Question.isValid (Choice)', () => {
    it('acceptsThreeUniqueOptionsContainingAnswer', 0, () => {
      const q: Question = makeChoice('apple', ['apple', 'banana', 'pear']);
      expect(q.isValid()).assertTrue();
    });
    it('rejectsAnswerNotInOptions', 0, () => {
      const q: Question = makeChoice('apple', ['kiwi', 'banana', 'pear']);
      expect(q.isValid()).assertFalse();
    });
    it('rejectsDuplicateOptions', 0, () => {
      const q: Question = makeChoice('apple', ['apple', 'apple', 'pear']);
      expect(q.isValid()).assertFalse();
    });
    it('defaultsToChoiceKind', 0, () => {
      const q: Question = new Question();
      expect(q.kind).assertEqual(QuestionKind.Choice);
    });
  });

  describe('Question.isValid (FillLetter)', () => {
    it('acceptsWellFormedFillLetter', 0, () => {
      expect(makeFillLetter().isValid()).assertTrue();
    });
    it('rejectsLetterAnswerNotInOptions', 0, () => {
      const q: Question = makeFillLetter();
      q.letterAnswer = 'z';
      expect(q.isValid()).assertFalse();
    });
    it('rejectsMismatchBetweenWordAndLetterAnswer', 0, () => {
      const q: Question = makeFillLetter();
      q.letterAnswer = 'b';
      q.letterOptions = ['b', 'c', 't'];
      expect(q.isValid()).assertFalse();
    });
    it('rejectsLetterOptionsLengthOtherThanThree', 0, () => {
      const q: Question = makeFillLetter();
      q.letterOptions = ['p', 'b'];
      expect(q.isValid()).assertFalse();
    });
    it('rejectsDuplicateLetterOptions', 0, () => {
      const q: Question = makeFillLetter();
      q.letterOptions = ['p', 'p', 't'];
      expect(q.isValid()).assertFalse();
    });
  });

  describe('Question.isValid (FillLetterMedium)', () => {
    it('acceptsWellFormedFillLetterMedium', 0, () => {
      expect(makeFillLetterMedium().isValid()).assertTrue();
    });
    it('rejectsMissingIndicesLengthOtherThanTwo', 0, () => {
      const q: Question = makeFillLetterMedium();
      q.missingIndices = [1];
      expect(q.isValid()).assertFalse();
    });
    it('rejectsDuplicateMissingIndices', 0, () => {
      const q: Question = makeFillLetterMedium();
      q.missingIndices = [1, 1];
      expect(q.isValid()).assertFalse();
    });
    it('rejectsMissingIndexAtZero', 0, () => {
      const q: Question = makeFillLetterMedium();
      q.letterTemplateBase = '_ p p _ e';
      q.missingIndices = [0, 3];
      q.letterOptionsSteps = [
        ['a', 'b', 't'],
        ['l', 'r', 's'],
      ];
      q.letterAnswers = ['a', 'l'];
      expect(q.isValid()).assertFalse();
    });
    it('rejectsOptionsOrAnswersLengthMismatch', 0, () => {
      const q: Question = makeFillLetterMedium();
      q.letterOptionsSteps = [['p', 'b', 't']];
      expect(q.isValid()).assertFalse();
    });
    it('rejectsMismatchBetweenWordAndLetterAnswers', 0, () => {
      const q: Question = makeFillLetterMedium();
      q.letterAnswers = ['b', 'l'];
      q.letterOptionsSteps = [
        ['b', 'p', 't'],
        ['l', 'r', 's'],
      ];
      expect(q.isValid()).assertFalse();
    });
  });
}
