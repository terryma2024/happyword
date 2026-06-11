import { AbilityConstant, common, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import preferences from '@ohos.data.preferences';
import { GameConfig, GAME_CONFIG_STORAGE_KEY } from '../models/GameConfig';
import { hydrateGameConfigFromPrefs } from '../services/GameConfigPersistence';
import { getLearningRecorder } from '../services/LearningRecorder';
import { DeviceIdProvider } from '../services/DeviceIdProvider';
import { CloudCredentials } from '../services/CloudCredentials';
import { ensureCloudSyncInstalled } from '../services/CloudSyncInstaller';
import { CloudSyncLike } from '../services/CloudSyncTypes';
import { CloudWishlistService } from '../services/CloudWishlistService';
import { ParentRedemptionPoll } from '../services/ParentRedemptionPoll';
import { RealParentFetchAdapter } from '../services/ParentApiClient';
import { initBackendEnvPrefs } from '../services/BackendEnv';
import { cocosEngineHost } from '../services/CocosEngineHost';
import { initPreviewManifestService } from '../services/PreviewManifestService';
import { isDebugBuild } from '../services/ReleaseGate';
import BuildProfile from 'BuildProfile';
import { StringPreferencesLike } from '../services/WrongAnswerStore';
import { APP_COLOR_MODE } from '../utils/theme';

const DOMAIN = 0x0000;
const WISHLIST_PREFS_NAME: string = 'wordmagic_cloud_wishlist';

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
  private cloudSyncSvc?: CloudSyncLike;
  private cloudWishlistSvc?: CloudWishlistService;
  private redemptionPoll?: ParentRedemptionPoll;
  // TEMPORARY (V1.1.0 Task 0.2 spike): `aa start ... --ps cocosLab true`
  // boots straight into the Cocos battle page so the embed can be verified
  // from the command line. Remove once the real battle routing lands.
  // Debug builds only — release builds never inspect this want parameter.
  private launchCocosLab: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const wantParams: Record<string, Object> | undefined = want.parameters;
    if (isDebugBuild(BuildProfile.BUILD_MODE_NAME) &&
        wantParams !== undefined && wantParams['cocosLab'] === 'true') {
      this.launchCocosLab = true;
    }
    try {
      this.context.getApplicationContext().setColorMode(APP_COLOR_MODE);
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
    // Backend env prefs MUST load before CloudSync / CloudWishlist wiring —
    // otherwise `effectiveServerBaseUrl()` reads empty AppStorage on cold
    // start and both services pin staging forever (Preview DevMenu ignored).
    initBackendEnvPrefs(this.context).then((): void => {
      // V0.6.4: assemble the cloud-sync companion and attach it to the
      // singleton recorder so flushNow / aboutToDisappear / onBackground
      // can fire-and-forget without re-discovering credentials.
      this.installCloudSync(this.context).catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, 'testTag', 'CloudSync wiring failed: %{public}s', JSON.stringify(err));
      });
      // V0.6.6: pre-build the cloud wishlist + redemption poller so the
      // redemption overlay survives navigation. The poller stays idle
      // until onForeground starts it.
      this.installCloudWishlist(this.context).catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, 'testTag', 'CloudWishlist wiring failed: %{public}s', JSON.stringify(err));
      });
    }).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, 'testTag', 'BackendEnv init failed: %{public}s', JSON.stringify(err));
    });
    initPreviewManifestService(this.context).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, 'testTag', 'PreviewManifest init failed: %{public}s', JSON.stringify(err));
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  private async installCloudSync(ctx: common.UIAbilityContext): Promise<void> {
    this.cloudSyncSvc = await ensureCloudSyncInstalled(ctx);
  }

  private async installCloudWishlist(ctx: common.UIAbilityContext): Promise<void> {
    const creds: CloudCredentials = new CloudCredentials();
    await creds.init(ctx);
    const svc: CloudWishlistService = new CloudWishlistService(
      creds,
      new RealParentFetchAdapter(),
      (): string => CloudWishlistService.defaultBaseUrlResolver(),
    );
    try {
      const handle: preferences.Preferences = await preferences.getPreferences(
        ctx, WISHLIST_PREFS_NAME,
      );
      svc.injectPreferences(new CloudSyncPrefs(handle));
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'CloudWishlist prefs unavailable: %{public}s', JSON.stringify(err as BusinessError));
    }
    await svc.hydrate();
    this.cloudWishlistSvc = svc;
    this.redemptionPoll = new ParentRedemptionPoll(svc);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // TEMPORARY (Task 0.2 spike): see launchCocosLab above.
    const initialPage: string = this.launchCocosLab ? 'pages/CocosBattlePage' : 'pages/HomePage';
    const loadHome = (): void => {
      windowStage.loadContent(initialPage, (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
          return;
        }
        hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      });
    };

    // Restore GameConfig (parent PIN, timers, etc.) before any page reads AppStorage.
    hydrateGameConfigFromPrefs(this.context).then((): void => {
      loadHome();
    }).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, 'testTag', 'hydrateGameConfigFromPrefs failed: %{public}s', JSON.stringify(err));
      loadHome();
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // V0.6.6: drive periodic redemption decision polling while visible.
    if (this.redemptionPoll !== undefined) {
      this.redemptionPoll.start();
    }
    // V1.1.0: relay to the embedded Cocos engine; no-op until the battle
    // page has booted it (see CocosEngineHost).
    cocosEngineHost().notifyForeground();
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    // V0.6.4: take advantage of the lifecycle to push pending learning
    // deltas before the system suspends us. CloudSyncService swallows
    // every failure so this is safe to fire-and-forget.
    if (this.cloudSyncSvc !== undefined) {
      this.cloudSyncSvc.syncOnce().catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, 'testTag', 'CloudSync.onBackground failed: %{public}s', JSON.stringify(err));
      });
    }
    // V0.6.6: pause redemption polling while backgrounded.
    if (this.redemptionPoll !== undefined) {
      this.redemptionPoll.stop();
    }
    // V1.1.0: pause the embedded Cocos engine while backgrounded.
    cocosEngineHost().notifyBackground();
  }

  /** V0.6.6: exposed for pages that need to display pending redemptions
   *  or apply incoming decisions. Returns undefined until installCloudWishlist
   *  resolves; pages should null-check before subscribing. */
  getCloudWishlist(): CloudWishlistService | undefined {
    return this.cloudWishlistSvc;
  }

  getRedemptionPoll(): ParentRedemptionPoll | undefined {
    return this.redemptionPoll;
  }
}
