/**
 * Pure Fisher–Yates shuffle.
 *
 * Always returns a new array — the input is never mutated. The random source
 * is injectable so unit tests can pin the order without mocking globals.
 *
 * Type constraints: `T` can be any value type. ArkTS strict mode requires that
 * callers pass a concrete element type at the call site.
 */
export type RandomFn = () => number;

export function shuffle<T>(input: T[], rng?: RandomFn): T[] {
  const out: T[] = input.slice();
  const rand: RandomFn = rng ?? Math.random;
  for (let i = out.length - 1; i > 0; i--) {
    const r: number = rand();
    const j: number = Math.floor(r * (i + 1));
    const safeJ: number = j < 0 ? 0 : (j > i ? i : j);
    const tmp: T = out[i];
    out[i] = out[safeJ];
    out[safeJ] = tmp;
  }
  return out;
}

/**
 * Deterministic RNG helper for tests: mulberry32. Given the same seed, produces
 * the same sequence of floats in [0, 1). Not cryptographically strong — only
 * for reproducible game-state tests.
 */
export function mulberry32(seed: number): RandomFn {
  let state: number = seed >>> 0;
  return (): number => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t: number = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
