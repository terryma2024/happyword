import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { clickByIdShared, tapConfigCancelShared } from './RoutingFlow.ui.test';

/**
 * V0.6 — parent-account binding lifecycle on ConfigPage.
 *
 * Coverage:
 *   1. unboundConfigPageRendersBindEntryOnly — fresh install: only
 *      `ConfigBindParentButton` is rendered; `ConfigBoundDeviceInfoButton`,
 *      `ConfigUnbindBindingButton`, and `ConfigCloudSyncButton` are
 *      absent (gated by `bindingPresent`).
 *   2. tapBindOpensScanBindingPage — tap the bind row; ScanBindingPage
 *      idle UI renders (打开扫码器 + 无法扫码？手动输入短码), and the
 *      back button returns to ConfigPage with the unbound row still
 *      visible.
 *   3. shortCodeRedeemFlipsConfigToBound — open ScanBindingPage, switch
 *      to manual entry, type a 6-digit short code, submit; the success
 *      panel appears (绑定成功). Back to ConfigPage; the bound rows
 *      (`ConfigBoundDeviceInfoButton`, `ConfigUnbindBindingButton`,
 *      `ConfigCloudSyncButton`) are now visible.
 *   4. unbindWithPinFlipsBackToUnbound — seed the parent PIN, tap
 *      `ConfigUnbindBindingButton`, type the PIN into ParentPinDialog;
 *      the unbind toast appears and ConfigPage flips back to showing
 *      `ConfigBindParentButton` with the bound rows hidden.
 *
 * All HTTP traffic is routed through the local mock at 127.0.0.1:8123
 * (see server/mock_ui_server.py: `/api/v1/pair/redeem` accepts any
 * 6-digit short code that is not 000000/111111/222222; `/api/v1/child/
 * unbind` clears the active binding for the deterministic mock JWT).
 */

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

const KNOWN_PIN: string = '123456';
const VALID_SHORT_CODE: string = '345678';

async function launchApp(): Promise<Driver> {
  const want: Want = { bundleName: BUNDLE, abilityName: 'EntryAbility' };
  await DELEGATOR.startAbility(want);
  const driver: Driver = Driver.create();
  await driver.delayMs(1200);
  return driver;
}

async function returnToHome(driver: Driver): Promise<void> {
  for (let i: number = 0; i < 6; i++) {
    const home: Component | null =
      await driver.findComponent(ON.id('HomeStartButton'));
    if (home !== null) {
      return;
    }
    await driver.pressBack();
    await driver.delayMs(500);
  }
}

async function openConfigPage(driver: Driver): Promise<void> {
  await clickByIdShared(driver, 'HomeConfigButton');
  await driver.delayMs(1500);
  // ConfigPage's outer Scroll() may carry over an offset from a
  // previous visit (HarmonyOS preserves scroll state across re-render
  // of the same page when the navigation is push/pop on the same
  // ability). Try to find the title; if not, swipe DOWN to reveal it.
  for (let attempt: number = 0; attempt < 3; attempt++) {
    const c: Component | null = await driver.findComponent(ON.id('ConfigTitle'));
    if (c !== null) {
      return;
    }
    await driver.swipe(1400, 300, 1400, 1100, 600);
    await driver.delayMs(400);
  }
  await driver.assertComponentExist(ON.id('ConfigTitle'));
}

/**
 * The parent-account row sits between `ConfigParentPinButton` and the
 * sync row, well below the fold on the landscape OpenHarmony emulator.
 * One upward swipe brings it into view; mirrors the pattern used by
 * `openConfigAndScrollToSync` in ConfigSyncFlow.ui.test.ets.
 */
async function scrollConfigToParentAccountRow(driver: Driver): Promise<void> {
  await driver.swipe(1400, 1100, 1400, 300, 600);
  await driver.delayMs(400);
}

async function exitConfigPage(driver: Driver): Promise<void> {
  // The form may have been scrolled up; tapConfigCancelShared performs
  // additional swipes if needed before tapping 取消.
  await tapConfigCancelShared(driver);
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('HomeStartButton'));
}

async function tapPinSetupKey(driver: Driver, key: string): Promise<void> {
  await clickByIdShared(driver, `ParentPinSetupKey_${key}`);
  await driver.delayMs(80);
}

async function tapPinDialogKey(driver: Driver, key: string): Promise<void> {
  await clickByIdShared(driver, `ParentPinDialogKey_${key}`);
  await driver.delayMs(80);
}

/**
 * Idempotent PIN seeder. Mirrors ParentAdminFlow's helper. Re-committing
 * the same PIN is a no-op from the operator's perspective — the
 * ParentPinSetupPage commitOrReset() persists firstBuf into AppStorage
 * and routes back to ConfigPage either way.
 */
async function ensureParentPin(driver: Driver, pin: string): Promise<void> {
  await openConfigPage(driver);
  // Scroll until the parent-PIN button is in view. The form grew with
  // V0.6.2/.4/.7 additions so a single swipe is no longer guaranteed.
  for (let attempt: number = 0; attempt < 4; attempt++) {
    const c: Component | null =
      await driver.findComponent(ON.id('ConfigParentPinButton'));
    if (c !== null) {
      break;
    }
    await driver.swipe(1400, 1100, 1400, 300, 600);
    await driver.delayMs(400);
  }
  await clickByIdShared(driver, 'ConfigParentPinButton');
  await driver.delayMs(1500);
  for (let i: number = 0; i < pin.length; i++) {
    await tapPinSetupKey(driver, pin.charAt(i));
  }
  await driver.delayMs(500);
  for (let i: number = 0; i < pin.length; i++) {
    await tapPinSetupKey(driver, pin.charAt(i));
  }
  await driver.delayMs(1800);
  // commitOrReset routes back to ConfigPage on success — same scroll
  // behaviour, so re-find ConfigTitle defensively.
  for (let attempt: number = 0; attempt < 3; attempt++) {
    const c: Component | null = await driver.findComponent(ON.id('ConfigTitle'));
    if (c !== null) {
      break;
    }
    await driver.swipe(1400, 300, 1400, 1100, 600);
    await driver.delayMs(400);
  }
  await exitConfigPage(driver);
}

/**
 * Attempt to find the bound-device button on ConfigPage by polling for
 * up to `maxMs` since the binding state is loaded asynchronously in
 * `aboutToAppear` (`refreshBindingState` reads from preferences via an
 * await chain). Returns true if the button surfaces in time.
 */
async function waitForBoundButton(driver: Driver, maxMs: number): Promise<boolean> {
  const stepMs: number = 250;
  let waited: number = 0;
  while (waited < maxMs) {
    const c: Component | null =
      await driver.findComponent(ON.id('ConfigBoundDeviceInfoButton'));
    if (c !== null) {
      return true;
    }
    await driver.delayMs(stepMs);
    waited += stepMs;
  }
  return false;
}

async function waitForBindEntryButton(driver: Driver, maxMs: number): Promise<boolean> {
  const stepMs: number = 250;
  let waited: number = 0;
  while (waited < maxMs) {
    const c: Component | null =
      await driver.findComponent(ON.id('ConfigBindParentButton'));
    if (c !== null) {
      return true;
    }
    await driver.delayMs(stepMs);
    waited += stepMs;
  }
  return false;
}

async function waitForUnbindToast(driver: Driver, maxMs: number): Promise<string> {
  const stepMs: number = 250;
  let waited: number = 0;
  while (waited < maxMs) {
    const c: Component | null =
      await driver.findComponent(ON.id('ConfigUnbindToast'));
    if (c !== null) {
      const t: string = await c.getText();
      if (t.length > 0) {
        return t;
      }
    }
    await driver.delayMs(stepMs);
    waited += stepMs;
  }
  return '';
}

export default function parentBindingFlowV06UiTest(): void {
  describe('ParentBindingFlowV06', () => {
    /**
     * Fresh install ConfigPage: only the unbound entry button renders.
     * The bound-only buttons (`ConfigBoundDeviceInfoButton`,
     * `ConfigUnbindBindingButton`, `ConfigCloudSyncButton`) are gated
     * by `bindingPresent` and must be absent on first launch.
     */
    it('unboundConfigPageRendersBindEntryOnly', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfigPage(driver);
      await scrollConfigToParentAccountRow(driver);

      // Bind row should be visible immediately after the binding-state
      // refresh resolves.
      const haveBind: boolean = await waitForBindEntryButton(driver, 5000);
      expect(haveBind).assertTrue();

      const bound: Component | null =
        await driver.findComponent(ON.id('ConfigBoundDeviceInfoButton'));
      expect(bound === null).assertTrue();

      const unbind: Component | null =
        await driver.findComponent(ON.id('ConfigUnbindBindingButton'));
      expect(unbind === null).assertTrue();

      const cloudSync: Component | null =
        await driver.findComponent(ON.id('ConfigCloudSyncButton'));
      expect(cloudSync === null).assertTrue();

      await exitConfigPage(driver);
      done();
    });

    /**
     * Bind row taps into ScanBindingPage. Verify the idle prompt and
     * the manual short-code entry UI render, then back returns to a
     * ConfigPage that is still in the unbound state.
     */
    it('tapBindOpensScanBindingPage', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfigPage(driver);
      await scrollConfigToParentAccountRow(driver);

      const haveBind: boolean = await waitForBindEntryButton(driver, 5000);
      expect(haveBind).assertTrue();
      await clickByIdShared(driver, 'ConfigBindParentButton');
      await driver.delayMs(1500);

      // ScanBindingPage idle UI: scanner button + manual fallback.
      await driver.assertComponentExist(ON.id('ScanBindingTitle'));
      await driver.assertComponentExist(ON.id('ScanBindingScannerButton'));
      await driver.assertComponentExist(ON.id('ScanBindingManualToggle'));

      // Switch to manual mode and assert the input + submit appear.
      await clickByIdShared(driver, 'ScanBindingManualToggle');
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('ScanBindingManualInput'));
      await driver.assertComponentExist(ON.id('ScanBindingManualSubmit'));
      await driver.assertComponentExist(ON.id('ScanBindingManualBackToScan'));

      // Flip back to scan mode (in-page state), then leave the page via
      // the top "返回" button so we land on ConfigPage deterministically
      // (pressBack on this page sometimes pops past ConfigPage).
      await clickByIdShared(driver, 'ScanBindingManualBackToScan');
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('ScanBindingScannerButton'));

      await clickByIdShared(driver, 'ScanBindingTopBack');
      await driver.delayMs(1500);

      // Returning from a pushed page restores ConfigPage's prior
      // scroll offset (we scrolled to the parent-account row). The
      // bind entry should still be visible because that's exactly
      // where we left the scroll.
      const stillBind: boolean = await waitForBindEntryButton(driver, 8000);
      expect(stillBind).assertTrue();

      await exitConfigPage(driver);
      done();
    });

    /**
     * Drive the manual short-code redeem path end-to-end through the
     * mock server. After a successful redeem, ScanBindingPage shows
     * 绑定成功; tapping 返回首页 routes back via router.back() to
     * ConfigPage, which now flips into bound state.
     */
    it('shortCodeRedeemFlipsConfigToBound', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfigPage(driver);
      await scrollConfigToParentAccountRow(driver);

      const haveBind: boolean = await waitForBindEntryButton(driver, 5000);
      expect(haveBind).assertTrue();
      await clickByIdShared(driver, 'ConfigBindParentButton');
      await driver.delayMs(1500);

      await clickByIdShared(driver, 'ScanBindingManualToggle');
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('ScanBindingManualInput'));

      // Type the 6-digit code into the input. inputText replaces the
      // existing content (empty here on first manual-mode entry).
      const input: Component =
        await driver.findComponent(ON.id('ScanBindingManualInput'));
      await input.inputText(VALID_SHORT_CODE);
      await driver.delayMs(500);

      // The numeric soft keyboard covers the lower half of the page,
      // hiding the submit button. pressBack dismisses the keyboard
      // without leaving the page.
      await driver.pressBack();
      await driver.delayMs(600);

      await clickByIdShared(driver, 'ScanBindingManualSubmit');
      // Wait for redeem round-trip + state flip — poll for success.
      let foundSuccess: boolean = false;
      for (let i: number = 0; i < 16; i++) {
        const c: Component | null =
          await driver.findComponent(ON.id('ScanBindingSuccessLabel'));
        if (c !== null) {
          foundSuccess = true;
          break;
        }
        await driver.delayMs(500);
      }
      expect(foundSuccess).assertTrue();

      // Tap "返回首页" (router.back to ConfigPage).
      await clickByIdShared(driver, 'ScanBindingSuccessBack');
      await driver.delayMs(1500);

      // The parent-account row should be in view (scroll preserved).
      // Bound state replaces "绑定家长账号" with the bound info button.
      const haveBound: boolean = await waitForBoundButton(driver, 8000);
      expect(haveBound).assertTrue();
      await driver.assertComponentExist(ON.id('ConfigUnbindBindingButton'));
      await driver.assertComponentExist(ON.id('ConfigCloudSyncButton'));

      await exitConfigPage(driver);
      done();
    });

    /**
     * Following the bound state from the previous case, seed the parent
     * PIN, then tap the unbind button. ParentPinDialog appears; correct
     * PIN auto-confirms and runs the unbind. After the toast appears
     * the page flips back to the unbound rendering.
     *
     * Order dependency: this case relies on `shortCodeRedeemFlipsConfig
     * ToBound` having left the device bound. List.test.ets schedules
     * the suite in declared order so this is safe.
     */
    it('unbindWithPinFlipsBackToUnbound', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);

      // Seed PIN. ensureParentPin returns to HomePage on completion.
      await ensureParentPin(driver, KNOWN_PIN);

      await openConfigPage(driver);
      await scrollConfigToParentAccountRow(driver);
      const haveBound: boolean = await waitForBoundButton(driver, 8000);
      if (!haveBound) {
        throw new Error('UNBIND-T1: bound info button not found at start');
      }
      await driver.assertComponentExist(ON.id('ConfigUnbindBindingButton'));

      await clickByIdShared(driver, 'ConfigUnbindBindingButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ParentPinDialog'));

      for (let i: number = 0; i < KNOWN_PIN.length; i++) {
        await tapPinDialogKey(driver, KNOWN_PIN.charAt(i));
      }
      // ParentPinDialog auto-dismisses on a correct PIN, then runUnbind
      // posts to /api/v1/child/unbind. Allow up to 8 s for round-trip.
      const toast: string = await waitForUnbindToast(driver, 8000);
      if (toast.length === 0) {
        throw new Error('UNBIND-T2: unbind toast never surfaced');
      }
      if (toast.indexOf('已解除') < 0) {
        throw new Error(`UNBIND-T3: unexpected toast text: ${toast}`);
      }

      // ConfigPage flips back to unbound — bind entry returns,
      // bound-only buttons disappear.
      const haveBind: boolean = await waitForBindEntryButton(driver, 8000);
      if (!haveBind) {
        throw new Error('UNBIND-T4: bind entry did not return after unbind');
      }
      const bound: Component | null =
        await driver.findComponent(ON.id('ConfigBoundDeviceInfoButton'));
      if (bound !== null) {
        throw new Error('UNBIND-T5: bound info button still visible after unbind');
      }
      const unbind: Component | null =
        await driver.findComponent(ON.id('ConfigUnbindBindingButton'));
      if (unbind !== null) {
        throw new Error('UNBIND-T6: unbind button still visible after unbind');
      }

      await exitConfigPage(driver);
      done();
    });
  });
}
