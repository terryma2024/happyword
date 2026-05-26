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

    it('keepsIntroImmediateWhenDefeatBubbleIsDisabled', 0, () => {
      const s: BossDialogueSequencer = new BossDialogueSequencer();
      s.beginDefeatTransition();

      const decision: BossDialogueIntroDecision = s.requestIntro(3, 18, 2, []);
      expect(decision.kind).assertEqual(BossDialogueIntroDecisionKind.Show);
      expect(decision.monsterIndex).assertEqual(3);
      expect(decision.catalogIndex).assertEqual(18);

      const released: BossDialogueIntroDecision = s.releaseAfterDefeat();
      expect(released.kind).assertEqual(BossDialogueIntroDecisionKind.Skip);
    });

    it('skipsDuplicateMonsterOrCatalogIntro', 0, () => {
      const s: BossDialogueSequencer = new BossDialogueSequencer();

      expect(s.requestIntro(2, 18, 2, []).kind).assertEqual(BossDialogueIntroDecisionKind.Skip);
      expect(s.requestIntro(3, 18, 2, [18]).kind).assertEqual(BossDialogueIntroDecisionKind.Skip);
    });
  });
}
