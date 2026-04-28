/**
 * Layout metrics for the FillLetter prompt row on BattlePage.
 *
 * The values used to be hardcoded constants tuned for short words
 * (≤8 letters), which made 11-letter prompts like "supermarket"
 * overflow QuestionArea (capped by `.layoutWeight(2)`) and clip the
 * trailing letters off-screen.
 *
 * `letterMetricsForLength` selects width / height / gap / font sizes
 * from length-banded buckets so short words still render at the
 * original 36×48 / 32 px size and longer words progressively tighten
 * until 13+-letter outliers fit a typical narrow viewport.
 *
 * Pulled out of BattlePage.ets so unit tests under entry/src/test
 * can lock the bucket boundaries without dragging the UI page (and
 * its @Entry / ArkUI dependencies) into the test compilation unit.
 */
export class LetterMetrics {
  width: number = 36;
  height: number = 48;
  gap: number = 8;
  fontFilled: number = 32;
  fontPlaceholder: number = 28;
}

export function letterMetricsForLength(n: number): LetterMetrics {
  const m: LetterMetrics = new LetterMetrics();
  if (n <= 6) {
    m.width = 36; m.height = 48; m.gap = 8;
    m.fontFilled = 32; m.fontPlaceholder = 28;
  } else if (n <= 9) {
    m.width = 30; m.height = 42; m.gap = 6;
    m.fontFilled = 26; m.fontPlaceholder = 24;
  } else if (n <= 12) {
    m.width = 24; m.height = 36; m.gap = 4;
    m.fontFilled = 22; m.fontPlaceholder = 20;
  } else {
    m.width = 20; m.height = 32; m.gap = 3;
    m.fontFilled = 18; m.fontPlaceholder = 16;
  }
  return m;
}
