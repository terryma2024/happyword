import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { StringPreferencesLike } from './WrongAnswerStore';

const PREFS_NAME: string = 'word_pack_cache';
// V0.5 client follow-up: bumped from `pack_v1` so legacy bad caches
// (e.g. a 1-word pack pulled from prod by the old background refresh)
// are dropped on first launch after upgrade. The slot now holds a
// JSON envelope (body + etag + schemaVersion + fetchedAt). Bare
// pack JSON written by VC0.5.A clients is still accepted by `read()`
// for one upgrade cycle so the rollout doesn't strand existing
// installs.
const PACK_KEY: string = 'pack_v2';

/**
 * V0.5 client follow-up envelope written by WordPackSyncService
 * after a successful pull. Stored as a single JSON string under
 * PACK_KEY. Bootstrap consumers don't need to know about this —
 * `WordPackCache.read()` returns just the body.
 */
export class WordPackCacheRecord {
  body: string = '';
  etag: string = '';
  schemaVersion: number = 1;
  fetchedAt: string = '';
}

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
 * V0.5.1 / V0.5 follow-up: persistent cache for the remote word pack.
 *
 * Two on-disk shapes coexist under PACK_KEY:
 *   - V0.5.1 bare pack JSON (legacy; written by old auto-refresh)
 *   - V0.5 follow-up envelope (body + etag + schemaVersion + fetchedAt)
 *
 * `read()` returns just the body so cold-start consumers (the
 * bootstrapper) are oblivious to the envelope. `readRecord()` is
 * used exclusively by the manual sync path on ConfigPage to render
 * status text and to populate the `If-None-Match` header on the
 * next pull.
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

  /**
   * Returns just the pack body (envelope or bare). Empty string when
   * the slot is empty, the value can't be parsed, or the parsed body
   * doesn't have a `words` array.
   */
  async read(): Promise<string> {
    if (this.prefs === undefined) {
      return '';
    }
    const raw: string = await this.prefs.getString(PACK_KEY);
    if (raw.length === 0) {
      return '';
    }
    const env: WordPackCacheRecord | undefined = WordPackCache.tryParseEnvelope(raw);
    if (env !== undefined) {
      return WordPackCache.looksValidBody(env.body) ? env.body : '';
    }
    return WordPackCache.looksValidBody(raw) ? raw : '';
  }

  async readRecord(): Promise<WordPackCacheRecord | undefined> {
    if (this.prefs === undefined) {
      return undefined;
    }
    const raw: string = await this.prefs.getString(PACK_KEY);
    if (raw.length === 0) {
      return undefined;
    }
    const env: WordPackCacheRecord | undefined = WordPackCache.tryParseEnvelope(raw);
    if (env === undefined) {
      return undefined;
    }
    if (!WordPackCache.looksValidBody(env.body)) {
      return undefined;
    }
    return env;
  }

  /**
   * Bare-body write retained for tests and any caller that hasn't
   * been moved to writeRecord. Validates body shape before persist.
   */
  async write(packJson: string): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    if (!WordPackCache.looksValidBody(packJson)) {
      return;
    }
    await this.prefs.putString(PACK_KEY, packJson);
    await this.prefs.flush();
  }

  async writeRecord(body: string, etag: string, schemaVersion: number): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    if (!WordPackCache.looksValidBody(body)) {
      return;
    }
    const rec: WordPackCacheRecord = new WordPackCacheRecord();
    rec.body = body;
    rec.etag = etag;
    rec.schemaVersion = schemaVersion;
    rec.fetchedAt = new Date().toISOString();
    await this.prefs.putString(PACK_KEY, JSON.stringify(rec));
    await this.prefs.flush();
  }

  async touchFetchedAt(): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    const rec: WordPackCacheRecord | undefined = await this.readRecord();
    if (rec === undefined) {
      return;
    }
    rec.fetchedAt = new Date().toISOString();
    await this.prefs.putString(PACK_KEY, JSON.stringify(rec));
    await this.prefs.flush();
  }

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

  /**
   * Kept for backward compatibility with VC0.5.A unit tests that
   * still call `WordPackCache.looksValid` directly. Returns true if
   * the raw string is either a valid envelope (with a valid body) or
   * a valid bare pack body.
   */
  static looksValid(raw: string): boolean {
    if (raw.length === 0) {
      return false;
    }
    const env: WordPackCacheRecord | undefined = WordPackCache.tryParseEnvelope(raw);
    if (env !== undefined) {
      return WordPackCache.looksValidBody(env.body);
    }
    return WordPackCache.looksValidBody(raw);
  }

  private static tryParseEnvelope(raw: string): WordPackCacheRecord | undefined {
    let parsed: object;
    try {
      parsed = JSON.parse(raw) as object;
    } catch (_err) {
      return undefined;
    }
    if (parsed === null || parsed === undefined) {
      return undefined;
    }
    const obj: Record<string, Object> = parsed as Record<string, Object>;
    const body: Object | undefined = obj.body;
    if (typeof body !== 'string') {
      return undefined;
    }
    const rec: WordPackCacheRecord = new WordPackCacheRecord();
    rec.body = body as string;
    rec.etag = typeof obj.etag === 'string' ? (obj.etag as string) : '';
    rec.schemaVersion =
      typeof obj.schemaVersion === 'number' ? (obj.schemaVersion as number) : 1;
    rec.fetchedAt = typeof obj.fetchedAt === 'string' ? (obj.fetchedAt as string) : '';
    return rec;
  }

  private static looksValidBody(body: string): boolean {
    if (body.length === 0) {
      return false;
    }
    let parsed: object;
    try {
      parsed = JSON.parse(body) as object;
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
