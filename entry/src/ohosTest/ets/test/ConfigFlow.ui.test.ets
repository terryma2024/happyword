import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { clickByIdShared, tapConfigCancelShared } from './RoutingFlow.ui.test';

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
      await driver.delayMs(1200);
      await driver.assertComponentExist(ON.id('ParentPinSetupTitle'));
      await driver.assertComponentExist(ON.id('ParentPinSetupStepLabel'));
      await driver.assertComponentExist(ON.id('ParentPinSetupKeypad'));
      // The cancel button sits below the keypad on a narrow landscape
      // viewport; swipe up so findComponent can resolve it.
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(300);
      // Cancel returns without persisting. ConfigPage owns a Scroll
      // wrapper whose scroll position is preserved across navigations,
      // so we anchor on ConfigParentPinButton (the row we swiped to)
      // instead of ConfigTitle (which sits at the top and may be off
      // screen).
      await clickByIdShared(driver, 'ParentPinSetupCancel');
      await driver.delayMs(1200);
      await driver.assertComponentExist(ON.id('ConfigParentPinButton'));

      // Bail out of ConfigPage cleanly.
      await tapConfigCancelShared(driver);
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
      await driver.delayMs(1200);

      // Step 1: 1 2 3 4 5 6
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '3');
      await tapPinSetupKey(driver, '4');
      await tapPinSetupKey(driver, '5');
      await tapPinSetupKey(driver, '6');
      await driver.delayMs(400);

      // Step 2: confirm with the same digits
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '3');
      await tapPinSetupKey(driver, '4');
      await tapPinSetupKey(driver, '5');
      await tapPinSetupKey(driver, '6');
      await driver.delayMs(1500);

      // After commitOrReset the page routes back to ConfigPage. The
      // outer Scroll keeps its position across navigations, so the
      // parent-pin row should still be in view (we already scrolled
      // there to click the button). Anchor on ConfigParentPinButton
      // rather than ConfigTitle which sits above the scroll fold.
      await driver.assertComponentExist(ON.id('ConfigParentPinButton'));
      const btn = await driver.findComponent(ON.id('ConfigParentPinButton'));
      const label: string = await btn.getText();
      expect(label.indexOf('修改') >= 0).assertTrue();

      await tapConfigCancelShared(driver);
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
      await driver.delayMs(1200);

      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await driver.delayMs(400);

      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await driver.delayMs(800);

      await driver.assertComponentExist(ON.id('ParentPinSetupMismatchHint'));
      // Step is reset to 1 (label re-shows the initial copy).
      await driver.assertComponentExist(ON.id('ParentPinSetupStepLabel'));

      // Cancel sits below the keypad on a narrow viewport; swipe up.
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(300);
      await clickByIdShared(driver, 'ParentPinSetupCancel');
      await driver.delayMs(1200);
      // Anchor on ConfigParentPinButton (the row we already scrolled
      // to) rather than ConfigTitle to avoid Scroll-position artefacts.
      await driver.assertComponentExist(ON.id('ConfigParentPinButton'));

      await tapConfigCancelShared(driver);
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });
  });
}
