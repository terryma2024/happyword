import { describe, it, expect } from '@ohos/hypium';
import {
  AssetStoreLike,
  DeviceIdProvider,
  DeviceIdResult,
  UuidGenerator,
  DEVICE_ID_SOURCE_ASSET,
  DEVICE_ID_SOURCE_PREFS,
} from '../main/ets/services/DeviceIdProvider';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

class StubAsset implements AssetStoreLike {
  stored: string | null = null;
  failOnAdd: boolean = false;
  queryThrows: boolean = false;
  queries: number = 0;
  adds: number = 0;
  async query(_alias: string): Promise<string | null> {
    this.queries += 1;
    if (this.queryThrows) {
      throw new Error('query failed');
    }
    return this.stored;
  }
  async add(_alias: string, secret: string): Promise<void> {
    this.adds += 1;
    if (this.failOnAdd) {
      throw new Error('add failed');
    }
    this.stored = secret;
  }
}

class FixedUuid implements UuidGenerator {
  private value: string;
  constructor(value: string) {
    this.value = value;
  }
  generate(): string {
    return this.value;
  }
}

class MemPrefs implements StringPreferencesLike {
  store: Map<string, string> = new Map<string, string>();
  flushCount: number = 0;
  async getString(key: string): Promise<string> {
    return this.store.get(key) ?? '';
  }
  async putString(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
  async flush(): Promise<void> {
    this.flushCount += 1;
  }
}

export default function deviceIdProviderTest(): void {
  describe('DeviceIdProvider.assetStorePath', () => {
    it('returnsExistingAssetWhenPresent', 0, async () => {
      const provider: DeviceIdProvider = new DeviceIdProvider();
      const asset: StubAsset = new StubAsset();
      asset.stored = 'cafebabe11112222deadbeef33334444';
      provider.injectAssetStore(asset);
      provider.injectPreferences(new MemPrefs());
      const r: DeviceIdResult = await provider.get();
      expect(r.deviceId).assertEqual('cafebabe11112222deadbeef33334444');
      expect(r.source).assertEqual(DEVICE_ID_SOURCE_ASSET);
      expect(asset.adds).assertEqual(0);
    });

    it('cachesIdAcrossCalls', 0, async () => {
      const provider: DeviceIdProvider = new DeviceIdProvider();
      const asset: StubAsset = new StubAsset();
      asset.stored = 'aabbccddeeff00112233445566778899';
      provider.injectAssetStore(asset);
      provider.injectPreferences(new MemPrefs());
      const a: DeviceIdResult = await provider.get();
      const b: DeviceIdResult = await provider.get();
      expect(a.deviceId).assertEqual(b.deviceId);
      expect(asset.queries).assertEqual(1);
    });

    it('generatesAndAddsAssetWhenMissing', 0, async () => {
      const provider: DeviceIdProvider = new DeviceIdProvider();
      const asset: StubAsset = new StubAsset();
      provider.injectAssetStore(asset);
      provider.injectPreferences(new MemPrefs());
      provider.injectUuidGenerator(new FixedUuid('11112222333344445555666677778888'));
      const r: DeviceIdResult = await provider.get();
      expect(r.deviceId).assertEqual('11112222333344445555666677778888');
      expect(r.source).assertEqual(DEVICE_ID_SOURCE_ASSET);
      expect(asset.stored).assertEqual('11112222333344445555666677778888');
    });
  });

  describe('DeviceIdProvider.preferencesFallback', () => {
    it('fallsBackWhenAssetAddThrows', 0, async () => {
      const provider: DeviceIdProvider = new DeviceIdProvider();
      const asset: StubAsset = new StubAsset();
      asset.failOnAdd = true;
      provider.injectAssetStore(asset);
      const prefs: MemPrefs = new MemPrefs();
      provider.injectPreferences(prefs);
      provider.injectUuidGenerator(new FixedUuid('99998888777766665555444433332222'));
      const r: DeviceIdResult = await provider.get();
      expect(r.deviceId).assertEqual('99998888777766665555444433332222');
      expect(r.source).assertEqual(DEVICE_ID_SOURCE_PREFS);
      expect(prefs.store.get('device_id')).assertEqual('99998888777766665555444433332222');
    });

    it('returnsExistingPrefsValueOnSecondProcessRestart', 0, async () => {
      const prefs: MemPrefs = new MemPrefs();
      prefs.store.set('device_id', 'aaaa11112222333344445555666677ff');
      const asset: StubAsset = new StubAsset();
      asset.failOnAdd = true;
      const provider: DeviceIdProvider = new DeviceIdProvider();
      provider.injectAssetStore(asset);
      provider.injectPreferences(prefs);
      const r: DeviceIdResult = await provider.get();
      expect(r.deviceId).assertEqual('aaaa11112222333344445555666677ff');
      expect(r.source).assertEqual(DEVICE_ID_SOURCE_PREFS);
    });

    it('survivesQueryThrowAndAddSuccess', 0, async () => {
      const provider: DeviceIdProvider = new DeviceIdProvider();
      const asset: StubAsset = new StubAsset();
      asset.queryThrows = true;
      provider.injectAssetStore(asset);
      provider.injectPreferences(new MemPrefs());
      provider.injectUuidGenerator(new FixedUuid('1234567890abcdef1234567890abcdef'));
      const r: DeviceIdResult = await provider.get();
      // Query threw → we generated and added; that succeeded so source = asset_store.
      expect(r.deviceId).assertEqual('1234567890abcdef1234567890abcdef');
      expect(r.source).assertEqual(DEVICE_ID_SOURCE_ASSET);
    });
  });
}
