/**
 * Shared UI-test helpers for parent-account mock binding (no `describe()`).
 * Used when a suite needs `ConfigParentPinButton` visible before the
 * global ParentBindingFlow runs.
 */
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import http from '@ohos.net.http';
import preferences from '@ohos.data.preferences';
import {
  clickByIdShared,
  clickParentPinSetupCancelShared,
  tapConfigCancelShared,
} from './RoutingFlow.ui.test';

const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

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
  await mockHttp(http.RequestMethod.POST, '/api/v1/child/unbind', '{}', MOCK_DEVICE_TOKEN);
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
    // Best-effort.
  }
}

/** Clears mock server binding + local prefs (matches ParentBindingFlow). */
export async function resetMockAndPrefsToUnboundShared(): Promise<void> {
  await unbindMockBinding();
  await wipeBoundDeviceState();
}

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

/**
 * Home → Config → ScanBinding manual short-code redeem → dismiss
 * auto ParentPinSetup → success → Config → Home. Leaves device mock-bound.
 */
export async function bindMockParentViaShortCodeFromHome(
  driver: Driver,
  shortCode: string,
): Promise<void> {
  try {
    await resetMockAndPrefsToUnboundShared();
    await clickByIdShared(driver, 'HomeConfigButton');
    await driver.delayMs(1500);
    await scrollConfigToParentAccountRow(driver);
    await clickByIdShared(driver, 'ConfigBindParentButton');
    await driver.delayMs(1500);
    await clickByIdShared(driver, 'ScanBindingManualToggle');
    await driver.delayMs(600);
    const input: Component =
      await driver.findComponent(ON.id('ScanBindingManualInput'));
    await input.inputText(shortCode);
    await driver.delayMs(500);
    await driver.pressBack();
    await driver.delayMs(600);
    await clickByIdShared(driver, 'ScanBindingManualSubmit');
    let keypad: Component | null = null;
    for (let i: number = 0; i < 20; i++) {
      keypad = await driver.findComponent(ON.id('ParentPinSetupKey_1'));
      if (keypad !== null) {
        break;
      }
      const successEarly: Component | null =
        await driver.findComponent(ON.id('ScanBindingSuccessLabel'));
      if (successEarly !== null) {
        keypad = null;
        break;
      }
      await driver.delayMs(400);
    }
    if (keypad !== null) {
      await clickParentPinSetupCancelShared(driver);
      await driver.delayMs(800);
    }
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
    if (!foundSuccess) {
      throw new Error('bindMockParentViaShortCodeFromHome: success label missing');
    }
    await clickByIdShared(driver, 'ScanBindingSuccessBack');
    await driver.delayMs(1500);
    await tapConfigCancelShared(driver);
    await driver.delayMs(800);
    for (let i: number = 0; i < 6; i++) {
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
