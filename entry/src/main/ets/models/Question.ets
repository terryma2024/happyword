/**
 * Question — one prompt shown to the player (spec §8.2).
 *
 * V0.1 invariant: exactly three options, the correct answer is always one of
 * them, and no option appears twice. `wordId` links the question back to the
 * originating WordEntry so BattleEngine can avoid picking the same word twice
 * in a row and can later track per-word accuracy.
 */
export class Question {
  promptZh: string = '';
  answer: string = '';
  options: string[] = [];
  wordId: string = '';

  /**
   * Runtime invariant check. Returns true when the question is well-formed.
   * Keep this cheap: it runs during QuestionGenerator tests on every generated
   * question.
   */
  isValid(): boolean {
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
    if (this.promptZh.length === 0) {
      return false;
    }
    if (this.wordId.length === 0) {
      return false;
    }
    return true;
  }
}
