import { describe, it, expect } from '@ohos/hypium';
import {
  validateChildNickname,
  CHILD_NICKNAME_MAX_CHARS,
  NicknameValidation,
} from '../main/ets/components/EditChildNicknameDialog';

export default function editChildNicknameDialogTest(): void {
  describe('validateChildNickname', () => {
    it('rejectsEmpty', 0, () => {
      const v: NicknameValidation = validateChildNickname('');
      expect(v.ok).assertEqual(false);
      expect(v.message.length).assertLargerOrEqual(1);
    });

    it('rejectsWhitespaceOnly', 0, () => {
      const v: NicknameValidation = validateChildNickname('   \t  ');
      expect(v.ok).assertEqual(false);
    });

    it('acceptsTrimmable', 0, () => {
      const v: NicknameValidation = validateChildNickname('  小明  ');
      expect(v.ok).assertEqual(true);
      expect(v.message).assertEqual('');
    });

    it('rejectsOverLength', 0, () => {
      const tooLong: string = 'x'.repeat(CHILD_NICKNAME_MAX_CHARS + 1);
      const v: NicknameValidation = validateChildNickname(tooLong);
      expect(v.ok).assertEqual(false);
    });

    it('acceptsExactlyMaxLength', 0, () => {
      const exact: string = 'a'.repeat(CHILD_NICKNAME_MAX_CHARS);
      const v: NicknameValidation = validateChildNickname(exact);
      expect(v.ok).assertEqual(true);
    });

    it('acceptsTypicalChineseName', 0, () => {
      const v: NicknameValidation = validateChildNickname('小明');
      expect(v.ok).assertEqual(true);
    });
  });
}
