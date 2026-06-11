import { describe, it, expect } from '@ohos/hypium';
import {
  decideBattleRoute,
  COCOS_BATTLE_PREF_KEY,
  cocosBattlePrefEnabledFromRaw,
} from '../main/ets/services/CocosBattlePreference';

/**
 * Unit tests for the pure battle-route decision function and the
 * preference-default helper.
 *
 * Context (AppStorage) and @ohos.data.preferences are NOT available in the
 * local test runner — only the pure functions are tested here.
 * The integrated `battleRouteUrl()` path (which reads AppStorage flags) is
 * verified by running the app on device and by build-time compilation
 * (static type-checking).
 */

export default function cocosBattlePreferenceTest() {
  describe('decideBattleRoute', () => {
    // Decision table (see CocosBattlePreference.ets header comment):
    //   cocos iff runtimeAvailable AND prefEnabled AND !fallbackActive AND !forceNative

    it('returnsCocos_whenAllConditionsMet', 0, () => {
      expect(decideBattleRoute(true, true, false, false)).assertEqual('cocos');
    });

    it('returnsNative_whenPrefDisabled', 0, () => {
      expect(decideBattleRoute(true, false, false, false)).assertEqual('native');
    });

    it('returnsNative_whenRuntimeUnavailable', 0, () => {
      expect(decideBattleRoute(false, true, false, false)).assertEqual('native');
    });

    it('returnsNative_whenFallbackActive', 0, () => {
      expect(decideBattleRoute(true, true, true, false)).assertEqual('native');
    });

    it('returnsNative_whenForceNative', 0, () => {
      expect(decideBattleRoute(true, true, false, true)).assertEqual('native');
    });

    it('returnsNative_whenAllFalse', 0, () => {
      expect(decideBattleRoute(false, false, true, true)).assertEqual('native');
    });

    it('returnsNative_whenBothFallbackAndForceNative', 0, () => {
      // Redundant but explicit: two override flags both independently force native.
      expect(decideBattleRoute(true, true, true, true)).assertEqual('native');
    });
  });

  describe('cocosBattlePrefEnabledFromRaw', () => {
    // iOS semantics: absent key (empty string) → true (default ON).

    it('returnsTrueWhenRawIsEmptyString', 0, () => {
      // Simulates absent key: preferences.get(key, '') returns '' when key
      // was never written.
      expect(cocosBattlePrefEnabledFromRaw('')).assertTrue();
    });

    it('returnsTrueWhenRawIsExplicitTrue', 0, () => {
      expect(cocosBattlePrefEnabledFromRaw('true')).assertTrue();
    });

    it('returnsFalseWhenRawIsExplicitFalse', 0, () => {
      expect(cocosBattlePrefEnabledFromRaw('false')).assertFalse();
    });

    it('returnsTrueWhenRawIsUnrecognised', 0, () => {
      // Any unrecognised value (e.g. corrupted store) falls back to the default ON.
      expect(cocosBattlePrefEnabledFromRaw('garbage')).assertTrue();
    });
  });

  describe('COCOS_BATTLE_PREF_KEY', () => {
    it('isExpectedValue', 0, () => {
      // Pin the constant so a typo-rename is caught immediately.
      expect(COCOS_BATTLE_PREF_KEY).assertEqual('battle.useCocosScene');
    });
  });
}
