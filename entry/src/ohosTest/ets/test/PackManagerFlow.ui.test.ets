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

/**
 * V0.6.5.1 / V0.6.7: ConfigPage scrolls vertically and the pack-
 * manager entry sits below the autoSpeak row. On a narrow landscape
 * viewport one swipe is enough; iterate up to 5x to be defensive
 * across emulator skins.
 */
async function scrollToPackManagerEntry(driver: Driver): Promise<void> {
  for (let attempt: number = 0; attempt < 5; attempt++) {
    const btn: Component | null =
      await driver.findComponent(ON.id('ConfigPackManagerEntry'));
    if (btn !== null) {
      return;
    }
    await driver.swipe(1400, 1100, 1400, 300, 600);
    await driver.delayMs(300);
  }
}

async function openPackManagerFromHome(driver: Driver): Promise<void> {
  await clickByIdShared(driver, 'HomeConfigButton');
  await driver.delayMs(1500);
  await scrollToPackManagerEntry(driver);
  await clickByIdShared(driver, 'ConfigPackManagerEntry');
  await driver.delayMs(1500);
  // Anchor on the page title so subsequent assertions are robust to
  // a slightly slow first cold-load (PackManagerPage.aboutToAppear
  // calls loadHomeIntegration which is async).
  for (let attempt: number = 0; attempt < 5; attempt++) {
    const title: Component | null =
      await driver.findComponent(ON.id('PackManagerTitle'));
    if (title !== null) {
      return;
    }
    await driver.delayMs(500);
  }
}

/**
 * V0.6.7.3 PackManagerPage uses a `Scroll() { Column { ForEach pack
 * row } }` layout. ArkUI lazily materialises rows that aren't on
 * screen yet, so `findComponent` returns null for any pack whose
 * row is off the viewport — even though it's part of the page's
 * data model. Iterate `swipe` until the target id is reachable.
 *
 * We anchor on `PackToggle_<id>` (always rendered for every pack
 * regardless of active state) instead of `PackPin_<id>` (only
 * rendered for active packs) so this helper works for the
 * "toggle-off then assert pin gone" case in test 3.
 */
async function scrollPackRowIntoView(driver: Driver, packId: string): Promise<void> {
  const toggleId: string = `PackToggle_${packId}`;
  const labelId: string = `PackLabel_${packId}`;
  for (let attempt: number = 0; attempt < 6; attempt++) {
    const toggle: Component | null = await driver.findComponent(ON.id(toggleId));
    const label: Component | null = await driver.findComponent(ON.id(labelId));
    if (toggle !== null || label !== null) {
      return;
    }
    // Swipe within the pack list. The Scroll container fills most
    // of the viewport (header + status row at top, optional toast
    // at bottom), so a centred upward swipe always advances the
    // visible pack window.
    await driver.swipe(1400, 1100, 1400, 400, 600);
    await driver.delayMs(400);
  }
}

/**
 * Cleanup helper used at the tail of every test in this file. The
 * key difference vs `tapConfigCancelShared` is that we never assume
 * ConfigCancelButton is reachable — pressing back twice (Pack →
 * Config → Home) is enough on this page chain, and polling
 * `HomeStartButton` instead of asserting once tolerates HomePage's
 * onPageShow → loadHomeIntegration cold load.
 */
async function leaveToHome(driver: Driver): Promise<void> {
  for (let i: number = 0; i < 6; i++) {
    const home: Component | null =
      await driver.findComponent(ON.id('HomeStartButton'));
    if (home !== null) {
      return;
    }
    await driver.pressBack();
    await driver.delayMs(800);
  }
  await driver.assertComponentExist(ON.id('HomeStartButton'));
}

const ALL_DEFAULT_PACK_IDS: string[] = [
  'fruit-forest',
  'school-castle',
  'home-cottage',
  'animal-safari',
  'ocean-realm',
];

const PIN_LABEL_UNPINNED: string = '📌 固定';
const PIN_LABEL_PINNED: string = '已固定';

/**
 * V0.6.7.3 acceptance for `pages/PackManagerPage.ets`:
 *
 *   1. ConfigPage's `ConfigPackManagerEntry` row routes to the
 *      dedicated PackManagerPage with `PackManagerTitle`,
 *      `PackManagerSyncButton`, and `PackManagerStatus` rendered.
 *
 *   2. Each of the 5 built-in packs is active on a fresh launch
 *      (status row reads `已激活 5 / 5`) and exposes a
 *      `PackPin_<id>` button. The button text is exactly the new
 *      V0.6.7.3 copy — `📌 固定` for unpinned, `已固定` for pinned —
 *      not the older single-emoji `📌` / middle-dot `·` placeholder.
 *
 *   3. Toggling a pack OFF via `PackToggle_<id>` immediately removes
 *      the corresponding `PackPin_<id>` from the accessibility tree
 *      (replaced by a `Blank` spacer); toggling it back ON re-adds
 *      the pin button. Drives the V0.6.7.3 conditional render
 *      `if (this.isActive(p.id)) Button(...) else Blank()` directly.
 *
 *   4. Tapping a pin button on an active pack flips its label
 *      between `📌 固定` and `已固定`. Each tap is observed via the
 *      live `getText()` round-trip rather than a static dump so we'd
 *      catch a regression where ArkUI fails to re-render after
 *      `togglePin` resolves.
 *
 * All tests restore PackSelection state to default (5/5 active, no
 * pinned packs) before returning to HomePage so this suite is
 * order-independent vs everything below it in `List.test.ets`.
 */
export default function packManagerFlowUiTest(): void {
  describe('PackManagerFlowV0673', () => {
    it('navigatesFromConfigAndRendersHeaderStatusAndSync', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openPackManagerFromHome(driver);

      // Header bar (back + title + sync) and status line should all
      // be reachable.
      await driver.assertComponentExist(ON.id('PackManagerBack'));
      await driver.assertComponentExist(ON.id('PackManagerTitle'));
      await driver.assertComponentExist(ON.id('PackManagerSyncButton'));
      await driver.assertComponentExist(ON.id('PackManagerStatus'));

      const status: Component | null =
        await driver.findComponent(ON.id('PackManagerStatus'));
      expect(status !== null).assertTrue();
      if (status !== null) {
        const text: string = await status.getText();
        // 已激活 5 / 5 on a fresh launch (5 built-in packs all on).
        expect(text.indexOf('5 / 5') >= 0).assertTrue();
      }

      await leaveToHome(driver);
      done();
    });

    it('activePacksRenderPinButtonsWithFixedLabelCopy', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openPackManagerFromHome(driver);

      // Each of the 5 default packs is active, so each must expose
      // a PackPin_<id> button. Some rows (animal-safari / ocean-realm)
      // sit below the fold on a narrow viewport; scroll each into
      // view before asserting since ArkUI only materialises Scroll
      // children that have been laid out.
      for (let i: number = 0; i < ALL_DEFAULT_PACK_IDS.length; i++) {
        const packId: string = ALL_DEFAULT_PACK_IDS[i];
        await scrollPackRowIntoView(driver, packId);
        const pinId: string = `PackPin_${packId}`;
        const btn: Component | null = await driver.findComponent(ON.id(pinId));
        expect(btn !== null).assertTrue();
        if (btn !== null) {
          const text: string = await btn.getText();
          // V0.6.7.3 contract: text is exactly one of the two
          // labels — never the legacy `📌` / `·` glyphs.
          const ok: boolean =
            text === PIN_LABEL_UNPINNED || text === PIN_LABEL_PINNED;
          expect(ok).assertTrue();
        }
      }

      await leaveToHome(driver);
      done();
    });

    it('togglingPackOffHidesPinButtonAndOnRestoresIt', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openPackManagerFromHome(driver);

      // Pick fruit-forest — first in the default list, always
      // above the fold on the landscape emulator.
      const TOGGLE_ID: string = 'PackToggle_fruit-forest';
      const PIN_ID: string = 'PackPin_fruit-forest';

      await scrollPackRowIntoView(driver, 'fruit-forest');
      // Sanity check: the pin button is rendered while the pack
      // is active (it would be in the test suite's default state).
      await driver.assertComponentExist(ON.id(PIN_ID));

      // Toggle OFF → V0.6.7.3 conditional render swaps the button
      // out for `Blank().height(36)`, so the pin id disappears.
      await clickByIdShared(driver, TOGGLE_ID);
      await driver.delayMs(800);
      const pinAfterOff: Component | null =
        await driver.findComponent(ON.id(PIN_ID));
      expect(pinAfterOff === null).assertTrue();

      // The status line should now read 已激活 4 / 5.
      const statusOff: Component | null =
        await driver.findComponent(ON.id('PackManagerStatus'));
      expect(statusOff !== null).assertTrue();
      if (statusOff !== null) {
        const text: string = await statusOff.getText();
        expect(text.indexOf('4 / 5') >= 0).assertTrue();
      }

      // Toggle ON → pin button comes back and status returns to 5/5.
      await clickByIdShared(driver, TOGGLE_ID);
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id(PIN_ID));
      const statusBack: Component | null =
        await driver.findComponent(ON.id('PackManagerStatus'));
      expect(statusBack !== null).assertTrue();
      if (statusBack !== null) {
        const text: string = await statusBack.getText();
        expect(text.indexOf('5 / 5') >= 0).assertTrue();
      }

      await leaveToHome(driver);
      done();
    });

    it('tappingPinFlipsLabelBetweenUnpinnedAndPinnedStates', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openPackManagerFromHome(driver);

      // school-castle is the second pack in the default list — also
      // always above the fold and unaffected by test 3's toggle.
      const PIN_ID: string = 'PackPin_school-castle';
      await scrollPackRowIntoView(driver, 'school-castle');

      const initial: Component | null =
        await driver.findComponent(ON.id(PIN_ID));
      expect(initial !== null).assertTrue();
      if (initial !== null) {
        const initialText: string = await initial.getText();
        expect(initialText).assertEqual(PIN_LABEL_UNPINNED);
        await initial.click();
      }
      await driver.delayMs(700);

      const afterPin: Component | null =
        await driver.findComponent(ON.id(PIN_ID));
      expect(afterPin !== null).assertTrue();
      if (afterPin !== null) {
        const pinnedText: string = await afterPin.getText();
        expect(pinnedText).assertEqual(PIN_LABEL_PINNED);
        // Tap again to restore — also keeps PackSelection state
        // clean for subsequent suites in List.test.ets.
        await afterPin.click();
      }
      await driver.delayMs(700);

      const afterUnpin: Component | null =
        await driver.findComponent(ON.id(PIN_ID));
      expect(afterUnpin !== null).assertTrue();
      if (afterUnpin !== null) {
        const restoredText: string = await afterUnpin.getText();
        expect(restoredText).assertEqual(PIN_LABEL_UNPINNED);
      }

      await leaveToHome(driver);
      done();
    });
  });
}
