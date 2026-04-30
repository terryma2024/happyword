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

async function openWishlist(driver: Driver): Promise<void> {
  await clickByIdShared(driver, 'HomeWishlistButton');
  await driver.delayMs(1500);
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
 * Mirror WishlistFlow.ensureParentPin so this suite is self-sufficient.
 * Idempotent re-commit is fine — the parent PIN persists across pages
 * via GameConfig in AppStorage.
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

async function enterPin(driver: Driver, pin: string): Promise<void> {
  for (let i: number = 0; i < pin.length; i++) {
    await tapPinDialogKey(driver, pin.charAt(i));
  }
  await driver.delayMs(400);
}

/**
 * V0.4.7 acceptance for parent-created custom wishlist entries.
 *
 *  - WishlistAddCustomButton renders alongside the existing history
 *    button on the WishlistPage header.
 *  - Default catalog wishes do NOT show a ✕ button.
 *  - Tapping the add button opens ParentPinDialog; entering the
 *    correct PIN advances to AddCustomWishDialog whose three input
 *    fields and submit/cancel buttons all render with their
 *    documented ids.
 *
 * The full add+remove flows (typing into TextInput on the simulator
 * brings up the soft IME which obscures the Submit button + races
 * with @CustomDialog autoCancel; the system AlertDialog from
 * promptAction.showDialog is a separate window that uitest cannot
 * inspect by id) are exercised by unit tests
 * (`WishlistStore.addCustomWish*` + `removeCustomWish*` +
 * `validateCustomWishForm`).
 */
export default function customWishlistFlowUiTest(): void {
  describe('CustomWishlistFlowV047', () => {
    it('addCustomButtonRendersOnWishlistAndDefaultsHaveNoRemove', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openWishlist(driver);

      await driver.assertComponentExist(ON.id('WishlistAddCustomButton'));
      await driver.assertComponentExist(ON.text('+ 添加'));

      // Default catalog wishes do not show a remove button: their
      // ids are `wish-…` and our ✕ id is keyed `WishRemove_…`.
      const remove: Component | null =
        await driver.findComponent(ON.id('WishRemove_wish-ipad-20min'));
      expect(remove === null).assertTrue();

      await driver.pressBack();
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    it('addCustomDialogOpensAfterCorrectPin', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, '123456');

      await openWishlist(driver);
      await driver.assertComponentExist(ON.id('WishlistAddCustomButton'));

      // Tap add → ParentPinDialog appears.
      await clickByIdShared(driver, 'WishlistAddCustomButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ParentPinDialog'));

      // Correct PIN dismisses ParentPinDialog and opens
      // AddCustomWishDialog. We assert each new id renders so a
      // future regression to the dispatch routing (V0.4.7
      // pendingPinIntent) surfaces here.
      await enterPin(driver, '123456');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('AddCustomWishDialog'));
      await driver.assertComponentExist(ON.id('AddCustomWishNameInput'));
      await driver.assertComponentExist(ON.id('AddCustomWishCostInput'));
      await driver.assertComponentExist(ON.id('AddCustomWishEmojiInput'));
      await driver.assertComponentExist(ON.id('AddCustomWishSubmitButton'));
      await driver.assertComponentExist(ON.id('AddCustomWishCancelButton'));

      // Cancel out so we leave the page clean for subsequent suites.
      await clickByIdShared(driver, 'AddCustomWishCancelButton');
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('WishlistTitle'));

      await driver.pressBack();
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });
  });
}
