import { WordEntry } from '../models/WordEntry';
import { WordRepository } from './WordRepository';
import { LearningRecorder } from './LearningRecorder';
import { MemoryScheduler, MemoryState } from './MemoryScheduler';
import { WordStat } from './WrongAnswerStore';
import {
  AdventureRegion,
  TodaySessionPlan,
  WordSlot,
  WordSource,
} from '../models/AdventureRegion';
import { TodayAdventureBuilder, RandomFn, localDayKey } from './TodayAdventureBuilder';
import { mulberry32 } from '../utils/shuffle';

/**
 * One row in the daily plan view. Pure data; the page reads these
 * fields verbatim into ArkUI components, no extra mapping.
 */
export class TodayPlanRow {
  wordId: string = '';
  word: string = '';
  meaningZh: string = '';
  source: WordSource = WordSource.New;
  memoryState: MemoryState = MemoryState.New;
  /**
   * True when the word's most recent answer happened today AND was
   * correct (consecutiveCorrect > 0). Derived from V0.4.3 streak data
   * so we don't add a parallel "completed-today" persistence layer.
   */
  doneToday: boolean = false;
}

/**
 * Bucketed view of TodayPlanRow lists. The page renders three
 * sections in this order: Review (most urgent), Learning, New.
 */
export class TodayPlanView {
  regionId: string = '';
  regionDisplayName: string = '';
  dayKey: string = '';
  review: TodayPlanRow[] = [];
  learning: TodayPlanRow[] = [];
  freshNew: TodayPlanRow[] = [];

  /** Total row count across all three buckets. */
  total(): number {
    return this.review.length + this.learning.length + this.freshNew.length;
  }

  /** Words the kid already cleared today (for header progress). */
  doneCount(): number {
    let n: number = 0;
    n += countDone(this.review);
    n += countDone(this.learning);
    n += countDone(this.freshNew);
    return n;
  }
}

function countDone(rows: TodayPlanRow[]): number {
  let n: number = 0;
  for (let i = 0; i < rows.length; i++) {
    if (rows[i].doneToday) {
      n += 1;
    }
  }
  return n;
}

/**
 * V0.4.4: stable seed for the page-side builder. We hash region.id +
 * localDayKey so refreshing the page mid-day doesn't shuffle the
 * preview; the next local day rolls a fresh seed automatically. We
 * intentionally don't use this seed in `enterTodayAdventure` — the
 * battle path keeps Math.random() so a kid replaying the day still
 * sees fresh ordering. The two views are both legitimate "today's
 * plan" projections; the page is the authoritative read-only one.
 */
export function todayPlanSeed(regionId: string, dayKey: string): number {
  let h: number = 5381;
  const s: string = `${regionId}:${dayKey}`;
  for (let i: number = 0; i < s.length; i++) {
    h = ((h << 5) - h) + s.charCodeAt(i);
    h = h | 0;
  }
  return h < 0 ? -h : h;
}

/**
 * Compute local-midnight epoch ms for `nowMs`. Used to decide
 * whether a word's `lastAnsweredMs` falls inside today's window.
 */
export function localStartOfDay(nowMs: number): number {
  const d: Date = new Date(nowMs);
  const start: Date = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
  return start.getTime();
}

/**
 * Build a read-only view of today's plan for the dedicated plan page.
 * Pulls the plan from `TodayAdventureBuilder` (deterministically
 * seeded by region + day), classifies each word's memory state via
 * `MemoryScheduler`, and tags rows that the kid already finished
 * today.
 */
export class TodayPlanService {
  build(
    region: AdventureRegion,
    repo: WordRepository,
    recorder: LearningRecorder,
    nowMs: number
  ): TodayPlanView {
    const dayKey: string = localDayKey(nowMs);
    const seed: number = todayPlanSeed(region.id, dayKey);
    const rng: RandomFn = mulberry32(seed);
    const scheduler: MemoryScheduler = new MemoryScheduler();
    const builder: TodayAdventureBuilder = new TodayAdventureBuilder(rng, scheduler);
    const plan: TodaySessionPlan = builder.build(region, repo, recorder, nowMs, false);

    const stats: WordStat[] = recorder.statsForTest();
    const statByWordId: Map<string, WordStat> = new Map<string, WordStat>();
    for (let i = 0; i < stats.length; i++) {
      statByWordId.set(stats[i].wordId, stats[i]);
    }

    const startOfDay: number = localStartOfDay(nowMs);
    const view: TodayPlanView = new TodayPlanView();
    view.regionId = region.id;
    view.regionDisplayName = region.displayName;
    view.dayKey = dayKey;

    for (let i = 0; i < plan.wordPlan.length; i++) {
      const slot: WordSlot = plan.wordPlan[i];
      const entry: WordEntry | undefined = repo.findById(slot.wordId);
      if (entry === undefined) {
        continue;
      }
      const row: TodayPlanRow = new TodayPlanRow();
      row.wordId = slot.wordId;
      row.word = entry.word;
      row.meaningZh = entry.meaningZh;
      row.source = slot.source;

      const stat: WordStat | undefined = statByWordId.get(slot.wordId);
      if (stat !== undefined) {
        row.memoryState = scheduler.classify(stat, nowMs);
        row.doneToday = stat.lastAnsweredMs >= startOfDay && stat.consecutiveCorrect > 0;
      } else {
        row.memoryState = MemoryState.New;
        row.doneToday = false;
      }

      if (slot.source === WordSource.Review) {
        view.review.push(row);
      } else if (slot.source === WordSource.Learning) {
        view.learning.push(row);
      } else {
        view.freshNew.push(row);
      }
    }
    return view;
  }
}

/**
 * Display label for `MemoryState`. Lives next to the service so the
 * page doesn't need to import MemoryState directly.
 */
export function describeMemoryState(state: MemoryState): string {
  if (state === MemoryState.Review) return '待复习';
  if (state === MemoryState.Learning) return '学习中';
  if (state === MemoryState.Familiar) return '熟悉';
  if (state === MemoryState.Mastered) return '掌握';
  return '新词';
}

/** Display label for `WordSource`. */
export function describeWordSource(source: WordSource): string {
  if (source === WordSource.Review) return '复习';
  if (source === WordSource.Learning) return '学习';
  return '新词';
}
