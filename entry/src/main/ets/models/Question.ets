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
}
