/**
 * Stateful triple-tap detector. UI-agnostic so it can be unit-tested
 * with a fake clock (`onTap(fakeNowMs)`).
 *
 * Lifecycle:
 *  - First tap (or any tap with `now - lastTapMs > windowMs`): reset count to 1.
 *  - Subsequent taps inside the window: increment.
 *  - On the 3rd tap: return true and zero the counter so a 4th tap
 *    does not re-fire.
 */
export class VersionTripleTap {
  private count: number = 0;
  private lastTapMs: number = 0;
  private readonly windowMs: number;

  constructor(windowMs: number = 1000) {
    this.windowMs = windowMs;
  }

  /** Returns true exactly when this tap completes a triple-tap. */
  onTap(nowMs: number): boolean {
    if (nowMs - this.lastTapMs > this.windowMs) {
      this.count = 1;
    } else {
      this.count += 1;
    }
    this.lastTapMs = nowMs;
    if (this.count >= 3) {
      this.count = 0;
      this.lastTapMs = 0;
      return true;
    }
    return false;
  }

  /** For tests: peek the internal counter without advancing it. */
  pendingCount(): number {
    return this.count;
  }
}
