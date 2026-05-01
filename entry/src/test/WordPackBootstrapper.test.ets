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
  callCount: number = 0;
  async fetch(
    _url: string,
    _h: string | undefined,
    _t: number,
  ): Promise<RemoteFetchResult> {
    this.callCount += 1;
    const r: RemoteFetchResult = new RemoteFetchResult();
    r.status = this.status;
    r.body = this.body;
    return r;
  }
}

// V0.5 client follow-up: padded to 3 entries because the bootstrapper
// now drops cached packs with < MIN_REPO_SIZE words. A 2-word fixture
// would always trip the guard and the "uses cache when valid" tests
// would silently fall through to the rawfile.
const SAMPLE_PACK: string =
  '{"version":1,"schema_version":1,"published_at":"2026-05-08T00:00:00Z",' +
  '"words":[' +
  '{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1},' +
  '{"id":"fruit-banana","word":"banana","meaningZh":"香蕉","category":"fruit","difficulty":1},' +
  '{"id":"fruit-pear","word":"pear","meaningZh":"梨","category":"fruit","difficulty":1}' +
  ']}';

// V0.5 client follow-up: rawfile fixture is now padded to >=3 entries
// because the bootstrapper enforces a min-size guard. A 1-word fixture
// would just trip the guard regardless of the cache state and obscure
// what each test is actually trying to assert.
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

class DepsBundle {
  deps: BootstrapDeps = { cache: new WordPackCache(), remote: new RemoteWordPackService(), rawfileLoader: async (): Promise<WordEntry[]> => [], serverUrl: '' };
  stub: StubRequester = new StubRequester();
}

function makeDeps(
  prefsContent: string,
  requesterStatus: number,
  requesterBody: string,
): BootstrapDeps {
  return makeDepsBundle(prefsContent, requesterStatus, requesterBody).deps;
}

function makeDepsBundle(
  prefsContent: string,
  requesterStatus: number,
  requesterBody: string,
): DepsBundle {
  const cache: WordPackCache = new WordPackCache();
  const prefs: MapPrefs = new MapPrefs();
  if (prefsContent.length > 0) {
    prefs.store.set('pack_v2', prefsContent);
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
  const bundle: DepsBundle = new DepsBundle();
  bundle.deps = deps;
  bundle.stub = stub;
  return bundle;
}

export default function wordPackBootstrapperTest() {
  describe('WordPackBootstrapper', () => {
    it('usesCacheWhenValid', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const bundle: DepsBundle = makeDepsBundle(SAMPLE_PACK, 0, '');
      const repo: WordRepository = await b.bootstrap(bundle.deps);
      expect(repo.size()).assertEqual(3);
      const apple: WordEntry | undefined = repo.findById('fruit-apple');
      expect(apple !== undefined).assertTrue();
      // VC0.5.A: bootstrap is read-only — no remote fetch must fire.
      expect(bundle.stub.callCount).assertEqual(0);
    });

    it('fallsBackToRawfileWhenCacheEmpty', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const bundle: DepsBundle = makeDepsBundle('', 0, '');
      const repo: WordRepository = await b.bootstrap(bundle.deps);
      expect(repo.size()).assertEqual(3);
      expect(repo.findById('rf-only') !== undefined).assertTrue();
      expect(bundle.stub.callCount).assertEqual(0);
    });

    it('fallsBackToRawfileWhenCacheCorrupt', 0, async () => {
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const bundle: DepsBundle = makeDepsBundle('{not json}', 0, '');
      const repo: WordRepository = await b.bootstrap(bundle.deps);
      expect(repo.size()).assertEqual(3);
    });

    it('fallsBackToRawfileWhenCachedPackHasFewerThanThreeWords', 0, async () => {
      // VC0.5.A: production prod was returning a 1-word pack at the time
      // of the bug screenshot. The old bootstrapper happily handed a
      // 1-word repo to QuestionGenerator and threw at the first call to
      // nextQuestion(); BattlePage's catch-all then painted "Failed to
      // load words". Min-size guard makes that recoverable.
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const bundle: DepsBundle = makeDepsBundle(ONE_WORD_PACK, 0, '');
      const repo: WordRepository = await b.bootstrap(bundle.deps);
      expect(repo.size()).assertEqual(3); // RAWFILE_PACK has 3 entries
      expect(repo.findById('rf-only') !== undefined).assertTrue();
      expect(repo.findById('fruit-apple') === undefined).assertTrue();
    });

    it('keepsCacheOnNetworkError', 0, async () => {
      // The network never gets touched any more, but legacy callers
      // (and a future "manual sync" path) may still configure a stub
      // requester. Keep the assertion that bootstrap leaves the cache
      // body intact regardless of what the requester is configured to
      // do, because it never asks.
      const b: WordPackBootstrapper = new WordPackBootstrapper();
      const bundle: DepsBundle = makeDepsBundle(SAMPLE_PACK, 0, '');
      const repo: WordRepository = await b.bootstrap(bundle.deps);
      const cached: string = await bundle.deps.cache.read();
      expect(cached).assertEqual(SAMPLE_PACK);
      expect(repo.size()).assertEqual(3);
      expect(bundle.stub.callCount).assertEqual(0);
    });
  });
}
