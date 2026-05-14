import { describe, it, expect } from '@ohos/hypium';
import {
  WordPackBootstrapper,
  BootstrapDeps,
} from '../main/ets/services/WordPackBootstrapper';
import { WordPackCache } from '../main/ets/services/WordPackCache';
import { WordRepository } from '../main/ets/services/WordRepository';
import { WordEntry } from '../main/ets/models/WordEntry';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

class MapPrefs implements StringPreferencesLike {
  readonly store: Map<string, string> = new Map<string, string>();
  async getString(key: string): Promise<string> {
    return this.store.get(key) ?? '';
  }
  async putString(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
  async flush(): Promise<void> {}
}

// Padded to 3 entries because the bootstrapper drops cached packs with < MIN_REPO_SIZE words.
const SAMPLE_PACK: string =
  '{"version":1,"schema_version":1,"published_at":"2026-05-08T00:00:00Z",' +
  '"words":[' +
  '{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1},' +
  '{"id":"fruit-banana","word":"banana","meaningZh":"香蕉","category":"fruit","difficulty":1},' +
  '{"id":"fruit-pear","word":"pear","meaningZh":"梨","category":"fruit","difficulty":1}' +
  ']}';

const RAWFILE_PACK: string =
  '{"version":1,"words":[' +
  '{"id":"rf-only","word":"only","meaningZh":"仅","category":"fruit","difficulty":1},' +
  '{"id":"rf-two","word":"two","meaningZh":"二","category":"fruit","difficulty":1},' +
  '{"id":"rf-three","word":"three","meaningZh":"三","category":"fruit","difficulty":1}' +
  ']}';

const ONE_WORD_PACK: string =
  '{"version":1,"schema_version":1,"published_at":"2026-05-01T00:00:00Z",' +
  '"words":[' +
  '{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1}' +
  ']}';

function makeDeps(prefsContent: string): BootstrapDeps {
  const cache: WordPackCache = new WordPackCache();
  const prefs: MapPrefs = new MapPrefs();
  if (prefsContent.length > 0) {
    prefs.store.set('pack_v2', prefsContent);
  }
  cache.injectPreferencesForTest(prefs);
  return {
    cache,
    rawfileLoader: async (): Promise<WordEntry[]> => WordRepository.parseWordsJson(RAWFILE_PACK),
  };
}

export default function wordPackBootstrapperTest() {
  describe('WordPackBootstrapper', () => {
    it('usesCacheWhenValid', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const repo: WordRepository = await b.bootstrap(makeDeps(SAMPLE_PACK));
      expect(repo.size()).assertEqual(3);
      const apple: WordEntry | undefined = repo.findById('fruit-apple');
      expect(apple !== undefined).assertTrue();
    });

    it('fallsBackToRawfileWhenCacheEmpty', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const repo: WordRepository = await b.bootstrap(makeDeps(''));
      expect(repo.size()).assertEqual(3);
      expect(repo.findById('rf-only') !== undefined).assertTrue();
    });

    it('fallsBackToRawfileWhenCacheCorrupt', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const repo: WordRepository = await b.bootstrap(makeDeps('{not json}'));
      expect(repo.size()).assertEqual(3);
    });

    it('fallsBackToRawfileWhenCachedPackHasFewerThanThreeWords', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const repo: WordRepository = await b.bootstrap(makeDeps(ONE_WORD_PACK));
      expect(repo.size()).assertEqual(3);
      expect(repo.findById('rf-only') !== undefined).assertTrue();
      expect(repo.findById('fruit-apple') === undefined).assertTrue();
    });

    it('keepsLegacyCacheBodyIntact', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const deps: BootstrapDeps = makeDeps(SAMPLE_PACK);
      const repo: WordRepository = await b.bootstrap(deps);
      const cached: string = await deps.cache.read();
      expect(cached).assertEqual(SAMPLE_PACK);
      expect(repo.size()).assertEqual(3);
    });
  });
}
