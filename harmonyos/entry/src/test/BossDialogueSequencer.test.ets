import { describe, expect, it } from '@ohos/hypium';
import {
  BossDialogueIntroDecision,
  BossDialogueIntroDecisionKind,
  BossDialogueSequencer,
} from '../main/ets/services/BossDialogueSequencer';

export default function bossDialogueSequencerTest(): void {
  describe('BossDialogueSequencer', () => {
    it('showsIntroImmediatelyWhenNoDefeatBubbleIsActive', 0, () => {
      const s: BossDialogueSequencer = new BossDialogueSequencer();
      const decision: BossDialogueIntroDecision = s.requestIntro(2, 17, 1, []);

      expect(decision.kind).assertEqual(BossDialogueIntroDecisionKind.Show);
      expect(decision.monsterIndex).assertEqual(2);
      expect(decision.catalogIndex).assertEqual(17);
    });

    it('defersNewIntroUntilDefeatBubbleClears', 0, () => {
      const s: BossDialogueSequencer = new BossDialogueSequencer();
      s.beginDefeatTransition();

      const deferred: BossDialogueIntroDecision = s.requestIntro(3, 18, 2, []);
      expect(deferred.kind).assertEqual(BossDialogueIntroDecisionKind.Defer);

      const released: BossDialogueIntroDecision = s.releaseAfterDefeat();
      expect(released.kind).assertEqual(BossDialogueIntroDecisionKind.Show);
      expect(released.monsterIndex).assertEqual(3);
      expect(released.catalogIndex).assertEqual(18);
    });

    it('skipsDuplicateMonsterOrCatalogIntro', 0, () => {
      const s: BossDialogueSequencer = new BossDialogueSequencer();

      expect(s.requestIntro(2, 18, 2, []).kind).assertEqual(BossDialogueIntroDecisionKind.Skip);
      expect(s.requestIntro(3, 18, 2, [18]).kind).assertEqual(BossDialogueIntroDecisionKind.Skip);
    });
  });
}
