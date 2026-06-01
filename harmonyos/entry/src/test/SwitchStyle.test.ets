import { describe, it, expect } from '@ohos/hypium';
import {
  APP_SWITCH_HEIGHT_VP,
  APP_SWITCH_POINT_COLOR,
  APP_SWITCH_SELECTED_COLOR,
  APP_SWITCH_WIDTH_VP,
} from '../main/ets/components/SwitchStyle';

export default function switchStyleTest(): void {
  describe('SwitchStyle', () => {
    it('matchesPackManagerSwitchStyle', 0, () => {
      expect(APP_SWITCH_SELECTED_COLOR).assertEqual('#FFB400');
      expect(APP_SWITCH_POINT_COLOR).assertEqual('#FFFFFF');
      expect(APP_SWITCH_WIDTH_VP).assertEqual(48);
      expect(APP_SWITCH_HEIGHT_VP).assertEqual(28);
    });
  });
}
