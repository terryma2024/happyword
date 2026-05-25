import { describe, expect, it } from '@ohos/hypium';
import {
  getMonsterDialogueByIndex,
  MONSTER_CATALOG,
  MonsterDialogue,
} from '../main/ets/data/MonsterCatalog';

function assertLine(value: string, label: string): void {
  expect(value.trim().length > 0).assertTrue();
  const missingMarkerA: string = 'TB' + 'D';
  const missingMarkerB: string = 'TO' + 'DO';
  expect(value.indexOf(missingMarkerA)).assertEqual(-1);
  expect(value.indexOf(missingMarkerB)).assertEqual(-1);
  if (label.indexOf('EN') >= 0) {
    expect(value.length <= 48).assertTrue();
  } else {
    expect(value.length <= 28).assertTrue();
  }
}

export default function monsterDialogueTest(): void {
  describe('MonsterDialogue V0.9.2', () => {
    it('allCatalogEntriesHaveBilingualIntroAndDefeatLines', 0, () => {
      expect(MONSTER_CATALOG.length).assertEqual(100);
      for (let i: number = 1; i <= MONSTER_CATALOG.length; i++) {
        const d: MonsterDialogue = getMonsterDialogueByIndex(i);
        assertLine(d.introLine.en, `intro EN ${i}`);
        assertLine(d.introLine.zh, `intro ZH ${i}`);
        assertLine(d.defeatLine.en, `defeat EN ${i}`);
        assertLine(d.defeatLine.zh, `defeat ZH ${i}`);
      }
    });

    it('resolverWrapsIndexAndReturnsSafeFallbackForInvalidInput', 0, () => {
      const first: MonsterDialogue = getMonsterDialogueByIndex(1);
      const wrapped: MonsterDialogue = getMonsterDialogueByIndex(101);
      const invalid: MonsterDialogue = getMonsterDialogueByIndex(0);
      expect(wrapped.introLine.en).assertEqual(first.introLine.en);
      expect(invalid.introLine.en.length > 0).assertTrue();
      expect(invalid.defeatLine.zh.length > 0).assertTrue();
    });
  });
}
