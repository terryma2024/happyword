import { describe, it, expect } from '@ohos/hypium';
import {
  CONFIG_LABEL_WIDTH_VP,
  CONFIG_CONTROL_GAP_VP,
  CONFIG_FORM_ROW_WIDTH_VP,
  CONFIG_LABEL_TEXT_COLOR,
  CONFIG_QUESTION_TYPE_CONTROL_KIND,
  CONFIG_QUESTION_TYPE_OPTIONS_LEFT_ALIGNED,
  CONFIG_TIMER_OPTIONS_PER_ROW,
  questionTypeColumnRows,
  timerOptionRows,
} from '../main/ets/components/ConfigPageLayout';

export default function configPageLayoutTest(): void {
  describe('ConfigPageLayout', () => {
    it('usesFixedLabelWidthAndControlGap', 0, () => {
      expect(CONFIG_LABEL_WIDTH_VP).assertEqual(120);
      expect(CONFIG_CONTROL_GAP_VP).assertEqual(12);
      expect(CONFIG_FORM_ROW_WIDTH_VP).assertEqual(352);
    });

    it('usesExplicitDarkLabelTextForLightPages', 0, () => {
      expect(CONFIG_LABEL_TEXT_COLOR).assertEqual('#333333');
    });

    it('stacksQuestionTypesVertically', 0, () => {
      const rows: string[][] = questionTypeColumnRows(['choice', 'fill', 'medium', 'spell']);
      expect(rows.length).assertEqual(4);
      expect(rows[0].length).assertEqual(1);
      expect(rows[0][0]).assertEqual('choice');
      expect(rows[3][0]).assertEqual('spell');
    });

    it('alignsQuestionTypeOptionsToTheLeft', 0, () => {
      expect(CONFIG_QUESTION_TYPE_OPTIONS_LEFT_ALIGNED).assertTrue();
    });

    it('usesSwitchControlsForQuestionTypes', 0, () => {
      expect(CONFIG_QUESTION_TYPE_CONTROL_KIND).assertEqual('switch');
    });

    it('groupsTimerOptionsThreePerRow', 0, () => {
      expect(CONFIG_TIMER_OPTIONS_PER_ROW).assertEqual(3);
      const rows: number[][] = timerOptionRows([30, 180, 300, 600, 0]);
      expect(rows.length).assertEqual(2);
      expect(rows[0].length).assertEqual(3);
      expect(rows[0][0]).assertEqual(30);
      expect(rows[0][1]).assertEqual(180);
      expect(rows[0][2]).assertEqual(300);
      expect(rows[1].length).assertEqual(2);
      expect(rows[1][0]).assertEqual(600);
      expect(rows[1][1]).assertEqual(0);
    });
  });
}
