import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { StringPreferencesLike } from './WrongAnswerStore';

/**
 * V0.6.2 — persistent storage for the parent-account session.
 *
 * The credentials live in the `wordmagic_cloud` preferences bag so they
 * survive app restarts but are wiped on app reinstall (matching server
 * expectation: a fresh install re-binds via ScanKit). The token alone
 * does NOT contain enough information to re-establish a binding without
 * the parent web's QR — we explicitly do not write it to a backed-up
 * location.
 *
 * Stored keys:
 * - `device_token`     — JWT issued by `/api/v1/pair/redeem`
 * - `binding_id`       — `bind-<8hex>` business id
 * - `family_id`        — `fam-<8hex>` business id
 * - `child_profile_id` — `child-<8hex>` business id
 * - `nickname`         — child profile nickname (last seen)
 * - `avatar_emoji`     — child profile avatar (last seen)
 * - `paired_at_ms`     — wall-clock ms at the time of redeem
 * - `device_id_source` — `asset_store` | `preferences_fallback`
 */

const PREFS_NAME: string = 'wordmagic_cloud';

const KEY_DEVICE_TOKEN: string = 'device_token';
const KEY_BINDING_ID: string = 'binding_id';
const KEY_FAMILY_ID: string = 'family_id';
const KEY_CHILD_PROFILE_ID: string = 'child_profile_id';
const KEY_NICKNAME: string = 'nickname';
const KEY_AVATAR: string = 'avatar_emoji';
const KEY_PAIRED_AT_MS: string = 'paired_at_ms';
const KEY_DEVICE_ID_SOURCE: string = 'device_id_source';

export class CloudCredentialsSnapshot {
  deviceToken: string = '';
  bindingId: string = '';
  familyId: string = '';
  childProfileId: string = '';
  nickname: string = '';
  avatarEmoji: string = '';
  pairedAtMs: number = 0;
  deviceIdSource: string = '';

  isBound(): boolean {
    return this.deviceToken.length > 0
      && this.bindingId.length > 0
      && this.familyId.length > 0;
  }
}

class RealCloudPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;
  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }
  async getString(key: string): Promise<string> {
    try {
      const v: preferences.ValueType = await this.handle.get(key, '');
      return typeof v === 'string' ? v : '';
    } catch (err) {
      console.error(`CloudCredentials.RealCloudPrefs.getString(${key}): ${JSON.stringify(err as BusinessError)}`);
      return '';
    }
  }
  async putString(key: string, value: string): Promise<void> {
    try {
      await this.handle.put(key, value);
    } catch (err) {
      console.error(`CloudCredentials.RealCloudPrefs.putString(${key}): ${JSON.stringify(err as BusinessError)}`);
    }
  }
  async flush(): Promise<void> {
    try {
      await this.handle.flush();
    } catch (err) {
      console.error(`CloudCredentials.RealCloudPrefs.flush: ${JSON.stringify(err as BusinessError)}`);
    }
  }
}

export class CloudCredentials {
  private prefs?: StringPreferencesLike;
  private ready: boolean = false;

  /** Override the storage backend; tests inject an in-memory stub. */
  injectPreferences(p: StringPreferencesLike): void {
    this.prefs = p;
    this.ready = true;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.ready && this.prefs !== undefined) {
      return;
    }
    try {
      const real: preferences.Preferences = await preferences.getPreferences(ctx, PREFS_NAME);
      this.prefs = new RealCloudPrefs(real);
      this.ready = true;
    } catch (err) {
      console.error(`CloudCredentials.init: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  /** Read the full snapshot. Empty fields when unbound. */
  async load(): Promise<CloudCredentialsSnapshot> {
    const out: CloudCredentialsSnapshot = new CloudCredentialsSnapshot();
    if (!this.ready || this.prefs === undefined) {
      return out;
    }
    out.deviceToken = await this.prefs.getString(KEY_DEVICE_TOKEN);
    out.bindingId = await this.prefs.getString(KEY_BINDING_ID);
    out.familyId = await this.prefs.getString(KEY_FAMILY_ID);
    out.childProfileId = await this.prefs.getString(KEY_CHILD_PROFILE_ID);
    out.nickname = await this.prefs.getString(KEY_NICKNAME);
    out.avatarEmoji = await this.prefs.getString(KEY_AVATAR);
    const pairedAtRaw: string = await this.prefs.getString(KEY_PAIRED_AT_MS);
    out.pairedAtMs = pairedAtRaw.length > 0 ? Number.parseInt(pairedAtRaw, 10) : 0;
    if (Number.isNaN(out.pairedAtMs)) {
      out.pairedAtMs = 0;
    }
    out.deviceIdSource = await this.prefs.getString(KEY_DEVICE_ID_SOURCE);
    return out;
  }

  async saveBinding(snap: CloudCredentialsSnapshot): Promise<void> {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(KEY_DEVICE_TOKEN, snap.deviceToken);
    await this.prefs.putString(KEY_BINDING_ID, snap.bindingId);
    await this.prefs.putString(KEY_FAMILY_ID, snap.familyId);
    await this.prefs.putString(KEY_CHILD_PROFILE_ID, snap.childProfileId);
    await this.prefs.putString(KEY_NICKNAME, snap.nickname);
    await this.prefs.putString(KEY_AVATAR, snap.avatarEmoji);
    await this.prefs.putString(KEY_PAIRED_AT_MS, snap.pairedAtMs.toString());
    if (snap.deviceIdSource.length > 0) {
      await this.prefs.putString(KEY_DEVICE_ID_SOURCE, snap.deviceIdSource);
    }
    await this.prefs.flush();
  }

  async setDeviceIdSource(source: string): Promise<void> {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(KEY_DEVICE_ID_SOURCE, source);
    await this.prefs.flush();
  }

  async clearBinding(): Promise<void> {
    if (!this.ready || this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(KEY_DEVICE_TOKEN, '');
    await this.prefs.putString(KEY_BINDING_ID, '');
    await this.prefs.putString(KEY_FAMILY_ID, '');
    await this.prefs.putString(KEY_CHILD_PROFILE_ID, '');
    await this.prefs.putString(KEY_NICKNAME, '');
    await this.prefs.putString(KEY_AVATAR, '');
    await this.prefs.putString(KEY_PAIRED_AT_MS, '0');
    // Intentionally retain device_id_source so we don't re-misdetect it.
    await this.prefs.flush();
  }
}
