import { describe, it, expect } from '@ohos/hypium';
import {
  LetterSlotView,
  buildLetterSlots,
  letterSlotRenderKey,
} from '../main/ets/services/LetterSlotKey';

function countMissing(slots: LetterSlotView[]): number {
  let total: number = 0;
  for (let i: number = 0; i < slots.length; i++) {
    if (slots[i].isMissing || slots[i].glyph === '_') {
      total++;
    }
  }
  return total;
}

export default function letterSlotKeyTest(): void {
  describe('LetterSlotKey', () => {
    it('changesWhenSlotRoleChangesForSameIndexAndGlyph', 0, () => {
      const filled: string = letterSlotRenderKey(3, 'e', false, false);
      const missing: string = letterSlotRenderKey(3, 'e', true, false);
      const pending: string = letterSlotRenderKey(3, 'e', false, true);

      expect(filled === missing).assertFalse();
      expect(filled === pending).assertFalse();
      expect(missing === pending).assertFalse();
    });

    it('usesTemplateIndicesWhenPhraseSpacesAreHidden', 0, () => {
      const slots: LetterSlotView[] = buildLetterSlots('do the housew__k', 13, 14);

      expect(slots.length).assertEqual(14);
      expect(countMissing(slots)).assertEqual(2);
      expect(slots[10].glyph).assertEqual('w');
      expect(slots[11].glyph).assertEqual('_');
      expect(slots[12].glyph).assertEqual('_');
      expect(slots[13].glyph).assertEqual('k');
    });

    it('doesNotAddSecondSingleBlankAfterHiddenPhraseSpaces', 0, () => {
      const slots: LetterSlotView[] = buildLetterSlots('do the house_ork', 12, -1);

      expect(slots.length).assertEqual(14);
      expect(countMissing(slots)).assertEqual(1);
      expect(slots[13].glyph).assertEqual('k');
      expect(slots[13].isMissing).assertFalse();
    });
  });
}
