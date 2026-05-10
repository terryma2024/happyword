import { describe, it, expect } from '@ohos/hypium';
import {
  validateCustomTimerSeconds,
  CustomTimerValidation,
} from '../main/ets/components/CustomTimerDialog';
import {
  TIMER_CUSTOM_MIN,
  TIMER_CUSTOM_MAX,
} from '../main/ets/models/GameConfig';

/**
 * V0.6.7.7 — pure-validator tests for the 自定义 timer dialog. The
 * dialog itself is awkward to drive from a Hypium describe/it harness
 * (CustomDialogController is bound to a UIContext), so we extract
 * `validateCustomTimerSeconds` as the unit-testable surface and lock
 * down the contract here. The UI test suite covers the `TextInput →
 * 确定 → ConfigPage chip update` round-trip end-to-end.
 */
export default function customTimerDialogTest(): void {
  describe('validateCustomTimerSeconds', () => {
    it('rejectsEmpty', 0, () => {
      const v: CustomTimerValidation = validateCustomTimerSeconds('');
      expect(v.ok).assertEqual(false);
      expect(v.seconds).assertEqual(0);
      expect(v.message.length).assertLargerOrEqual(1);
    });

    it('rejectsWhitespaceOnly', 0, () => {
      const v: CustomTimerValidation = validateCustomTimerSeconds('   \t  ');
      expect(v.ok).assertEqual(false);
    });

    it('rejectsNonDigit', 0, () => {
      const v: CustomTimerValidation = validateCustomTimerSeconds('3a');
      expect(v.ok).assertEqual(false);
      expect(v.message.length).assertLargerOrEqual(1);
    });

    it('rejectsNegative', 0, () => {
      // Leading "-" fails the digit-only regex before the bounds
      // check, surfacing the "正整数" hint instead of the
      // "最少 N 秒" hint — both are valid signals to the parent that
      // the input is not acceptable.
      const v: CustomTimerValidation = validateCustomTimerSeconds('-5');
      expect(v.ok).assertEqual(false);
    });

    it('rejectsFloat', 0, () => {
      // `.` fails the digit-only regex; we want strictly positive
      // integers because BattleEngine ticks at 1Hz.
      const v: CustomTimerValidation = validateCustomTimerSeconds('3.5');
      expect(v.ok).assertEqual(false);
    });

    it('rejectsZero', 0, () => {
      // 0 parses as a non-negative integer but fails the lower-bound
      // check because BattleEngine.startingSeconds requires a positive
      // countdown (TIMER_CUSTOM_MIN === 1).
      const v: CustomTimerValidation = validateCustomTimerSeconds('0');
      expect(v.ok).assertEqual(false);
      expect(v.message.indexOf(`${TIMER_CUSTOM_MIN}`) >= 0).assertTrue();
    });

    it('rejectsAboveCeiling', 0, () => {
      const v: CustomTimerValidation =
        validateCustomTimerSeconds(`${TIMER_CUSTOM_MAX + 1}`);
      expect(v.ok).assertEqual(false);
      expect(v.message.indexOf(`${TIMER_CUSTOM_MAX}`) >= 0).assertTrue();
    });

    it('acceptsThreeSeconds', 0, () => {
      // The motivating fast-UI-test value. UI suites use 3s so a
      // battle timer expires inside a single test's wall-clock
      // budget without forcing the runner to wait the 30s minimum
      // chip preset.
      const v: CustomTimerValidation = validateCustomTimerSeconds('3');
      expect(v.ok).assertEqual(true);
      expect(v.seconds).assertEqual(3);
      expect(v.message).assertEqual('');
    });

    it('acceptsTrimmable', 0, () => {
      const v: CustomTimerValidation = validateCustomTimerSeconds('  42  ');
      expect(v.ok).assertEqual(true);
      expect(v.seconds).assertEqual(42);
    });

    it('acceptsMin', 0, () => {
      const v: CustomTimerValidation =
        validateCustomTimerSeconds(`${TIMER_CUSTOM_MIN}`);
      expect(v.ok).assertEqual(true);
      expect(v.seconds).assertEqual(TIMER_CUSTOM_MIN);
    });

    it('acceptsMax', 0, () => {
      const v: CustomTimerValidation =
        validateCustomTimerSeconds(`${TIMER_CUSTOM_MAX}`);
      expect(v.ok).assertEqual(true);
      expect(v.seconds).assertEqual(TIMER_CUSTOM_MAX);
    });
  });
}
