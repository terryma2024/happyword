import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@ohos.base';
import { WordEntry } from '../models/WordEntry';

/**
 * Shape of the raw JSON payload bundled in `rawfile/data/words_v1.json`.
 * Keeping it explicit (not `any`) so the parser stays strictly typed.
 */
interface WordsFilePayload {
  version: number;
  words: WordEntryJson[];
}

interface WordEntryJson {
  id: string;
  word: string;
  meaningZh: string;
  category: string;
  difficulty: number;
  image?: string;
  audio?: string;
}

/** Default rawfile location for the V0.1 bundled word list. */
export const DEFAULT_WORDS_RAWFILE: string = 'data/words_v1.json';

/**
 * WordRepository loads the bundled vocabulary and exposes query helpers.
 *
 * Design: platform IO (resourceManager / Uint8Array / TextDecoder) is isolated
 * in `loadFromRawfile`. Pure JSON -> WordEntry[] conversion lives in
 * `parseWordsJson`, which is the only thing unit tests need to touch — local
 * unit tests do not have a live UIAbilityContext.
 *
 * Invalid entries are dropped (not thrown). A single malformed word in the
 * bundled JSON should not crash the game; `isValid()` from WordEntry decides.
 */
export class WordRepository {
  private entries: WordEntry[] = [];

  /** In-memory size. Zero until `loadFromRawfile` or `setEntries` is called. */
  size(): number {
    return this.entries.length;
  }

  /** Return a shallow copy so callers cannot mutate internal state. */
  all(): WordEntry[] {
    return this.entries.slice();
  }

  byCategory(category: string): WordEntry[] {
    const out: WordEntry[] = [];
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].category === category) {
        out.push(this.entries[i]);
      }
    }
    return out;
  }

  findById(id: string): WordEntry | undefined {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].id === id) {
        return this.entries[i];
      }
    }
    return undefined;
  }

  /** Test hook: inject a pre-parsed list, bypassing rawfile IO entirely. */
  setEntries(entries: WordEntry[]): void {
    this.entries = entries.slice();
  }

  /**
   * Load and parse `rawfile/data/words_v1.json` (or a caller-provided path)
   * via the HarmonyOS resource manager. Safe to call more than once; the last
   * successful load replaces the cache.
   */
  async loadFromRawfile(
    context: common.UIAbilityContext,
    rawfilePath: string = DEFAULT_WORDS_RAWFILE
  ): Promise<void> {
    try {
      const bytes: Uint8Array = await context.resourceManager.getRawFileContent(rawfilePath);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const jsonText: string = decoder.decodeToString(bytes);
      this.entries = WordRepository.parseWordsJson(jsonText);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      const detail: string = JSON.stringify(be);
      console.error(`WordRepository: failed to load ${rawfilePath}: ${detail}`);
      // ArkTS strict mode requires throwing an Error subclass.
      throw new Error(`WordRepository load failed for ${rawfilePath}: ${detail}`);
    }
  }

  /**
   * Pure function: parse a JSON string matching the bundled word file schema
   * into validated WordEntry instances. Returns an empty array on structural
   * failure instead of throwing — callers decide how to surface empty state.
   *
   * Kept static so local unit tests can call it without constructing a
   * repository instance.
   */
  static parseWordsJson(jsonText: string): WordEntry[] {
    if (jsonText.length === 0) {
      return [];
    }
    let payload: WordsFilePayload;
    try {
      payload = JSON.parse(jsonText) as WordsFilePayload;
    } catch (err) {
      console.error(`WordRepository: invalid JSON: ${JSON.stringify(err)}`);
      return [];
    }
    if (payload === null || payload === undefined) {
      return [];
    }
    const rawList: WordEntryJson[] = payload.words;
    if (rawList === null || rawList === undefined || rawList.length === 0) {
      return [];
    }
    const out: WordEntry[] = [];
    const seenIds: Set<string> = new Set<string>();
    for (let i = 0; i < rawList.length; i++) {
      const raw: WordEntryJson = rawList[i];
      const entry: WordEntry = new WordEntry();
      entry.id = raw.id ?? '';
      entry.word = raw.word ?? '';
      entry.meaningZh = raw.meaningZh ?? '';
      entry.category = raw.category ?? '';
      entry.difficulty = typeof raw.difficulty === 'number' ? raw.difficulty : 1;
      entry.image = raw.image;
      entry.audio = raw.audio;
      if (!entry.isValid()) {
        continue;
      }
      if (seenIds.has(entry.id)) {
        // Duplicate id — skip silently; data file should guarantee uniqueness.
        continue;
      }
      seenIds.add(entry.id);
      out.push(entry);
    }
    return out;
  }
}
