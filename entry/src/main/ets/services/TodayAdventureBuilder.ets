import { WordEntry } from '../models/WordEntry';
import { WordRepository } from './WordRepository';
import { LearningRecorder } from './LearningRecorder';
import { MemoryScheduler, MemoryState } from './MemoryScheduler';
import { WordStat } from './WrongAnswerStore';
import {
  AdventureRegion,
  MonsterSlot,
  TodaySessionPlan,
  WordSlot,
  WordSource,
  MONSTER_PLAN_SLOT_COUNT,
  WORD_PLAN_MULTIPLIER,
} from '../models/AdventureRegion';
import { MonsterKind } from '../data/MonsterCatalog';

export type RandomFn = () => number;

/**
 * Pluggable RNG so tests get reproducible plans. Default is
 * Math.random; tests inject a seeded mulberry32.
 */
const defaultRng: RandomFn = (): number => Math.random();

/**
 * Day-key derived from a millisecond timestamp using LOCAL midnight.
 * Used by the recorder snapshot — same wallclock day produces the
 * same key.
 */
export function localDayKey(nowMs: number): string {
  const d: Date = new Date(nowMs);
  const y: number = d.getFullYear();
  const m: number = d.getMonth() + 1;
  const day: number = d.getDate();
  const mm: string = m < 10 ? '0' + m.toString() : m.toString();
  const dd: string = day < 10 ? '0' + day.toString() : day.toString();
  return `${y}-${mm}-${dd}`;
}

/**
 * TodayAdventureBuilder produces today's session plan when the
 * player taps the home-page adventure card. The builder is purely
 * deterministic: same inputs → same plan. No persistence happens
 * here; the plan is held in AppStorage by HomePage and consumed
 * once by BattlePage.
 *
 * Word ratio target: 50% review / 30% learning / 20% new.
 * `MONSTER_PLAN_SLOT_COUNT` (5) drives how many monsters fight,
 * each consuming up to `WORD_PLAN_MULTIPLIER` words per slot —
 * giving the wordPlan length headroom before PlanQuestionSource
 * starts cycling.
 */
export class TodayAdventureBuilder {
  private rng: RandomFn;
  private scheduler: MemoryScheduler;

  constructor(rng?: RandomFn, scheduler?: MemoryScheduler) {
    this.rng = rng !== undefined ? rng : defaultRng;
    this.scheduler = scheduler !== undefined ? scheduler : new MemoryScheduler();
  }

  build(
    region: AdventureRegion,
    repo: WordRepository,
    recorder: LearningRecorder,
    nowMs: number,
    isFirstToday: boolean
  ): TodaySessionPlan {
    const candidates: WordEntry[] = this.gatherCandidates(region, repo);
    const stats: WordStat[] = recorder.statsForTest();
    const buckets: BucketedIds = this.bucketByMemoryState(stats, candidates, nowMs);
    const targetCount: number = MONSTER_PLAN_SLOT_COUNT * WORD_PLAN_MULTIPLIER;
    const wordPlan: WordSlot[] = this.composePlan(buckets, candidates, targetCount);
    const bossWordIds: string[] = this.pickBossWords(buckets, candidates, 2);

    const plan: TodaySessionPlan = new TodaySessionPlan();
    plan.regionId = region.id;
    plan.monsterSlots = region.monsterPlan.slots.slice();
    plan.wordPlan = wordPlan;
    plan.bossWordIds = bossWordIds;
    plan.isFirstToday = isFirstToday;

    // V0.3.8: per-region boss rotation. Override slot 5 catalogIndex
    // with a deterministic pick from region.bossCandidates so each
    // local day can surface a different boss SVG without breaking
    // the existing today-plan determinism contract (same inputs ->
    // same plan, replays of the same day yield the same boss).
    this.applyBossRotation(plan, region, nowMs);

    return plan;
  }

  private applyBossRotation(
    plan: TodaySessionPlan,
    region: AdventureRegion,
    nowMs: number
  ): void {
    if (region.bossCandidates.length === 0) {
      return;
    }
    const slots: MonsterSlot[] = plan.monsterSlots;
    if (slots.length === 0) {
      return;
    }
    const lastIdx: number = slots.length - 1;
    const dayKey: string = localDayKey(nowMs);
    const bossIdx: number = this.pickBossCatalogIndexForDay(region, dayKey);
    const oldSlot: MonsterSlot = slots[lastIdx];
    const newSlot: MonsterSlot = new MonsterSlot();
    newSlot.kind = oldSlot.kind;
    newSlot.catalogIndex = bossIdx;
    slots[lastIdx] = newSlot;
  }

  private pickBossCatalogIndexForDay(region: AdventureRegion, dayKey: string): number {
    const seedStr: string = `${region.id}:${dayKey}`;
    const hash: number = this.hashSeed(seedStr);
    const idx: number = hash % region.bossCandidates.length;
    return region.bossCandidates[idx];
  }

  /**
   * djb2 string hash truncated to a non-negative 32-bit integer. We
   * intentionally avoid this.rng so word-plan shuffling stays on its
   * own RNG path; boss rotation only depends on regionId + dayKey.
   */
  private hashSeed(s: string): number {
    let h: number = 5381;
    for (let i: number = 0; i < s.length; i++) {
      h = ((h << 5) - h) + s.charCodeAt(i);
      h = h | 0;
    }
    return h < 0 ? -h : h;
  }

  private gatherCandidates(region: AdventureRegion, repo: WordRepository): WordEntry[] {
    const out: WordEntry[] = [];
    const seen: Set<string> = new Set<string>();
    for (let c = 0; c < region.themeWordCategories.length; c++) {
      const list: WordEntry[] = repo.byCategory(region.themeWordCategories[c]);
      for (let i = 0; i < list.length; i++) {
        if (!seen.has(list[i].id)) {
          seen.add(list[i].id);
          out.push(list[i]);
        }
      }
    }
    if (out.length === 0) {
      // Theme miss — fall back to whole repo so we never produce an
      // empty plan that softlocks BattlePage.
      const all: WordEntry[] = repo.all();
      for (let i = 0; i < all.length; i++) {
        if (!seen.has(all[i].id)) {
          seen.add(all[i].id);
          out.push(all[i]);
        }
      }
    }
    return out;
  }

  private bucketByMemoryState(
    stats: WordStat[],
    candidates: WordEntry[],
    nowMs: number
  ): BucketedIds {
    const review: string[] = [];
    const learning: string[] = [];
    const seenIds: Set<string> = new Set<string>();
    const candidateIds: Set<string> = new Set<string>();
    for (let i = 0; i < candidates.length; i++) {
      candidateIds.add(candidates[i].id);
    }
    for (let i = 0; i < stats.length; i++) {
      const s: WordStat = stats[i];
      if (!candidateIds.has(s.wordId)) {
        continue;
      }
      seenIds.add(s.wordId);
      const state: MemoryState = this.scheduler.classify(s, nowMs);
      if (state === MemoryState.Review) {
        review.push(s.wordId);
      } else if (state === MemoryState.Learning) {
        learning.push(s.wordId);
      }
    }
    const fresh: string[] = [];
    for (let i = 0; i < candidates.length; i++) {
      if (!seenIds.has(candidates[i].id)) {
        fresh.push(candidates[i].id);
      }
    }
    const out: BucketedIds = new BucketedIds();
    out.review = review;
    out.learning = learning;
    out.fresh = fresh;
    return out;
  }

  private composePlan(
    buckets: BucketedIds,
    candidates: WordEntry[],
    target: number
  ): WordSlot[] {
    const reviewQuota: number = Math.round(target * 0.5);
    const learningQuota: number = Math.round(target * 0.3);
    const newQuota: number = target - reviewQuota - learningQuota;

    const taken: Set<string> = new Set<string>();
    const out: WordSlot[] = [];
    this.drawInto(out, buckets.review, reviewQuota, WordSource.Review, taken);
    this.drawInto(out, buckets.learning, learningQuota, WordSource.Learning, taken);
    this.drawInto(out, buckets.fresh, newQuota, WordSource.New, taken);

    if (out.length < target) {
      this.drawInto(out, buckets.review, target - out.length, WordSource.Review, taken);
    }
    if (out.length < target) {
      this.drawInto(out, buckets.learning, target - out.length, WordSource.Learning, taken);
    }
    if (out.length < target) {
      this.drawInto(out, buckets.fresh, target - out.length, WordSource.New, taken);
    }
    if (out.length < target) {
      const allIds: string[] = candidates.map((w: WordEntry): string => w.id);
      this.drawInto(out, allIds, target - out.length, WordSource.New, taken);
    }
    return out;
  }

  private drawInto(
    sink: WordSlot[],
    pool: string[],
    quota: number,
    source: WordSource,
    taken: Set<string>
  ): void {
    if (quota <= 0 || pool.length === 0) {
      return;
    }
    const shuffled: string[] = this.shuffle(pool);
    let added: number = 0;
    for (let i = 0; i < shuffled.length && added < quota; i++) {
      const id: string = shuffled[i];
      if (taken.has(id)) {
        continue;
      }
      const slot: WordSlot = new WordSlot();
      slot.wordId = id;
      slot.source = source;
      sink.push(slot);
      taken.add(id);
      added += 1;
    }
  }

  private pickBossWords(
    buckets: BucketedIds,
    candidates: WordEntry[],
    n: number
  ): string[] {
    const pool: string[] = [];
    for (let i = 0; i < buckets.review.length; i++) pool.push(buckets.review[i]);
    for (let i = 0; i < buckets.learning.length; i++) pool.push(buckets.learning[i]);
    if (pool.length < n) {
      for (let i = 0; i < buckets.fresh.length; i++) pool.push(buckets.fresh[i]);
    }
    if (pool.length < n) {
      for (let i = 0; i < candidates.length; i++) pool.push(candidates[i].id);
    }
    const shuffled: string[] = this.shuffle(pool);
    const out: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < shuffled.length && out.length < n; i++) {
      if (!seen.has(shuffled[i])) {
        out.push(shuffled[i]);
        seen.add(shuffled[i]);
      }
    }
    return out;
  }

  private shuffle(arr: string[]): string[] {
    const out: string[] = arr.slice();
    for (let i = out.length - 1; i > 0; i--) {
      const j: number = Math.floor(this.rng() * (i + 1));
      const tmp: string = out[i];
      out[i] = out[j];
      out[j] = tmp;
    }
    return out;
  }
}

class BucketedIds {
  review: string[] = [];
  learning: string[] = [];
  fresh: string[] = [];
}

/**
 * Helper used by HomePage to surface the per-slot MonsterKind
 * label (e.g. "拼写挑战") on the adventure preview card without
 * pulling MonsterKind into UI files.
 */
export function describeMonsterKind(kind: MonsterKind): string {
  if (kind === MonsterKind.Spelling) return '拼写';
  if (kind === MonsterKind.Review) return '复习';
  if (kind === MonsterKind.Elite) return '精英';
  if (kind === MonsterKind.Boss) return '首领';
  return '常规';
}
