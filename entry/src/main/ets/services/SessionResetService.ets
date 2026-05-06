import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { CloudCredentials } from './CloudCredentials';

const PREFS_SYNC: string = 'wordmagic_cloud_sync';
const PREFS_WISHLIST: string = 'wordmagic_cloud_wishlist';

/**
 * Clears device binding + cloud-sync prefs so switching backends cannot leak
 * credentials across environments.
 */
export async function resetForEnvSwitch(ctx: common.UIAbilityContext): Promise<void> {
  const creds: CloudCredentials = new CloudCredentials();
  await creds.init(ctx);
  await creds.clearBinding();
  try {
    await preferences.deletePreferences(ctx, PREFS_SYNC);
  } catch (err) {
    console.error(`SessionReset.deletePreferences(${PREFS_SYNC}): ${JSON.stringify(err as BusinessError)}`);
  }
  try {
    await preferences.deletePreferences(ctx, PREFS_WISHLIST);
  } catch (err) {
    console.error(`SessionReset.deletePreferences(${PREFS_WISHLIST}): ${JSON.stringify(err as BusinessError)}`);
  }
}
