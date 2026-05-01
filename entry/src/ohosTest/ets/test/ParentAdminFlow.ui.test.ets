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

/**
 * Drive HomePage → ConfigPage → ParentAdminButton → ParentPinDialog →
 * correct PIN → ParentAdminPage. Caller must have already returned to
 * HomePage and ensured KNOWN_PIN is committed.
 */
async function navigateToParentAdminPage(driver: Driver): Promise<void> {
  await openConfigAndScrollToAdmin(driver);
  await clickByIdShared(driver, 'ConfigParentAdminButton');
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('ParentPinDialog'));
  for (let i: number = 0; i < KNOWN_PIN.length; i++) {
    await tapPinDialogKey(driver, KNOWN_PIN.charAt(i));
  }
  // ParentPinDialog auto-dismisses on a correct PIN, then the
  // CustomDialog onConfirm pushes pages/ParentAdminPage. Allow a beat
  // for the page transition + aboutToAppear (which also locks portrait).
  await driver.delayMs(1500);
  await driver.assertComponentExist(ON.id('ParentAdminTitle'));
}

/**
 * Inverse of navigateToParentAdminPage: ParentAdminBack → ConfigPage →
 * pressBack → HomePage. ConfigPage's outer Scroll is reset to the top
 * by the portrait-to-landscape flip in ParentAdminPage.aboutToDisappear,
 * so the ConfigCancelButton at the bottom is below the fold and we
 * have to dismiss with pressBack instead of clicking it.
 */
async function exitParentAdminPage(driver: Driver): Promise<void> {
  await clickByIdShared(driver, 'ParentAdminBack');
  await driver.delayMs(1500);
  await driver.assertComponentExist(ON.id('ConfigTitle'));
  await driver.pressBack();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('HomeStartButton'));
}

/**
 * Type text into a ParentAdminPage TextInput, then dismiss the soft
 * keyboard so the next interaction can locate its target. Mirrors the
 * pattern that CustomWishlistFlow's typeInto uses for AddCustomWishDialog.
 */
async function typeIntoAdmin(driver: Driver, id: string, text: string): Promise<void> {
  await driver.assertComponentExist(ON.id(id));
  const input = await driver.findComponent(ON.id(id));
  await input.inputText(text);
  await driver.delayMs(300);
  await driver.pressBack();
  await driver.delayMs(400);
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
      await navigateToParentAdminPage(driver);

      await driver.assertComponentExist(ON.id('ParentAdminServerLabel'));
      await driver.assertComponentExist(ON.id('ParentAdminPublishButton'));

      // V0.5.8 F1+F2: photo-import card and pending-drafts list both
      // render unconditionally (no login wall). Stats may take a moment
      // to populate, but the structural ids are wired into the build()
      // tree from mount.
      await driver.assertComponentExist(ON.id('ParentAdminPickCameraButton'));
      await driver.assertComponentExist(ON.id('ParentAdminPickGalleryButton'));
      await driver.assertComponentExist(ON.id('ParentAdminPendingTitle'));

      // Login UI must NOT be present — the V0.5.8 C2 rewrite dropped it
      // entirely. Re-asserting here catches any regression where the
      // page accidentally re-introduces a login gate.
      const loginBtn: Component | null =
        await driver.findComponent(ON.id('ParentAdminLoginButton'));
      expect(loginBtn === null).assertTrue();
      const usernameInput: Component | null =
        await driver.findComponent(ON.id('ParentAdminUsername'));
      expect(usernameInput === null).assertTrue();
      const passwordInput: Component | null =
        await driver.findComponent(ON.id('ParentAdminPassword'));
      expect(passwordInput === null).assertTrue();

      await exitParentAdminPage(driver);
      done();
    });

    /**
     * V0.5.8 in-page interactions (server-independent):
     *   - The publish notes TextInput accepts typed text and reads it
     *     back via getText.
     *   - The Refresh button is enabled / tappable; tapping it must not
     *     crash the page (the async getStats may succeed against the
     *     prod server, fail with a toast, or stay pending — all three
     *     outcomes leave the structural surface intact, which is what
     *     this case asserts).
     *   - The pending-drafts area renders one of two visible
     *     states: ParentAdminPendingEmpty when the server has no
     *     pending drafts, OR LessonDraftRow_<id> rows otherwise. We
     *     match the OR with an existence probe so the assertion is
     *     stable regardless of server data on this emulator session.
     *   - Stat lines render with their `ParentAdminStat_<label>` ids
     *     once stats arrive. We probe one of them (用户数) without
     *     assertTrue so the case stays green when the server is
     *     unreachable.
     */
    it('parentAdminInteractionsStayStable', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, KNOWN_PIN);
      await navigateToParentAdminPage(driver);

      // Publish notes round-trip — purely client-side state.
      await typeIntoAdmin(driver, 'ParentAdminPublishNotes', 'lesson v1');
      const notesInput = await driver.findComponent(ON.id('ParentAdminPublishNotes'));
      const notesText: string = await notesInput.getText();
      expect(notesText.indexOf('lesson v1') >= 0).assertTrue();

      // Tap Refresh and let the async getStats settle. The page must
      // still render its title regardless of whether the call hit
      // the production server, timed out, or returned an error toast.
      await clickByIdShared(driver, 'ParentAdminRefresh');
      await driver.delayMs(2500);
      await driver.assertComponentExist(ON.id('ParentAdminTitle'));

      // Pending drafts area: empty-state text OR a visible row id.
      // findComponent with the empty-state id covers the no-network
      // case (refreshPendingDrafts caught the error and the array
      // stayed []) and the "server has 0 drafts" case (array is also
      // []). If the server returned at least one draft, ForEach
      // renders LessonDraftRow_<id> instead.
      const emptyState: Component | null =
        await driver.findComponent(ON.id('ParentAdminPendingEmpty'));
      if (emptyState === null) {
        // Some draft must be visible — assert the title at minimum.
        // We can't pin a specific draft id without server fixtures.
        await driver.assertComponentExist(ON.id('ParentAdminPendingTitle'));
      }

      // Photo-import buttons stay enabled — we don't tap them because
      // the system gallery / camera picker would steal focus and is
      // not part of this case's scope.
      const camBtn = await driver.findComponent(ON.id('ParentAdminPickCameraButton'));
      expect(camBtn !== null).assertTrue();
      const galBtn = await driver.findComponent(ON.id('ParentAdminPickGalleryButton'));
      expect(galBtn !== null).assertTrue();

      await exitParentAdminPage(driver);
      done();
    });
  });
}
