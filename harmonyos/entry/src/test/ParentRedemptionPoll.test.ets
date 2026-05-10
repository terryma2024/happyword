import { describe, it, expect } from '@ohos/hypium';
import { ParentRedemptionPoll } from '../main/ets/services/ParentRedemptionPoll';
import {
  RedemptionDecision,
  RedemptionPollSource,
} from '../main/ets/services/CloudWishlistService';

class FakeSource implements RedemptionPollSource {
  decisionsQueue: RedemptionDecision[][] = [];
  callCount: number = 0;
  override?: () => Promise<RedemptionDecision[]>;
  async pollDecisions(): Promise<RedemptionDecision[]> {
    this.callCount += 1;
    if (this.override !== undefined) {
      return await this.override();
    }
    if (this.decisionsQueue.length === 0) {
      return [];
    }
    return this.decisionsQueue.shift() as RedemptionDecision[];
  }
}

function makeDecision(reqId: string, status: string): RedemptionDecision {
  const d: RedemptionDecision = new RedemptionDecision();
  d.requestId = reqId;
  d.status = status;
  d.costCoinsAtRequest = 10;
  d.decidedAtMs = 1700;
  return d;
}

export default function parentRedemptionPollTest(): void {
  describe('ParentRedemptionPoll.tick', () => {
    it('emptyRoundDoesNotNotifyListeners', 0, async () => {
      const svc: FakeSource = new FakeSource();
      const poll: ParentRedemptionPoll = new ParentRedemptionPoll(svc);
      let calls: number = 0;
      poll.subscribe((_d: RedemptionDecision[]): void => {
        calls += 1;
      });
      const out: RedemptionDecision[] = await poll.tick();
      expect(out.length).assertEqual(0);
      expect(calls).assertEqual(0);
    });

    it('notifiesListenersWithDecisions', 0, async () => {
      const svc: FakeSource = new FakeSource();
      svc.decisionsQueue.push([makeDecision('rdm-1', 'approved')]);
      const poll: ParentRedemptionPoll = new ParentRedemptionPoll(svc);
      let received: RedemptionDecision[] = [];
      poll.subscribe((d: RedemptionDecision[]): void => {
        received = d;
      });
      await poll.tick();
      expect(received.length).assertEqual(1);
      expect(received[0].requestId).assertEqual('rdm-1');
      expect(received[0].status).assertEqual('approved');
    });

    it('skipsTickWhenInFlight', 0, async () => {
      const svc: FakeSource = new FakeSource();
      let resolveFirst: (v: RedemptionDecision[]) => void = (
        _v: RedemptionDecision[],
      ): void => {};
      svc.override = (): Promise<RedemptionDecision[]> => {
        return new Promise<RedemptionDecision[]>(
          (resolve: (v: RedemptionDecision[]) => void): void => {
            resolveFirst = resolve;
          },
        );
      };
      const poll: ParentRedemptionPoll = new ParentRedemptionPoll(svc);
      const first: Promise<RedemptionDecision[]> = poll.tick();
      const second: RedemptionDecision[] = await poll.tick();
      expect(second.length).assertEqual(0);
      expect(svc.callCount).assertEqual(1);
      resolveFirst([]);
      await first;
    });

    it('unsubscribeRemovesListener', 0, async () => {
      const svc: FakeSource = new FakeSource();
      svc.decisionsQueue.push([makeDecision('rdm-1', 'approved')]);
      svc.decisionsQueue.push([makeDecision('rdm-2', 'rejected')]);
      const poll: ParentRedemptionPoll = new ParentRedemptionPoll(svc);
      let calls: number = 0;
      const listener: (d: RedemptionDecision[]) => void = (
        _d: RedemptionDecision[],
      ): void => {
        calls += 1;
      };
      poll.subscribe(listener);
      await poll.tick();
      poll.unsubscribe(listener);
      await poll.tick();
      expect(calls).assertEqual(1);
    });
  });

  describe('ParentRedemptionPoll.start/stop', () => {
    it('schedulesTimerOnStartAndClampsBelowMin', 0, async () => {
      const svc: FakeSource = new FakeSource();
      const poll: ParentRedemptionPoll = new ParentRedemptionPoll(svc);
      let scheduledMs: number = 0;
      poll.injectTimers(
        (_cb: () => void, ms: number): number => {
          scheduledMs = ms;
          return 42;
        },
        (_id: number): void => {},
      );
      poll.setIntervalMs(1000); // clamps below MIN_INTERVAL_MS to 5000
      poll.start();
      expect(scheduledMs >= 5000).assertEqual(true);
      poll.stop();
    });

    it('idempotentStartDoesNotDoubleSchedule', 0, async () => {
      const svc: FakeSource = new FakeSource();
      const poll: ParentRedemptionPoll = new ParentRedemptionPoll(svc);
      let scheduleCount: number = 0;
      poll.injectTimers(
        (_cb: () => void, _ms: number): number => {
          scheduleCount += 1;
          return scheduleCount;
        },
        (_id: number): void => {},
      );
      poll.start();
      poll.start();
      expect(scheduleCount).assertEqual(1);
      poll.stop();
    });
  });
}
