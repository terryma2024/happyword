import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { application, Want, common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import http from '@ohos.net.http';
import preferences from '@ohos.data.preferences';
import { clickByIdShared, scrollToParentPinButton, tapConfigCancelShared } from './RoutingFlow.ui.test';
import {
  SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY,
  SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY,
} from '../../../main/ets/services/BarcodeImageDecoder';

/**
 * V0.6 — parent-account binding lifecycle on ConfigPage.
 *
 * Coverage:
 *   1. unboundConfigPageRendersBindEntryOnly — fresh install: only
 *      `ConfigBindParentButton` is rendered; `ConfigBoundDeviceInfoButton`
 *      and `ConfigCloudSyncButton` are absent (gated by `bindingPresent`).
 *   2. tapBindOpensScanBindingPage — tap the bind row; ScanBindingPage
 *      idle UI renders (打开扫码器 + 无法扫码？手动输入短码), and the
 *      back button returns to ConfigPage with the unbound row still
 *      visible.
 *   3. shortCodeRedeemFlipsConfigToBound — open ScanBindingPage, switch
 *      to manual entry, type a 6-digit short code, submit; the success
 *      panel appears (绑定成功). Back to ConfigPage; the bound rows
 *      (`ConfigBoundDeviceInfoButton`, `ConfigCloudSyncButton`) are now
 *      visible.
 *   4. unbindFromBoundDeviceInfoPageFlipsBackToUnbound — seed the parent
 *      PIN, tap `ConfigBoundDeviceInfoButton` to open BoundDeviceInfoPage,
 *      tap `BoundDeviceInfoUnbindButton`, type the PIN into ParentPinDialog;
 *      the unbind toast appears, the page auto-routes back, and ConfigPage
 *      flips back to showing `ConfigBindParentButton` with the bound rows
 *      hidden. (V0.6.7.2: the unbind row moved from ConfigPage to
 *      BoundDeviceInfoPage.)
 *
 * All HTTP traffic is routed through the local mock at 127.0.0.1:8123
 * (see server/mock_ui_server.py: `/api/v1/public/pair/redeem` accepts any
 * 6-digit short code that is not 000000/111111/222222; `/api/v1/family/_/
 * unbind` clears the active binding for the deterministic mock JWT).
 */

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

async function createEntryTestModuleContext(): Promise<common.Context> {
  try {
    const ability = await DELEGATOR.getCurrentTopAbility();
    const uiCtx: common.UIAbilityContext = ability.context as common.UIAbilityContext;
    return await application.createModuleContext(uiCtx, 'entry_test');
  } catch (err) {
    throw err as Error;
  }
}

const KNOWN_PIN: string = '123456';
const VALID_SHORT_CODE: string = '345678';

// Must match `PackManagerFlow.ui.test.ets` / `server/mock_ui_server.py` — after
// PackManager seeds a mock redeem, the device prefs + mock server must be
// reset before `unboundConfigPageRendersBindEntryOnly`.
const MOCK_BASE_URL: string = 'http://127.0.0.1:8123';
const MOCK_DEVICE_TOKEN: string = 'ui-mock-device-jwt';
const PREFS_CLOUD: string = 'wordmagic_cloud';

async function mockHttp(
  method: http.RequestMethod,
  path: string,
  body: string,
  bearer: string,
): Promise<string> {
  try {
    const req: http.HttpRequest = http.createHttp();
    try {
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      if (bearer.length > 0) {
        headers['Authorization'] = `Bearer ${bearer}`;
      }
      const opts: http.HttpRequestOptions = {
        method,
        header: headers,
        extraData: body,
        connectTimeout: 5000,
        readTimeout: 5000,
      };
      const resp: http.HttpResponse = await req.request(`${MOCK_BASE_URL}${path}`, opts);
      return typeof resp.result === 'string' ? resp.result : '';
    } catch (_err) {
      return '';
    } finally {
      try {
        req.destroy();
      } catch (_err) {
        // Best-effort destroy.
      }
    }
  } catch (_err) {
    return '';
  }
}

async function unbindMockBinding(): Promise<void> {
  await mockHttp(http.RequestMethod.POST, '/api/v1/family/_/unbind', '{}', MOCK_DEVICE_TOKEN);
}

async function wipeBoundDeviceState(): Promise<void> {
  try {
    const ability = await DELEGATOR.getCurrentTopAbility();
    const ctx: common.UIAbilityContext = ability.context as common.UIAbilityContext;
    const handle: preferences.Preferences =
      await preferences.getPreferences(ctx, PREFS_CLOUD);
    await handle.put('device_token', '');
    await handle.put('binding_id', '');
    await handle.put('family_id', '');
    await handle.put('child_profile_id', '');
    await handle.put('nickname', '');
    await handle.put('avatar_emoji', '');
    await handle.put('paired_at_ms', '0');
    await handle.flush();
  } catch (_err) {
    // Best-effort — same rationale as PackManagerFlow.wipeBoundDeviceState.
  }
}

/**
 * ParentBindingFlow runs after PackManagerFlow. PackManager may leave both
 * the mock server's binding slot and `wordmagic_cloud` prefs populated; the
 * first unbound-only case must start clean.
 */
async function resetMockAndPrefsToUnbound(): Promise<void> {
  await unbindMockBinding();
  await wipeBoundDeviceState();
}

async function launchApp(): Promise<Driver> {
  // ArkTS strict mode flags direct @kit calls as may-throw — wrap the
  // helper body in try/catch+rethrow to silence the warning while
  // preserving propagation to hypium's per-`it` handler.
  try {
    const want: Want = { bundleName: BUNDLE, abilityName: 'EntryAbility' };
    await DELEGATOR.startAbility(want);
    const driver: Driver = Driver.create();
    await driver.delayMs(1200);
    return driver;
  } catch (err) {
    throw err as Error;
  }
}

async function returnToHome(driver: Driver): Promise<void> {
  try {
    for (let i: number = 0; i < 12; i++) {
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

async function openConfigPage(driver: Driver): Promise<void> {
  try {
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
  } catch (err) {
    throw err as Error;
  }
}

/**
 * The parent-account row sits below `ConfigParentPinButton` and above
 * the sync row, well below the fold on the landscape OpenHarmony
 * emulator. V0.6.5.1 inserted the 📦 packPickerSection (5+ pack rows)
 * between autoSpeak and parentPin, so a single upward swipe is no
 * longer enough — iterate until the bind/bound button is on screen,
 * up to 5 attempts.
 */
async function scrollConfigToParentAccountRow(driver: Driver): Promise<void> {
  try {
    for (let attempt: number = 0; attempt < 5; attempt++) {
      const bind: Component | null =
        await driver.findComponent(ON.id('ConfigBindParentButton'));
      const bound: Component | null =
        await driver.findComponent(ON.id('ConfigBoundDeviceInfoButton'));
      if (bind !== null || bound !== null) {
        return;
      }
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(400);
    }
  } catch (err) {
    throw err as Error;
  }
}

async function exitConfigPage(driver: Driver): Promise<void> {
  try {
    // The form may have been scrolled up; tapConfigCancelShared performs
    // additional swipes if needed before tapping 取消.
    await tapConfigCancelShared(driver);
    await driver.delayMs(800);
    await driver.assertComponentExist(ON.id('HomeStartButton'));
  } catch (err) {
    throw err as Error;
  }
}

async function tapPinSetupKey(driver: Driver, key: string): Promise<void> {
  try {
    await clickByIdShared(driver, `ParentPinSetupKey_${key}`);
    await driver.delayMs(80);
  } catch (err) {
    throw err as Error;
  }
}

async function waitForParentPinSetupKeypad(driver: Driver, maxMs: number): Promise<boolean> {
  try {
    const stepMs: number = 300;
    let waited: number = 0;
    let nudge: number = 0;
    while (waited < maxMs) {
      const k: Component | null =
        await driver.findComponent(ON.id('ParentPinSetupKey_1'));
      if (k !== null) {
        return true;
      }
      nudge += 1;
      if (nudge % 4 === 0) {
        await driver.swipe(360, 880, 360, 420, 550);
      }
      await driver.delayMs(stepMs);
      waited += stepMs;
    }
    return false;
  } catch (err) {
    throw err as Error;
  }
}

async function tapPinDialogKey(driver: Driver, key: string): Promise<void> {
  try {
    await clickByIdShared(driver, `ParentPinDialogKey_${key}`);
    await driver.delayMs(80);
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Idempotent PIN seeder. Mirrors ParentAdminFlow's helper. Re-committing
 * the same PIN is a no-op from the operator's perspective — the
 * ParentPinSetupPage commitOrReset() persists firstBuf into AppStorage
 * and routes back to ConfigPage either way.
 */
async function ensureParentPin(driver: Driver, pin: string): Promise<void> {
  try {
    await openConfigPage(driver);
    await scrollToParentPinButton(driver);
    await clickByIdShared(driver, 'ConfigParentPinButton');
    const keypadReady: boolean = await waitForParentPinSetupKeypad(driver, 12000);
    if (!keypadReady) {
      throw new Error('ParentPinSetup keypad not reachable');
    }
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
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Attempt to find the bound-device button on ConfigPage by polling for
 * up to `maxMs` since the binding state is loaded asynchronously in
 * `aboutToAppear` (`refreshBindingState` reads from preferences via an
 * await chain). Returns true if the button surfaces in time.
 */
async function waitForBoundButton(driver: Driver, maxMs: number): Promise<boolean> {
  try {
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
  } catch (err) {
    throw err as Error;
  }
}

async function waitForBindEntryButton(driver: Driver, maxMs: number): Promise<boolean> {
  try {
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
  } catch (err) {
    throw err as Error;
  }
}

/**
 * V0.6.x — materialise the scan-binding QR fixture into the app
 * sandbox. Mirrors `ensureLessonImportFixtureOnDevice()` in
 * ParentAdminFlow.ui.test.ets: the PNG bytes are bundled in the
 * ohosTest module's rawfile
 * (`entry/src/ohosTest/resources/rawfile/scan_binding_qr_fixture.png`,
 * generated by `tools/generate_scan_binding_qr_fixture.py`); we copy
 * them to `<appCtx.tempDir>/<name>` once per ability lifetime, and
 * the AppStorage picker-override key points there.
 *
 * Why bundled rawfile + tempDir rather than `hdc file send`:
 * HarmonyOS NEXT's selinux blocks the bundle UID from reading
 * shell-writable paths like /data/local/tmp, and the system gallery
 * picker's URIs are version-specific datashare URIs. Going through
 * the app sandbox is the only stable path.
 */
const SCAN_QR_FIXTURE_NAME: string = 'scan_binding_qr_fixture.png';
const SCAN_QR_FIXTURE_PAYLOAD: string =
  'https://happyword.cool/p/uitestqr01';

async function ensureScanBindingQrFixtureOnDevice(): Promise<string> {
  try {
    const appCtx: common.Context = DELEGATOR.getAppContext();
    const dest: string = `${appCtx.tempDir}/${SCAN_QR_FIXTURE_NAME}`;
    if (fs.accessSync(dest)) {
      return dest;
    }
    const moduleCtx: common.Context = await createEntryTestModuleContext();
    const bytes: Uint8Array = await moduleCtx.resourceManager.getRawFileContent(
      SCAN_QR_FIXTURE_NAME,
    );
    const file: fs.File = await fs.open(
      dest,
      fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
    );
    try {
      await fs.write(file.fd, bytes.buffer);
    } finally {
      await fs.close(file);
    }
    return dest;
  } catch (err) {
    throw err as Error;
  }
}

async function waitForUnbindToast(driver: Driver, maxMs: number): Promise<string> {
  try {
    const stepMs: number = 250;
    let waited: number = 0;
    while (waited < maxMs) {
      const c: Component | null =
        await driver.findComponent(ON.id('BoundDeviceInfoUnbindToast'));
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
  } catch (err) {
    throw err as Error;
  }
}

export default function parentBindingFlowUiTest(): void {
  describe('ParentBindingFlow', () => {
    /**
     * Fresh install ConfigPage: only the unbound entry button renders.
     * The bound-only buttons (`ConfigBoundDeviceInfoButton`,
     * `ConfigCloudSyncButton`) are gated by `bindingPresent` and must
     * be absent on first launch. (V0.6.7.2: `ConfigUnbindBindingButton`
     * was removed; unbind lives on BoundDeviceInfoPage now.)
     */
    it('unboundConfigPageRendersBindEntryOnly', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await resetMockAndPrefsToUnbound();
      await openConfigPage(driver);
      await scrollConfigToParentAccountRow(driver);

      // Bind row should be visible immediately after the binding-state
      // refresh resolves.
      const haveBind: boolean = await waitForBindEntryButton(driver, 5000);
      expect(haveBind).assertTrue();

      const bound: Component | null =
        await driver.findComponent(ON.id('ConfigBoundDeviceInfoButton'));
      expect(bound === null).assertTrue();

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
      await resetMockAndPrefsToUnbound();
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

      // The scanner button MUST become enabled once bootstrapService
      // resolves — it gates on the @State `serviceReady` mirror of
      // `this.service !== undefined`. A regression to a plain field
      // (which ArkUI does not track for re-render) leaves the button
      // gated false forever and clicks become silent no-ops on real
      // devices. Poll up to 5 s for the bootstrap promise.
      let scannerEnabled: boolean = false;
      for (let attempt: number = 0; attempt < 20; attempt++) {
        const c: Component | null =
          await driver.findComponent(ON.id('ScanBindingScannerButton'));
        if (c !== null) {
          const enabled: boolean = await c.isEnabled();
          if (enabled) {
            scannerEnabled = true;
            break;
          }
        }
        await driver.delayMs(250);
      }
      expect(scannerEnabled).assertTrue();

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
      await resetMockAndPrefsToUnbound();
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
      // V0.6.7.2: `ConfigUnbindBindingButton` no longer exists — unbind
      // lives on BoundDeviceInfoPage (孩子档案页) instead.
      const haveBound: boolean = await waitForBoundButton(driver, 8000);
      expect(haveBound).assertTrue();
      await driver.assertComponentExist(ON.id('ConfigCloudSyncButton'));

      await exitConfigPage(driver);
      done();
    });

    /**
     * Following the bound state from the previous case, seed the parent
     * PIN, then drive the unbind flow from `pages/BoundDeviceInfoPage`
     * (孩子档案页 — opened by tapping `ConfigBoundDeviceInfoButton`).
     * ParentPinDialog appears; correct PIN auto-confirms and runs the
     * unbind. After the success toast surfaces, the page auto-pops back
     * to ConfigPage and the bound rows disappear.
     *
     * V0.6.7.2: the unbind row used to live on ConfigPage; this test
     * was rewritten to reflect the new single-source-of-truth layout.
     *
     * Order dependency: this case relies on `shortCodeRedeemFlipsConfig
     * ToBound` having left the device bound. List.test.ets schedules
     * the suite in declared order so this is safe.
     */
    it('unbindFromBoundDeviceInfoPageFlipsBackToUnbound', 0, async (done: Function) => {
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

      // Open BoundDeviceInfoPage by tapping the bound child profile entry.
      await clickByIdShared(driver, 'ConfigBoundDeviceInfoButton');
      await driver.delayMs(1500);
      await driver.assertComponentExist(ON.id('BoundDeviceInfoUnbindButton'));

      await clickByIdShared(driver, 'BoundDeviceInfoUnbindButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ParentPinDialog'));

      for (let i: number = 0; i < KNOWN_PIN.length; i++) {
        await tapPinDialogKey(driver, KNOWN_PIN.charAt(i));
      }
      // ParentPinDialog auto-dismisses on a correct PIN, then runUnbind
      // posts to /api/v1/family/_/unbind. Allow up to 8 s for round-trip.
      const toast: string = await waitForUnbindToast(driver, 8000);
      if (toast.length === 0) {
        throw new Error('UNBIND-T2: unbind toast never surfaced');
      }
      if (toast.indexOf('已解除') < 0) {
        throw new Error(`UNBIND-T3: unexpected toast text: ${toast}`);
      }

      // BoundDeviceInfoPage auto-pops back to ConfigPage ~600 ms after
      // the toast surfaces; ConfigPage's onPageShow then reloads the
      // binding state and flips the row to "绑定家长账号" (unbound).
      const haveBind: boolean = await waitForBindEntryButton(driver, 8000);
      if (!haveBind) {
        throw new Error('UNBIND-T4: bind entry did not return after unbind');
      }
      const bound: Component | null =
        await driver.findComponent(ON.id('ConfigBoundDeviceInfoButton'));
      if (bound !== null) {
        throw new Error('UNBIND-T5: bound info button still visible after unbind');
      }

      await exitConfigPage(driver);
      done();
    });

    /**
     * V0.6.x — pick a saved QR from the gallery, decode, and redeem
     * end-to-end through the local mock server.
     *
     * Two AppStorage overrides bypass system services that are
     * unstable on the OpenHarmony emulator:
     *   - SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY → makes the
     *     RealPhotoPickerAdapter return a fixed on-device path
     *     without showing the out-of-process system picker UI.
     *   - SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY → makes
     *     RealBarcodeImageDecoder return the pre-known QR payload
     *     without invoking @kit.ScanKit's detectBarcode.decode (which
     *     can't reliably read app-sandbox tempDir URIs on the emulator).
     *
     * The on-device PNG fixture is still copied (and asserted to
     * exist) to keep the picker-override seam honest: the file IS
     * surfaced to the production picker pipeline as the picked URI.
     *
     * Order: this case runs after unbindWithPinFlipsBackToUnbound
     * leaves the device unbound, so the bind-from-gallery path is
     * exercised cleanly (no "already bound" branch).
     */
    it('pickQrFromGalleryRedeemsAndFlipsToBound', 0, async (done: Function) => {
      const fixturePath: string = await ensureScanBindingQrFixtureOnDevice();
      expect(fs.accessSync(fixturePath)).assertTrue();

      AppStorage.setOrCreate<string>(
        SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY, fixturePath);
      AppStorage.setOrCreate<string>(
        SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY,
        SCAN_QR_FIXTURE_PAYLOAD);

      try {
        const driver: Driver = await launchApp();
        await returnToHome(driver);
        await openConfigPage(driver);
        await scrollConfigToParentAccountRow(driver);

        const haveBind: boolean = await waitForBindEntryButton(driver, 5000);
        expect(haveBind).assertTrue();
        await clickByIdShared(driver, 'ConfigBindParentButton');
        await driver.delayMs(1500);

        // The gallery button gates on `serviceReady` (same @State as
        // the scanner button). Poll until enabled to avoid racing
        // bootstrapService's async init chain.
        let galleryEnabled: boolean = false;
        for (let attempt: number = 0; attempt < 20; attempt++) {
          const c: Component | null =
            await driver.findComponent(ON.id('ScanBindingGalleryButton'));
          if (c !== null) {
            const enabled: boolean = await c.isEnabled();
            if (enabled) {
              galleryEnabled = true;
              break;
            }
          }
          await driver.delayMs(250);
        }
        expect(galleryEnabled).assertTrue();

        await clickByIdShared(driver, 'ScanBindingGalleryButton');

        // Picker stub returns the fixture path instantly; decoder
        // stub returns SCAN_QR_FIXTURE_PAYLOAD instantly; redeem
        // round-trips against the local mock. Poll up to 8 s for
        // the success label.
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
      } finally {
        AppStorage.delete(SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY);
        AppStorage.delete(SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY);
      }
      done();
    });
  });
}
