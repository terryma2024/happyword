import { describe, it, expect } from '@ohos/hypium';
import { CloudCredentials, CloudCredentialsSnapshot } from '../main/ets/services/CloudCredentials';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

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

function makeSnap(): CloudCredentialsSnapshot {
  const s: CloudCredentialsSnapshot = new CloudCredentialsSnapshot();
  s.deviceToken = 'jwt.token.value';
  s.bindingId = 'bind-aabbccdd';
  s.familyId = 'fam-12345678';
  s.childProfileId = 'child-deadbeef';
  s.nickname = '小明';
  s.avatarEmoji = '🦊';
  s.pairedAtMs = 1746068000000;
  s.deviceIdSource = 'asset_store';
  return s;
}

export default function cloudCredentialsTest(): void {
  describe('CloudCredentials.snapshot', () => {
    it('isBoundFalseWhenEmpty', 0, () => {
      const snap: CloudCredentialsSnapshot = new CloudCredentialsSnapshot();
      expect(snap.isBound()).assertEqual(false);
    });

    it('isBoundTrueWhenAllRequiredFieldsPresent', 0, () => {
      const snap: CloudCredentialsSnapshot = makeSnap();
      expect(snap.isBound()).assertEqual(true);
    });
  });

  describe('CloudCredentials.io', () => {
    it('saveThenLoadRoundTrips', 0, async () => {
      const cc: CloudCredentials = new CloudCredentials();
      const mem: MemPrefs = new MemPrefs();
      cc.injectPreferences(mem);
      await cc.saveBinding(makeSnap());
      const loaded: CloudCredentialsSnapshot = await cc.load();
      expect(loaded.deviceToken).assertEqual('jwt.token.value');
      expect(loaded.familyId).assertEqual('fam-12345678');
      expect(loaded.nickname).assertEqual('小明');
      expect(loaded.pairedAtMs).assertEqual(1746068000000);
      expect(loaded.deviceIdSource).assertEqual('asset_store');
      expect(loaded.isBound()).assertEqual(true);
      expect(mem.flushCount).assertLarger(0);
    });

    it('clearBindingZeroesTokenButKeepsDeviceIdSource', 0, async () => {
      const cc: CloudCredentials = new CloudCredentials();
      const mem: MemPrefs = new MemPrefs();
      cc.injectPreferences(mem);
      await cc.saveBinding(makeSnap());
      await cc.clearBinding();
      const loaded: CloudCredentialsSnapshot = await cc.load();
      expect(loaded.deviceToken).assertEqual('');
      expect(loaded.bindingId).assertEqual('');
      expect(loaded.familyId).assertEqual('');
      expect(loaded.deviceIdSource).assertEqual('asset_store');
      expect(loaded.isBound()).assertEqual(false);
    });

    it('setDeviceIdSourceUpdatesIndependently', 0, async () => {
      const cc: CloudCredentials = new CloudCredentials();
      const mem: MemPrefs = new MemPrefs();
      cc.injectPreferences(mem);
      await cc.setDeviceIdSource('preferences_fallback');
      const loaded: CloudCredentialsSnapshot = await cc.load();
      expect(loaded.deviceIdSource).assertEqual('preferences_fallback');
      expect(loaded.isBound()).assertEqual(false);
    });
  });
}
