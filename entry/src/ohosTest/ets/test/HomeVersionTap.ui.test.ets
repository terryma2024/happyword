import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';

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
 * V0.6 acceptance — debug-only version label triple-tap navigates
 * to DevMenuPage. Always runs in debug (ohosTest = debug build), so
 * the gate is always open here. Three cases:
 *   1. label exists,
 *   2. triple-tap navigates,
 *   3. spaced taps (gap > 1s) do not navigate.
 *
 * The two navigating cases end on DevMenuPage; both press Back at
 * the tail so subsequent suites still start on HomePage.
 */
export default function homeVersionTapUiTest(): void {
  describe('HomeVersionTap', () => {
    it('versionLabelExistsOnHome', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await driver.assertComponentExist(ON.id('HomeVersionLabel'));
      done();
    });

    it('tripleTapNavigatesToDevMenu', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      // Cache the Component once so all three taps go through the
      // same handle. clickByIdShared re-runs assertComponentExist +
      // findComponent on every call, which can take 300-500ms on a
      // slow emulator and blow out the triple-tap window.
      await driver.assertComponentExist(ON.id('HomeVersionLabel'));
      const label: Component = await driver.findComponent(ON.id('HomeVersionLabel'));
      await label.click();
      await driver.delayMs(150);
      await label.click();
      await driver.delayMs(150);
      await label.click();
      await driver.delayMs(2000);
      // DevMenuPage signal: the "Developer options" header at the
      // top of the page is unique to DevMenuPage and visible without
      // scrolling. The Apply button is below the fold once cards
      // populate the manifest list, so findComponent(ON.text('Apply'))
      // can return null even when navigation succeeded.
      const devMenuHeader: Component | null = await driver.findComponent(ON.text('Developer options'));
      expect(devMenuHeader !== null).assertTrue();
      // HomeStartButton must NOT be present any more.
      const homeStart: Component | null = await driver.findComponent(ON.id('HomeStartButton'));
      expect(homeStart === null).assertTrue();
      // Cleanup so the next case starts on HomePage.
      await driver.pressBack();
      await driver.delayMs(500);
      done();
    });

    it('gapExceedingWindowDoesNotFire', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await driver.assertComponentExist(ON.id('HomeVersionLabel'));
      const label: Component = await driver.findComponent(ON.id('HomeVersionLabel'));
      await label.click();
      await driver.delayMs(150);
      await label.click();
      // 2500ms wait > 1500ms window — counter resets so the 3rd tap
      // starts a fresh count instead of completing a triple-tap.
      await driver.delayMs(2500);
      await label.click();
      await driver.delayMs(800);
      // Still on HomePage.
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      // DevMenuPage's header text must NOT be present.
      const devMenuHeader: Component | null = await driver.findComponent(ON.text('Developer options'));
      expect(devMenuHeader === null).assertTrue();
      done();
    });
  });
}
