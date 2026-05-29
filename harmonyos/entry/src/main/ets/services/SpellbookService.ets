import { Pack } from '../models/Pack';
import { WordEntry } from '../models/WordEntry';
import { WordStat } from './WrongAnswerStore';
import { MemoryState } from './MemoryScheduler';

export enum SpellbookCardState {
  Locked = 'locked',
  Seen = 'seen',
  Mastered = 'mastered',
}

export class SpellbookCard {
  packId: string = '';
  word: WordEntry = new WordEntry();
  state: SpellbookCardState = SpellbookCardState.Locked;
}

export class SpellbookPackProgress {
  packId: string = '';
  total: number = 0;
  seen: number = 0;
  mastered: number = 0;
  complete: boolean = false;
}

export const SPELLBOOK_REWARD_COINS: number = 50;
const SPELLBOOK_REWARD_TXN_PREFIX: string = 'spellbook-pack-complete:';

export function spellbookRewardTxnId(packId: string): string {
  return `${SPELLBOOK_REWARD_TXN_PREFIX}${packId}`;
}

export function spellbookStateForWord(wordId: string, stats: WordStat[]): SpellbookCardState {
  const stat: WordStat | undefined = findStat(wordId, stats);
  if (stat === undefined || stat.seenCount <= 0) {
    return SpellbookCardState.Locked;
  }
  if (stat.memoryState === MemoryState.Mastered) {
    return SpellbookCardState.Mastered;
  }
  return SpellbookCardState.Seen;
}

export function buildSpellbookCards(pack: Pack, stats: WordStat[]): SpellbookCard[] {
  const out: SpellbookCard[] = [];
  for (let i = 0; i < pack.words.length; i++) {
    const card: SpellbookCard = new SpellbookCard();
    card.packId = pack.id;
    card.word = pack.words[i];
    card.state = spellbookStateForWord(pack.words[i].id, stats);
    out.push(card);
  }
  return out;
}

export function spellbookProgressForPack(pack: Pack, stats: WordStat[]): SpellbookPackProgress {
  const progress: SpellbookPackProgress = new SpellbookPackProgress();
  progress.packId = pack.id;
  progress.total = pack.words.length;
  for (let i = 0; i < pack.words.length; i++) {
    const state: SpellbookCardState = spellbookStateForWord(pack.words[i].id, stats);
    if (state === SpellbookCardState.Seen || state === SpellbookCardState.Mastered) {
      progress.seen += 1;
    }
    if (state === SpellbookCardState.Mastered) {
      progress.mastered += 1;
    }
  }
  progress.complete = progress.total > 0 && progress.mastered === progress.total;
  return progress;
}

export function isSpellbookPackComplete(pack: Pack, stats: WordStat[]): boolean {
  return spellbookProgressForPack(pack, stats).complete;
}

function findStat(wordId: string, stats: WordStat[]): WordStat | undefined {
  for (let i = 0; i < stats.length; i++) {
    if (stats[i].wordId === wordId) {
      return stats[i];
    }
  }
  return undefined;
}
