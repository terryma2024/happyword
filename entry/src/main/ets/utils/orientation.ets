import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

/**
 * V0.5.8: per-window portrait orientation lock for the parent admin
 * flow. Battle and home stay landscape (the app default), but the
 * admin pages prefer portrait because they are vertical lists of
 * forms / words.
 *
 * Lifecycle policy (see spec §6.2):
 *   - ParentAdminPage:        aboutToAppear + onPageShow → lockPortrait
 *                             aboutToDisappear           → restoreAutoLandscape
 *   - LessonDraftReviewPage:  aboutToAppear + onPageShow → lockPortrait
 *                             (no restore — outer page handles it)
 *
 * Helpers swallow adapter errors so a buggy emulator or runtime
 * denial still leaves the page usable (just in landscape).
 */

export type OrientationName = 'PORTRAIT' | 'AUTO_ROTATION_LANDSCAPE';

export interface IOrientationAdapter {
  setPreferredOrientation(name: OrientationName): Promise<void>;
}

export class RealOrientationAdapter implements IOrientationAdapter {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  async setPreferredOrientation(name: OrientationName): Promise<void> {
    // window.getLastWindow + Window.setPreferredOrientation can both
    // throw (window not ready, permission denied, etc.). The outer
    // helpers (lockPortrait / restoreAutoLandscape) catch + swallow,
    // but ArkTS still wants explicit handling at this call site.
    try {
      const win: window.Window = await window.getLastWindow(this.ctx);
      const target: window.Orientation = name === 'PORTRAIT'
        ? window.Orientation.PORTRAIT
        : window.Orientation.AUTO_ROTATION_LANDSCAPE;
      try {
        await win.setPreferredOrientation(target);
      } catch (e) {
        throw new Error(`setPreferredOrientation failed: ${JSON.stringify(e)}`);
      }
    } catch (e) {
      throw new Error(`getLastWindow failed: ${JSON.stringify(e)}`);
    }
  }
}

export async function lockPortrait(adapter: IOrientationAdapter): Promise<void> {
  try {
    await adapter.setPreferredOrientation('PORTRAIT');
  } catch (_e) {
    // Swallow — see spec §6.3 fallback.
  }
}

export async function restoreAutoLandscape(adapter: IOrientationAdapter): Promise<void> {
  try {
    await adapter.setPreferredOrientation('AUTO_ROTATION_LANDSCAPE');
  } catch (_e) {
    // Swallow.
  }
}
