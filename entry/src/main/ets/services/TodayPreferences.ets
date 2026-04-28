import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { DEFAULT_REGION_ID, getRegionById } from '../data/AdventureCatalog';
import { StringPreferencesLike } from './WrongAnswerStore';

const PREFS_NAME: string = 'today_settings';
const REGION_ID_KEY: string = 'region_id';

class RealPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;
  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }
  async getString(key: string): Promise<string> {
    const v: preferences.ValueType = await this.handle.get(key, '');
    return typeof v === 'string' ? v : '';
  }
  putString(key: string, value: string): Promise<void> {
    return this.handle.put(key, value);
  }
  flush(): Promise<void> {
    return this.handle.flush();
  }
}

function isKnownRegionId(id: string): boolean {
  if (id.length === 0) {
    return false;
  }
  // getRegionById falls back, so we compare the id.
  return getRegionById(id).id === id;
}

/**
 * Tiny preferences wrapper for Today Adventure settings.
 *
 * Currently stores only the selected region id (V0.3.5).
 */
export class TodayPreferences {
  private prefs?: StringPreferencesLike;
  private ready: boolean = false;

  injectPreferencesForTest(p: StringPreferencesLike): void {
    this.prefs = p;
    this.ready = true;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.ready && this.prefs !== undefined) {
      return;
    }
    const real: preferences.Preferences = await preferences.getPreferences(ctx, PREFS_NAME);
    this.prefs = new RealPrefs(real);
    this.ready = true;
  }

  async loadRegionId(): Promise<string> {
    if (!this.ready || this.prefs === undefined) {
      return DEFAULT_REGION_ID;
    }
    try {
      const raw: string = await this.prefs.getString(REGION_ID_KEY);
      if (isKnownRegionId(raw)) {
        return raw;
      }
      return DEFAULT_REGION_ID;
    } catch (err) {
      console.error(`TodayPreferences.loadRegionId failed: ${JSON.stringify(err as BusinessError)}`);
      return DEFAULT_REGION_ID;
    }
  }

  async saveRegionId(id: string): Promise<void> {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    const safe: string = isKnownRegionId(id) ? id : DEFAULT_REGION_ID;
    this.prefs.putString(REGION_ID_KEY, safe)
      .catch((err: BusinessError): void => {
        console.error(`TodayPreferences.saveRegionId failed: ${JSON.stringify(err)}`);
      });
  }

  async flushNow(): Promise<void> {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    await this.prefs.flush();
  }
}

let globalTodayPrefs: TodayPreferences | undefined = undefined;

export function getTodayPreferences(): TodayPreferences {
  if (globalTodayPrefs === undefined) {
    globalTodayPrefs = new TodayPreferences();
  }
  return globalTodayPrefs;
}

export function __resetTodayPreferencesForTest(): void {
  globalTodayPrefs = undefined;
}

