import { common } from '@kit.AbilityKit';
import { WordEntry } from '../models/WordEntry';
import { WordRepository } from './WordRepository';
import { WordPackCache } from './WordPackCache';
import { effectiveServerBaseUrl } from './RemoteWordPackConfig';
import { MIN_REPO_SIZE } from './QuestionGenerator';
import { Pack } from '../models/Pack';
import { BuiltinPackLoader } from './BuiltinPackLoader';
import { GlobalPackService } from './GlobalPackService';
import { FamilyPackService } from './FamilyPackService';
import { FamilyPacksBlob, FamilyPackEntry } from './FamilyPackMerge';
import { PackLibrary } from './PackLibrary';
import { PackNetworkFetchAdapter } from './PackNetworkFetchAdapter';

export type RawfileLoader = () => Promise<WordEntry[]>;

export interface BootstrapDeps {
  /** Legacy on-disk cache from pre-V0.6.6 public single-pack sync; read-only in bootstrap(). */
  cache: WordPackCache;
  rawfileLoader: RawfileLoader;
}

/**
 * V0.5 client follow-up: cold-start orchestrator for the word pack.
 *
 * Read-only. bootstrap() NEVER touches the network. New installs rely
 * on rawfile/bundled words; upgrades may still read a non-empty legacy
 * `WordPackCache` prefs blob until the user clears app data. Removing
 * the old auto-refresh avoids the cache-poisoning class of bug that
 * surfaced in V0.5.7 (prod was serving a 1-word pack; the old
 * auto-refresh wrote it to disk; next cold start handed a 1-word repo
 * to QuestionGenerator and threw).
 *
 * Sync section (returns within tens of ms):
 *   1. read cache.
 *   2. if cache parses to >= MIN_REPO_SIZE valid words, build the
 *      WordRepository from it.
 *   3. otherwise (empty / corrupt / too small), fall back to the
 *      caller-provided rawfile loader.
 */
export class WordPackBootstrapper {
  static async forContext(ctx: common.UIAbilityContext): Promise<BootstrapDeps> {
    const cache: WordPackCache = new WordPackCache();
    await cache.init(ctx);
    const repo: WordRepository = new WordRepository();
    const deps: BootstrapDeps = {
      cache,
      rawfileLoader: async (): Promise<WordEntry[]> => {
        await repo.loadFromRawfile(ctx);
        return repo.all();
      },
    };
    return deps;
  }

  async bootstrap(deps: BootstrapDeps): Promise<WordRepository> {
    const cached: string = await deps.cache.read();
    const repo: WordRepository = new WordRepository();
    if (cached.length > 0) {
      const entries: WordEntry[] = WordRepository.parseWordsJson(cached);
      if (entries.length >= MIN_REPO_SIZE) {
        repo.setEntries(entries);
        return repo;
      }
    }
    repo.setEntries(await deps.rawfileLoader());
    return repo;
  }

  /**
   * V0.6.5.1 — read-only / offline cold-start composer for the
   * three-layer Pack model. Loads:
   *
   *   - built-in packs from `rawfile/data/builtin/*.json` (5 files);
   *   - global packs from `wordmagic_global_packs` prefs cache (no network);
   *   - family packs from `wordmagic_family_packs` prefs cache (no network),
   *     adapted from FamilyPacksBlob → Pack[] using the same lift
   *     `GlobalPackService.parsePacks` performs on the global-packs
   *     latest.json wire format.
   *
   * Returns an assembled PackLibrary ready to feed the home-page chip
   * row and BattlePage's repo construction. NEVER touches the network —
   * that is reserved for ConfigPage's manual sync button (which calls
   * GlobalPackService.ensureLatest / FamilyPackService.ensureLatest
   * directly via the same `PackNetworkFetchAdapter`).
   */
  static async bootstrapPackLibrary(ctx: common.UIAbilityContext): Promise<PackLibrary> {
    const lib: PackLibrary = new PackLibrary();

    // 1. Built-in packs — deterministic order, scene metadata baked in.
    const builtinPromise: Promise<Pack[]> = BuiltinPackLoader.loadAll(ctx);

    // 2. Global packs — warm from prefs cache only.
    const baseUrl: string = effectiveServerBaseUrl();
    const sharedAdapter: PackNetworkFetchAdapter = new PackNetworkFetchAdapter();
    const gps: GlobalPackService = new GlobalPackService(sharedAdapter, baseUrl);
    await gps.init(ctx);
    const globalPromise: Promise<Pack[]> = gps.warmFromCache();

    // 3. Family packs — warm from prefs cache only, then adapt blob → Pack[].
    const fps: FamilyPackService = new FamilyPackService(sharedAdapter, baseUrl);
    await fps.init(ctx);
    const familyPromise: Promise<Pack[]> = WordPackBootstrapper.familyPacksFromService(fps);

    const builtins: Pack[] = await builtinPromise;
    const globals: Pack[] = await globalPromise;
    const families: Pack[] = await familyPromise;
    lib.setBuiltins(builtins);
    lib.setGlobals(globals);
    lib.setFamilies(families);
    return lib;
  }

  /**
   * Adapt the cached `FamilyPacksBlob` (server merged-JSON envelope,
   * see FamilyPackMerge) into the V0.6.5 `Pack[]` shape. Each pack's
   * raw words array is re-serialised through GlobalPackService.parsePacks
   * so the field-level lift (snake_case ↔ camelCase, distractors,
   * example, illustration/audio URLs) only lives in one place.
   */
  private static async familyPacksFromService(fps: FamilyPackService): Promise<Pack[]> {
    const blob: FamilyPacksBlob | null = await fps.warmFromCache();
    if (blob === null) return [];
    if (blob.packs.length === 0) return [];

    // Build the same wire envelope the public global-packs endpoint
    // returns and reuse GlobalPackService.parsePacks. Family packs come
    // out with `source = 'global'` from that parser; rewrite to 'family'
    // post-hoc.
    // V0.6.7.3 codelinter (@performance/reuse-date-instances-check):
    // hoist a single Date instance out of the loop and use setTime()
    // per pack instead of `new Date(ms)` each iteration. Family pack
    // counts are small (≤ MAX_ACTIVE_PACKS×N), but the rule fires
    // unconditionally on `new Date(...)` inside any loop body.
    const parts: string[] = [];
    const dateScratch: Date = new Date(0);
    for (let i = 0; i < blob.packs.length; i++) {
      const p: FamilyPackEntry = blob.packs[i];
      const wordsJson: string = JSON.stringify(p.words);
      let publishedIso: string = '';
      if (p.publishedAtMs > 0) {
        dateScratch.setTime(p.publishedAtMs);
        publishedIso = dateScratch.toISOString();
      }
      const piece: string =
        '{"pack_id":' + JSON.stringify(p.packId) + ',' +
        '"name":' + JSON.stringify(p.name) + ',' +
        '"version":' + p.version.toString() + ',' +
        '"schema_version":' + p.schemaVersion.toString() + ',' +
        '"published_at":' + JSON.stringify(publishedIso) + ',' +
        '"words":' + wordsJson + '}';
      parts.push(piece);
    }
    const envelope: string =
      '{"schema_version":' + blob.schemaVersion.toString() + ',' +
      '"merged_at":"","packs":[' + parts.join(',') + ']}';
    const lifted: Pack[] = GlobalPackService.parsePacks(envelope);
    for (let i = 0; i < lifted.length; i++) {
      lifted[i].source = 'family';
    }
    return lifted;
  }
}
