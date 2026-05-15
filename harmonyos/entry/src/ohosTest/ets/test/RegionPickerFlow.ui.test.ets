import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want, common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { clickByIdShared } from './RoutingFlow.ui.test';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();
const PACK_SELECTION_PREFS: string = 'wordmagic_pack_selection';
const PACK_SELECTION_KEY: string = 'selection_v1';
const DEFAULT_PACK_SELECTION_BLOB: string =
  '{"schemaVersion":1,"activePackIds":["fruit-forest","school-castle","home-cottage","animal-safari","ocean-realm"],"pinnedPackIds":[],"perfectScoresByPack":{}}';

async function launchApp(): Promise<Driver> {
  // ArkTS strict mode flags direct @kit calls as may-throw — wrap the
  // helper body in try/catch+rethrow to silence the warning while
  // preserving propagation to hypium's per-`it` handler.
  try {
    const want: Want = { bundleName: BUNDLE, abilityName: 'EntryAbility' };
    await DELEGATOR.startAbility(want);
    const driver: Driver = Driver.create();
    await driver.delayMs(1000);
    return driver;
  } catch (err) {
    throw err as Error;
  }
}

async function returnToHome(driver: Driver): Promise<void> {
  try {
    for (let i: number = 0; i < 5; i++) {
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

async function resetDefaultPackSelection(driver: Driver): Promise<void> {
  try {
    const ability = await DELEGATOR.getCurrentTopAbility();
    const ctx: common.UIAbilityContext = ability.context as common.UIAbilityContext;
    const handle: preferences.Preferences =
      await preferences.getPreferences(ctx, PACK_SELECTION_PREFS);
    await handle.put(PACK_SELECTION_KEY, DEFAULT_PACK_SELECTION_BLOB);
    await handle.flush();
    await clickByIdShared(driver, 'HomeConfigButton');
    await driver.delayMs(900);
    await driver.pressBack();
    await driver.delayMs(900);
    await returnToHome(driver);
  } catch (err) {
    throw err as Error;
  }
}

async function findRegionChip(driver: Driver, id: string): Promise<Component | null> {
  try {
    for (let attempt: number = 0; attempt < 8; attempt++) {
      const chip: Component | null = await driver.findComponent(ON.id(id));
      if (chip !== null) {
        return chip;
      }
      const y: number = (attempt % 2) === 0 ? 900 : 650;
      await driver.swipe(1050, y, 250, y, 500);
      await driver.delayMs(250);
    }
    for (let attempt: number = 0; attempt < 4; attempt++) {
      const chip: Component | null = await driver.findComponent(ON.id(id));
      if (chip !== null) {
        return chip;
      }
      const y: number = (attempt % 2) === 0 ? 900 : 650;
      await driver.swipe(250, y, 1050, y, 500);
      await driver.delayMs(250);
    }
    return await driver.findComponent(ON.id(id));
  } catch (err) {
    throw err as Error;
  }
}

/**
 * V0.4.6 acceptance:
 *  - HomePage region picker exposes 5 chips (fruit-forest /
 *    school-castle / home-cottage / animal-safari / ocean-realm).
 *  - Picker is a horizontal Scroll (RegionPickerScroll id) so all
 *    chips are reachable on narrow viewports.
 *  - Tapping a new region updates AdventureCardTitle and the
 *    AdventureCard background switches to that region.
 *  - The default region remains fruit-forest after a fresh launch.
 */
export default function regionPickerFlowUiTest(): void {
  describe('RegionPickerFlow', () => {
    it('exposesFiveRegionChipsInScrollContainer', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await resetDefaultPackSelection(driver);
      // Scroll container itself must exist so off-screen chips are
      // reachable. Using findComponent because the scroll might be
      // partially off-screen depending on the AdventureCard height.
      const picker: Component | null =
        await driver.findComponent(ON.id('RegionPickerScroll'));
      expect(picker !== null).assertTrue();

      // The first 3 chips are usually visible without scrolling;
      // animal-safari and ocean-realm may sit off-screen until the
      // user scrolls. We assert via findComponent (a11y tree).
      const ids: string[] = [
        'RegionChip_fruit-forest',
        'RegionChip_school-castle',
        'RegionChip_home-cottage',
        'RegionChip_animal-safari',
        'RegionChip_ocean-realm',
      ];
      for (let i: number = 0; i < ids.length; i++) {
        const chip: Component | null = await findRegionChip(driver, ids[i]);
        expect(chip !== null).assertTrue();
      }
      done();
    });

    it('animalSafariChipReadsAnimalSafariLabel', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await resetDefaultPackSelection(driver);
      const chip: Component | null =
        await findRegionChip(driver, 'RegionChip_animal-safari');
      expect(chip !== null).assertTrue();
      if (chip !== null) {
        const text: string = await chip.getText();
        expect(text).assertEqual('Animal Safari');
      }
      // Intentionally no chip taps here — clicking a region chip
      // persists to TodayPreferences asynchronously, and the
      // resulting backgrounded write has tripped the uitest-api
      // concurrency check in downstream suites. The unit tests
      // (AdventureCatalog) cover the click outcome (region object
      // wired to the right category + boss); this UI test only
      // needs to verify chip presence and labelling.
      done();
    });
  });
}
