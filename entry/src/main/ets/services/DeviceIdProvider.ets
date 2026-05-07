import { BusinessError } from '@ohos.base';
import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { StringPreferencesLike } from './WrongAnswerStore';

/**
 * V0.6.2 — stable device id that survives app reinstalls on the same device.
 *
 * Strategy (per spec §V0.6 r2 lock-in #c):
 *  1. Try to read `wordmagic.device_id` from `@kit.AssetStoreKit`. The Asset
 *     SDK persists the entry in keychain-backed storage (with
 *     `IS_PERSISTENT=true` + `ohos.permission.STORE_PERSISTENT_DATA`) so it
 *     survives app uninstall/reinstall on the same physical device.
 *  2. If the asset is missing, generate a fresh 32-char hex UUID and write
 *     it back via `Asset.add(...)`. Subsequent calls return the same id.
 *  3. If the Asset write throws (vendor / OS / permissions), fall back to
 *     a per-install UUID stored in app-private preferences. We mark
 *     `device_id_source = preferences_fallback` so the parent web can
 *     surface the degraded experience and the user can re-install if they
 *     replace their device.
 *
 * Tests inject `AssetStoreLike` + `StringPreferencesLike` so we never touch
 * real OS APIs in CI.
 */

const ASSET_ALIAS: string = 'wordmagic.device_id';
const PREFS_NAME: string = 'wordmagic_device';
const PREFS_KEY_DEVICE_ID: string = 'device_id';

export const DEVICE_ID_SOURCE_ASSET: string = 'asset_store';
export const DEVICE_ID_SOURCE_PREFS: string = 'preferences_fallback';

/** Result returned by `DeviceIdProvider.get()`. */
export class DeviceIdResult {
  deviceId: string = '';
  source: string = '';

  constructor(deviceId: string, source: string) {
    this.deviceId = deviceId;
    this.source = source;
  }
}

/**
 * Minimal abstraction over the @kit.AssetStoreKit Asset SDK. Concrete
 * implementations call `Asset.query` / `Asset.add`. Tests stub all three
 * methods.
 */
export interface AssetStoreLike {
  query(alias: string): Promise<string | null>;
  add(alias: string, secret: string): Promise<void>;
}

/** Optional injection point so tests can supply deterministic ids. */
export interface UuidGenerator {
  generate(): string;
}

class DefaultUuidGenerator implements UuidGenerator {
  generate(): string {
    // 16 bytes ⇒ 32-char lowercase hex. Uses Math.random which is fine for
    // a non-cryptographic device identifier (server side never trusts it
    // for auth — it's a stable handle, not a secret).
    let out: string = '';
    for (let i: number = 0; i < 32; i++) {
      const n: number = Math.floor(Math.random() * 16);
      out += n.toString(16);
    }
    return out;
  }
}

/** Default no-op AssetStore — used when @kit.AssetStoreKit is unavailable
 *  (e.g. in test). Throws on every method so the fallback path engages. */
class UnavailableAssetStore implements AssetStoreLike {
  async query(_alias: string): Promise<string | null> {
    throw new Error('AssetStoreKit not bound');
  }
  async add(_alias: string, _secret: string): Promise<void> {
    throw new Error('AssetStoreKit not bound');
  }
}

class RealPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;
  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }
  async getString(key: string): Promise<string> {
    try {
      const v: preferences.ValueType = await this.handle.get(key, '');
      return typeof v === 'string' ? v : '';
    } catch (err) {
      console.error(`DeviceIdProvider.RealPrefs.getString: ${JSON.stringify(err as BusinessError)}`);
      return '';
    }
  }
  async putString(key: string, value: string): Promise<void> {
    try {
      await this.handle.put(key, value);
    } catch (err) {
      console.error(`DeviceIdProvider.RealPrefs.putString: ${JSON.stringify(err as BusinessError)}`);
    }
  }
  async flush(): Promise<void> {
    try {
      await this.handle.flush();
    } catch (err) {
      console.error(`DeviceIdProvider.RealPrefs.flush: ${JSON.stringify(err as BusinessError)}`);
    }
  }
}

export class DeviceIdProvider {
  private assetStore: AssetStoreLike = new UnavailableAssetStore();
  private prefs?: StringPreferencesLike;
  private uuid: UuidGenerator = new DefaultUuidGenerator();
  private cached: DeviceIdResult | null = null;

  injectAssetStore(s: AssetStoreLike): void {
    this.assetStore = s;
  }

  injectPreferences(p: StringPreferencesLike): void {
    this.prefs = p;
  }

  injectUuidGenerator(u: UuidGenerator): void {
    this.uuid = u;
  }

  /** Reset the in-memory cache; tests use this to simulate a process restart. */
  resetForTest(): void {
    this.cached = null;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.prefs !== undefined) {
      return;
    }
    try {
      const real: preferences.Preferences = await preferences.getPreferences(ctx, PREFS_NAME);
      this.prefs = new RealPrefs(real);
    } catch (err) {
      console.error(`DeviceIdProvider.init: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  /** Returns the device id, generating + persisting it if missing. */
  async get(): Promise<DeviceIdResult> {
    if (this.cached !== null) {
      return this.cached;
    }

    // 1) Try AssetStoreKit-backed read.
    try {
      const existing: string | null = await this.assetStore.query(ASSET_ALIAS);
      if (existing !== null && existing.length > 0) {
        this.cached = new DeviceIdResult(existing, DEVICE_ID_SOURCE_ASSET);
        return this.cached;
      }
    } catch (err) {
      // Query failure is normal on a fresh install (no entry yet); we
      // fall through to add-or-fallback below.
      console.info(`DeviceIdProvider.get: assetStore.query miss: ${JSON.stringify(err as BusinessError)}`);
    }

    // 2) Try AssetStoreKit-backed write of a freshly generated id.
    const generated: string = this.uuid.generate();
    try {
      await this.assetStore.add(ASSET_ALIAS, generated);
      this.cached = new DeviceIdResult(generated, DEVICE_ID_SOURCE_ASSET);
      return this.cached;
    } catch (err) {
      console.warn(`DeviceIdProvider.get: assetStore.add failed, falling back to preferences: ${JSON.stringify(err as BusinessError)}`);
    }

    // 3) Preferences-only fallback. Read first, then write generated value.
    if (this.prefs !== undefined) {
      const stored: string = await this.prefs.getString(PREFS_KEY_DEVICE_ID);
      if (stored.length > 0) {
        this.cached = new DeviceIdResult(stored, DEVICE_ID_SOURCE_PREFS);
        return this.cached;
      }
      await this.prefs.putString(PREFS_KEY_DEVICE_ID, generated);
      await this.prefs.flush();
    }
    this.cached = new DeviceIdResult(generated, DEVICE_ID_SOURCE_PREFS);
    return this.cached;
  }
}
