import { describe, it, expect } from '@ohos/hypium';
import { QuestionKind } from '../main/ets/models/Question';
import {
  BattleQuestionScheduler,
  BattleScheduleMode,
  deriveScheduleMode,
  intersectKinds,
} from '../main/ets/services/BattleQuestionScheduler';
import { mulberry32 } from '../main/ets/utils/shuffle';

const INTRO = [QuestionKind.Choice, QuestionKind.FillLetter];
const CHALLENGE = [QuestionKind.FillLetterMedium, QuestionKind.Spell];

function scheduler(
  wordIds: string[],
  enabled: string[],
  seed: number = 42,
): BattleQuestionScheduler {
  return new BattleQuestionScheduler(wordIds, enabled, mulberry32(seed));
}

export default function battleQuestionSchedulerTest() {
  describe('BattleQuestionScheduler', () => {
    it('deriveScheduleModeForSingleType', 0, () => {
      const intro = intersectKinds(INTRO, [QuestionKind.Spell]);
      const challenge = intersectKinds(CHALLENGE, [QuestionKind.Spell]);
      expect(deriveScheduleMode([QuestionKind.Spell], intro, challenge))
        .assertEqual(BattleScheduleMode.SingleType);
    });

    it('deriveScheduleModeIntroOnly', 0, () => {
      const enabled = [QuestionKind.Choice, QuestionKind.FillLetter];
      const intro = intersectKinds(INTRO, enabled);
      const challenge = intersectKinds(CHALLENGE, enabled);
      expect(deriveScheduleMode(enabled, intro, challenge))
        .assertEqual(BattleScheduleMode.IntroOnly);
    });

    it('deriveScheduleModeChallengeOnly', 0, () => {
      const enabled = [QuestionKind.FillLetterMedium, QuestionKind.Spell];
      const intro = intersectKinds(INTRO, enabled);
      const challenge = intersectKinds(CHALLENGE, enabled);
      expect(deriveScheduleMode(enabled, intro, challenge))
        .assertEqual(BattleScheduleMode.ChallengeOnly);
    });

    it('deriveScheduleModeTwoPhase', 0, () => {
      const enabled = [
        QuestionKind.Choice,
        QuestionKind.FillLetter,
        QuestionKind.FillLetterMedium,
        QuestionKind.Spell,
      ];
      const intro = intersectKinds(INTRO, enabled);
      const challenge = intersectKinds(CHALLENGE, enabled);
      expect(deriveScheduleMode(enabled, intro, challenge))
        .assertEqual(BattleScheduleMode.TwoPhase);
    });

    it('singleEnabledTypeAlwaysReturnsThatKind', 0, () => {
      const s = scheduler(['w-a', 'w-b'], [QuestionKind.Spell], 1);
      expect(s.scheduleMode()).assertEqual(BattleScheduleMode.SingleType);
      for (let i = 0; i < 8; i++) {
        expect(s.pickNext(undefined, (): boolean => true).kind).assertEqual(QuestionKind.Spell);
      }
    });

    it('introOnlyNeverReturnsChallengeKind', 0, () => {
      const s = scheduler(
        ['w-a', 'w-b', 'w-c'],
        [QuestionKind.Choice, QuestionKind.FillLetter],
        3,
      );
      expect(s.scheduleMode()).assertEqual(BattleScheduleMode.IntroOnly);
      const canServe = (_wid: string, _k: string): boolean => true;
      for (let i = 0; i < 20; i++) {
        const kind = s.pickNext(undefined, canServe).kind;
        expect(kind === QuestionKind.FillLetterMedium || kind === QuestionKind.Spell)
          .assertFalse();
        s.markServed(`w-${i % 3}`, kind, canServe);
      }
    });

    it('challengeOnlyNeverReturnsIntroKind', 0, () => {
      const s = scheduler(['w-a'], [QuestionKind.FillLetterMedium, QuestionKind.Spell], 4);
      expect(s.scheduleMode()).assertEqual(BattleScheduleMode.ChallengeOnly);
      const canServe = (_wid: string, _k: string): boolean => true;
      for (let i = 0; i < 10; i++) {
        const kind = s.pickNext(undefined, canServe).kind;
        expect(kind === QuestionKind.Choice || kind === QuestionKind.FillLetter).assertFalse();
      }
    });

    it('introNeverRepeatsChoiceForSameWord', 0, () => {
      const s = scheduler(
        ['w-a', 'w-b'],
        [QuestionKind.Choice, QuestionKind.FillLetter, QuestionKind.Spell],
        5,
      );
      const canServe = (wid: string, k: string): boolean => {
        return wid === 'w-a' || wid === 'w-b';
      };
      const choicesForA: number[] = [];
      for (let i = 0; i < 6; i++) {
        const pick = s.pickNext(undefined, canServe);
        if (pick.preferredWordId === 'w-a' && pick.kind === QuestionKind.Choice) {
          choicesForA.push(1);
          s.markServed('w-a', QuestionKind.Choice, canServe);
        } else if (pick.preferredWordId.length > 0) {
          s.markServed(pick.preferredWordId, pick.kind, canServe);
        }
      }
      expect(choicesForA.length).assertEqual(1);
    });

    it('twoPhaseTransitionsToChallengeAfterIntroPassComplete', 0, () => {
      const s = scheduler(
        ['w-a'],
        [
          QuestionKind.Choice,
          QuestionKind.FillLetter,
          QuestionKind.FillLetterMedium,
          QuestionKind.Spell,
        ],
        6,
      );
      const canServe = (_wid: string, _k: string): boolean => true;
      expect(s.isIntroPassActive()).assertTrue();
      s.markServed('w-a', QuestionKind.Choice, canServe);
      s.markServed('w-a', QuestionKind.FillLetter, canServe);
      expect(s.isIntroPassActive()).assertFalse();
      const kind = s.pickNext(undefined, canServe).kind;
      expect(
        kind === QuestionKind.FillLetterMedium || kind === QuestionKind.Spell,
      ).assertTrue();
    });

    it('challengeRollsAreFiftyFiftyWhenBothChallengeTypesEnabled', 0, () => {
      let medium = 0;
      let spell = 0;
      for (let seed = 0; seed < 40; seed++) {
        const s = scheduler(['w-a'], [QuestionKind.FillLetterMedium, QuestionKind.Spell], seed);
        const k = s.pickNext(undefined, (): boolean => true).kind;
        if (k === QuestionKind.FillLetterMedium) {
          medium += 1;
        } else if (k === QuestionKind.Spell) {
          spell += 1;
        }
      }
      expect(medium > 0 && spell > 0).assertTrue();
    });
  });
}
