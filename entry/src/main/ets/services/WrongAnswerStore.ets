import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';

/**
 * Per-word learning stats. Keeps the full counter triple (seen /
 * correct / wrong) so downstream review heuristics can tune their
 * priority without needing to remember historic classifications —
 * e.g. a word answered right 3/5 times is still partially "known",
 * whereas a 0/5 deserves aggressive review surfacing.
 */
export class WordStat {
  wordId: string = '';
  seenCount: number = 0;
  correctCount: number = 0;
  wrongCount: number = 0;
  lastAnsweredMs: number = 0;
  // V0.3 forgetting-curve fields. Defaults preserve V0.2 semantics:
  // a fresh WordStat is treated as "new" and never due for review.
  lastCorrectMs: number = 0;
  nextReviewMs: number = 0;
  memoryState: string = 'new';
  // V0.4.3 refined-memory fields. `consecutiveCorrect` resets on a
  // wrong answer and counts the current correct streak; ditto for
  // `consecutiveWrong`. `mastery` is a confidence score in [0, 1]
  // updated each answer (+0.1 / -0.2, clamped). MemoryScheduler now
  // promotes by streak rather than cumulative count so a kid who
  // alternates right/wrong does not accidentally land in Familiar.
  consecutiveCorrect: number = 0;
  consecutiveWrong: number = 0;
  mastery: number = 0;
}

/**
 * Full on-disk snapshot of the learning log. The `version` field is
 * reserved for future schema migrations — bumping it lets us rewrite
 * the stored blob incrementally without throwing away user progress.
 */
export class LearningSnapshot {
  version: number = 1;
  stats: WordStat[] = [];
}

const PREFS_NAME: string = 'wordmagic_learning';
const PREFS_KEY: string = 'snapshot_v1';

/**
 * WrongAnswerStore is the persistence façade behind the V0.2
 * learning record. It wraps `@ohos.data.preferences` so the rest of
 * the app talks to a plain Promise-based API (`load` / `save`)
 * instead of juggling preference handles.
 *
 * Behaviour:
 * - Missing key or malformed JSON resolves to a fresh snapshot; the
 *   user never sees a startup crash from a corrupt on-disk blob.
 * - `save` is idempotent and fire-and-forget safe — callers that only
 *   care about the write landing eventually can drop the returned
 *   Promise.
 *
 * Test seam: `injectPreferences` swaps in a synchronous in-memory
 * stand-in so unit tests can assert round-trip behaviour without
 * touching the real preferences store.
 */
/**
 * Narrow string-only facade over `@ohos.data.preferences`. Keeps the
 * unit-testable seam simple — tests can supply a plain Map-backed
 * stand-in without referencing the full preferences.ValueType union.
 */
export interface StringPreferencesLike {
  getString(key: string): Promise<string>;
  putString(key: string, value: string): Promise<void>;
  flush(): Promise<void>;
}

/**
 * Concrete adapter around the real `preferences.Preferences` handle.
 * Broken out into a named class because ArkTS strict mode rejects the
 * untyped object literal that would otherwise be the shortest way to
 * implement `StringPreferencesLike`.
 */
class RealPreferencesAdapter implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;

  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }

  async getString(key: string): Promise<string> {
    const value: preferences.ValueType = await this.handle.get(key, '');
    return typeof value === 'string' ? value : '';
  }

  putString(key: string, value: string): Promise<void> {
    return this.handle.put(key, value);
  }

  flush(): Promise<void> {
    return this.handle.flush();
  }
}

export class WrongAnswerStore {
  private prefs?: StringPreferencesLike;
  private loaded: boolean = false;

  /** Overrides the preferences backend. Used only from unit tests. */
  injectPreferences(prefs: StringPreferencesLike): void {
    this.prefs = prefs;
    this.loaded = true;
  }

  /**
   * Open the preferences handle if not already opened. Safe to call
   * repeatedly. Errors are surfaced to the caller — the recorder
   * decides whether to keep retrying or silently degrade.
   */
  async open(ctx: common.UIAbilityContext): Promise<void> {
    if (this.loaded && this.prefs !== undefined) {
      return;
    }
    const real: preferences.Preferences =
      await preferences.getPreferences(ctx, PREFS_NAME);
    this.prefs = new RealPreferencesAdapter(real);
    this.loaded = true;
  }

  /**
   * Load the snapshot. Returns an empty snapshot when no prior data
   * exists or when the stored blob fails to parse.
   */
  async load(): Promise<LearningSnapshot> {
    if (this.prefs === undefined) {
      return new LearningSnapshot();
    }
    const raw: string = await this.prefs.getString(PREFS_KEY);
    if (raw.length === 0) {
      return new LearningSnapshot();
    }
    return parseSnapshot(raw);
  }

  /**
   * Persist the snapshot. Serialises to JSON and flushes the
   * underlying preferences store so the change survives an app
   * force-stop (per spec §15 V0.2-C acceptance).
   */
  async save(snapshot: LearningSnapshot): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    const payload: string = serializeSnapshot(snapshot);
    await this.prefs.putString(PREFS_KEY, payload);
    await this.prefs.flush();
  }
}

/**
 * Private shape we cast the JSON blob into. Matches LearningSnapshot
 * field-for-field but with every field optional so malformed data is
 * tolerated. Mirrors the `WordEntryJson` pattern used in
 * WordRepository.parseWordsJson.
 */
interface WordStatJson {
  wordId?: string;
  seenCount?: number;
  correctCount?: number;
  wrongCount?: number;
  lastAnsweredMs?: number;
  lastCorrectMs?: number;
  nextReviewMs?: number;
  memoryState?: string;
  consecutiveCorrect?: number;
  consecutiveWrong?: number;
  mastery?: number;
}

interface LearningSnapshotJson {
  version?: number;
  stats?: WordStatJson[];
}

/**
 * Parse the JSON blob into a LearningSnapshot. Exported so unit tests
 * can exercise the shape-tolerance path without touching preferences.
 * Returns an empty snapshot on any parse failure rather than throwing,
 * matching WordRepository.parseWordsJson's error posture.
 */
export function parseSnapshot(raw: string): LearningSnapshot {
  const snapshot: LearningSnapshot = new LearningSnapshot();
  if (raw.length === 0) {
    return snapshot;
  }
  let parsed: LearningSnapshotJson;
  try {
    parsed = JSON.parse(raw) as LearningSnapshotJson;
  } catch (err) {
    console.error(`WrongAnswerStore.parseSnapshot failed: ${JSON.stringify(err as BusinessError)}`);
    return snapshot;
  }
  if (parsed === null || parsed === undefined) {
    return snapshot;
  }
  if (typeof parsed.version === 'number') {
    snapshot.version = parsed.version;
  }
  const rawStats: WordStatJson[] | undefined = parsed.stats;
  if (rawStats !== undefined && rawStats !== null) {
    for (let i = 0; i < rawStats.length; i++) {
      const item: WordStatJson = rawStats[i];
      const stat: WordStat = new WordStat();
      stat.wordId = item.wordId ?? '';
      stat.seenCount = typeof item.seenCount === 'number' ? item.seenCount : 0;
      stat.correctCount = typeof item.correctCount === 'number' ? item.correctCount : 0;
      stat.wrongCount = typeof item.wrongCount === 'number' ? item.wrongCount : 0;
      stat.lastAnsweredMs = typeof item.lastAnsweredMs === 'number' ? item.lastAnsweredMs : 0;
      // V0.3 fields. When the stored blob is v1 (no fields present),
      // synthesize sensible defaults so MemoryScheduler.classify
      // treats the word as 'learning' if it was ever answered right
      // and 'new' otherwise. nextReviewMs left at 0 means "never
      // scheduled" — the scheduler treats that as not-due.
      stat.lastCorrectMs = typeof item.lastCorrectMs === 'number'
        ? item.lastCorrectMs
        : (stat.correctCount > 0 ? stat.lastAnsweredMs : 0);
      stat.nextReviewMs = typeof item.nextReviewMs === 'number' ? item.nextReviewMs : 0;
      stat.memoryState = typeof item.memoryState === 'string' && item.memoryState.length > 0
        ? item.memoryState
        : (stat.correctCount > 0 ? 'learning' : 'new');
      // V0.4.3: streaks default to 0 when migrating from a v2 blob.
      // Mastery seeds from correct/seen ratio so previously-learned
      // words don't snap back to "new" confidence after the upgrade.
      stat.consecutiveCorrect = typeof item.consecutiveCorrect === 'number'
        ? item.consecutiveCorrect
        : 0;
      stat.consecutiveWrong = typeof item.consecutiveWrong === 'number'
        ? item.consecutiveWrong
        : 0;
      if (typeof item.mastery === 'number') {
        stat.mastery = clampMastery(item.mastery);
      } else if (stat.seenCount > 0) {
        stat.mastery = clampMastery(stat.correctCount / stat.seenCount);
      } else {
        stat.mastery = 0;
      }
      if (stat.wordId.length > 0) {
        snapshot.stats.push(stat);
      }
    }
  }
  return snapshot;
}

/** Inverse of parseSnapshot. */
export function serializeSnapshot(snapshot: LearningSnapshot): string {
  return JSON.stringify(snapshot);
}

/**
 * Clamp a mastery score into [0, 1]. Exposed (vs inlined) so unit
 * tests can exercise the boundary handling without driving the
 * surrounding parser.
 */
export function clampMastery(value: number): number {
  if (value < 0 || Number.isNaN(value)) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}

/**
 * V0.4.3: per-answer mastery delta. A correct answer nudges the
 * confidence up by MASTERY_DELTA_CORRECT; a wrong answer pulls it
 * down by MASTERY_DELTA_WRONG. The asymmetry (wrong > correct) is
 * intentional — kids should re-earn mastery rather than bounce in
 * after a single right tap.
 */
export const MASTERY_DELTA_CORRECT: number = 0.1;
export const MASTERY_DELTA_WRONG: number = 0.2;
