/**
 * WordEntry — single vocabulary record (spec §8.1; V0.5 schemas v2/v5).
 *
 * Plain ArkTS class with only public fields so it can be populated
 * from JSON via field-by-field hydration in `WordRepository.parseWordsJson`.
 *
 * Optional fields (all `undefined` for v1 packs):
 *   - distractors:    server-curated wrong-answer suggestions (V0.5 schema v2)
 *   - example:        bilingual sample sentence (V0.5 schema v2)
 *   - illustrationUrl: Vercel Blob URL for a PNG illustration (V0.5 schema v5)
 *   - audioUrl:        Vercel Blob URL for an MP3 pronunciation (V0.5 schema v5)
 *
 * The legacy `image` / `audio` fields (V0.1 reservation, never
 * populated by the bundled rawfile) stay around to keep
 * forward-compatibility for any caller that still references them.
 */
export class ExampleSentence {
  en: string = '';
  zh: string = '';
}

export class WordEntry {
  id: string = '';
  word: string = '';
  meaningZh: string = '';
  category: string = '';
  difficulty: number = 1;
  image?: string;
  audio?: string;
  distractors?: string[];
  example?: ExampleSentence;
  illustrationUrl?: string;
  audioUrl?: string;

  /**
   * Structural validation of a single entry. Kept here (not in the repository)
   * so both the parser and future dynamic content sources can reuse it.
   */
  isValid(): boolean {
    if (this.id.length === 0) {
      return false;
    }
    if (this.word.length === 0) {
      return false;
    }
    if (this.meaningZh.length === 0) {
      return false;
    }
    if (this.category.length === 0) {
      return false;
    }
    if (!Number.isFinite(this.difficulty) || this.difficulty < 1) {
      return false;
    }
    return true;
  }
}

/**
 * Canonical category ids used by V0.1 word list. Strings, not an enum, so the
 * JSON data file stays human-readable and extensions don't require code changes.
 */
export const CATEGORY_FRUIT: string = 'fruit';
export const CATEGORY_PLACE: string = 'place';
export const CATEGORY_HOME: string = 'home';
