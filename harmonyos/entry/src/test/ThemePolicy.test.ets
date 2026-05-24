import { ConfigurationConstant } from '@kit.AbilityKit';
import { describe, it, expect } from '@ohos/hypium';
import { APP_COLOR_MODE } from '../main/ets/utils/theme';

export default function themePolicyTest(): void {
  describe('ThemePolicy', () => {
    it('forcesLightModeSoSystemNightModeDoesNotInvertText', 0, () => {
      expect(APP_COLOR_MODE).assertEqual(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    });
  });
}
