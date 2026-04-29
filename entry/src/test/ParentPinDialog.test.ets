import { describe, it, expect } from '@ohos/hypium';
import {
  PIN_LENGTH,
  validatePin,
  pushDigit,
  popDigit,
} from '../main/ets/components/ParentPinDialog';

export default function parentPinDialogTest() {
  describe('ParentPinDialog helpers', () => {
    it('pinLengthIsSix', 0, () => {
      expect(PIN_LENGTH).assertEqual(6);
    });

    it('validatePinReturnsTrueWhenInputMatchesExpectedAndLengthIsSix', 0, () => {
      expect(validatePin('123456', '123456')).assertTrue();
    });

    it('validatePinReturnsFalseWhenInputDiffers', 0, () => {
      expect(validatePin('123456', '654321')).assertFalse();
    });

    it('validatePinReturnsFalseWhenInputIsNotSixDigits', 0, () => {
      expect(validatePin('12345', '12345')).assertFalse();
      expect(validatePin('1234567', '1234567')).assertFalse();
      expect(validatePin('', '')).assertFalse();
    });

    it('validatePinReturnsFalseWhenExpectedIsEmpty', 0, () => {
      // Defensive: when parent has not configured a PIN, the gate
      // should never accept any input — even an empty buffer.
      expect(validatePin('123456', '')).assertFalse();
    });

    it('validatePinRejectsNonDigitInput', 0, () => {
      expect(validatePin('12345a', '12345a')).assertFalse();
      expect(validatePin('1234.6', '1234.6')).assertFalse();
    });

    it('pushDigitAppendsWhenBufferUnderCap', 0, () => {
      expect(pushDigit('', '1')).assertEqual('1');
      expect(pushDigit('123', '4')).assertEqual('1234');
      expect(pushDigit('12345', '6')).assertEqual('123456');
    });

    it('pushDigitNoopsWhenBufferAtCap', 0, () => {
      expect(pushDigit('123456', '7')).assertEqual('123456');
    });

    it('pushDigitNoopsOnNonDigitInput', 0, () => {
      expect(pushDigit('12', 'a')).assertEqual('12');
      expect(pushDigit('12', '')).assertEqual('12');
      expect(pushDigit('12', '12')).assertEqual('12');
    });

    it('popDigitDropsLastCharacter', 0, () => {
      expect(popDigit('123456')).assertEqual('12345');
      expect(popDigit('1')).assertEqual('');
    });

    it('popDigitNoopsOnEmpty', 0, () => {
      expect(popDigit('')).assertEqual('');
    });
  });
}
