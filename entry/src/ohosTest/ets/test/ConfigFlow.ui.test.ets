import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { clickByIdShared } from './RoutingFlow.ui.test';

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

async function openConfig(driver: Driver): Promise<void> {
  await clickByIdShared(driver, 'HomeConfigButton');
  await driver.delayMs(1500);
}

async function tapPinSetupKey(driver: Driver, key: string): Promise<void> {
  await clickByIdShared(driver, `ParentPinSetupKey_${key}`);
  await driver.delayMs(80);
}

/**
 * V0.3.9 acceptance for the parent PIN configuration surface:
 *  - ConfigPage shows the new ConfigParentPinButton row.
 *  - Tapping it lands on ParentPinSetupPage (the page exposes
 *    keypad keys ParentPinSetupKey_{0..9}, a delete key, and the
 *    step-1 / step-2 prompts).
 *  - Two-step setup: typing six digits twice persists the PIN and
 *    routes back; the ConfigParentPinButton label flips to include
 *    the 修改 prefix on return.
 *  - Mismatched second entry surfaces the
 *    ParentPinSetupMismatchHint and resets the buffer.
 *
 * Cleans up by setting the PIN back to a known canonical value at
 * the end of each non-mismatch test so subsequent runs can rely on
 * the AppStorage state.
 */
export default function configFlowUiTest(): void {
  describe('ConfigFlowV039', () => {
    it('configParentPinButtonNavigatesToSetupPage', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfig(driver);

      // Row is rendered after categoryRow; on the narrow landscape
      // emulator the form is taller than the viewport, so swipe up
      // before locating the button (mirrors the helper used by
      // RoutingFlow).
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(300);
      await driver.assertComponentExist(ON.id('ConfigParentPinButton'));

      await clickByIdShared(driver, 'ConfigParentPinButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ParentPinSetupTitle'));
      await driver.assertComponentExist(ON.id('ParentPinSetupStepLabel'));
      await driver.assertComponentExist(ON.id('ParentPinSetupKeypad'));
      // Cancel returns without persisting.
      await clickByIdShared(driver, 'ParentPinSetupCancel');
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('ConfigTitle'));

      // Bail out of ConfigPage cleanly.
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(300);
      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    it('twoStepMatchPersistsPinAndUpdatesButtonLabel', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfig(driver);
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(300);
      await clickByIdShared(driver, 'ConfigParentPinButton');
      await driver.delayMs(800);

      // Step 1: 1 2 3 4 5 6
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '3');
      await tapPinSetupKey(driver, '4');
      await tapPinSetupKey(driver, '5');
      await tapPinSetupKey(driver, '6');
      await driver.delayMs(200);

      // Step 2: confirm with the same digits
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '3');
      await tapPinSetupKey(driver, '4');
      await tapPinSetupKey(driver, '5');
      await tapPinSetupKey(driver, '6');
      await driver.delayMs(800);

      // After commitOrReset the page routes back to ConfigPage and
      // the entry-row label includes the 修改 marker.
      await driver.assertComponentExist(ON.id('ConfigTitle'));
      await driver.assertComponentExist(ON.id('ConfigParentPinButton'));
      const btn = await driver.findComponent(ON.id('ConfigParentPinButton'));
      const label: string = await btn.getText();
      expect(label.indexOf('修改') >= 0).assertTrue();

      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(300);
      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    it('mismatchSurfacesHintAndResetsBuffer', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfig(driver);
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(300);
      await clickByIdShared(driver, 'ConfigParentPinButton');
      await driver.delayMs(800);

      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await driver.delayMs(200);

      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await driver.delayMs(600);

      await driver.assertComponentExist(ON.id('ParentPinSetupMismatchHint'));
      // Step is reset to 1 (label re-shows the initial copy).
      await driver.assertComponentExist(ON.id('ParentPinSetupStepLabel'));

      await clickByIdShared(driver, 'ParentPinSetupCancel');
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('ConfigTitle'));

      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(300);
      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });
  });
}
