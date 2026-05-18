/**
 * Pure reward helpers for V0.8.3 bonus monsters (✨ ×1.3 ceil when any bonus kill).
 */

export function computeFinalCoinAward(stars: number, bonusKillCount: number, won: boolean): number {
  if (!won || bonusKillCount <= 0 || stars <= 0) {
    return stars;
  }
  return Math.ceil(stars * 1.3);
}

export function computeBonusCoinDelta(stars: number, bonusKillCount: number, won: boolean): number {
  const finalCoins: number = computeFinalCoinAward(stars, bonusKillCount, won);
  return finalCoins - stars;
}
