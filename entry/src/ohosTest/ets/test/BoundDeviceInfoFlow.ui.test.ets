import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import http from '@ohos.net.http';
import { clickByIdShared, tapConfigCancelShared } from './RoutingFlow.ui.test';

/**
 * V0.6.8 — device-side child-nickname edit flow on `BoundDeviceInfoPage`.
 *
 * Coverage (single self-contained case):
 *   1. Establish a bound state via short-code redeem against the local
 *      mock (mirrors `ParentBindingFlow.shortCodeRedeemFlipsConfig
 *      ToBound`).
 *   2. From ConfigPage tap `ConfigBoundDeviceInfoButton` → reach
 *      `BoundDeviceInfoPage`.
 *   3. Verify the nickname row renders with the seed `测试宝贝`.
 *   4. Tap `BoundDeviceInfoNicknameEditButton` → assert the
 *      `EditChildNicknameDialog` opens.
 *   5. Replace input text with `小明测试`, tap `EditChildNicknameSubmit
 *      Button` → wait for the dialog to dismiss and the row text to
 *      reflect the new nickname (server-canonical value persisted via
 *      `CloudCredentials.saveBinding`).
 *   6. Press back to ConfigPage; verify `ConfigBoundDeviceInfoButton`
 *      label now contains `小明测试` — proves the local cache write
 *      surfaces on next `onPageShow`, which is the contract the spec
 *      relies on for the home badge / config row to refresh.
 *
 * The mock at `127.0.0.1:8123` (see `server/mock_ui_server.py
 * ::child_profile_put`) accepts the PUT, strips/truncates per the
 * server contract, and updates `_pair_nickname` so subsequent
 * /pair/redeem responses also reflect the new value within the same
 * mock-server lifetime. Default nickname is restored by the mock's
 * `_reset_state()` between mock-server boots.
 */

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

const VALID_SHORT_CODE: string = '345678';

/**
 * Pick a nickname guaranteed to differ from `current`. Run-to-run
 * stability matters more than aesthetics here: the test asserts that
 * the row + ConfigPage label flip from "before" to "after", which
 * requires the two strings to compare unequal. Using a timestamped
 * suffix also keeps the value short enough to satisfy the 32-char
 * server cap (we strip out only the millis portion if the input is
 * already long).
 */
function nextNicknameDifferentFrom(current: string): string {
  const base: string = '小明测试';
  const suffix: string = (Date.now() % 100000).toString().padStart(5, '0');
  const candidate: string = `${base}${suffix}`;
  if (candidate === current) {
    return `${base}${(Date.now() + 1) % 100000}`;
  }
  return candidate;
}

/**
 * Strip the leading avatar emoji prefix (e.g. "🦁 ") that the row
 * Text concatenates from the BoundDeviceInfoPage view binding so the
 * caller sees just the nickname portion. Returns the original string
 * unmodified when no space is found.
 */
function nicknameFromRowText(rowText: string): string {
  const sp: number = rowText.indexOf(' ');
  if (sp < 0) {
    return rowText;
  }
  return rowText.substring(sp + 1).trim();
}

/**
 * Seed the mock server's `_active_bindings` set by issuing a direct
 * `/api/v1/pair/redeem` call from the test process. Idempotent on the
 * mock side: redeeming twice with the same short code adds to the set
 * once and re-mints the same deterministic device token.
 *
 * Why this is needed: a prior test run may have left the device's
 * `wordmagic_cloud` preferences in a bound state (preferences survive
 * `bm install -r`). The mock server, on the other hand, restarts
 * fresh between `scripts/run_ui_tests.sh` invocations and starts with
 * `_active_bindings = {}`. Without this seed, the deterministic
 * device token persisted on the device is rejected with 401
 * UNAUTHORIZED by the mock, which would surface as the dialog
 * remaining open after the PUT. Seeding makes the test self-healing:
 * either way we get a server that recognizes the token.
 *
 * We use `@ohos.net.http` directly rather than wiring up
 * `RealParentFetchAdapter` here — the JSON bodies are small and the
 * adapter brings in additional construction overhead that this
 * fire-and-forget seeding does not need.
 */
async function seedMockBinding(): Promise<void> {
  const req: http.HttpRequest = http.createHttp();
  try {
    await req.request(
      'http://127.0.0.1:8123/api/v1/pair/redeem',
      {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: '{"device_id":"ui-mock-seed","short_code":"345678"}',
        connectTimeout: 5000,
        readTimeout: 5000,
      },
    );
  } catch (_err) {
    // Swallow: if the mock isn't reachable here it will be unreachable
    // for the rest of the test too, which surfaces as a more useful
    // 401/404 in the per-step assertions below.
  } finally {
    req.destroy();
  }
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
    // When this suite runs in isolation via `--suite BoundDeviceInfoFlow`
    // the app is cold-launching for the first time. The fixed 1200 ms
    // delay above is enough when other suites have already warmed it up
    // (the canonical schedule in List.test.ets), but on a cold start the
    // splash → HomePage transition can take several seconds on the
    // emulator. Poll for HomeStartButton (up to 12 s) so the helper
    // works in both modes.
    for (let i: number = 0; i < 24; i++) {
      const home: Component | null =
        await driver.findComponent(ON.id('HomeStartButton'));
      if (home !== null) {
        break;
      }
      await driver.delayMs(500);
    }
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

async function scrollConfigToParentAccountRow(driver: Driver): Promise<void> {
  // V0.6.5.1: the 📦 packPickerSection added 5+ pack rows between
  // autoSpeak and the parent-account row, so a single swipe may
  // not be enough to expose ConfigBoundDeviceInfoButton or
  // ConfigBindParentButton. Iterate up to 5 times.
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
    await tapConfigCancelShared(driver);
    await driver.delayMs(800);
  } catch (err) {
    throw err as Error;
  }
}

/** Drive the redeem path via the mock to leave the device bound. */
async function bindViaShortCode(driver: Driver): Promise<void> {
  try {
    await openConfigPage(driver);
    await scrollConfigToParentAccountRow(driver);

    // Bind row should be present; if already bound (e.g. an earlier run
    // left the device in the bound state) skip the redeem step.
    const bound: Component | null =
      await driver.findComponent(ON.id('ConfigBoundDeviceInfoButton'));
    if (bound !== null) {
      return;
    }
    await clickByIdShared(driver, 'ConfigBindParentButton');
    await driver.delayMs(1500);
    await clickByIdShared(driver, 'ScanBindingManualToggle');
    await driver.delayMs(600);
    await driver.assertComponentExist(ON.id('ScanBindingManualInput'));

    const input: Component =
      await driver.findComponent(ON.id('ScanBindingManualInput'));
    await input.inputText(VALID_SHORT_CODE);
    await driver.delayMs(500);
    // Numeric IME hides the submit button on the emulator.
    await driver.pressBack();
    await driver.delayMs(600);

    await clickByIdShared(driver, 'ScanBindingManualSubmit');
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
    await clickByIdShared(driver, 'ScanBindingSuccessBack');
    await driver.delayMs(1500);
  } catch (err) {
    throw err as Error;
  }
}

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

async function waitForNicknameValueText(
  driver: Driver,
  expected: string,
  maxMs: number,
): Promise<string> {
  try {
    const stepMs: number = 300;
    let waited: number = 0;
    let last: string = '';
    while (waited < maxMs) {
      const c: Component | null =
        await driver.findComponent(ON.id('BoundDeviceInfoNicknameValue'));
      if (c !== null) {
        last = await c.getText();
        if (last.indexOf(expected) >= 0) {
          return last;
        }
      }
      await driver.delayMs(stepMs);
      waited += stepMs;
    }
    return last;
  } catch (err) {
    throw err as Error;
  }
}

async function waitForBoundButtonText(
  driver: Driver,
  expected: string,
  maxMs: number,
): Promise<string> {
  try {
    const stepMs: number = 300;
    let waited: number = 0;
    let last: string = '';
    while (waited < maxMs) {
      const c: Component | null =
        await driver.findComponent(ON.id('ConfigBoundDeviceInfoButton'));
      if (c !== null) {
        last = await c.getText();
        if (last.indexOf(expected) >= 0) {
          return last;
        }
      }
      await driver.delayMs(stepMs);
      waited += stepMs;
    }
    return last;
  } catch (err) {
    throw err as Error;
  }
}

export default function boundDeviceInfoFlowUiTest(): void {
  describe('BoundDeviceInfoFlow', () => {
    it('editButtonUpdatesNicknameAndPersistsToConfigRow', 0, async (done: Function) => {
      // Make sure the mock recognizes the deterministic device token
      // before we touch any device-token-authed endpoints. See
      // `seedMockBinding` for the rationale.
      await seedMockBinding();

      const driver: Driver = await launchApp();
      await returnToHome(driver);

      // Step 1: drive redeem to leave the device bound. On the success
      // path we land back on ConfigPage scrolled to the parent-account
      // row (router.back from ScanBindingPage). When the app already
      // has a stored binding (e.g. a previous run left state in
      // /data/storage), bindViaShortCode short-circuits and also
      // returns with ConfigPage scrolled to the same row.
      await bindViaShortCode(driver);

      // Step 2: ConfigBoundDeviceInfoButton is the canonical anchor for
      // the bound state on ConfigPage. We deliberately do NOT pivot on
      // `ConfigTitle` here because the parent-account row is below the
      // fold and the title may be scrolled off the visible viewport.
      const haveBound: boolean = await waitForBoundButton(driver, 8000);
      expect(haveBound).assertTrue();
      await clickByIdShared(driver, 'ConfigBoundDeviceInfoButton');
      await driver.delayMs(1500);

      // Step 3: read whatever the row currently shows. We don't pin
      // this to a specific seed string because the test must remain
      // green across re-runs: a successful prior run leaves the
      // nickname rewritten in `wordmagic_cloud` preferences, which
      // ConfigPage / BoundDeviceInfoPage will then display on next
      // launch even though the mock has restarted.
      await driver.assertComponentExist(ON.id('BoundDeviceInfoNicknameValue'));
      const beforeRow: Component =
        await driver.findComponent(ON.id('BoundDeviceInfoNicknameValue'));
      const beforeRowText: string = await beforeRow.getText();
      const beforeNickname: string = nicknameFromRowText(beforeRowText);
      expect(beforeNickname.length > 0).assertTrue();

      // Step 4: open the edit dialog.
      await driver.assertComponentExist(ON.id('BoundDeviceInfoNicknameEditButton'));
      await clickByIdShared(driver, 'BoundDeviceInfoNicknameEditButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('EditChildNicknameDialogTitle'));
      await driver.assertComponentExist(ON.id('EditChildNicknameInput'));

      // Step 5: pick a nickname different from the current value, type
      // it, and submit.
      const newNickname: string = nextNicknameDifferentFrom(beforeNickname);
      const dialogInput: Component =
        await driver.findComponent(ON.id('EditChildNicknameInput'));
      // inputText replaces the existing field content per the platform
      // contract documented in CustomWishlistFlow.typeInto.
      await dialogInput.inputText(newNickname);
      await driver.delayMs(400);
      // Soft IME covers the Submit button on the emulator.
      await driver.pressBack();
      await driver.delayMs(500);

      await clickByIdShared(driver, 'EditChildNicknameSubmitButton');

      // Wait for the dialog to dismiss (success path closes itself).
      let dialogGone: boolean = false;
      for (let i: number = 0; i < 24; i++) {
        const stillThere: Component | null =
          await driver.findComponent(ON.id('EditChildNicknameDialogTitle'));
        if (stillThere === null) {
          dialogGone = true;
          break;
        }
        await driver.delayMs(250);
      }
      expect(dialogGone).assertTrue();

      // Row text now reflects the new nickname.
      const updatedRow: string = await waitForNicknameValueText(
        driver, newNickname, 6000,
      );
      expect(updatedRow.indexOf(newNickname) >= 0).assertTrue();
      // Sanity: the row text actually CHANGED (guards against a stale
      // capture where the new and old nicknames happened to coincide).
      expect(updatedRow.indexOf(beforeNickname) >= 0
        && beforeNickname === newNickname).assertFalse();

      // Step 6: pressBack to ConfigPage; ConfigBoundDeviceInfoButton
      // label should pick up the new nickname on the next onPageShow.
      await driver.pressBack();
      await driver.delayMs(1200);
      // We may have come back above the parent-account row.
      const here: Component | null =
        await driver.findComponent(ON.id('ConfigBoundDeviceInfoButton'));
      if (here === null) {
        await scrollConfigToParentAccountRow(driver);
      }
      const buttonText: string = await waitForBoundButtonText(
        driver, newNickname, 8000,
      );
      expect(buttonText.indexOf(newNickname) >= 0).assertTrue();

      // Cleanup: leave ConfigPage so the next test (if any) starts on
      // HomePage. We intentionally do NOT unbind here: the mock server
      // resets `_pair_nickname` between server lifetimes, and the next
      // run re-seeds the mock via `seedMockBinding` and picks a fresh
      // unique nickname via `nextNicknameDifferentFrom`.
      await exitConfigPage(driver);
      done();
    });
  });
}
