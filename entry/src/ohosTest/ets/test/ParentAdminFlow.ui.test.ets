import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { clickByIdShared } from './RoutingFlow.ui.test';

/**
 * V0.5.8 acceptance: parent admin backend + parent-PIN gate.
 *
 * ConfigPage exposes `ConfigParentAdminButton`; tapping it either
 * nudges the operator to set up a parent PIN (when none is configured)
 * or pops the existing `ParentPinDialog` and routes to ParentAdminPage
 * on the correct PIN.
 *
 * V0.5.8 removed the JWT login UI. The parent admin page now renders
 * the stats / publish surface immediately on mount; we DO NOT assert
 * statsCard contents because that would require a live server.
 *
 * Order: this file MUST run after configFlowUiTest's
 * twoStepMatchPersistsPinAndUpdatesButtonLabel (which is what seeds
 * GameConfig.parentPin = "123456" into AppStorage). List.test.ets
 * registers it after that suite; if you reorder, also re-seed the
 * PIN here.
 */

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

/** PIN value committed by configFlowUiTest's twoStep test. */
const KNOWN_PIN: string = '123456';

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

async function openConfigAndScrollToAdmin(driver: Driver): Promise<void> {
  await clickByIdShared(driver, 'HomeConfigButton');
  await driver.delayMs(1500);
  await driver.assertComponentExist(ON.id('ConfigTitle'));
  // The admin row sits below the sync row at the very bottom of the
  // form. A single swipe-up is enough on the narrow landscape
  // emulator viewport to bring it into view.
  await driver.swipe(1400, 1100, 1400, 300, 600);
  await driver.delayMs(400);
}

async function tapPinDialogKey(driver: Driver, key: string): Promise<void> {
  await clickByIdShared(driver, `ParentPinDialogKey_${key}`);
  await driver.delayMs(80);
}

async function tapPinSetupKey(driver: Driver, key: string): Promise<void> {
  await clickByIdShared(driver, `ParentPinSetupKey_${key}`);
  await driver.delayMs(80);
}

/**
 * Idempotent PIN seeder. Mirrors WishlistFlow.ui.test.ets's
 * ensureParentPin so this suite can run independently of
 * configFlowUiTest's ordering. Re-committing the same PIN is a no-op
 * from the operator's perspective: ParentPinSetupPage's
 * commitOrReset() persists `firstBuf` into AppStorage and routes
 * back to ConfigPage either way.
 */
async function ensureParentPin(driver: Driver, pin: string): Promise<void> {
  await clickByIdShared(driver, 'HomeConfigButton');
  await driver.delayMs(1500);
  await driver.swipe(1400, 1100, 1400, 300, 600);
  await driver.delayMs(300);
  await clickByIdShared(driver, 'ConfigParentPinButton');
  await driver.delayMs(1200);

  for (let i: number = 0; i < pin.length; i++) {
    await tapPinSetupKey(driver, pin.charAt(i));
  }
  await driver.delayMs(400);
  for (let i: number = 0; i < pin.length; i++) {
    await tapPinSetupKey(driver, pin.charAt(i));
  }
  await driver.delayMs(1500);

  await clickByIdShared(driver, 'ConfigCancelButton');
  await driver.delayMs(800);
  await returnToHome(driver);
}

export default function parentAdminFlowUiTest(): void {
  describe('ParentAdminFlowV058', () => {
    /**
     * The admin entry button lives on ConfigPage just below the
     * sync row. Renders unconditionally — the parent-PIN guard is
     * applied on the click handler, not via visibility.
     */
    it('configHasAdminEntryButton', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfigAndScrollToAdmin(driver);

      await driver.assertComponentExist(ON.id('ConfigParentAdminButton'));
      const btn = await driver.findComponent(ON.id('ConfigParentAdminButton'));
      const label: string = await btn.getText();
      expect(label.indexOf('家长管理后台') >= 0).assertTrue();

      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    /**
     * With a configured PIN, tapping the admin entry pops the
     * `ParentPinDialog`. Wrong PIN keeps the dialog open and lights
     * up the inline error; pressBack then dismisses the dialog
     * without ever pushing ParentAdminPage onto the route stack.
     *
     * pressBack (rather than the in-dialog Cancel button) is the
     * dismissal channel because the keypad fills the dialog's full
     * height on the narrow landscape emulator viewport, leaving
     * `ParentPinDialogCancel` below the visible frame for findComponent.
     */
    it('adminButtonOpensPinDialogAndWrongPinStays', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      // Idempotent PIN seed — the configFlow twoStep test already
      // committed 123456, but re-seeding makes this case independent.
      await ensureParentPin(driver, KNOWN_PIN);

      await openConfigAndScrollToAdmin(driver);
      await clickByIdShared(driver, 'ConfigParentAdminButton');
      await driver.delayMs(800);

      await driver.assertComponentExist(ON.id('ParentPinDialog'));
      await driver.assertComponentExist(ON.id('ParentPinDialogTitle'));
      await driver.assertComponentExist(ON.id('ParentPinDialogKeypad'));

      // Wrong PIN: 000000 (KNOWN_PIN is 123456). Six taps fills
      // ParentPinDialog.buf, fails validatePin, fires the shake
      // animation and clears the buffer. The dialog STAYS open and
      // ParentAdminPage MUST NOT have been pushed.
      const wrong: string = '000000';
      for (let i: number = 0; i < wrong.length; i++) {
        await tapPinDialogKey(driver, wrong.charAt(i));
      }
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ParentPinDialog'));
      const adminTitle: Component | null =
        await driver.findComponent(ON.id('ParentAdminTitle'));
      expect(adminTitle === null).assertTrue();

      // Dismiss the dialog and confirm we're still on ConfigPage.
      await driver.pressBack();
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ConfigParentAdminButton'));
      const dialog: Component | null =
        await driver.findComponent(ON.id('ParentPinDialog'));
      expect(dialog === null).assertTrue();

      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    /**
     * Entering the correct 6-digit PIN auto-dismisses ParentPinDialog
     * and pushes ParentAdminPage. We assert the structural surface
     * (title, server label, publish button) and back out.
     *
     * V0.5.8 removed the JWT login UI, so the page surfaces stats /
     * publish directly. We do NOT assert stats values — that would
     * require a live server response.
     */
    it('correctPinNavigatesToParentAdmin', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, KNOWN_PIN);

      await openConfigAndScrollToAdmin(driver);
      await clickByIdShared(driver, 'ConfigParentAdminButton');
      await driver.delayMs(800);

      await driver.assertComponentExist(ON.id('ParentPinDialog'));
      for (let i: number = 0; i < KNOWN_PIN.length; i++) {
        await tapPinDialogKey(driver, KNOWN_PIN.charAt(i));
      }
      // ParentPinDialog auto-dismisses on a correct PIN, then the
      // CustomDialog onConfirm pushes pages/ParentAdminPage. Allow
      // a beat for the page transition + aboutToAppear.
      await driver.delayMs(1500);

      await driver.assertComponentExist(ON.id('ParentAdminTitle'));
      await driver.assertComponentExist(ON.id('ParentAdminServerLabel'));
      await driver.assertComponentExist(ON.id('ParentAdminPublishButton'));

      // Back button on ParentAdminPage routes back to ConfigPage.
      // ConfigPage's outer Scroll preserves its position across
      // navigations, so we anchor on the row we already scrolled to
      // (ConfigParentAdminButton) rather than ConfigTitle which
      // sits above the fold.
      await clickByIdShared(driver, 'ParentAdminBack');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ConfigParentAdminButton'));

      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });
  });
}
