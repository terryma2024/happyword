import { describe, it, expect } from '@ohos/hypium';
import {
  validateChildNickname,
  CHILD_NICKNAME_MAX_CHARS,
  NicknameValidation,
  buildChildAvatarEmojiChoices,
  CHILD_AVATAR_EMOJI_BACKUP_POOL,
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

  describe('buildChildAvatarEmojiChoices', () => {
    it('returnsTenUniqueWithCurrentFirst', 0, () => {
      const choices: string[] = buildChildAvatarEmojiChoices('🐻');
      expect(choices.length).assertEqual(10);
      expect(choices[0]).assertEqual('🐻');
      const seen: Record<string, boolean> = {};
      for (let i = 0; i < choices.length; i++) {
        const e: string = choices[i];
        expect(seen[e] === true).assertEqual(false);
        seen[e] = true;
      }
    });

    it('usesFallbackWhenInitialEmpty', 0, () => {
      const choices: string[] = buildChildAvatarEmojiChoices('');
      expect(choices.length).assertEqual(10);
      expect(choices[0]).assertEqual('🦄');
    });

    it('backupPoolLargeEnoughForDistinctFill', 0, () => {
      expect(CHILD_AVATAR_EMOJI_BACKUP_POOL.length).assertLargerOrEqual(9);
    });
  });
}
