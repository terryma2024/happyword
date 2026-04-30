import { common } from '@kit.AbilityKit';
import { WordEntry } from '../models/WordEntry';
import { WordRepository } from './WordRepository';
import { WordPackCache } from './WordPackCache';
import { RemoteWordPackService, RemoteFetchResult } from './RemoteWordPackService';
import { latestPackUrl } from './RemoteWordPackConfig';

export type RawfileLoader = () => Promise<WordEntry[]>;

export interface BootstrapDeps {
  cache: WordPackCache;
  remote: RemoteWordPackService;
  rawfileLoader: RawfileLoader;
  serverUrl: string;
}

/**
 * V0.5.1: cold-start orchestrator for the word pack.
 *
 * Sync section (returns within tens of ms):
 *   1. read cache
 *   2. if valid -> WordRepository from cache JSON
 *   3. else -> WordRepository from rawfile loader
 *
 * Async section (fire-and-forget, no UI block):
 *   4. fetch latest pack with If-None-Match
 *   5. on 200 -> write cache (next cold start picks it up)
 *   6. on 304 / error -> keep cache as-is
 *
 * Critical invariant: the in-memory `WordRepository` returned from `bootstrap`
 * is NOT replaced if a remote refresh succeeds. The new pack only takes effect
 * on the next cold start, preventing word-pool swaps mid-battle.
 */
export class WordPackBootstrapper {
  /**
   * Production helper: resolve real cache + service from the ability context.
   */
  static async forContext(ctx: common.UIAbilityContext): Promise<BootstrapDeps> {
    const cache: WordPackCache = new WordPackCache();
    await cache.init(ctx);
    const remote: RemoteWordPackService = new RemoteWordPackService();
    const repo: WordRepository = new WordRepository();
    const deps: BootstrapDeps = {
      cache,
      remote,
      rawfileLoader: async (): Promise<WordEntry[]> => {
        await repo.loadFromRawfile(ctx);
        return repo.all();
      },
      serverUrl: latestPackUrl(),
    };
    return deps;
  }

  async bootstrap(deps: BootstrapDeps): Promise<WordRepository> {
    const cached: string = await deps.cache.read();
    const repo: WordRepository = new WordRepository();

    if (cached.length > 0) {
      const entries: WordEntry[] = WordRepository.parseWordsJson(cached);
      if (entries.length > 0) {
        repo.setEntries(entries);
      } else {
        repo.setEntries(await deps.rawfileLoader());
      }
    } else {
      repo.setEntries(await deps.rawfileLoader());
    }

    this.refreshInBackground(deps);
    return repo;
  }

  private refreshInBackground(deps: BootstrapDeps): void {
    void (async (): Promise<void> => {
      try {
        const res: RemoteFetchResult = await deps.remote.fetchLatest(deps.serverUrl, undefined);
        if (res.status !== 200 || res.body.length === 0) {
          return;
        }
        await deps.cache.write(res.body);
      } catch (err) {
        console.error(`WordPackBootstrapper.refresh failed: ${JSON.stringify(err)}`);
      }
    })();
  }
}
