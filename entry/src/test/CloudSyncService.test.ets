import { describe, it, expect } from '@ohos/hypium';
import { CloudSyncService } from '../main/ets/services/CloudSyncService';
import { CloudSyncResult } from '../main/ets/services/CloudSyncTypes';
import { LearningRecorder } from '../main/ets/services/LearningRecorder';
import { CloudCredentials, CloudCredentialsSnapshot } from '../main/ets/services/CloudCredentials';
import {
  LearningSnapshot,
  StringPreferencesLike,
  WordStat,
  WrongAnswerStore,
} from '../main/ets/services/WrongAnswerStore';
import { ParentFetchAdapter, ParentFetchResult } from '../main/ets/services/ParentApiClient';

const BASE: string = 'https://happyword.vercel.app';
const SYNC_PATH: string = '/api/v1/child/word-stats/sync';

class MemPrefs implements StringPreferencesLike {
  store: Map<string, string> = new Map<string, string>();
  flushCount: number = 0;
  async getString(key: string): Promise<string> {
    return this.store.get(key) ?? '';
  }
  async putString(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
  async flush(): Promise<void> {
    this.flushCount += 1;
  }
}

function makeStore(): WrongAnswerStore {
  const store: WrongAnswerStore = new WrongAnswerStore();
  store.injectPreferences(new MemPrefs());
  return store;
}

class CapturedPost {
  url: string = '';
  body: string = '';
  auth: string = '';
}

class CapturingAdapter implements ParentFetchAdapter {
  responses: ParentFetchResult[] = [];
  posts: CapturedPost[] = [];
  failNetwork: boolean = false;

  enqueue(status: number, body: string): void {
    const r: ParentFetchResult = new ParentFetchResult();
    r.status = status;
    r.body = body;
    this.responses.push(r);
  }

  async get(_url: string, _h: Record<string, string>): Promise<ParentFetchResult> {
    return this.serve();
  }
  async post(url: string, headers: Record<string, string>, body: string): Promise<ParentFetchResult> {
    if (this.failNetwork) {
      throw new Error('network');
    }
    const p: CapturedPost = new CapturedPost();
    p.url = url;
    p.body = body;
    p.auth = headers['Authorization'] ?? '';
    this.posts.push(p);
    return this.serve();
  }
  async put(_url: string, _h: Record<string, string>, _b: string): Promise<ParentFetchResult> {
    return this.serve();
  }
  async patch(_url: string, _h: Record<string, string>, _b: string): Promise<ParentFetchResult> {
    return this.serve();
  }
  async del(_url: string, _h: Record<string, string>): Promise<ParentFetchResult> {
    return this.serve();
  }

  private serve(): ParentFetchResult {
    const next: ParentFetchResult | undefined = this.responses.shift();
    if (next === undefined) {
      const fb: ParentFetchResult = new ParentFetchResult();
      fb.status = 500;
      fb.body = '{}';
      return fb;
    }
    return next;
  }
}

function makeBoundCreds(): CloudCredentials {
  const cc: CloudCredentials = new CloudCredentials();
  cc.injectPreferences(new MemPrefs());
  const snap: CloudCredentialsSnapshot = new CloudCredentialsSnapshot();
  snap.deviceToken = 'jwt.body.sig';
  snap.bindingId = 'bind-aabbccdd';
  snap.familyId = 'fam-12345678';
  snap.childProfileId = 'child-deadbeef';
  snap.pairedAtMs = 1746068000000;
  snap.deviceIdSource = 'asset_store';
  cc.saveBinding(snap);
  return cc;
}

function makeRecorderWith(stats: WordStat[]): LearningRecorder {
  const r: LearningRecorder = new LearningRecorder();
  const snap: LearningSnapshot = new LearningSnapshot();
  snap.stats = stats;
  r.attachStore(makeStore(), snap);
  return r;
}

function ws(wordId: string, lastAnsweredMs: number, correct: number, wrong: number): WordStat {
  const s: WordStat = new WordStat();
  s.wordId = wordId;
  s.lastAnsweredMs = lastAnsweredMs;
  s.seenCount = correct + wrong;
  s.correctCount = correct;
  s.wrongCount = wrong;
  s.mastery = correct / Math.max(1, correct + wrong);
  return s;
}

export default function cloudSyncServiceTest(): void {
  describe('CloudSyncService.unbound', () => {
    it('returnsUnboundWhenNoCredentials', 0, async () => {
      const cc: CloudCredentials = new CloudCredentials();
      cc.injectPreferences(new MemPrefs());
      const recorder: LearningRecorder = makeRecorderWith([ws('w1', 1000, 1, 0)]);
      const adapter: CapturingAdapter = new CapturingAdapter();
      const svc: CloudSyncService = new CloudSyncService(recorder, cc, adapter, BASE);
      const out: CloudSyncResult = await svc.syncOnce();
      expect(out.status).assertEqual('unbound');
      expect(adapter.posts.length).assertEqual(0);
    });
  });

  describe('CloudSyncService.push', () => {
    it('pushesDirtyStatsAndUpdatesCheckpoint', 0, async () => {
      const recorder: LearningRecorder = makeRecorderWith([ws('w1', 5000, 1, 0)]);
      const cc: CloudCredentials = makeBoundCreds();
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(
        200,
        '{"accepted":["w1"],"rejected":[],"server_pulls":[],"server_now_ms":6000}',
      );
      const prefs: MemPrefs = new MemPrefs();
      const svc: CloudSyncService = new CloudSyncService(recorder, cc, adapter, BASE);
      svc.injectPreferences(prefs);
      const out: CloudSyncResult = await svc.syncOnce();
      expect(out.status).assertEqual('pushed');
      expect(out.pushed).assertEqual(1);
      expect(out.serverNowMs).assertEqual(6000);
      expect(adapter.posts.length).assertEqual(1);
      expect(adapter.posts[0].url.indexOf(SYNC_PATH)).assertLargerOrEqual(0);
      expect(adapter.posts[0].auth).assertEqual('Bearer jwt.body.sig');
      expect(adapter.posts[0].body.indexOf('"word_id":"w1"')).assertLargerOrEqual(0);
      expect(prefs.store.get('sync_checkpoint_ms') ?? '').assertEqual('6000');
    });

    it('skipsAlreadySyncedStatsAfterCheckpoint', 0, async () => {
      const recorder: LearningRecorder = makeRecorderWith([
        ws('w1', 1000, 1, 0),
        ws('w2', 9000, 2, 1),
      ]);
      const cc: CloudCredentials = makeBoundCreds();
      const adapter: CapturingAdapter = new CapturingAdapter();
      const prefs: MemPrefs = new MemPrefs();
      prefs.store.set('sync_checkpoint_ms', '5000');
      adapter.enqueue(
        200,
        '{"accepted":["w2"],"rejected":[],"server_pulls":[],"server_now_ms":9500}',
      );
      const svc: CloudSyncService = new CloudSyncService(recorder, cc, adapter, BASE);
      svc.injectPreferences(prefs);
      const out: CloudSyncResult = await svc.syncOnce();
      expect(out.pushed).assertEqual(1);
      expect(adapter.posts[0].body.indexOf('"word_id":"w2"')).assertLargerOrEqual(0);
      expect(adapter.posts[0].body.indexOf('"word_id":"w1"')).assertEqual(-1);
      expect(adapter.posts[0].body.indexOf('"synced_through_ms":5000')).assertLargerOrEqual(0);
    });
  });

  describe('CloudSyncService.pull', () => {
    it('appliesServerNewerPullsViaApplyCloudPull', 0, async () => {
      const recorder: LearningRecorder = makeRecorderWith([ws('w1', 1000, 1, 0)]);
      const cc: CloudCredentials = makeBoundCreds();
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(
        200,
        '{"accepted":[],"rejected":[],"server_pulls":[{"word_id":"w1","seen_count":5,"correct_count":4,"wrong_count":1,"last_answered_ms":9000,"last_correct_ms":9000,"next_review_ms":12000,"memory_state":"familiar","consecutive_correct":3,"consecutive_wrong":0,"mastery":0.75},{"word_id":"w2","seen_count":2,"correct_count":2,"wrong_count":0,"last_answered_ms":7000,"last_correct_ms":7000,"next_review_ms":10000,"memory_state":"new","consecutive_correct":2,"consecutive_wrong":0,"mastery":0.4}],"server_now_ms":9500}',
      );
      const prefs: MemPrefs = new MemPrefs();
      // Pretend we already shipped w1 above its checkpoint, so the only
      // delta in this run is the inbound pull.
      prefs.store.set('sync_checkpoint_ms', '2000');
      const svc: CloudSyncService = new CloudSyncService(recorder, cc, adapter, BASE);
      svc.injectPreferences(prefs);
      const out: CloudSyncResult = await svc.syncOnce();
      expect(out.status).assertEqual('pulled');
      expect(out.pulled).assertEqual(2);
      const stats: WordStat[] = recorder.allStats();
      const w1: WordStat | undefined = stats.find((s: WordStat): boolean => s.wordId === 'w1');
      const w2: WordStat | undefined = stats.find((s: WordStat): boolean => s.wordId === 'w2');
      expect(w1 !== undefined).assertEqual(true);
      expect((w1 as WordStat).correctCount).assertEqual(4);
      expect((w1 as WordStat).memoryState).assertEqual('familiar');
      expect(w2 !== undefined).assertEqual(true);
      expect((w2 as WordStat).correctCount).assertEqual(2);
    });

    it('ignoresServerOlderPulls', 0, async () => {
      const recorder: LearningRecorder = makeRecorderWith([ws('w1', 9000, 4, 1)]);
      const cc: CloudCredentials = makeBoundCreds();
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(
        200,
        '{"accepted":[],"rejected":[],"server_pulls":[{"word_id":"w1","seen_count":3,"correct_count":1,"wrong_count":2,"last_answered_ms":4000,"last_correct_ms":4000,"next_review_ms":5000,"memory_state":"new","consecutive_correct":1,"consecutive_wrong":0,"mastery":0.1}],"server_now_ms":9500}',
      );
      const prefs: MemPrefs = new MemPrefs();
      prefs.store.set('sync_checkpoint_ms', '9500');
      const svc: CloudSyncService = new CloudSyncService(recorder, cc, adapter, BASE);
      svc.injectPreferences(prefs);
      const out: CloudSyncResult = await svc.syncOnce();
      expect(out.pulled).assertEqual(0);
      const stats: WordStat[] = recorder.allStats();
      expect(stats[0].correctCount).assertEqual(4);
      expect(stats[0].lastAnsweredMs).assertEqual(9000);
    });
  });

  describe('CloudSyncService.combinedAndIdempotency', () => {
    it('reportsPushedAndPulledWhenBothHappen', 0, async () => {
      const recorder: LearningRecorder = makeRecorderWith([ws('w1', 9000, 2, 0)]);
      const cc: CloudCredentials = makeBoundCreds();
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(
        200,
        '{"accepted":["w1"],"rejected":[],"server_pulls":[{"word_id":"w2","seen_count":1,"correct_count":1,"wrong_count":0,"last_answered_ms":8000,"last_correct_ms":8000,"next_review_ms":12000,"memory_state":"new","consecutive_correct":1,"consecutive_wrong":0,"mastery":0.2}],"server_now_ms":9100}',
      );
      const svc: CloudSyncService = new CloudSyncService(recorder, cc, adapter, BASE);
      svc.injectPreferences(new MemPrefs());
      const out: CloudSyncResult = await svc.syncOnce();
      expect(out.status).assertEqual('pushed_and_pulled');
      expect(out.pushed).assertEqual(1);
      expect(out.pulled).assertEqual(1);
    });

    it('returnsNoChangesWhenNothingDirtyAndNoPulls', 0, async () => {
      const recorder: LearningRecorder = makeRecorderWith([ws('w1', 1000, 1, 0)]);
      const cc: CloudCredentials = makeBoundCreds();
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(200, '{"accepted":[],"rejected":[],"server_pulls":[],"server_now_ms":2000}');
      const prefs: MemPrefs = new MemPrefs();
      prefs.store.set('sync_checkpoint_ms', '5000');
      const svc: CloudSyncService = new CloudSyncService(recorder, cc, adapter, BASE);
      svc.injectPreferences(prefs);
      const out: CloudSyncResult = await svc.syncOnce();
      expect(out.status).assertEqual('no_changes');
      expect(out.pushed).assertEqual(0);
      expect(out.pulled).assertEqual(0);
    });
  });

  describe('CloudSyncService.errors', () => {
    it('returnsNetworkErrorWhenAdapterThrows', 0, async () => {
      const recorder: LearningRecorder = makeRecorderWith([ws('w1', 9000, 1, 0)]);
      const cc: CloudCredentials = makeBoundCreds();
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.failNetwork = true;
      const prefs: MemPrefs = new MemPrefs();
      prefs.store.set('sync_checkpoint_ms', '1000');
      const svc: CloudSyncService = new CloudSyncService(recorder, cc, adapter, BASE);
      svc.injectPreferences(prefs);
      const out: CloudSyncResult = await svc.syncOnce();
      expect(out.status).assertEqual('network_error');
      expect(prefs.store.get('sync_checkpoint_ms') ?? '').assertEqual('1000');
    });

    it('treatsNon2xxAsNetworkErrorWithoutCheckpointAdvance', 0, async () => {
      const recorder: LearningRecorder = makeRecorderWith([ws('w1', 9000, 1, 0)]);
      const cc: CloudCredentials = makeBoundCreds();
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(503, 'busy');
      const prefs: MemPrefs = new MemPrefs();
      prefs.store.set('sync_checkpoint_ms', '7000');
      const svc: CloudSyncService = new CloudSyncService(recorder, cc, adapter, BASE);
      svc.injectPreferences(prefs);
      const out: CloudSyncResult = await svc.syncOnce();
      expect(out.status).assertEqual('network_error');
      expect(prefs.store.get('sync_checkpoint_ms') ?? '').assertEqual('7000');
    });
  });

  describe('CloudSyncService.batching', () => {
    it('splitsLargeWorkloadsIntoMultiplePostsAndAggregates', 0, async () => {
      const stats: WordStat[] = [];
      for (let i = 0; i < 250; i++) {
        stats.push(ws(`w${i}`, 9000 + i, 1, 0));
      }
      const recorder: LearningRecorder = makeRecorderWith(stats);
      const cc: CloudCredentials = makeBoundCreds();
      const adapter: CapturingAdapter = new CapturingAdapter();
      adapter.enqueue(200, '{"accepted":[],"rejected":[],"server_pulls":[],"server_now_ms":9300}');
      adapter.enqueue(200, '{"accepted":[],"rejected":[],"server_pulls":[],"server_now_ms":9400}');
      const prefs: MemPrefs = new MemPrefs();
      const svc: CloudSyncService = new CloudSyncService(recorder, cc, adapter, BASE);
      svc.injectPreferences(prefs);
      const out: CloudSyncResult = await svc.syncOnce();
      expect(out.status).assertEqual('pushed');
      expect(adapter.posts.length).assertEqual(2);
      expect(prefs.store.get('sync_checkpoint_ms') ?? '').assertEqual('9400');
    });
  });
}
