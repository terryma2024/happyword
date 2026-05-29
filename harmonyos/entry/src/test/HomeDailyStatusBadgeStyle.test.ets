import { describe, it, expect } from '@ohos/hypium';
import {
  HOME_DAILY_STATUS_BADGE_BACKGROUND,
  HOME_DAILY_STATUS_BADGE_TEXT_COLOR,
  HOME_DAILY_STATUS_BADGE_FONT_SIZE_VP,
  HOME_DAILY_STATUS_BADGE_HORIZONTAL_PADDING_VP,
  HOME_DAILY_STATUS_BADGE_VERTICAL_PADDING_VP,
  HOME_DAILY_STATUS_BADGE_RADIUS_VP,
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
  });
}
