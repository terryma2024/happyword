import { QuestionKind } from '../models/Question';
import {
  DEFAULT_ENABLED_QUESTION_TYPES,
  sanitizeEnabledQuestionTypes,
} from './BattleQuestionTypePolicy';
import {
  MonsterLevel,
  monsterCatalogIndicesForLevel,
} from '../data/MonsterCatalog';
import { RandomFn } from '../utils/shuffle';

export type StageSupportFn = (wordId: string, kind: string) => boolean;

export class BattleStagePick {
  kind: string = '';
  wordId: string = '';
}

class BattleStage {
  kind: string = QuestionKind.Choice;
  wordIds: string[] = [];
  servedIds: string[] = [];
  cursor: number = 0;
}

export function monsterLevelForStageQuestionType(kind: string): MonsterLevel {
  if (kind === QuestionKind.FillLetter) {
    return MonsterLevel.Intermediate;
  }
  if (kind === QuestionKind.FillLetterMedium) {
    return MonsterLevel.Advanced;
  }
  if (kind === QuestionKind.Spell || kind === QuestionKind.SentenceCloze) {
    return MonsterLevel.Super;
  }
  return MonsterLevel.Beginner;
}

export class BattleStageScheduler {
  private readonly stages: BattleStage[] = [];
  private readonly rng: RandomFn;
  private activeStageIndex: number = 0;
  private lastMonsterIndex: number = 0;
  private readonly monsterStageByIndex: Map<number, number> = new Map<number, number>();
  private readonly monsterCatalogByIndex: Map<number, number> = new Map<number, number>();

  constructor(
    wordIds: string[],
    enabledTypes: string[],
    canServe: StageSupportFn,
    rng?: RandomFn,
  ) {
    this.rng = rng !== undefined ? rng : Math.random;
    const uniqueWordIds: string[] = this.uniqueNonEmpty(wordIds);
    const safeTypes: string[] = sanitizeEnabledQuestionTypes(enabledTypes);
    for (let t: number = 0; t < safeTypes.length; t++) {
      const kind: string = safeTypes[t];
      const stage: BattleStage = new BattleStage();
      stage.kind = kind;
      for (let w: number = 0; w < uniqueWordIds.length; w++) {
        const wordId: string = uniqueWordIds[w];
        if (canServe(wordId, kind)) {
          stage.wordIds.push(wordId);
        }
      }
      if (stage.wordIds.length > 0) {
        this.stages.push(stage);
      }
    }
  }

  pickNext(monsterIndex: number, lastWordId?: string): BattleStagePick {
    this.syncMonsterIndex(monsterIndex);
    const out: BattleStagePick = new BattleStagePick();
    const stage: BattleStage | undefined = this.currentStage();
    if (stage === undefined) {
      out.kind = DEFAULT_ENABLED_QUESTION_TYPES[0];
      out.wordId = '';
      return out;
    }
    out.kind = stage.kind;
    out.wordId = this.pickWordFromStage(stage, lastWordId);
    return out;
  }

  markServed(wordId: string, kind: string): void {
    const stage: BattleStage | undefined = this.currentStage();
    if (stage === undefined || stage.kind !== kind || wordId.length === 0) {
      return;
    }
    if (stage.servedIds.indexOf(wordId) < 0 && stage.wordIds.indexOf(wordId) >= 0) {
      stage.servedIds.push(wordId);
    }
  }

  catalogIndexForMonster(monsterIndex: number): number {
    const safeIndex: number = monsterIndex <= 0 ? 1 : monsterIndex;
    this.syncMonsterIndex(safeIndex);
    const existing: number | undefined = this.monsterCatalogByIndex.get(safeIndex);
    if (existing !== undefined && existing > 0) {
      return existing;
    }
    const stageIndex: number = this.monsterStageByIndex.get(safeIndex) ?? this.activeStageIndex;
    const stage: BattleStage | undefined = this.stages[stageIndex];
    const level: MonsterLevel = stage !== undefined
      ? monsterLevelForStageQuestionType(stage.kind)
      : MonsterLevel.Beginner;
    const pool: number[] = monsterCatalogIndicesForLevel(level);
    const rawIdx: number = Math.floor(this.rng() * pool.length);
    const idx: number = rawIdx < 0 ? 0 : (rawIdx >= pool.length ? pool.length - 1 : rawIdx);
    const catalogIndex: number = pool[idx];
    this.monsterCatalogByIndex.set(safeIndex, catalogIndex);
    return catalogIndex;
  }

  activeKindForTest(): string {
    const stage: BattleStage | undefined = this.currentStage();
    return stage !== undefined ? stage.kind : '';
  }

  private syncMonsterIndex(monsterIndex: number): void {
    const safeIndex: number = monsterIndex <= 0 ? 1 : monsterIndex;
    if (this.lastMonsterIndex === 0) {
      this.lastMonsterIndex = safeIndex;
    } else if (safeIndex !== this.lastMonsterIndex) {
      if (this.isCurrentStageCovered() && this.activeStageIndex < this.stages.length - 1) {
        this.activeStageIndex += 1;
      }
      this.lastMonsterIndex = safeIndex;
    }
    if (!this.monsterStageByIndex.has(safeIndex)) {
      this.monsterStageByIndex.set(safeIndex, this.activeStageIndex);
    }
  }

  private currentStage(): BattleStage | undefined {
    if (this.stages.length === 0) {
      return undefined;
    }
    const idx: number = this.activeStageIndex < this.stages.length
      ? this.activeStageIndex
      : this.stages.length - 1;
    return this.stages[idx];
  }

  private isCurrentStageCovered(): boolean {
    const stage: BattleStage | undefined = this.currentStage();
    if (stage === undefined) {
      return true;
    }
    return stage.servedIds.length >= stage.wordIds.length;
  }

  private pickWordFromStage(stage: BattleStage, lastWordId?: string): string {
    const source: string[] = this.isStageCovered(stage)
      ? stage.wordIds
      : this.unservedWordIds(stage);
    if (source.length === 0) {
      return stage.wordIds.length > 0 ? stage.wordIds[0] : '';
    }
    let attempts: number = 0;
    while (attempts < source.length) {
      const idx: number = stage.cursor % source.length;
      const wordId: string = source[idx];
      stage.cursor = (stage.cursor + 1) % source.length;
      attempts += 1;
      if (lastWordId !== undefined && wordId === lastWordId && source.length > 1) {
        continue;
      }
      return wordId;
    }
    return source[0];
  }

  private isStageCovered(stage: BattleStage): boolean {
    return stage.servedIds.length >= stage.wordIds.length;
  }

  private unservedWordIds(stage: BattleStage): string[] {
    const out: string[] = [];
    for (let i: number = 0; i < stage.wordIds.length; i++) {
      if (stage.servedIds.indexOf(stage.wordIds[i]) < 0) {
        out.push(stage.wordIds[i]);
      }
    }
    return out;
  }

  private uniqueNonEmpty(input: string[]): string[] {
    const out: string[] = [];
    for (let i: number = 0; i < input.length; i++) {
      const id: string = input[i];
      if (id.length > 0 && out.indexOf(id) < 0) {
        out.push(id);
      }
    }
    return out;
  }
}
