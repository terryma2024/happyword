export class CheckInSnapshot {
  version: number = 1;
  checkedDayKeys: string[] = [];
  weeklyBonusDayKeys: string[] = [];
  currentStreak: number = 0;
  bestStreak: number = 0;
  lastSyncedAtMs: number = 0;
  pendingSync: boolean = false;
}

export const CHECKIN_PREFS_NAME: string = 'wordmagic_checkins';
export const CHECKIN_PREFS_KEY: string = 'snapshot_v1';
export const CHECKIN_WEEKLY_BONUS_COINS: number = 50;
