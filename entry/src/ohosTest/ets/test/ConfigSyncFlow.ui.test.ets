import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { clickByIdShared } from './RoutingFlow.ui.test';

/**
 * V0.5 client follow-up (VC0.5.B) acceptance: the manual word-pack
 * sync entry on ConfigPage. ConfigPage drops the silent background
 * refresh so a deliberate operator tap is the *only* thing that
 * pulls a fresh pack from the server, and the same row surfaces a
 * status line + transient toast describing the outcome.
 *
 * The two cases here are both navigation-only — they DO trigger a
 * real fetch against `SERVER_BASE_URL` (production by default), so
 * we tolerate either the `Updated` or `UpToDate` toast wording. The
 * exact pack version is non-deterministic (whatever happens to be
 * the latest published pack at the moment of the test run), so we
 * read the status text shape rather than pinning a specific schema
 * version number.
 */

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

async function launchApp(): Promise<Driver> {
  const want: Want = { bundleName: BUNDLE, abilityName: 'EntryAbility' };
  await DELEGATOR.startAbility(want);
  const driver: Driver = Driver.create();
  await driver.delayMs(1000);
  return driver;
}

async function returnToHome(driver: Driver): Promise<void> {
  for (let i: number = 0; i < 5; i++) {
    const home: Component | null =
      await driver.findComponent(ON.id('HomeStartButton'));
    if (home !== null) {
      return;
    }
    await driver.pressBack();
    await driver.delayMs(500);
  }
}

/**
 * Open ConfigPage and scroll the sync/admin row pair into view. The
 * narrow landscape emulator viewport is shorter than the form once
 * we appended ConfigSync* + ConfigAdminConsoleButton, so a single
 * swipe-up is required before any of the new V0.5 ids resolve.
 */
async function openConfigAndScrollToSync(driver: Driver): Promise<void> {
  await clickByIdShared(driver, 'HomeConfigButton');
  await driver.delayMs(1500);
  await driver.assertComponentExist(ON.id('ConfigTitle'));
  await driver.swipe(1400, 1100, 1400, 300, 600);
  await driver.delayMs(400);
}

/**
 * Wait up to `maxMs` for the ConfigSyncToast to appear, polling at
 * 250ms. The sync round-trip against the production server typically
 * lands within 1.5–4s on a warm emulator + CDN, but a cold Vercel
 * function can extend that to 8s; pick a 20s ceiling so we don't
 * flake on CDN cold-start. Returns the toast text (or empty string
 * when the toast never appeared, which the caller should assertFail).
 */
async function waitForSyncToast(driver: Driver, maxMs: number): Promise<string> {
  const stepMs: number = 250;
  let waited: number = 0;
  while (waited < maxMs) {
    const toast: Component | null =
      await driver.findComponent(ON.id('ConfigSyncToast'));
    if (toast !== null) {
      return await toast.getText();
    }
    await driver.delayMs(stepMs);
    waited += stepMs;
  }
  return '';
}

export default function configSyncFlowUiTest(): void {
  describe('ConfigSyncFlowV050B', () => {
    /**
     * The sync row is rendered under ConfigPage with both the button
     * (`ConfigSyncButton`) and the status text (`ConfigSyncStatus`).
     * The status text is non-empty even before any sync — it shows
     * either "尚未同步 (使用内置词库)" on a fresh install or the
     * cached schema version + fetched-at timestamp once a previous
     * run wrote one.
     */
    it('syncRowIsRendered', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfigAndScrollToSync(driver);

      await driver.assertComponentExist(ON.id('ConfigSyncButton'));
      await driver.assertComponentExist(ON.id('ConfigSyncStatus'));

      // Status text must be non-empty so it always conveys *something*
      // to the operator. Either of the two valid prefixes is fine.
      const statusComp = await driver.findComponent(ON.id('ConfigSyncStatus'));
      const status: string = await statusComp.getText();
      expect(status.length > 0).assertTrue();
      const looksValid: boolean =
        status.indexOf('尚未同步') >= 0 || status.indexOf('已缓存 schema') >= 0;
      expect(looksValid).assertTrue();

      // Bail back to Home cleanly so the next case starts fresh.
      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    /**
     * Tapping the sync button surfaces a transient toast and the
     * status text refreshes to the post-sync shape ("已缓存 schema vN
     * · 同步时间 ..."). We accept any of the success / up-to-date /
     * (rare) failure wordings so the test is deterministic against
     * production: what we're verifying is the wiring (button →
     * service → toast/status update), not a particular server state.
     */
    it('tappingSyncRefreshesStatusAndShowsToast', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfigAndScrollToSync(driver);

      await driver.assertComponentExist(ON.id('ConfigSyncButton'));
      await clickByIdShared(driver, 'ConfigSyncButton');

      // Wait for the toast (the sync result) to land. 20s is well
      // above the production round-trip even with a Vercel cold start.
      const toastText: string = await waitForSyncToast(driver, 20000);
      expect(toastText.length > 0).assertTrue();
      const recognisedToast: boolean =
        toastText.indexOf('已同步至') >= 0 ||
        toastText.indexOf('已是最新') >= 0 ||
        toastText.indexOf('同步失败') >= 0;
      expect(recognisedToast).assertTrue();

      // After the round-trip resolves, the status row shows either
      // the cached schema (success) or stays at "尚未同步" (network
      // failure preserved cache invariants). Both are acceptable
      // outputs — the row must just render *something* and not be
      // blanked out.
      const statusComp = await driver.findComponent(ON.id('ConfigSyncStatus'));
      const status: string = await statusComp.getText();
      expect(status.length > 0).assertTrue();

      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });
  });
}
