import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import preferences from '@ohos.data.preferences';

export const PRIVACY_POLICY_URL: string = 'https://happyword.com.cn/privacy';
export const TERMS_OF_SERVICE_URL: string = 'https://happyword.com.cn/terms';
export const REPORT_CHANNEL_URL: string = 'https://happyword.com.cn/report_and_appeal';

export const PRIVACY_CONSENT_PREF_NAME: string = 'wordmagic_compliance';
export const PRIVACY_CONSENT_PREF_KEY: string = 'privacy_consent_v1';

export async function hasPrivacyConsent(ctx: common.UIAbilityContext): Promise<boolean> {
  try {
    const handle: preferences.Preferences =
      await preferences.getPreferences(ctx, PRIVACY_CONSENT_PREF_NAME);
    const v: preferences.ValueType = await handle.get(PRIVACY_CONSENT_PREF_KEY, false);
    return typeof v === 'boolean' ? v : false;
  } catch (err) {
    console.error(`hasPrivacyConsent failed: ${JSON.stringify(err as BusinessError)}`);
    return false;
  }
}

export async function savePrivacyConsent(ctx: common.UIAbilityContext): Promise<boolean> {
  try {
    const handle: preferences.Preferences =
      await preferences.getPreferences(ctx, PRIVACY_CONSENT_PREF_NAME);
    await handle.put(PRIVACY_CONSENT_PREF_KEY, true);
    await handle.flush();
    return true;
  } catch (err) {
    console.error(`savePrivacyConsent failed: ${JSON.stringify(err as BusinessError)}`);
    return false;
  }
}
