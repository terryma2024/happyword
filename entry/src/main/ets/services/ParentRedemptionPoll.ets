import { RedemptionDecision } from './CloudWishlistService';

/** Test seam: a thin interface CloudWishlistService implements so tests
 *  don't need to construct the real service (which depends on CloudCredentials,
 *  ParentFetchAdapter, baseUrl). */
export interface RedemptionPollSource {
  pollDecisions(): Promise<RedemptionDecision[]>;
}

/**
 * V0.6.6 — periodic poller that drives `CloudWishlistService.pollDecisions`
 * while the app is in the foreground. Owned by EntryAbility:
 *  - `start()` from `onForeground`
 *  - `stop()` from `onBackground` and `onDestroy`
 *
 * The poller never blocks the UI: each tick is a fire-and-forget promise
 * scheduled via setTimeout. If the previous tick is still in flight, the
 * next tick is skipped to avoid stacking.
 *
 * Listeners (typically WishlistPage when on screen) subscribe to receive
 * decisions. Unsubscribe must be called on page disposal or the listener
 * leaks across navigations.
 */

export type RedemptionDecisionListener = (decisions: RedemptionDecision[]) => void;

const DEFAULT_INTERVAL_MS: number = 60_000;
const MIN_INTERVAL_MS: number = 5_000;

export class ParentRedemptionPoll {
  private readonly service: RedemptionPollSource;
  private listeners: RedemptionDecisionListener[] = [];
  private intervalMs: number = DEFAULT_INTERVAL_MS;
  private timerId: number = -1;
  private inFlight: boolean = false;
  private active: boolean = false;
  private setTimeoutFn: (cb: () => void, ms: number) => number =
    (cb: () => void, ms: number): number => setTimeout(cb, ms) as number;
  private clearTimeoutFn: (id: number) => void =
    (id: number): void => clearTimeout(id);

  constructor(service: RedemptionPollSource) {
    this.service = service;
  }

  setIntervalMs(ms: number): void {
    if (ms < MIN_INTERVAL_MS) {
      this.intervalMs = MIN_INTERVAL_MS;
    } else {
      this.intervalMs = ms;
    }
  }

  /** Test seam: replace setTimeout/clearTimeout. */
  injectTimers(
    setTimeoutFn: (cb: () => void, ms: number) => number,
    clearTimeoutFn: (id: number) => void,
  ): void {
    this.setTimeoutFn = setTimeoutFn;
    this.clearTimeoutFn = clearTimeoutFn;
  }

  subscribe(listener: RedemptionDecisionListener): void {
    this.listeners.push(listener);
  }

  unsubscribe(listener: RedemptionDecisionListener): void {
    const next: RedemptionDecisionListener[] = [];
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] !== listener) {
        next.push(this.listeners[i]);
      }
    }
    this.listeners = next;
  }

  start(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    this.scheduleNext();
  }

  stop(): void {
    this.active = false;
    if (this.timerId >= 0) {
      this.clearTimeoutFn(this.timerId);
      this.timerId = -1;
    }
  }

  /** Run a single poll cycle synchronously (for tests). Returns the
   * decisions returned by the underlying service. */
  async tick(): Promise<RedemptionDecision[]> {
    if (this.inFlight) {
      return [];
    }
    this.inFlight = true;
    try {
      const decisions: RedemptionDecision[] = await this.service.pollDecisions();
      if (decisions.length > 0) {
        for (let i = 0; i < this.listeners.length; i++) {
          this.listeners[i](decisions);
        }
      }
      return decisions;
    } finally {
      this.inFlight = false;
    }
  }

  private scheduleNext(): void {
    if (!this.active) {
      return;
    }
    this.timerId = this.setTimeoutFn((): void => {
      this.timerId = -1;
      this.tick().then((): void => {
        this.scheduleNext();
      }).catch((): void => {
        this.scheduleNext();
      });
    }, this.intervalMs);
  }
}
