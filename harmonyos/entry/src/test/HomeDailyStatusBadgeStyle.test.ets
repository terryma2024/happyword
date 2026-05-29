import { describe, it, expect } from '@ohos/hypium';
import {
  HOME_DAILY_STATUS_BADGE_BACKGROUND,
  HOME_DAILY_STATUS_BADGE_TEXT_COLOR,
  HOME_DAILY_STATUS_BADGE_FONT_SIZE_VP,
  HOME_DAILY_STATUS_BADGE_HORIZONTAL_PADDING_VP,
  HOME_DAILY_STATUS_BADGE_VERTICAL_PADDING_VP,
  HOME_DAILY_STATUS_BADGE_RADIUS_VP,
  HOME_ADVENTURE_CARD_STORY_MAX_LINES,
  HOME_ADVENTURE_CARD_STORY_LINE_HEIGHT_VP,
  HOME_ADVENTURE_CARD_STORY_RESERVED_HEIGHT_VP,
  HOME_REVIEW_COUNT_BADGE_BACKGROUND,
  HOME_REVIEW_COUNT_BADGE_FONT_SIZE_VP,
  HOME_REVIEW_COUNT_BADGE_HORIZONTAL_PADDING_VP,
  HOME_REVIEW_COUNT_BADGE_MIN_SIZE_VP,
  HOME_REVIEW_COUNT_BADGE_POSITION_X_VP,
  HOME_REVIEW_COUNT_BADGE_POSITION_Y_VP,
  HOME_REVIEW_COUNT_BADGE_RADIUS_VP,
} from '../main/ets/components/HomeDailyStatusBadgeStyle';

export default function homeDailyStatusBadgeStyleTest(): void {
  describe('HomeDailyStatusBadgeStyle', () => {
    it('usesWarmNeutralPillStyleShownInHarmonyReference', 0, () => {
      expect(HOME_DAILY_STATUS_BADGE_BACKGROUND).assertEqual('#F2DFC9');
      expect(HOME_DAILY_STATUS_BADGE_TEXT_COLOR).assertEqual('#8C877F');
      expect(HOME_DAILY_STATUS_BADGE_FONT_SIZE_VP).assertEqual(16);
      expect(HOME_DAILY_STATUS_BADGE_HORIZONTAL_PADDING_VP).assertEqual(22);
      expect(HOME_DAILY_STATUS_BADGE_VERTICAL_PADDING_VP).assertEqual(8);
      expect(HOME_DAILY_STATUS_BADGE_RADIUS_VP).assertEqual(22);
    });

    it('reservesTwoLinesForPackStoryCopyToMatchAndroid', 0, () => {
      expect(HOME_ADVENTURE_CARD_STORY_MAX_LINES).assertEqual(2);
      expect(HOME_ADVENTURE_CARD_STORY_LINE_HEIGHT_VP).assertEqual(22);
      expect(HOME_ADVENTURE_CARD_STORY_RESERVED_HEIGHT_VP).assertEqual(44);
    });

    it('usesIosToolbarOverlayStyleForReviewCountBadge', 0, () => {
      expect(HOME_REVIEW_COUNT_BADGE_BACKGROUND).assertEqual('#E63946');
      expect(HOME_REVIEW_COUNT_BADGE_MIN_SIZE_VP).assertEqual(20);
      expect(HOME_REVIEW_COUNT_BADGE_RADIUS_VP).assertEqual(10);
      expect(HOME_REVIEW_COUNT_BADGE_FONT_SIZE_VP).assertEqual(12);
      expect(HOME_REVIEW_COUNT_BADGE_HORIZONTAL_PADDING_VP).assertEqual(6);
      expect(HOME_REVIEW_COUNT_BADGE_POSITION_X_VP).assertEqual(34);
      expect(HOME_REVIEW_COUNT_BADGE_POSITION_Y_VP).assertEqual(0);
    });
  });
}
