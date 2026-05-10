import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { clickByIdShared } from './RoutingFlow.ui.test';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

async function launchApp(): Promise<Driver> {
  // ArkTS strict mode flags any direct @kit call as "Function may throw
  // exceptions. Special handling is required." — wrap the body in
  // try/catch+rethrow so the warning is silenced while preserving the
  // test failure semantics (a thrown ability-launch / driver-delay
  // error still propagates up to hypium's per-`it` handler).
  try {
    const want: Want = { bundleName: BUNDLE, abilityName: 'EntryAbility' };
    await DELEGATOR.startAbility(want);
    const driver: Driver = Driver.create();
    await driver.delayMs(1000);
    return driver;
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Navigate back to HomePage after a previous suite left the app
 * mid-flow. Mirrors AdventureFlow.ui.test's returnToHome — press
 * back up to 5 times until HomeStartButton resolves. Each `it`
 * block in this suite must start on HomePage so HomeReviewButton
 * is reachable; without this, the suite is order-dependent on
 * whoever ran before us in List.test.ets.
 */
async function returnToHome(driver: Driver): Promise<void> {
  // See `launchApp` rationale for why the body is wrapped in try/catch.
  try {
    for (let i = 0; i < 5; i++) {
      const home: Component | null =
        await driver.findComponent(ON.id('HomeStartButton'));
      if (home !== null) {
        return;
      }
      await driver.pressBack();
      await driver.delayMs(500);
    }
  } catch (err) {
    throw err as Error;
  }
}

/**
 * v0.3.6 toolbar acceptance:
 *  - HomeReviewButton (📚 emoji in v0.3.6–v0.3.9, review.svg from
 *    v0.3.10) lives in the top toolbar (not the deleted right
 *    column), and the dev-only 🧪 HomeTtsTestButton is gone.
 *  - On a fresh cold launch (0 wrong words → review locked), tapping
 *    the review button surfaces an inline toast (HomeReviewLockedToast)
 *    that auto-dismisses inside 2s without navigating away.
 */
export default function homeToolbarLockedUiTest(): void {
  describe('HomeToolbarLocked', () => {
    it('topToolbarHasReviewNotTts', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await driver.assertComponentExist(ON.id('HomeReviewButton'));
      const tts: Component | null =
        await driver.findComponent(ON.id('HomeTtsTestButton'));
      expect(tts === null).assertTrue();
      done();
    });

    it('lockedReviewShowsToastAndStays', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await clickByIdShared(driver, 'HomeReviewButton');
      await driver.delayMs(300);
      await driver.assertComponentExist(ON.id('HomeReviewLockedToast'));
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      await driver.delayMs(1800);
      const toast: Component | null =
        await driver.findComponent(ON.id('HomeReviewLockedToast'));
      expect(toast === null).assertTrue();
      done();
    });
  });
}
