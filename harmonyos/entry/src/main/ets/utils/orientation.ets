import display from '@ohos.display';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

/**
 * Runtime page orientation policy.
 *
 * Phone:
 *   - listed child/game/debug pages stay landscape.
 *   - listed list/form/parent pages stay portrait.
 * Pad:
 *   - every page releases to full auto-rotation.
 *
 * Helpers swallow adapter errors so a buggy emulator or runtime
 * denial still leaves the page usable.
 */

export type OrientationName = 'PORTRAIT' | 'AUTO_ROTATION_LANDSCAPE' | 'AUTO_ROTATION';

export const PAD_SHORT_EDGE_BREAKPOINT_VP: number = 600;
const PHONE_SHORT_EDGE_FALLBACK_VP: number = 360;

const PHONE_PORTRAIT_PAGES: string[] = [
  'ConfigPage',
  'TodayPlanPage',
  'CheckInPage',
  'PackManagerPage',
  'LearningReportPage',
  'RedemptionHistoryPage',
  'ParentPinSetupPage',
  'ScanBindingPage',
  'BoundDeviceInfoPage',
  'ParentAdminPage',
  'LessonDraftReviewPage',
];

export interface IOrientationAdapter {
  setPreferredOrientation(name: OrientationName): Promise<void>;
}

function pageNameIn(list: string[], pageName: string): boolean {
  for (let i = 0; i < list.length; i++) {
    if (list[i] === pageName) {
      return true;
    }
  }
  return false;
}

export function desiredOrientationForPage(pageName: string, shortEdgeVp: number): OrientationName {
  if (shortEdgeVp >= PAD_SHORT_EDGE_BREAKPOINT_VP) {
    return 'AUTO_ROTATION';
  }
  if (pageNameIn(PHONE_PORTRAIT_PAGES, pageName)) {
    return 'PORTRAIT';
  }
  return 'AUTO_ROTATION_LANDSCAPE';
}

export function readCurrentShortEdgeVp(pxToVp: (px: number) => number): number {
  try {
    const d: display.Display = display.getDefaultDisplaySync();
    const widthVp: number = pxToVp(d.width);
    const heightVp: number = pxToVp(d.height);
    return Math.min(widthVp, heightVp);
  } catch (_e) {
    return PHONE_SHORT_EDGE_FALLBACK_VP;
  }
}

export async function applyPageOrientation(
  adapter: IOrientationAdapter,
  pageName: string,
  shortEdgeVp: number,
): Promise<void> {
  try {
    await adapter.setPreferredOrientation(desiredOrientationForPage(pageName, shortEdgeVp));
  } catch (_e) {
    // Orientation is best-effort; pages remain usable if the runtime denies it.
  }
}

export function requestPageOrientation(
  ctx: common.UIAbilityContext,
  pageName: string,
  pxToVp: (px: number) => number,
): void {
  const adapter: IOrientationAdapter = new RealOrientationAdapter(ctx);
  const shortEdgeVp: number = readCurrentShortEdgeVp(pxToVp);
  applyPageOrientation(adapter, pageName, shortEdgeVp).catch((_e: Error): void => {
    // applyPageOrientation already swallows runtime orientation failures.
  });
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
        : name === 'AUTO_ROTATION'
          ? window.Orientation.AUTO_ROTATION
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
