import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { StringPreferencesLike } from './WrongAnswerStore';

const PREFS_NAME: string = 'word_pack_cache';
// V0.5 client follow-up: bumped from `pack_v1` so legacy bad caches
// (e.g. a 1-word pack pulled from prod by the old background refresh)
// are dropped on first launch after upgrade.
const PACK_KEY: string = 'pack_v2';

class RealPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;
  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }
  async getString(key: string): Promise<string> {
    const v: preferences.ValueType = await this.handle.get(key, '');
    return typeof v === 'string' ? v : '';
  }
  putString(key: string, value: string): Promise<void> {
    return this.handle.put(key, value);
  }
  flush(): Promise<void> {
    return this.handle.flush();
  }
}

/**
 * V0.5.1: persistent cache for the remote word pack JSON.
 *
 * Stored as a single string (the entire pack JSON envelope). Parsing happens
 * in WordPackBootstrapper / WordRepository. This class only enforces:
 *   - non-empty string round-trip
 *   - reject obviously corrupt payloads (parse fails, missing `words` array)
 */
export class WordPackCache {
  private prefs?: StringPreferencesLike;

  injectPreferencesForTest(p: StringPreferencesLike): void {
    this.prefs = p;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.prefs !== undefined) {
      return;
    }
    try {
      const handle: preferences.Preferences = await preferences.getPreferences(ctx, PREFS_NAME);
      this.prefs = new RealPrefs(handle);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      console.error(`WordPackCache.init failed: ${JSON.stringify(be)}`);
    }
  }

  async read(): Promise<string> {
    if (this.prefs === undefined) {
      return '';
    }
    const raw: string = await this.prefs.getString(PACK_KEY);
    if (raw.length === 0) {
      return '';
    }
    if (!WordPackCache.looksValid(raw)) {
      return '';
    }
    return raw;
  }

  async write(packJson: string): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    if (!WordPackCache.looksValid(packJson)) {
      return;
    }
    await this.prefs.putString(PACK_KEY, packJson);
    await this.prefs.flush();
  }

  /**
   * V0.5 client follow-up: wipe the cache slot so a UiTest scenario
   * starts from a known-empty state and bootstrap falls through to the
   * rawfile. Production code never calls this.
   */
  async clearForTest(ctx: common.UIAbilityContext): Promise<void> {
    if (this.prefs === undefined) {
      await this.init(ctx);
    }
    if (this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(PACK_KEY, '');
    await this.prefs.flush();
  }

  static looksValid(raw: string): boolean {
    if (raw.length === 0) {
      return false;
    }
    let parsed: object;
    try {
      parsed = JSON.parse(raw) as object;
    } catch (_err) {
      return false;
    }
    if (parsed === null || parsed === undefined) {
      return false;
    }
    const obj: Record<string, Object> = parsed as Record<string, Object>;
    const words: Object | undefined = obj.words;
    if (words === undefined || words === null) {
      return false;
    }
    return Array.isArray(words);
  }
}
