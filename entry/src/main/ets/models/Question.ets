/**
 * Question — one prompt shown to the player (spec §8.2).
 *
 * V0.3 introduces a `kind` discriminator. Choice questions keep
 * the V0.1/V0.2 invariants exactly; FillLetter questions add a
 * letter template + 3 candidate letters and reuse `answer` to
 * carry the full English word so TTS auto-speak still works.
 */
export enum QuestionKind {
  Choice = 'choice',
  FillLetter = 'fill-letter',
  FillLetterMedium = 'fill-letter-medium',
}

export class Question {
  promptZh: string = '';
  answer: string = '';
  options: string[] = [];
  wordId: string = '';

  kind: QuestionKind = QuestionKind.Choice;

  letterTemplate: string = '';
  missingIndex: number = -1;
  letterOptions: string[] = [];
  letterAnswer: string = '';

  // V0.3.5: atomic two-step fill-letter (two blanks).
  letterTemplateBase: string = '';
  missingIndices: number[] = [];
  letterOptionsSteps: string[][] = [];
  letterAnswers: string[] = [];
  // Engine runtime state: 0 = step 0 (first blank), 1 = step 1 (second blank).
  currentStep: number = 0;

  /**
   * Runtime invariant check. Returns true when the question is well-formed.
   * Keep this cheap: it runs during QuestionGenerator tests on every generated
   * question.
   */
  isValid(): boolean {
    if (this.wordId.length === 0) {
      return false;
    }
    if (this.answer.length === 0) {
      return false;
    }
    if (this.kind === QuestionKind.FillLetter) {
      return this.isValidFillLetter();
    }
    if (this.kind === QuestionKind.FillLetterMedium) {
      return this.isValidFillLetterMedium();
    }
    return this.isValidChoice();
  }

  private isValidChoice(): boolean {
    if (this.promptZh.length === 0) {
      return false;
    }
    if (this.options.length !== 3) {
      return false;
    }
    if (this.options.indexOf(this.answer) < 0) {
      return false;
    }
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < this.options.length; i++) {
      if (seen.has(this.options[i])) {
        return false;
      }
      seen.add(this.options[i]);
    }
    return true;
  }

  private isValidFillLetter(): boolean {
    if (this.letterTemplate.length === 0) {
      return false;
    }
    if (this.letterOptions.length !== 3) {
      return false;
    }
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < this.letterOptions.length; i++) {
      const c: string = this.letterOptions[i];
      if (c.length !== 1) {
        return false;
      }
      if (seen.has(c)) {
        return false;
      }
      seen.add(c);
    }
    if (this.letterOptions.indexOf(this.letterAnswer) < 0) {
      return false;
    }
    if (this.missingIndex < 0) {
      return false;
    }
    const word: string = this.answer.toLowerCase();
    if (this.missingIndex >= word.length) {
      return false;
    }
    if (word.charAt(this.missingIndex) !== this.letterAnswer) {
      return false;
    }
    return true;
  }

  private isValidFillLetterMedium(): boolean {
    if (this.letterTemplateBase.length === 0) {
      return false;
    }
    if (this.missingIndices.length !== 2) {
      return false;
    }
    if (this.letterOptionsSteps.length !== 2) {
      return false;
    }
    if (this.letterAnswers.length !== 2) {
      return false;
    }
    if (this.currentStep < 0 || this.currentStep > 1) {
      return false;
    }

    const idx0: number = this.missingIndices[0];
    const idx1: number = this.missingIndices[1];
    // Disallow missing the first letter (keeps the question readable).
    if (idx0 <= 0 || idx1 <= 0) {
      return false;
    }
    if (idx0 === idx1) {
      return false;
    }

    const word: string = this.answer.toLowerCase();
    if (idx0 >= word.length || idx1 >= word.length) {
      return false;
    }

    const parts: string[] = this.letterTemplateBase.split(' ');
    if (parts.length !== word.length) {
      return false;
    }
    // Medium runtime UX may reveal a previously-correct letter in-place.
    // Accept '_' or the correct answer letter at each missing index.
    const expected0: string = this.letterAnswers[0];
    const expected1: string = this.letterAnswers[1];
    if (!((parts[idx0] === '_' || parts[idx0] === expected0)
      && (parts[idx1] === '_' || parts[idx1] === expected1))) {
      return false;
    }

    for (let step: number = 0; step < 2; step++) {
      const options: string[] = this.letterOptionsSteps[step];
      if (options.length !== 3) {
        return false;
      }
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < options.length; i++) {
        const c: string = options[i];
        if (c.length !== 1) {
          return false;
        }
        if (seen.has(c)) {
          return false;
        }
        seen.add(c);
      }
      const ans: string = this.letterAnswers[step];
      if (ans.length !== 1) {
        return false;
      }
      if (options.indexOf(ans) < 0) {
        return false;
      }
      const missingIdx: number = this.missingIndices[step];
      if (word.charAt(missingIdx) !== ans) {
        return false;
      }
    }

    return true;
  }
}
