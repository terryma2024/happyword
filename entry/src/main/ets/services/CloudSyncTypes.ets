/**
 * V0.6.4 — types shared between LearningRecorder, CloudSyncService and
 * UI surfaces (ConfigPage, EntryAbility). Lives in its own file so
 * LearningRecorder can describe the cloud-sync protocol without
 * importing the concrete CloudSyncService implementation, which would
 * otherwise create a circular module dependency.
 */
export type CloudSyncStatus =
  | 'unbound'
  | 'no_changes'
  | 'pushed'
  | 'pulled'
  | 'pushed_and_pulled'
  | 'network_error';

export class CloudSyncResult {
  status: CloudSyncStatus = 'unbound';
  pushed: number = 0;
  pulled: number = 0;
  rejected: number = 0;
  serverNowMs: number = 0;
}

/**
 * Minimal sync surface used by LearningRecorder. The cloud-sync
 * service implements `syncOnce` and never throws; callers
 * fire-and-forget.
 */
export interface CloudSyncLike {
  syncOnce(): Promise<CloudSyncResult>;
}
