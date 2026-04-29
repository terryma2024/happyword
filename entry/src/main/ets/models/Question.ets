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
  Spell = 'spell',
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

  // V0.4.1: Spell — full-word point-select spelling. SpellingArea owns
  // per-tap state in @State; these fields are read once on question
  // reveal and never mutated afterwards (unlike FillLetterMedium's
  // letterTemplateBase which is rewritten in-place on step advance).
  spellLetters: string[] = [];
  spellRevealedMask: boolean[] = [];
  spellPool: string[] = [];

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
    if (this.kind === QuestionKind.Spell) {
      return this.isValidSpell();
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

  /**
   * V0.4.1 Spell invariants:
   * - spellLetters length is in [SPELL_MIN_LEN, SPELL_MAX_LEN]
   * - spellRevealedMask matches spellLetters length, with index 0 = true
   *   and every other index = false (only the first letter is revealed)
   * - spellLetters joined equals answer.toLowerCase()
   * - spellPool is the multiset of spellLetters[1..] in any order
   * - every letter in spellLetters and spellPool is a single a-z char
   */
  private isValidSpell(): boolean {
    const SPELL_MIN_LEN: number = 4;
    const SPELL_MAX_LEN: number = 9;
    const len: number = this.spellLetters.length;
    if (len < SPELL_MIN_LEN || len > SPELL_MAX_LEN) {
      return false;
    }
    if (this.spellRevealedMask.length !== len) {
      return false;
    }
    if (!this.spellRevealedMask[0]) {
      return false;
    }
    for (let i = 1; i < len; i++) {
      if (this.spellRevealedMask[i]) {
        return false;
      }
    }
    for (let i = 0; i < len; i++) {
      const c: string = this.spellLetters[i];
      if (c.length !== 1) {
        return false;
      }
      const code: number = c.charCodeAt(0);
      if (code < 97 || code > 122) {
        return false;
      }
    }
    // Compare joined letters against the alphabetic projection of `answer`
    // so words with hyphens / uppercase (e.g. 'ice-cream', 'Apple') still
    // validate after the generator strips non-a-z characters.
    let normalizedAnswer: string = '';
    const lowerAnswer: string = this.answer.toLowerCase();
    for (let i = 0; i < lowerAnswer.length; i++) {
      const c: string = lowerAnswer.charAt(i);
      if (c >= 'a' && c <= 'z') {
        normalizedAnswer += c;
      }
    }
    const joined: string = this.spellLetters.join('');
    if (joined !== normalizedAnswer) {
      return false;
    }
    if (this.spellPool.length !== len - 1) {
      return false;
    }
    for (let i = 0; i < this.spellPool.length; i++) {
      const c: string = this.spellPool[i];
      if (c.length !== 1) {
        return false;
      }
      const code: number = c.charCodeAt(0);
      if (code < 97 || code > 122) {
        return false;
      }
    }
    // Multiset check: spellPool must equal spellLetters[1..] as a multiset.
    const expectedCounts: Map<string, number> = new Map<string, number>();
    for (let i = 1; i < len; i++) {
      const c: string = this.spellLetters[i];
      const prev: number = expectedCounts.has(c) ? (expectedCounts.get(c) as number) : 0;
      expectedCounts.set(c, prev + 1);
    }
    const actualCounts: Map<string, number> = new Map<string, number>();
    for (let i = 0; i < this.spellPool.length; i++) {
      const c: string = this.spellPool[i];
      const prev: number = actualCounts.has(c) ? (actualCounts.get(c) as number) : 0;
      actualCounts.set(c, prev + 1);
    }
    if (expectedCounts.size !== actualCounts.size) {
      return false;
    }
    const keys: IterableIterator<string> = expectedCounts.keys();
    let next: IteratorResult<string> = keys.next();
    while (!next.done) {
      const k: string = next.value;
      if (expectedCounts.get(k) !== actualCounts.get(k)) {
        return false;
      }
      next = keys.next();
    }
    return true;
  }
}
