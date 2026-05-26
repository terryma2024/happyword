import { describe, it, expect } from '@ohos/hypium';
import { QuestionKind } from '../main/ets/models/Question';
import {
  BattleStagePick,
  BattleStageScheduler,
  StageSupportFn,
} from '../main/ets/services/BattleStageScheduler';
import {
  MonsterLevel,
  monsterLevelForCatalogIndex,
} from '../main/ets/data/MonsterCatalog';
import { mulberry32 } from '../main/ets/utils/shuffle';

function supportFrom(map: Map<string, string[]>): StageSupportFn {
  return (wordId: string, kind: string): boolean => {
    const kinds: string[] | undefined = map.get(wordId);
    return kinds !== undefined && kinds.indexOf(kind) >= 0;
  };
}

function allSupport(wordIds: string[], kinds: string[]): StageSupportFn {
  const map: Map<string, string[]> = new Map<string, string[]>();
  for (let i: number = 0; i < wordIds.length; i++) {
    map.set(wordIds[i], kinds.slice());
  }
  return supportFrom(map);
}

function pickAndMark(
  scheduler: BattleStageScheduler,
  monsterIndex: number,
  lastWordId?: string,
): BattleStagePick {
  const pick: BattleStagePick = scheduler.pickNext(monsterIndex, lastWordId);
  scheduler.markServed(pick.wordId, pick.kind);
  return pick;
}

export default function battleStageSchedulerTest() {
  describe('BattleStageScheduler', () => {
    it('keepsSameStageWhenLowHpMonsterDiesBeforeWordsCovered', 0, () => {
      const scheduler: BattleStageScheduler = new BattleStageScheduler(
        ['w1', 'w2', 'w3', 'w4'],
        [QuestionKind.Choice, QuestionKind.FillLetter],
        allSupport(['w1', 'w2', 'w3', 'w4'], [QuestionKind.Choice, QuestionKind.FillLetter]),
        mulberry32(1),
      );

      const p1: BattleStagePick = pickAndMark(scheduler, 1);
      const p2: BattleStagePick = pickAndMark(scheduler, 1, p1.wordId);
      const p3: BattleStagePick = pickAndMark(scheduler, 2, p2.wordId);

      expect(p1.kind).assertEqual(QuestionKind.Choice);
      expect(p2.kind).assertEqual(QuestionKind.Choice);
      expect(p3.kind).assertEqual(QuestionKind.Choice);
      expect(scheduler.activeKindForTest()).assertEqual(QuestionKind.Choice);
      expect(monsterLevelForCatalogIndex(scheduler.catalogIndexForMonster(2)))
        .assertEqual(MonsterLevel.Beginner);
    });

    it('advancesQuestionStageImmediatelyWhileKeepingCurrentMonsterCatalog', 0, () => {
      const scheduler: BattleStageScheduler = new BattleStageScheduler(
        ['w1', 'w2'],
        [QuestionKind.Choice, QuestionKind.FillLetter],
        allSupport(['w1', 'w2'], [QuestionKind.Choice, QuestionKind.FillLetter]),
        mulberry32(2),
      );

      const p1: BattleStagePick = pickAndMark(scheduler, 1);
      const p2: BattleStagePick = pickAndMark(scheduler, 1, p1.wordId);
      const p3: BattleStagePick = pickAndMark(scheduler, 1, p2.wordId);
      const p4: BattleStagePick = pickAndMark(scheduler, 2, p3.wordId);

      expect(p1.kind).assertEqual(QuestionKind.Choice);
      expect(p2.kind).assertEqual(QuestionKind.Choice);
      expect(p3.kind).assertEqual(QuestionKind.FillLetter);
      expect(p4.kind).assertEqual(QuestionKind.FillLetter);
      expect(monsterLevelForCatalogIndex(scheduler.catalogIndexForMonster(1)))
        .assertEqual(MonsterLevel.Beginner);
      expect(monsterLevelForCatalogIndex(scheduler.catalogIndexForMonster(2)))
        .assertEqual(MonsterLevel.Intermediate);
    });

    it('newMonsterUsesCurrentStageAfterOldMonsterSpansMultipleStages', 0, () => {
      const scheduler: BattleStageScheduler = new BattleStageScheduler(
        ['w1', 'w2'],
        [QuestionKind.Choice, QuestionKind.FillLetter, QuestionKind.FillLetterMedium],
        allSupport(
          ['w1', 'w2'],
          [QuestionKind.Choice, QuestionKind.FillLetter, QuestionKind.FillLetterMedium],
        ),
        mulberry32(8),
      );

      const p1: BattleStagePick = pickAndMark(scheduler, 1);
      const p2: BattleStagePick = pickAndMark(scheduler, 1, p1.wordId);
      const p3: BattleStagePick = pickAndMark(scheduler, 1, p2.wordId);
      const p4: BattleStagePick = pickAndMark(scheduler, 1, p3.wordId);
      const p5: BattleStagePick = pickAndMark(scheduler, 1, p4.wordId);
      const p6: BattleStagePick = pickAndMark(scheduler, 2, p5.wordId);

      expect(p1.kind).assertEqual(QuestionKind.Choice);
      expect(p2.kind).assertEqual(QuestionKind.Choice);
      expect(p3.kind).assertEqual(QuestionKind.FillLetter);
      expect(p4.kind).assertEqual(QuestionKind.FillLetter);
      expect(p5.kind).assertEqual(QuestionKind.FillLetterMedium);
      expect(p6.kind).assertEqual(QuestionKind.FillLetterMedium);
      expect(monsterLevelForCatalogIndex(scheduler.catalogIndexForMonster(1)))
        .assertEqual(MonsterLevel.Beginner);
      expect(monsterLevelForCatalogIndex(scheduler.catalogIndexForMonster(2)))
        .assertEqual(MonsterLevel.Advanced);
    });

    it('usesOnlyEnabledTypesInDifficultyOrder', 0, () => {
      const scheduler: BattleStageScheduler = new BattleStageScheduler(
        ['w1', 'w2'],
        [QuestionKind.Spell, QuestionKind.FillLetter],
        allSupport(['w1', 'w2'], [QuestionKind.FillLetter, QuestionKind.Spell]),
        mulberry32(3),
      );

      pickAndMark(scheduler, 1);
      pickAndMark(scheduler, 1);
      const p3: BattleStagePick = pickAndMark(scheduler, 2);

      expect(p3.kind).assertEqual(QuestionKind.Spell);
      expect(monsterLevelForCatalogIndex(scheduler.catalogIndexForMonster(2)))
        .assertEqual(MonsterLevel.Super);
    });

    it('skipsUnsupportedWordsWithinAStage', 0, () => {
      const map: Map<string, string[]> = new Map<string, string[]>();
      map.set('w1', [QuestionKind.Choice]);
      map.set('w2', [QuestionKind.Choice, QuestionKind.Spell]);
      map.set('w3', [QuestionKind.Choice, QuestionKind.Spell]);
      const scheduler: BattleStageScheduler = new BattleStageScheduler(
        ['w1', 'w2', 'w3'],
        [QuestionKind.Spell],
        supportFrom(map),
        mulberry32(4),
      );

      const ids: Set<string> = new Set<string>();
      ids.add(pickAndMark(scheduler, 1).wordId);
      ids.add(pickAndMark(scheduler, 1).wordId);

      expect(ids.has('w1')).assertFalse();
      expect(ids.has('w2')).assertTrue();
      expect(ids.has('w3')).assertTrue();
    });

    it('skipsEmptyStagesAndDoesNotSpawnTheirMonsterLevel', 0, () => {
      const map: Map<string, string[]> = new Map<string, string[]>();
      map.set('w1', [QuestionKind.Choice]);
      map.set('w2', [QuestionKind.Choice]);
      const scheduler: BattleStageScheduler = new BattleStageScheduler(
        ['w1', 'w2'],
        [QuestionKind.FillLetter, QuestionKind.Spell, QuestionKind.Choice],
        supportFrom(map),
        mulberry32(5),
      );

      const p1: BattleStagePick = pickAndMark(scheduler, 1);

      expect(p1.kind).assertEqual(QuestionKind.Choice);
      expect(monsterLevelForCatalogIndex(scheduler.catalogIndexForMonster(1)))
        .assertEqual(MonsterLevel.Beginner);
    });

    it('sustainsLastStageAfterAllStagesCompleteUntilMonsterTotalEndsBattle', 0, () => {
      const scheduler: BattleStageScheduler = new BattleStageScheduler(
        ['w1', 'w2'],
        [QuestionKind.Choice, QuestionKind.FillLetter],
        allSupport(['w1', 'w2'], [QuestionKind.Choice, QuestionKind.FillLetter]),
        mulberry32(6),
      );

      pickAndMark(scheduler, 1);
      pickAndMark(scheduler, 1);
      pickAndMark(scheduler, 2);
      pickAndMark(scheduler, 2);
      const p5: BattleStagePick = pickAndMark(scheduler, 3);

      expect(p5.kind).assertEqual(QuestionKind.FillLetter);
      expect(monsterLevelForCatalogIndex(scheduler.catalogIndexForMonster(3)))
        .assertEqual(MonsterLevel.Intermediate);
    });

    it('mapsEveryQuestionTypeToStrictCatalogLevelPool', 0, () => {
      const wordIds: string[] = ['w1'];
      const kinds: string[] = [
        QuestionKind.Choice,
        QuestionKind.FillLetter,
        QuestionKind.FillLetterMedium,
        QuestionKind.Spell,
        QuestionKind.SentenceCloze,
      ];
      const scheduler: BattleStageScheduler = new BattleStageScheduler(
        wordIds,
        kinds,
        allSupport(wordIds, kinds),
        mulberry32(7),
      );

      const expected: MonsterLevel[] = [
        MonsterLevel.Beginner,
        MonsterLevel.Intermediate,
        MonsterLevel.Advanced,
        MonsterLevel.Super,
        MonsterLevel.Super,
      ];
      for (let i: number = 0; i < expected.length; i++) {
        const pick: BattleStagePick = pickAndMark(scheduler, i + 1);
        expect(pick.kind).assertEqual(kinds[i]);
        expect(monsterLevelForCatalogIndex(scheduler.catalogIndexForMonster(i + 1)))
          .assertEqual(expected[i]);
      }
    });
  });
}
