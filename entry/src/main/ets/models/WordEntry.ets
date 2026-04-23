/**
 * WordEntry — single vocabulary record (spec §8.1).
 *
 * Designed to be a plain ArkTS class with only public fields so it can be
 * populated from JSON via Object.assign and safely serialized. `image` and
 * `audio` are optional and reserved for future question types (picture prompt,
 * listen-and-pick). For V0.1 they stay undefined.
 */
export class WordEntry {
  id: string = '';
  word: string = '';
  meaningZh: string = '';
  category: string = '';
  difficulty: number = 1;
  image?: string;
  audio?: string;

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
