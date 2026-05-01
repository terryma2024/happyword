import { common } from '@kit.AbilityKit';
import { WordEntry } from '../models/WordEntry';
import { WordRepository } from './WordRepository';
import { WordPackCache } from './WordPackCache';
import { RemoteWordPackService } from './RemoteWordPackService';
import { latestPackUrl } from './RemoteWordPackConfig';
import { MIN_REPO_SIZE } from './QuestionGenerator';

export type RawfileLoader = () => Promise<WordEntry[]>;

export interface BootstrapDeps {
  cache: WordPackCache;
  // Kept in the bag because the manual sync path (VC0.5.B) still needs
  // it. bootstrap() itself ignores this field.
  remote: RemoteWordPackService;
  rawfileLoader: RawfileLoader;
  serverUrl: string;
}

/**
 * V0.5 client follow-up: cold-start orchestrator for the word pack.
 *
 * Read-only. bootstrap() NEVER touches the network. The only path
 * that writes the cache is `WordPackSyncService.syncOnce`, triggered
 * by an operator tap on ConfigPage. Removing the auto-refresh kills
 * the cache-poisoning class of bug that surfaced in V0.5.7 (prod was
 * serving a 1-word pack; the old auto-refresh wrote it to disk; next
 * cold start handed a 1-word repo to QuestionGenerator and threw).
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
      if (entries.length >= MIN_REPO_SIZE) {
        repo.setEntries(entries);
        return repo;
      }
    }
    repo.setEntries(await deps.rawfileLoader());
    return repo;
  }
}
