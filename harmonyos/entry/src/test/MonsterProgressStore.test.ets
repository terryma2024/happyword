import { describe, it, expect } from '@ohos/hypium';
import { CoinAccount } from '../main/ets/services/CoinAccount';
import {
  MonsterProgressRecord,
  MonsterProgressSnapshot,
  MonsterProgressStore,
  MonsterRewardState,
  maskedQuestionMarks,
  parseMonsterProgressSnapshot,
  rewardStateForMilestone,
} from '../main/ets/services/MonsterProgressStore';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

class MapPrefs implements StringPreferencesLike {
  private map: Map<string, string> = new Map<string, string>();
  getString(key: string): Promise<string> {
    return Promise.resolve(this.map.has(key) ? (this.map.get(key) as string) : '');
  }
  putString(key: string, value: string): Promise<void> {
    this.map.set(key, value);
    return Promise.resolve();
  }
  flush(): Promise<void> {
    return Promise.resolve();
  }
}

const NOW: number = Date.parse('2026-06-05T08:00:00Z');

function freshStore(): MonsterProgressStore {
  const store: MonsterProgressStore = new MonsterProgressStore();
  store.injectPreferencesForTest(new MapPrefs());
  return store;
}

function coinAccount(): CoinAccount {
  const acct: CoinAccount = new CoinAccount();
  acct.injectPreferencesForTest(new MapPrefs());
  acct.beginToday(NOW);
  return acct;
}

function findRecord(snapshot: MonsterProgressSnapshot, catalogIndex: number): MonsterProgressRecord {
  for (let i: number = 0; i < snapshot.records.length; i++) {
    if (snapshot.records[i].catalogIndex === catalogIndex) {
      return snapshot.records[i];
    }
  }
  return new MonsterProgressRecord();
}

export default function monsterProgressStoreTest(): void {
  describe('MonsterProgressStore', () => {
    it('parseDefaultsToEmptySnapshot', 0, () => {
      const snap: MonsterProgressSnapshot = parseMonsterProgressSnapshot('');
      expect(snap.version).assertEqual(1);
      expect(snap.records.length).assertEqual(0);
    });

    it('parseFiltersInvalidRecordsAndNormalizesMilestones', 0, () => {
      const snap: MonsterProgressSnapshot = parseMonsterProgressSnapshot(
        '{"version":2,"records":[' +
          '{"catalogIndex":1,"encountered":true,"defeatCount":51,"claimedMilestones":[50,50,25,100]},' +
          '{"catalogIndex":0,"encountered":true,"defeatCount":9,"claimedMilestones":[50]},' +
          '{"catalogIndex":2,"encountered":false,"defeatCount":-3,"claimedMilestones":[100]}' +
        ']}',
      );
      expect(snap.version).assertEqual(2);
      expect(snap.records.length).assertEqual(2);
      const first: MonsterProgressRecord = findRecord(snap, 1);
      const second: MonsterProgressRecord = findRecord(snap, 2);
      expect(first.encountered).assertTrue();
      expect(first.defeatCount).assertEqual(51);
      expect(first.claimedMilestones.length).assertEqual(2);
      expect(first.claimedMilestones[0]).assertEqual(50);
      expect(first.claimedMilestones[1]).assertEqual(100);
      expect(second.defeatCount).assertEqual(0);
      expect(second.claimedMilestones.length).assertEqual(1);
      expect(second.claimedMilestones[0]).assertEqual(100);
    });

    it('encounterRevealsWithoutIncrementingDefeatCount', 0, () => {
      const store: MonsterProgressStore = freshStore();
      store.recordEncounter(3);
      const rec: MonsterProgressRecord = store.recordFor(3);
      expect(rec.encountered).assertTrue();
      expect(rec.defeatCount).assertEqual(0);
    });

    it('defeatMarksEncounteredAndIncrementsOnlyThatMonster', 0, () => {
      const store: MonsterProgressStore = freshStore();
      store.recordDefeat(2);
      store.recordDefeat(2);
      store.recordDefeat(4);
      expect(store.recordFor(2).encountered).assertTrue();
      expect(store.recordFor(2).defeatCount).assertEqual(2);
      expect(store.recordFor(4).defeatCount).assertEqual(1);
      expect(store.recordFor(5).defeatCount).assertEqual(0);
    });

    it('rewardStateShowsDisabledProgressEnabledAndClaimed', 0, () => {
      let state: MonsterRewardState = rewardStateForMilestone(17, false, 50);
      expect(state.enabled).assertFalse();
      expect(state.label).assertEqual('50 金币 17/50');

      state = rewardStateForMilestone(50, false, 50);
      expect(state.enabled).assertTrue();
      expect(state.label).assertEqual('领 50 金币');

      state = rewardStateForMilestone(100, true, 100);
      expect(state.enabled).assertFalse();
      expect(state.label).assertEqual('已领 100 金币');
    });

    it('canCatchUpClaimFiftyAndHundredAtOneHundredDefeats', 0, () => {
      const store: MonsterProgressStore = freshStore();
      const acct: CoinAccount = coinAccount();
      for (let i: number = 0; i < 100; i++) {
        store.recordDefeat(1);
      }
      const fifty: boolean = store.claimReward(1, 50, acct, NOW);
      const hundred: boolean = store.claimReward(1, 100, acct, NOW + 1);
      expect(fifty).assertTrue();
      expect(hundred).assertTrue();
      expect(acct.balance()).assertEqual(150);
      expect(store.recordFor(1).defeatCount).assertEqual(100);
    });

    it('claimRewardRejectsDuplicatesAndUnderThreshold', 0, () => {
      const store: MonsterProgressStore = freshStore();
      const acct: CoinAccount = coinAccount();
      for (let i: number = 0; i < 50; i++) {
        store.recordDefeat(1);
      }
      expect(store.claimReward(1, 100, acct, NOW)).assertFalse();
      expect(store.claimReward(1, 50, acct, NOW)).assertTrue();
      expect(store.claimReward(1, 50, acct, NOW + 1)).assertFalse();
      expect(acct.balance()).assertEqual(50);
    });

    it('maskedQuestionMarksPreservesCharacterCount', 0, () => {
      expect(maskedQuestionMarks('软泥小灵')).assertEqual('????');
      expect(maskedQuestionMarks('「普通怪物」')).assertEqual('??????');
      expect(maskedQuestionMarks('Dragon 是住在云朵后面')).assertEqual('??????????????');
    });
  });
}
