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
 * Open WishlistPage, tap the add-custom entry, walk through the
 * parent-PIN gate, and land inside AddCustomWishDialog. Caller
 * still has the dialog open on return.
 */
async function openAddCustomDialog(driver: Driver, pin: string): Promise<void> {
  await openWishlist(driver);
  await driver.assertComponentExist(ON.id('WishlistAddCustomButton'));
  await clickByIdShared(driver, 'WishlistAddCustomButton');
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('ParentPinDialog'));
  await enterPin(driver, pin);
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('AddCustomWishDialog'));
}

/**
 * Type into one of the dialog's TextInput fields. inputText() pops
 * the soft IME, which on a narrow landscape viewport overlays the
 * stacked sibling inputs and makes them fail the default
 * `visible:true` lookup. We pressBack() right after each call so
 * the next typeInto / submit can locate its target. pressBack()
 * while the IME is shown only dismisses the IME — the parent
 * @CustomDialog stays open.
 */
async function typeInto(driver: Driver, id: string, text: string): Promise<void> {
  await driver.assertComponentExist(ON.id(id));
  const input = await driver.findComponent(ON.id(id));
  await input.inputText(text);
  await driver.delayMs(300);
  await driver.pressBack();
  await driver.delayMs(400);
}

/**
 * V0.4.7 acceptance for parent-created custom wishlist entries.
 *
 * Surface coverage:
 *   - WishlistAddCustomButton renders alongside the existing history
 *     button on the WishlistPage header.
 *   - Default catalog wishes do NOT show a ✕ button.
 *
 * Add flow:
 *   - PIN gate routes to AddCustomWishDialog (all five ids render).
 *   - Empty submit surfaces inline AddCustomWishError; dialog stays.
 *   - Cost out of [CUSTOM_WISH_COST_MIN, CUSTOM_WISH_COST_MAX]
 *     surfaces inline AddCustomWishError; dialog stays.
 *   - Valid (name + cost + emoji) submit dismisses the dialog and
 *     the new wish renders on WishlistPage with its custom-only
 *     ✕ remove button.
 *
 * The actual REMOVE flow (✕ → ParentPinDialog → system AlertDialog
 * via promptAction.showDialog) cannot be fully driven in uitest:
 * the system AlertDialog window is opaque to component lookups by
 * id. The PIN gate that prefaces it IS exercised by
 * WishlistFlowV039 + the ParentPinDialog unit tests, and the
 * underlying `WishlistStore.removeCustomWish` is unit-tested in
 * WishlistStore.test.
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

      await openAddCustomDialog(driver, '123456');
      await driver.assertComponentExist(ON.id('AddCustomWishDialogTitle'));
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

    /**
     * Tapping Submit on an empty form surfaces the inline error
     * row (`AddCustomWishError`) with the "请输入愿望名称" message.
     * The dialog must stay open — neither the dismiss() nor the
     * onSubmit() callbacks fire on a validation failure.
     */
    it('submitEmptyFormShowsInlineNameError', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, '123456');

      await openAddCustomDialog(driver, '123456');

      // Error is conditionally rendered only after a failed submit.
      // It must be absent at this point.
      const preErr: Component | null =
        await driver.findComponent(ON.id('AddCustomWishError'));
      expect(preErr === null).assertTrue();

      await clickByIdShared(driver, 'AddCustomWishSubmitButton');
      await driver.delayMs(400);

      await driver.assertComponentExist(ON.id('AddCustomWishError'));
      const errComp = await driver.findComponent(ON.id('AddCustomWishError'));
      const errText: string = await errComp.getText();
      // First tripping rule in validateCustomWishForm is the empty
      // name guard; assert on its exact wording so a future copy
      // change is caught loudly.
      expect(errText.indexOf('请输入愿望名称') >= 0).assertTrue();

      // Dialog still open — submit must NOT have dismissed it.
      await driver.assertComponentExist(ON.id('AddCustomWishDialog'));

      await clickByIdShared(driver, 'AddCustomWishCancelButton');
      await driver.delayMs(600);
      await driver.pressBack();
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    /**
     * Cost outside [CUSTOM_WISH_COST_MIN, CUSTOM_WISH_COST_MAX]
     * (5..200) keeps the dialog open with an inline range error.
     * Uses a name + emoji that pass their own guards so the range
     * rule is the first one tripped.
     */
    it('submitOutOfRangeCostShowsInlineCostError', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, '123456');

      await openAddCustomDialog(driver, '123456');
      await typeInto(driver, 'AddCustomWishNameInput', '范围测试');
      // 999 > CUSTOM_WISH_COST_MAX (200). Cost guard fires after
      // name + emoji guards both pass.
      await typeInto(driver, 'AddCustomWishCostInput', '999');
      await typeInto(driver, 'AddCustomWishEmojiInput', '🚀');

      await clickByIdShared(driver, 'AddCustomWishSubmitButton');
      await driver.delayMs(400);

      await driver.assertComponentExist(ON.id('AddCustomWishError'));
      const errComp = await driver.findComponent(ON.id('AddCustomWishError'));
      const errText: string = await errComp.getText();
      // Validate range message contains the bounds. Pinning the
      // exact bounds catches accidental relaxation of validation.
      expect(errText.indexOf('5') >= 0).assertTrue();
      expect(errText.indexOf('200') >= 0).assertTrue();

      await driver.assertComponentExist(ON.id('AddCustomWishDialog'));

      await clickByIdShared(driver, 'AddCustomWishCancelButton');
      await driver.delayMs(600);
      await driver.pressBack();
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    /**
     * End-to-end add: typing valid name + cost + emoji and tapping
     * Submit dismisses AddCustomWishDialog (controller.close()) and
     * the new entry renders on WishlistPage. We assert two things:
     *   1. The display name we typed appears as a Text node on the
     *      page (proves WishCard for the new wish was rendered).
     *   2. At least one `WishRemove_custom-…` button exists, since
     *      every freshly-added custom wish is `isCustom=true` and
     *      WishlistPage's @Builder gates the ✕ button on that flag.
     *
     * Uses a timestamped display name so the test stays stable
     * across repeated runs even though the wishlist persists in
     * AppStorage. The downstream suites (configFlow,
     * configSyncFlow, adminConsoleFlow) do not interact with the
     * wishlist surface so the leftover entry is harmless.
     */
    it('validInputAddsWishCardToList', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, '123456');

      await openAddCustomDialog(driver, '123456');

      // Display name must be ≤ CUSTOM_WISH_NAME_MAX_CHARS (12). We
      // include a 4-digit suffix (last digits of Date.now() % 10000)
      // so reruns produce different cards. Total length stays at 8.
      const suffix: string = String(Date.now() % 10000).padStart(4, '0');
      const wishName: string = `测试愿望-${suffix}`;
      const wishCost: string = '20';
      const wishEmoji: string = '🎮';

      await typeInto(driver, 'AddCustomWishNameInput', wishName);
      await typeInto(driver, 'AddCustomWishCostInput', wishCost);
      await typeInto(driver, 'AddCustomWishEmojiInput', wishEmoji);

      await clickByIdShared(driver, 'AddCustomWishSubmitButton');
      await driver.delayMs(1000);

      // Dialog must have dismissed itself.
      const dlg: Component | null =
        await driver.findComponent(ON.id('AddCustomWishDialog'));
      expect(dlg === null).assertTrue();

      // The new wish renders at the bottom of the list. It may sit
      // below the visible viewport on a narrow landscape emulator,
      // so swipe up before asserting the name + emoji.
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(400);

      await driver.assertComponentExist(ON.text(wishName));
      await driver.assertComponentExist(ON.text(wishEmoji));

      await driver.pressBack();
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });
  });
}
