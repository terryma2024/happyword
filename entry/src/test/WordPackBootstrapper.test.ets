import { describe, it, expect } from '@ohos/hypium';
import {
  WordPackBootstrapper,
  BootstrapDeps,
} from '../main/ets/services/WordPackBootstrapper';
import { WordPackCache } from '../main/ets/services/WordPackCache';
import {
  RemoteWordPackService,
  RemoteFetchResult,
  HttpRequester,
} from '../main/ets/services/RemoteWordPackService';
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

class StubRequester implements HttpRequester {
  status: number = 200;
  body: string = '';
  async fetch(
    _url: string,
    _h: string | undefined,
    _t: number,
  ): Promise<RemoteFetchResult> {
    const r: RemoteFetchResult = new RemoteFetchResult();
    r.status = this.status;
    r.body = this.body;
    return r;
  }
}

const SAMPLE_PACK: string =
  '{"version":1,"schema_version":1,"published_at":"2026-05-08T00:00:00Z",' +
  '"words":[' +
  '{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1},' +
  '{"id":"fruit-banana","word":"banana","meaningZh":"香蕉","category":"fruit","difficulty":1}' +
  ']}';

const RAWFILE_PACK: string =
  '{"version":1,"words":[' +
  '{"id":"rf-only","word":"only","meaningZh":"仅","category":"fruit","difficulty":1}' +
  ']}';

function makeDeps(
  prefsContent: string,
  requesterStatus: number,
  requesterBody: string,
): BootstrapDeps {
  const cache: WordPackCache = new WordPackCache();
  const prefs: MapPrefs = new MapPrefs();
  if (prefsContent.length > 0) {
    prefs.store.set('pack_v1', prefsContent);
  }
  cache.injectPreferencesForTest(prefs);

  const remote: RemoteWordPackService = new RemoteWordPackService();
  const stub: StubRequester = new StubRequester();
  stub.status = requesterStatus;
  stub.body = requesterBody;
  remote.injectHttpRequesterForTest(stub);

  const deps: BootstrapDeps = {
    cache,
    remote,
    rawfileLoader: async (): Promise<WordEntry[]> => WordRepository.parseWordsJson(RAWFILE_PACK),
    serverUrl: 'https://x/api/v1/packs/latest.json',
  };
  return deps;
}

export default function wordPackBootstrapperTest() {
  describe('WordPackBootstrapper', () => {
    it('usesCacheWhenValid', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const deps: BootstrapDeps = makeDeps(SAMPLE_PACK, 0, '');
      const repo: WordRepository = await b.bootstrap(deps);
      expect(repo.size()).assertEqual(2);
      const apple: WordEntry | undefined = repo.findById('fruit-apple');
      expect(apple !== undefined).assertTrue();
    });

    it('fallsBackToRawfileWhenCacheEmpty', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const deps: BootstrapDeps = makeDeps('', 0, '');
      const repo: WordRepository = await b.bootstrap(deps);
      expect(repo.size()).assertEqual(1);
      expect(repo.findById('rf-only') !== undefined).assertTrue();
    });

    it('fallsBackToRawfileWhenCacheCorrupt', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const deps: BootstrapDeps = makeDeps('{not json}', 0, '');
      const repo: WordRepository = await b.bootstrap(deps);
      expect(repo.size()).assertEqual(1);
    });

    it('writesCacheAfterSuccessfulRefresh', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const deps: BootstrapDeps = makeDeps('', 200, SAMPLE_PACK);
      await b.bootstrap(deps);
      // wait a tick for fire-and-forget refresh
      await new Promise<void>((resolve): void => {
        setTimeout(resolve, 20);
      });
      const cached: string = await deps.cache.read();
      expect(cached).assertEqual(SAMPLE_PACK);
    });

    it('keepsCacheOn304', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const deps: BootstrapDeps = makeDeps(SAMPLE_PACK, 304, '');
      const repo: WordRepository = await b.bootstrap(deps);
      await new Promise<void>((resolve): void => {
        setTimeout(resolve, 20);
      });
      expect(repo.size()).assertEqual(2);
      const cached: string = await deps.cache.read();
      expect(cached).assertEqual(SAMPLE_PACK);
    });

    it('keepsCacheOnNetworkError', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const deps: BootstrapDeps = makeDeps(SAMPLE_PACK, 0, '');
      const repo: WordRepository = await b.bootstrap(deps);
      await new Promise<void>((resolve): void => {
        setTimeout(resolve, 20);
      });
      const cached: string = await deps.cache.read();
      expect(cached).assertEqual(SAMPLE_PACK);
      expect(repo.size()).assertEqual(2);
    });
  });
}
