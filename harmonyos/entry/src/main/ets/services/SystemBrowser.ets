import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';

/**
 * Opens `url` in the user's default system browser (implicit browsable URI).
 */
export async function openUrlInSystemBrowser(
  ctx: common.UIAbilityContext,
  url: string,
): Promise<void> {
  const want: Want = {
    action: 'ohos.want.action.viewData',
    entities: ['entity.system.browsable'],
    uri: url,
  };
  try {
    await ctx.startAbility(want);
  } catch (err) {
    const be: BusinessError = err as BusinessError;
    console.error(`openUrlInSystemBrowser failed: ${JSON.stringify(be)}`);
    const msg: string =
      be.message !== undefined && be.message.length > 0 ? be.message : JSON.stringify(be);
    throw new Error(msg);
  }
}
