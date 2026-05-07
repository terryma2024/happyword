import { LearningRecorder } from './LearningRecorder';
import { CloudCredentials, CloudCredentialsSnapshot } from './CloudCredentials';
import { ParentFetchAdapter, ParentFetchResult } from './ParentApiClient';
import { StringPreferencesLike, WordStat } from './WrongAnswerStore';
import { CloudSyncLike, CloudSyncResult } from './CloudSyncTypes';

/**
 * V0.6.4 — push LearningRecorder deltas + apply server-newer pulls.
 *
 * Design notes:
 * - `syncOnce` never throws; transport failures leave the checkpoint
 *   unchanged so the next call retries.
 * - Pushes are batched to keep individual POST bodies small (≤200 items
 *   per request, matching plan client contract #6).
 * - Checkpoint = `synced_through_ms`, persisted in a tiny preferences
 *   slot so restarts pull only what changed since last success.
 */

const HEADER_AUTH: string = 'Authorization';
const HEADER_CONTENT_TYPE: string = 'Content-Type';
const HEADER_ACCEPT: string = 'Accept';
const CONTENT_JSON: string = 'application/json';
const PREFS_KEY_CHECKPOINT_MS: string = 'sync_checkpoint_ms';
const BATCH_SIZE: number = 200;

interface RawSyncOut {
  accepted?: string[];
  rejected?: string[];
  server_pulls?: RawPullItem[];
  server_now_ms?: number;
}

interface RawPullItem {
  word_id?: string;
  seen_count?: number;
  correct_count?: number;
  wrong_count?: number;
  last_answered_ms?: number;
  last_correct_ms?: number;
  next_review_ms?: number;
  memory_state?: string;
  consecutive_correct?: number;
  consecutive_wrong?: number;
  mastery?: number;
}

interface RawWordStatPushItem {
  word_id: string;
  seen_count: number;
  correct_count: number;
  wrong_count: number;
  last_answered_ms: number;
  last_correct_ms: number;
  next_review_ms: number;
  memory_state: string;
  consecutive_correct: number;
  consecutive_wrong: number;
  mastery: number;
}

interface RawSyncIn {
  items: RawWordStatPushItem[];
  synced_through_ms: number;
}

export class CloudSyncService implements CloudSyncLike {
  private readonly recorder: LearningRecorder;
  private readonly credentials: CloudCredentials;
  private readonly adapter: ParentFetchAdapter;
  private readonly baseUrl: string;
  private nowMs: () => number = (): number => Date.now();
  private prefs?: StringPreferencesLike;
  private inFlight: boolean = false;

  constructor(
    recorder: LearningRecorder,
    credentials: CloudCredentials,
    adapter: ParentFetchAdapter,
    baseUrl: string,
  ) {
    this.recorder = recorder;
    this.credentials = credentials;
    this.adapter = adapter;
    this.baseUrl = CloudSyncService.trimTrailingSlash(baseUrl);
  }

  injectPreferences(p: StringPreferencesLike): void {
    this.prefs = p;
  }

  injectClock(now: () => number): void {
    this.nowMs = now;
  }

  /**
   * Push deltas + apply server pulls. Returns a structured outcome but
   * never throws. Callers (BattlePage.aboutToDisappear, etc.) can
   * fire-and-forget.
   */
  async syncOnce(): Promise<CloudSyncResult> {
    const out: CloudSyncResult = new CloudSyncResult();
    if (this.inFlight) {
      out.status = 'no_changes';
      return out;
    }
    this.inFlight = true;
    try {
      return await this.runSync(out);
    } finally {
      this.inFlight = false;
    }
  }

  private async runSync(out: CloudSyncResult): Promise<CloudSyncResult> {
    const snap: CloudCredentialsSnapshot = await this.credentials.load();
    if (!snap.isBound() || snap.deviceToken.length === 0) {
      out.status = 'unbound';
      return out;
    }

    const checkpointMs: number = await this.readCheckpoint();
    const allStats: WordStat[] = this.recorder.allStats();
    const dirty: WordStat[] = allStats.filter(
      (s: WordStat): boolean => s.lastAnsweredMs > checkpointMs,
    );

    if (dirty.length === 0) {
      // Even with no pushes we still pull server-newer rows so a
      // freshly-bound second device sees its sibling's progress.
      const result: RawSyncOut | null = await this.postSync(
        snap.deviceToken, [], checkpointMs,
      );
      if (result === null) {
        out.status = 'network_error';
        return out;
      }
      const applied: number = this.applyPulls(result.server_pulls);
      out.pulled = applied;
      out.serverNowMs = result.server_now_ms !== undefined ? result.server_now_ms : 0;
      out.status = applied > 0 ? 'pulled' : 'no_changes';
      if (out.serverNowMs > 0) {
        await this.writeCheckpoint(out.serverNowMs);
      }
      return out;
    }

    let pushed: number = 0;
    let rejected: number = 0;
    let pulled: number = 0;
    let lastServerNowMs: number = 0;
    for (let i = 0; i < dirty.length; i += BATCH_SIZE) {
      const batch: WordStat[] = dirty.slice(i, i + BATCH_SIZE);
      const result: RawSyncOut | null = await this.postSync(
        snap.deviceToken, batch, checkpointMs,
      );
      if (result === null) {
        out.status = 'network_error';
        return out;
      }
      pushed += Array.isArray(result.accepted) ? result.accepted.length : 0;
      rejected += Array.isArray(result.rejected) ? result.rejected.length : 0;
      pulled += this.applyPulls(result.server_pulls);
      if (typeof result.server_now_ms === 'number' && result.server_now_ms > 0) {
        lastServerNowMs = result.server_now_ms;
      }
    }
    out.pushed = pushed;
    out.pulled = pulled;
    out.rejected = rejected;
    out.serverNowMs = lastServerNowMs;
    if (lastServerNowMs > 0) {
      await this.writeCheckpoint(lastServerNowMs);
    }
    out.status = pulled > 0 ? 'pushed_and_pulled' : 'pushed';
    return out;
  }

  private async postSync(
    token: string,
    items: WordStat[],
    syncedThroughMs: number,
  ): Promise<RawSyncOut | null> {
    const url: string = `${this.baseUrl}/api/v1/child/word-stats/sync`;
    const headers: Record<string, string> = {};
    headers[HEADER_CONTENT_TYPE] = CONTENT_JSON;
    headers[HEADER_ACCEPT] = CONTENT_JSON;
    headers[HEADER_AUTH] = `Bearer ${token}`;

    const wireItems: RawWordStatPushItem[] = items.map(toWireItem);
    const body: string = JSON.stringify({
      items: wireItems,
      synced_through_ms: syncedThroughMs,
    } as RawSyncIn);

    let res: ParentFetchResult;
    try {
      res = await this.adapter.post(url, headers, body);
    } catch (_err) {
      return null;
    }
    if (res.status !== 200 && res.status !== 201) {
      return null;
    }
    try {
      return JSON.parse(res.body) as RawSyncOut;
    } catch (_err) {
      return null;
    }
  }

  private applyPulls(rawPulls: RawPullItem[] | undefined): number {
    if (!Array.isArray(rawPulls) || rawPulls.length === 0) {
      return 0;
    }
    let applied: number = 0;
    for (let i = 0; i < rawPulls.length; i++) {
      const r: RawPullItem = rawPulls[i];
      if (typeof r.word_id !== 'string' || r.word_id.length === 0) {
        continue;
      }
      const stat: WordStat = new WordStat();
      stat.wordId = r.word_id;
      stat.seenCount = typeof r.seen_count === 'number' ? r.seen_count : 0;
      stat.correctCount = typeof r.correct_count === 'number' ? r.correct_count : 0;
      stat.wrongCount = typeof r.wrong_count === 'number' ? r.wrong_count : 0;
      stat.lastAnsweredMs = typeof r.last_answered_ms === 'number' ? r.last_answered_ms : 0;
      stat.lastCorrectMs = typeof r.last_correct_ms === 'number' ? r.last_correct_ms : 0;
      stat.nextReviewMs = typeof r.next_review_ms === 'number' ? r.next_review_ms : 0;
      stat.memoryState = typeof r.memory_state === 'string' ? r.memory_state : 'new';
      stat.consecutiveCorrect = typeof r.consecutive_correct === 'number' ? r.consecutive_correct : 0;
      stat.consecutiveWrong = typeof r.consecutive_wrong === 'number' ? r.consecutive_wrong : 0;
      stat.mastery = typeof r.mastery === 'number' ? r.mastery : 0;
      if (this.recorder.applyCloudPull(stat)) {
        applied += 1;
      }
    }
    return applied;
  }

  private async readCheckpoint(): Promise<number> {
    if (this.prefs === undefined) {
      return 0;
    }
    const raw: string = await this.prefs.getString(PREFS_KEY_CHECKPOINT_MS);
    if (raw.length === 0) {
      return 0;
    }
    const n: number = Number.parseInt(raw, 10);
    return Number.isNaN(n) ? 0 : n;
  }

  private async writeCheckpoint(ms: number): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(PREFS_KEY_CHECKPOINT_MS, ms.toString());
    await this.prefs.flush();
  }

  private static trimTrailingSlash(p: string): string {
    let end: number = p.length;
    while (end > 0 && p.charAt(end - 1) === '/') {
      end -= 1;
    }
    return p.substring(0, end);
  }
}

function toWireItem(s: WordStat): RawWordStatPushItem {
  return {
    word_id: s.wordId,
    seen_count: s.seenCount,
    correct_count: s.correctCount,
    wrong_count: s.wrongCount,
    last_answered_ms: s.lastAnsweredMs,
    last_correct_ms: s.lastCorrectMs,
    next_review_ms: s.nextReviewMs,
    memory_state: s.memoryState,
    consecutive_correct: s.consecutiveCorrect,
    consecutive_wrong: s.consecutiveWrong,
    mastery: s.mastery,
  };
}
