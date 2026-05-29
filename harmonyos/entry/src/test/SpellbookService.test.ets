import { describe, it, expect } from '@ohos/hypium';
import { Pack } from '../main/ets/models/Pack';
import { WordEntry } from '../main/ets/models/WordEntry';
import { WordStat } from '../main/ets/services/WrongAnswerStore';
import {
  SpellbookCardState,
  SpellbookCard,
  SpellbookPackProgress,
  SPELLBOOK_REWARD_COINS,
  buildSpellbookCards,
  isSpellbookPackComplete,
  spellbookProgressForPack,
  spellbookRewardTxnId,
  spellbookStateForWord,
} from '../main/ets/services/SpellbookService';

function word(id: string): WordEntry {
  const w: WordEntry = new WordEntry();
  w.id = id;
  w.word = id;
  w.meaningZh = `${id}中文`;
  w.category = 'test';
  w.difficulty = 1;
  return w;
}

function stat(id: string, seen: number, memoryState: string): WordStat {
  const s: WordStat = new WordStat();
  s.wordId = id;
  s.seenCount = seen;
  s.memoryState = memoryState;
  return s;
}

function packWith(ids: string[]): Pack {
  const p: Pack = new Pack();
  p.id = 'pack-a';
  p.name = 'Pack A';
  const words: WordEntry[] = [];
  for (let i = 0; i < ids.length; i++) {
    words.push(word(ids[i]));
  }
  p.words = words;
  return p;
}

export default function spellbookServiceTest(): void {
  describe('SpellbookService', () => {
    it('classifies missing stats as locked', 0, () => {
      const state: SpellbookCardState = spellbookStateForWord('apple', []);
      expect(state).assertEqual(SpellbookCardState.Locked);
    });

    it('classifies seen non-mastered stats as seen', 0, () => {
      const state: SpellbookCardState = spellbookStateForWord('apple', [
        stat('apple', 2, 'learning'),
      ]);
      expect(state).assertEqual(SpellbookCardState.Seen);
    });

    it('classifies mastered memory state as mastered', 0, () => {
      const state: SpellbookCardState = spellbookStateForWord('apple', [
        stat('apple', 5, 'mastered'),
      ]);
      expect(state).assertEqual(SpellbookCardState.Mastered);
    });

    it('builds cards with pack-aware ids and states', 0, () => {
      const cards: SpellbookCard[] = buildSpellbookCards(packWith(['apple', 'pear']), [
        stat('pear', 1, 'learning'),
      ]);
      expect(cards.length).assertEqual(2);
      expect(cards[0].packId).assertEqual('pack-a');
      expect(cards[0].word.id).assertEqual('apple');
      expect(cards[0].state).assertEqual(SpellbookCardState.Locked);
      expect(cards[1].state).assertEqual(SpellbookCardState.Seen);
    });

    it('requires every pack word to be mastered for completion', 0, () => {
      const p: Pack = packWith(['apple', 'pear']);
      expect(isSpellbookPackComplete(p, [
        stat('apple', 5, 'mastered'),
        stat('pear', 2, 'learning'),
      ])).assertFalse();
      expect(isSpellbookPackComplete(p, [
        stat('apple', 5, 'mastered'),
        stat('pear', 5, 'mastered'),
      ])).assertTrue();
      expect(isSpellbookPackComplete(packWith([]), [])).assertFalse();
    });

    it('counts total seen mastered and completion in progress', 0, () => {
      const progress: SpellbookPackProgress = spellbookProgressForPack(packWith(['apple', 'pear', 'plum']), [
        stat('apple', 5, 'mastered'),
        stat('pear', 1, 'learning'),
      ]);
      expect(progress.packId).assertEqual('pack-a');
      expect(progress.total).assertEqual(3);
      expect(progress.seen).assertEqual(2);
      expect(progress.mastered).assertEqual(1);
      expect(progress.complete).assertFalse();
    });

    it('defines reward amount and stable transaction id', 0, () => {
      expect(SPELLBOOK_REWARD_COINS).assertEqual(50);
      expect(spellbookRewardTxnId('pack-a')).assertEqual('spellbook-pack-complete:pack-a');
    });
  });
}
