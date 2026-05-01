import { AbilityConstant, common, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import preferences from '@ohos.data.preferences';
import { GameConfig, GAME_CONFIG_STORAGE_KEY } from '../models/GameConfig';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
import { DeviceIdProvider } from '../services/DeviceIdProvider';
import { CloudCredentials } from '../services/CloudCredentials';
import { CloudSyncService } from '../services/CloudSyncService';
import { RealParentFetchAdapter } from '../services/ParentApiClient';
import { effectiveServerBaseUrl } from '../services/RemoteWordPackConfig';
import { StringPreferencesLike } from '../services/WrongAnswerStore';

const DOMAIN = 0x0000;
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
      hilog.warn(DOMAIN, 'testTag', 'CloudSyncPrefs.getString failed: %{public}s', JSON.stringify(err as BusinessError));
      return '';
    }
  }
  async putString(key: string, value: string): Promise<void> {
    try {
      await this.handle.put(key, value);
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'CloudSyncPrefs.putString failed: %{public}s', JSON.stringify(err as BusinessError));
    }
  }
  async flush(): Promise<void> {
    try {
      await this.handle.flush();
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'CloudSyncPrefs.flush failed: %{public}s', JSON.stringify(err as BusinessError));
    }
  }
}

export default class EntryAbility extends UIAbility {
  private cloudSyncSvc?: CloudSyncService;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    const existing: GameConfig | undefined = AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    if (existing === undefined) {
      AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, new GameConfig());
    }
    // Boot the learning recorder so HomePage can check recentWrongIds
    // before any battle has started. init() is idempotent — BattlePage
    // will call it again and the second call resolves immediately.
    getLearningRecorder().init(this.context).catch((err: BusinessError): void => {
      hilog.error(DOMAIN, 'testTag', 'LearningRecorder.init failed: %{public}s', JSON.stringify(err));
    });
    // V0.6.2: warm the device-id provider so the AssetStoreKit lookup happens
    // before the user opens ScanBindingPage. The result is cached internally.
    const deviceIdProvider: DeviceIdProvider = new DeviceIdProvider();
    deviceIdProvider.init(this.context).then(() => deviceIdProvider.get())
      .then(() => undefined)
      .catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, 'testTag', 'DeviceIdProvider.warmup failed: %{public}s', JSON.stringify(err));
      });
    // V0.6.4: assemble the cloud-sync companion and attach it to the
    // singleton recorder so flushNow / aboutToDisappear / onBackground
    // can fire-and-forget without re-discovering credentials.
    this.installCloudSync(this.context).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, 'testTag', 'CloudSync wiring failed: %{public}s', JSON.stringify(err));
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  private async installCloudSync(ctx: common.UIAbilityContext): Promise<void> {
    const recorder: LearningRecorder = getLearningRecorder();
    const creds: CloudCredentials = new CloudCredentials();
    await creds.init(ctx);
    const svc: CloudSyncService = new CloudSyncService(
      recorder,
      creds,
      new RealParentFetchAdapter(),
      effectiveServerBaseUrl(),
    );
    try {
      const handle: preferences.Preferences = await preferences.getPreferences(ctx, SYNC_PREFS_NAME);
      svc.injectPreferences(new CloudSyncPrefs(handle));
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'CloudSync prefs unavailable: %{public}s', JSON.stringify(err as BusinessError));
    }
    recorder.attachCloudSync(svc);
    this.cloudSyncSvc = svc;
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/HomePage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    // V0.6.4: take advantage of the lifecycle to push pending learning
    // deltas before the system suspends us. CloudSyncService swallows
    // every failure so this is safe to fire-and-forget.
    if (this.cloudSyncSvc !== undefined) {
      this.cloudSyncSvc.syncOnce().catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, 'testTag', 'CloudSync.onBackground failed: %{public}s', JSON.stringify(err));
      });
    }
  }
}