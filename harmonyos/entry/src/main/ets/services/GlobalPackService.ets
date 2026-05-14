import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';

import { StringPreferencesLike } from './WrongAnswerStore';
import { ParentFetchAdapter, ParentFetchResult } from './ParentApiClient';
import { Pack, SceneMetadata } from '../models/Pack';
import { WordEntry, ExampleSentence } from '../models/WordEntry';
import { MonsterPlan, MonsterSlot } from '../models/AdventureRegion';
import { MonsterKind, monsterIndexForKind } from '../data/MonsterCatalog';

/**
 * V0.6.5 — anonymous client for the public global-packs endpoint.
 *
 * Twin of `FamilyPackService` (same prefs envelope, same 200/304/204 handling)
 * with three differences:
 *   - No `Authorization: Bearer ...` header (anonymous).
 *   - Different prefs slot: `wordmagic_global_packs`.
 *   - Endpoint path: `/api/v1/public/global-packs/latest.json`.
 *
 * The service caches both the raw envelope (etag/body/fetchedAtMs) and a
 * parsed `Pack[]` in memory; consumers (PackLibrary) read `currentPacks()`
 * after `init()` + `warmFromCache()`. Network failures fall back to whatever
 * is cached and never throw.
 */

const PREFS_NAME: string = 'wordmagic_global_packs';
const KEY_BLOB: string = 'global_packs_v1';

const HEADER_IF_NONE_MATCH: string = 'If-None-Match';
const HEADER_ETAG: string = 'ETag';
const HEADER_ETAG_LOWER: string = 'etag';

class CachedEnvelope {
  etag: string = '';
  body: string = '';
  fetchedAtMs: number = 0;
}

interface RawEnvelope {
  etag?: string;
  body?: string;
  fetchedAtMs?: number;
}

/** Same shape as FamilyPackFetchAdapter — adapter + lastResponseHeader probe. */
export interface GlobalPackFetchAdapter extends ParentFetchAdapter {
  head(url: string, headers: Record<string, string>): Promise<ParentFetchResult>;
  lastResponseHeader(name: string): string;
}

class RealGlobalPackPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;
  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }
  async getString(key: string): Promise<string> {
    try {
      const v: preferences.ValueType = await this.handle.get(key, '');
      return typeof v === 'string' ? v : '';
    } catch (err) {
      console.error(`GlobalPackService.RealGlobalPackPrefs.getString failed: ${JSON.stringify(err as BusinessError)}`);
      return '';
    }
  }
  async putString(key: string, value: string): Promise<void> {
    try {
      await this.handle.put(key, value);
    } catch (err) {
      console.error(`GlobalPackService.RealGlobalPackPrefs.putString failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
  async flush(): Promise<void> {
    try {
      await this.handle.flush();
    } catch (err) {
      console.error(`GlobalPackService.RealGlobalPackPrefs.flush failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
}

export class GlobalPackEnsureResult {
  status: 'updated' | 'not_modified' | 'cleared' | 'cached_fallback' | 'no_data' = 'no_data';
  packs: Pack[] = [];
}

export class GlobalPackService {
  private readonly adapter: GlobalPackFetchAdapter;
  private readonly baseUrl: string;
  private prefs?: StringPreferencesLike;
  private nowMs: () => number = (): number => Date.now();
  private memoryPacks: Pack[] = [];
  private memoryEnvelope: CachedEnvelope | null = null;

  constructor(adapter: GlobalPackFetchAdapter, baseUrl: string) {
    this.adapter = adapter;
    this.baseUrl = GlobalPackService.trimTrailingSlash(baseUrl);
  }

  injectPreferences(p: StringPreferencesLike): void {
    this.prefs = p;
  }

  injectClock(now: () => number): void {
    this.nowMs = now;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.prefs !== undefined) {
      return;
    }
    try {
      const real: preferences.Preferences = await preferences.getPreferences(ctx, PREFS_NAME);
      this.prefs = new RealGlobalPackPrefs(real);
    } catch (err) {
      console.error(`GlobalPackService.init failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  /** In-memory copy of the parsed pack list. Empty when nothing is cached. */
  currentPacks(): Pack[] {
    return this.memoryPacks.slice();
  }

  /** Pre-load the in-memory cache from preferences. */
  async warmFromCache(): Promise<Pack[]> {
    const env: CachedEnvelope | null = await this.readCache();
    if (env === null) {
      this.memoryPacks = [];
      this.memoryEnvelope = null;
      return [];
    }
    this.memoryEnvelope = env;
    this.memoryPacks = GlobalPackService.parsePacks(env.body);
    return this.memoryPacks.slice();
  }

  /** Pull (or revalidate) the latest merged JSON. Never throws. */
  async ensureLatest(): Promise<GlobalPackEnsureResult> {
    const out: GlobalPackEnsureResult = new GlobalPackEnsureResult();
    const url: string = `${this.baseUrl}/api/v1/public/global-packs/latest.json`;
    const headers: Record<string, string> = {};

    const cached: CachedEnvelope | null = this.memoryEnvelope ?? await this.readCache();
    if (cached !== null && cached.etag.length > 0) {
      headers[HEADER_IF_NONE_MATCH] = cached.etag;
    }

    let res: ParentFetchResult;
    try {
      res = await this.adapter.get(url, headers);
    } catch (_err) {
      out.status = 'cached_fallback';
      out.packs = this.memoryPacks.slice();
      return out;
    }

    if (res.status === 304) {
      out.status = 'not_modified';
      out.packs = this.memoryPacks.slice();
      if (cached !== null) {
        cached.fetchedAtMs = this.nowMs();
        await this.writeCache(cached);
      }
      return out;
    }

    if (res.status === 204) {
      await this.clearCache();
      this.memoryPacks = [];
      this.memoryEnvelope = null;
      out.status = 'cleared';
      out.packs = [];
      return out;
    }

    if (res.status === 200 || res.status === 201) {
      const etagHeader: string = this.adapter.lastResponseHeader(HEADER_ETAG);
      const etagFallback: string = this.adapter.lastResponseHeader(HEADER_ETAG_LOWER);
      const etag: string = etagHeader.length > 0 ? etagHeader : etagFallback;
      const env: CachedEnvelope = new CachedEnvelope();
      env.etag = etag;
      env.body = res.body;
      env.fetchedAtMs = this.nowMs();
      await this.writeCache(env);
      this.memoryEnvelope = env;
      this.memoryPacks = GlobalPackService.parsePacks(env.body);
      out.status = 'updated';
      out.packs = this.memoryPacks.slice();
      return out;
    }

    out.status = 'cached_fallback';
    out.packs = this.memoryPacks.slice();
    return out;
  }

  /** HEAD-only ETag probe. Returns null on error; never throws. */
  async peekRemoteEtag(): Promise<string | null> {
    const url: string = `${this.baseUrl}/api/v1/public/global-packs/latest.json`;
    const headers: Record<string, string> = {};
    try {
      const res: ParentFetchResult = await this.adapter.head(url, headers);
      if (res.status === 204) {
        return '';
      }
      if (res.status >= 400) {
        return null;
      }
    } catch (_err) {
      return null;
    }
    const etagHeader: string = this.adapter.lastResponseHeader(HEADER_ETAG);
    const etagFallback: string = this.adapter.lastResponseHeader(HEADER_ETAG_LOWER);
    const etag: string = etagHeader.length > 0 ? etagHeader : etagFallback;
    return etag.length > 0 ? etag : null;
  }

  private async readCache(): Promise<CachedEnvelope | null> {
    if (this.prefs === undefined) {
      return null;
    }
    const raw: string = await this.prefs.getString(KEY_BLOB);
    if (raw.length === 0) {
      return null;
    }
    try {
      const env: RawEnvelope = JSON.parse(raw) as RawEnvelope;
      const out: CachedEnvelope = new CachedEnvelope();
      out.etag = typeof env.etag === 'string' ? env.etag : '';
      out.body = typeof env.body === 'string' ? env.body : '';
      out.fetchedAtMs = typeof env.fetchedAtMs === 'number' ? env.fetchedAtMs : 0;
      return out;
    } catch (_err) {
      return null;
    }
  }

  private async writeCache(env: CachedEnvelope): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    const wire: RawEnvelope = { etag: env.etag, body: env.body, fetchedAtMs: env.fetchedAtMs };
    await this.prefs.putString(KEY_BLOB, JSON.stringify(wire));
    await this.prefs.flush();
  }

  private async clearCache(): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(KEY_BLOB, '');
    await this.prefs.flush();
  }

  private static trimTrailingSlash(p: string): string {
    let end: number = p.length;
    while (end > 0 && p.charAt(end - 1) === '/') {
      end -= 1;
    }
    return p.substring(0, end);
  }

  /**
   * Pure parser exposed for unit tests. Converts the global-packs
   * latest.json envelope into a list of fully-hydrated Pack objects with `source = 'global'`.
   * Returns an empty list on any parse error.
   */
  static parsePacks(body: string): Pack[] {
    if (body.length === 0) {
      return [];
    }
    let raw: RawLatest;
    try {
      raw = JSON.parse(body) as RawLatest;
    } catch (_err) {
      return [];
    }
    if (raw === null || raw === undefined || !Array.isArray(raw.packs)) {
      return [];
    }
    const out: Pack[] = [];
    for (let i = 0; i < raw.packs.length; i++) {
      const r: RawPack = raw.packs[i];
      if (typeof r.pack_id !== 'string' || r.pack_id.length === 0) continue;
      const p: Pack = new Pack();
      p.id = r.pack_id;
      p.name = typeof r.name === 'string' ? r.name : r.pack_id;
      p.labelZh = typeof r.description === 'string' ? r.description : '';
      p.source = 'global';
      p.version = typeof r.version === 'number' ? r.version : 0;
      p.publishedAtMs = parseIsoMs(r.published_at);
      p.scene = parseScene(r.scene);
      p.words = parseWords(r.words);
      out.push(p);
    }
    return out;
  }
}

interface RawLatest {
  schema_version?: number;
  merged_at?: string;
  packs?: RawPack[];
}

interface RawPack {
  pack_id?: string;
  name?: string;
  description?: string;
  scene?: RawScene;
  version?: number;
  schema_version?: number;
  published_at?: string;
  words?: RawWord[];
}

interface RawSlot {
  kind?: string;
  catalogIndex?: number;
}

interface RawScene {
  bgPrimary?: string;
  bgAccent?: string;
  bossName?: string;
  bossCandidates?: number[];
  monsterPlan?: RawSlot[];
  storyZh?: string;
}

interface RawExample {
  en?: string;
  zh?: string;
}

interface RawWord {
  id?: string;
  word?: string;
  meaningZh?: string;
  meaning_zh?: string;
  category?: string;
  difficulty?: number;
  distractors?: string[];
  example?: RawExample;
  exampleEn?: string;
  example_en?: string;
  exampleZh?: string;
  example_zh?: string;
  illustrationUrl?: string;
  illustration_url?: string;
  audioUrl?: string;
  audio_url?: string;
}

function parseIsoMs(iso: string | undefined): number {
  if (typeof iso !== 'string' || iso.length === 0) return 0;
  const parsed: number = Date.parse(iso);
  if (Number.isNaN(parsed)) return 0;
  return parsed;
}

function parseKind(s: string | undefined): MonsterKind {
  if (s === 'spelling') return MonsterKind.Spelling;
  if (s === 'review') return MonsterKind.Review;
  if (s === 'elite') return MonsterKind.Elite;
  if (s === 'boss') return MonsterKind.Boss;
  return MonsterKind.Normal;
}

function parseScene(raw: RawScene | undefined): SceneMetadata {
  const scene: SceneMetadata = new SceneMetadata();
  if (raw === undefined || raw === null) return scene;
  if (typeof raw.bgPrimary === 'string') scene.bgPrimary = raw.bgPrimary;
  if (typeof raw.bgAccent === 'string') scene.bgAccent = raw.bgAccent;
  if (typeof raw.bossName === 'string') scene.bossName = raw.bossName;
  if (Array.isArray(raw.bossCandidates)) {
    const cleaned: number[] = [];
    for (let i = 0; i < raw.bossCandidates.length; i++) {
      const n: number = raw.bossCandidates[i];
      if (typeof n === 'number' && Number.isFinite(n)) cleaned.push(n);
    }
    scene.bossCandidates = cleaned;
  }
  if (typeof raw.storyZh === 'string' && raw.storyZh.length > 0) scene.storyZh = raw.storyZh;
  if (Array.isArray(raw.monsterPlan)) {
    const plan: MonsterPlan = new MonsterPlan();
    const slots: MonsterSlot[] = [];
    for (let i = 0; i < raw.monsterPlan.length; i++) {
      const r: RawSlot = raw.monsterPlan[i];
      const slot: MonsterSlot = new MonsterSlot();
      slot.kind = parseKind(r.kind);
      slot.catalogIndex = typeof r.catalogIndex === 'number' && Number.isFinite(r.catalogIndex)
        ? r.catalogIndex
        : monsterIndexForKind(slot.kind);
      slots.push(slot);
    }
    plan.slots = slots;
    scene.monsterPlan = plan;
  }
  return scene;
}

function pickStr(primary: string | undefined, fallback: string | undefined): string {
  if (typeof primary === 'string' && primary.length > 0) return primary;
  if (typeof fallback === 'string' && fallback.length > 0) return fallback;
  return '';
}

function pickStrNullable(primary: string | undefined, fallback: string | undefined): string | undefined {
  if (typeof primary === 'string' && primary.length > 0) return primary;
  if (typeof fallback === 'string' && fallback.length > 0) return fallback;
  return undefined;
}

function parseWords(raw: RawWord[] | undefined): WordEntry[] {
  if (!Array.isArray(raw)) return [];
  const out: WordEntry[] = [];
  const seen: Set<string> = new Set<string>();
  for (let i = 0; i < raw.length; i++) {
    const r: RawWord = raw[i];
    const e: WordEntry = new WordEntry();
    e.id = typeof r.id === 'string' ? r.id : '';
    e.word = typeof r.word === 'string' ? r.word : '';
    e.meaningZh = pickStr(r.meaningZh, r.meaning_zh);
    e.category = typeof r.category === 'string' ? r.category : '';
    e.difficulty = typeof r.difficulty === 'number' && Number.isFinite(r.difficulty) ? r.difficulty : 1;
    if (Array.isArray(r.distractors)) {
      const cleaned: string[] = [];
      for (let j = 0; j < r.distractors.length; j++) {
        const d: string = r.distractors[j];
        if (typeof d === 'string' && d.length > 0) cleaned.push(d);
      }
      if (cleaned.length > 0) e.distractors = cleaned;
    }
    const exEn: string | undefined = r.example !== undefined && r.example !== null
      ? pickStrNullable(r.example.en, undefined)
      : pickStrNullable(r.exampleEn, r.example_en);
    const exZh: string | undefined = r.example !== undefined && r.example !== null
      ? pickStrNullable(r.example.zh, undefined)
      : pickStrNullable(r.exampleZh, r.example_zh);
    if (exEn !== undefined || exZh !== undefined) {
      const ex: ExampleSentence = new ExampleSentence();
      ex.en = exEn !== undefined ? exEn : '';
      ex.zh = exZh !== undefined ? exZh : '';
      e.example = ex;
    }
    const illust: string | undefined = pickStrNullable(r.illustrationUrl, r.illustration_url);
    if (illust !== undefined) e.illustrationUrl = illust;
    const audio: string | undefined = pickStrNullable(r.audioUrl, r.audio_url);
    if (audio !== undefined) e.audioUrl = audio;
    if (!e.isValid()) continue;
    if (seen.has(e.id)) continue;
    seen.add(e.id);
    out.push(e);
  }
  return out;
}
