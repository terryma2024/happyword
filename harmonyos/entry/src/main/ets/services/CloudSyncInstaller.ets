import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { initBackendEnvPrefs } from './BackendEnv';
import { CloudCredentials } from './CloudCredentials';
import { CloudSyncService } from './CloudSyncService';
import { CloudSyncLike } from './CloudSyncTypes';
import { getLearningRecorder, LearningRecorder } from './LearningRecorder';
import { RealParentFetchAdapter } from './ParentApiClient';
import { StringPreferencesLike } from './WrongAnswerStore';

const SYNC_PREFS_NAME: string = 'wordmagic_cloud_sync';

class CloudSyncPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;

  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }

  async getString(key: string): Promise<string> {
    try {
      const v: preferences.ValueType = await this.handle.get(key, '');
      return typeof v === 'string' ? v : '';
    } catch (err) {
      console.warn(`CloudSyncPrefs.getString failed: ${JSON.stringify(err as BusinessError)}`);
      return '';
    }
  }

  async putString(key: string, value: string): Promise<void> {
    try {
      await this.handle.put(key, value);
    } catch (err) {
      console.warn(`CloudSyncPrefs.putString failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  async flush(): Promise<void> {
    try {
      await this.handle.flush();
    } catch (err) {
      console.warn(`CloudSyncPrefs.flush failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
}

let installPromise: Promise<CloudSyncLike> | undefined = undefined;

export async function ensureCloudSyncInstalled(
  ctx: common.UIAbilityContext,
): Promise<CloudSyncLike> {
  const recorder: LearningRecorder = getLearningRecorder();
  const existing: CloudSyncLike | undefined = recorder.getCloudSync();
  if (existing !== undefined) {
    return existing;
  }
  if (installPromise !== undefined) {
    return installPromise;
  }
  installPromise = installCloudSync(ctx);
  try {
    return await installPromise;
  } finally {
    installPromise = undefined;
  }
}

async function installCloudSync(ctx: common.UIAbilityContext): Promise<CloudSyncLike> {
  await initBackendEnvPrefs(ctx);

  const recorder: LearningRecorder = getLearningRecorder();
  const creds: CloudCredentials = new CloudCredentials();
  await creds.init(ctx);
  const svc: CloudSyncService = new CloudSyncService(
    recorder,
    creds,
    new RealParentFetchAdapter(),
    (): string => CloudSyncService.defaultBaseUrlResolver(),
  );
  try {
    const handle: preferences.Preferences = await preferences.getPreferences(ctx, SYNC_PREFS_NAME);
    svc.injectPreferences(new CloudSyncPrefs(handle));
  } catch (err) {
    console.warn(`CloudSync prefs unavailable: ${JSON.stringify(err as BusinessError)}`);
  }
  recorder.attachCloudSync(svc);
  return svc;
}
