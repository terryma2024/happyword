import { MonsterLevel } from '../data/MonsterCatalog';

/**
 * Pure reward helpers for V0.8.6 monster-level coin scoring.
 */
export function coinValueForMonsterLevel(level: MonsterLevel): number {
  if (level === MonsterLevel.Intermediate) {
    return 2;
  }
  if (level === MonsterLevel.Advanced) {
    return 3;
  }
  if (level === MonsterLevel.Super) {
    return 4;
  }
  return 1;
}

export function computeMonsterLevelCoinAward(monsterLevelScore: number): number {
  if (monsterLevelScore <= 0) {
    return 0;
  }
  return Math.floor(monsterLevelScore);
}

export function computeRetiredBonusCoinDelta(
  _monsterLevelScore: number,
  _bonusKillCount: number,
  _won: boolean,
): number {
  return 0;
}
