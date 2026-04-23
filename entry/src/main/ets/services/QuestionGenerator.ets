import { WordEntry } from '../models/WordEntry';
import { Question } from '../models/Question';
import { WordRepository } from './WordRepository';
import { RandomFn, shuffle } from '../utils/shuffle';

/**
 * QuestionGenerator turns a WordRepository into a stream of three-option
 * multiple-choice questions (spec §5.2 and §13.1).
 *
 * Invariants guaranteed per call to `nextQuestion`:
 *   1. `options.length === 3` and all three options are unique English words.
 *   2. `answer` is exactly one of the options.
 *   3. When `lastWordId` is provided and the repository has more than one word,
 *      the returned question's `wordId` is not equal to `lastWordId`.
 *   4. Distractors are drawn from the same category first; if that pool is too
 *      small, the generator degrades to the global word list (spec §5.2 last
 *      bullet) instead of throwing.
 *
 * Randomness is injected via `rng` so tests can pin the sequence. Production
 * code passes `Math.random`.
 */
export const MIN_REPO_SIZE: number = 3;
export const OPTIONS_PER_QUESTION: number = 3;

export class QuestionGenerator {
  private readonly repo: WordRepository;
  private readonly rng: RandomFn;

  constructor(repo: WordRepository, rng?: RandomFn) {
    this.repo = repo;
    this.rng = rng ?? Math.random;
  }

  /**
   * Generate the next question, optionally avoiding a word that was just used.
   * Throws if the repository has fewer than `OPTIONS_PER_QUESTION` total words;
   * BattleEngine is expected to guard against this at startup.
   */
  nextQuestion(lastWordId?: string): Question {
    const all: WordEntry[] = this.repo.all();
    if (all.length < OPTIONS_PER_QUESTION) {
      throw new Error(
        `QuestionGenerator: repository has ${all.length} words, need at least ${OPTIONS_PER_QUESTION}`
      );
    }

    const answerEntry: WordEntry = this.pickAnswer(all, lastWordId);
    const distractors: WordEntry[] = this.pickDistractors(all, answerEntry);

    const optionWords: string[] = [answerEntry.word];
    for (let i = 0; i < distractors.length; i++) {
      optionWords.push(distractors[i].word);
    }

    const shuffled: string[] = shuffle<string>(optionWords, this.rng);

    const q: Question = new Question();
    q.promptZh = answerEntry.meaningZh;
    q.answer = answerEntry.word;
    q.options = shuffled;
    q.wordId = answerEntry.id;
    return q;
  }

  private pickAnswer(all: WordEntry[], lastWordId?: string): WordEntry {
    // Candidates exclude the word used by the previous question unless the
    // repository only has one entry — in which case repetition is unavoidable.
    const candidates: WordEntry[] = [];
    for (let i = 0; i < all.length; i++) {
      if (lastWordId !== undefined && all[i].id === lastWordId) {
        continue;
      }
      candidates.push(all[i]);
    }
    const pool: WordEntry[] = candidates.length > 0 ? candidates : all;
    const idx: number = this.randomIndex(pool.length);
    return pool[idx];
  }

  private pickDistractors(all: WordEntry[], answer: WordEntry): WordEntry[] {
    const needed: number = OPTIONS_PER_QUESTION - 1;

    // 1) Same-category candidates, excluding the answer and avoiding duplicate
    //    words (different WordEntry objects can legally share the same word
    //    spelling if curators do so; we still want distinct option strings).
    const sameCategory: WordEntry[] = this.collectDistractorCandidates(
      this.repo.byCategory(answer.category),
      answer
    );
    const picked: WordEntry[] = this.takeRandom(sameCategory, needed);
    if (picked.length >= needed) {
      return picked;
    }

    // 2) Global fallback — spec §5.2 explicitly allows dropping the same-category
    //    constraint rather than crashing when the category pool is too small.
    const takenWords: Set<string> = new Set<string>();
    takenWords.add(answer.word);
    for (let i = 0; i < picked.length; i++) {
      takenWords.add(picked[i].word);
    }
    const globalPool: WordEntry[] = [];
    for (let i = 0; i < all.length; i++) {
      const e: WordEntry = all[i];
      if (e.id === answer.id) {
        continue;
      }
      if (takenWords.has(e.word)) {
        continue;
      }
      globalPool.push(e);
    }
    const extra: WordEntry[] = this.takeRandom(globalPool, needed - picked.length);
    for (let i = 0; i < extra.length; i++) {
      picked.push(extra[i]);
    }
    return picked;
  }

  private collectDistractorCandidates(pool: WordEntry[], answer: WordEntry): WordEntry[] {
    const seenWords: Set<string> = new Set<string>();
    seenWords.add(answer.word);
    const out: WordEntry[] = [];
    for (let i = 0; i < pool.length; i++) {
      const e: WordEntry = pool[i];
      if (e.id === answer.id) {
        continue;
      }
      if (seenWords.has(e.word)) {
        continue;
      }
      seenWords.add(e.word);
      out.push(e);
    }
    return out;
  }

  private takeRandom(pool: WordEntry[], count: number): WordEntry[] {
    if (count <= 0 || pool.length === 0) {
      return [];
    }
    const shuffled: WordEntry[] = shuffle<WordEntry>(pool, this.rng);
    const take: number = count < shuffled.length ? count : shuffled.length;
    return shuffled.slice(0, take);
  }

  private randomIndex(upperExclusive: number): number {
    if (upperExclusive <= 0) {
      return 0;
    }
    const r: number = this.rng();
    const idx: number = Math.floor(r * upperExclusive);
    if (idx < 0) {
      return 0;
    }
    if (idx >= upperExclusive) {
      return upperExclusive - 1;
    }
    return idx;
  }
}
