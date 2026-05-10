import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { common, Want } from '@kit.AbilityKit';
import http from '@ohos.net.http';
import preferences from '@ohos.data.preferences';
import { clickByIdShared } from './RoutingFlow.ui.test';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

const MOCK_BASE_URL: string = 'http://127.0.0.1:8123';

// Mock-server constants — must stay in sync with `server/mock_ui_server.py`
// (`_PAIR_*` module constants and `FIXTURE_*_PACK_PAYLOAD`). These are the
// deterministic identifiers the mock mints on a `/api/v1/pair/redeem`
// success and the pack ids served by the global / family endpoints.
const MOCK_DEVICE_TOKEN: string = 'ui-mock-device-jwt';
const MOCK_VALID_SHORT_CODE: string = '654321';

const GLOBAL_PACK_ID: string = 'space-station';
const GLOBAL_PACK_NAME: string = 'Space Station';
const FAMILY_PACK_ID: string = 'family-snacks';
const FAMILY_PACK_NAME: string = 'Family Snacks';

// Preferences bag name (must match `services/CloudCredentials.ts::PREFS_NAME`).
// Used in the family-pack test's cleanup so we can wipe the device's
// bound state without driving the PIN-gated unbind UI flow. Pack caches
// (`wordmagic_global_packs`, `wordmagic_family_packs`) are intentionally
// left alone — see `wipeBoundDeviceState` for the rationale.
const PREFS_CLOUD: string = 'wordmagic_cloud';

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

/**
 * V0.6.5.1 / V0.6.7: ConfigPage scrolls vertically and the pack-
 * manager entry sits below the autoSpeak row. On a narrow landscape
 * viewport one swipe is enough; iterate up to 5x to be defensive
 * across emulator skins.
 */
async function scrollToPackManagerEntry(driver: Driver): Promise<void> {
  try {
    for (let attempt: number = 0; attempt < 5; attempt++) {
      const btn: Component | null =
        await driver.findComponent(ON.id('ConfigPackManagerEntry'));
      if (btn !== null) {
        return;
      }
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(300);
    }
  } catch (err) {
    throw err as Error;
  }
}

async function openPackManagerFromHome(driver: Driver): Promise<void> {
  try {
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
  } catch (err) {
    throw err as Error;
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
  try {
    const toggleId: string = `PackToggle_${packId}`;
    const labelId: string = `PackLabel_${packId}`;
    // V0.6.7.8: builtins (fruit-forest … home-cottage) render above
    // synced globals (space-station). Tests that first scroll DOWN to
    // assert the global row must be able to scroll BACK UP to reach a
    // builtin toggle — upward-only swipes never moved the viewport back,
    // producing `PackToggle_home-cottage` not exist. Alternate swipe
    // directions each attempt so rows above and below the current window
    // are both reachable within a bounded loop.
    for (let attempt: number = 0; attempt < 14; attempt++) {
      const toggle: Component | null = await driver.findComponent(ON.id(toggleId));
      const label: Component | null = await driver.findComponent(ON.id(labelId));
      if (toggle !== null || label !== null) {
        return;
      }
      if ((attempt % 2) === 0) {
        await driver.swipe(1400, 1100, 1400, 400, 600);
      } else {
        await driver.swipe(1400, 400, 1400, 1100, 600);
      }
      await driver.delayMs(400);
    }
  } catch (err) {
    throw err as Error;
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
  try {
    for (let i: number = 0; i < 6; i++) {
      const home: Component | null =
        await driver.findComponent(ON.id('HomeStartButton'));
      if (home !== null) {
        // Give HomePage.onPageShow → applyActivePacks one tick to
        // re-resolve chipPacks / todayPack / todayRegion before the
        // caller inspects RegionChip_* / AdventureCardTitle. Without
        // this delay the chip ForEach can still be rendering the
        // previous pack set.
        await driver.delayMs(400);
        return;
      }
      await driver.pressBack();
      await driver.delayMs(800);
    }
    await driver.assertComponentExist(ON.id('HomeStartButton'));
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Toggle a single pack in PackManagerPage and return all the way
 * back to HomePage. Wraps the open / scroll / tap / leave dance
 * used by the V0.6.7.4 "config-affects-home" tests so each `it`
 * stays focused on its assertions, not the navigation plumbing.
 */
async function togglePackAndReturnHome(driver: Driver, packId: string): Promise<void> {
  try {
    await openPackManagerFromHome(driver);
    await scrollPackRowIntoView(driver, packId);
    await clickByIdShared(driver, `PackToggle_${packId}`);
    // The toggle persists synchronously to AppStorage via
    // PackSelectionService.setActiveIds; the @State refresh in
    // PackManagerPage and HomePage's eventual onPageShow are async
    // but already covered by leaveToHome's polling + 400ms grace.
    await driver.delayMs(600);
    await leaveToHome(driver);
  } catch (err) {
    throw err as Error;
  }
}

async function getTextById(driver: Driver, id: string): Promise<string> {
  try {
    const comp: Component | null = await driver.findComponent(ON.id(id));
    if (comp === null) {
      return '';
    }
    return await comp.getText();
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Issue a fire-and-forget HTTP call against the mock server. We thread
 * everything through @ohos.net.http directly because the test process
 * has no network MCP client and the mock is reached over the loopback
 * (`hdc rport tcp:8123`). Bodies are intentionally optional so callers
 * can do redeem (POST + JSON body) and unbind (POST + empty body)
 * through the same helper.
 *
 * Errors are swallowed: the test will fail later via the UI-level
 * assertions if the mock is unreachable, and that's a much more
 * actionable signal than a raw HTTP exception bubbling up here.
 */
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
    // Outer guard: http.createHttp itself can throw on resource
    // exhaustion. Swallow — caller treats empty response as failure.
    return '';
  }
}

/**
 * Seed the mock server's `_active_bindings` set so the family-packs
 * endpoint accepts the deterministic device JWT. Idempotent: calling
 * twice is identical to calling once. Mirrors `BoundDeviceInfoFlow`'s
 * `seedMockBinding` helper but is duplicated here so the suite stays
 * self-contained vs. ordering changes in `List.test.ets`.
 */
async function seedMockBinding(): Promise<void> {
  try {
    const body: string =
      `{"device_id":"ui-mock-pack-suite","short_code":"${MOCK_VALID_SHORT_CODE}"}`;
    await mockHttp(http.RequestMethod.POST, '/api/v1/pair/redeem', body, '');
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Tell the mock server to drop the binding for the deterministic JWT
 * so subsequent suites that assume an unbound device (most notably
 * `ParentBindingFlow.unboundConfigPageRendersBindEntryOnly`) start
 * from a clean slate even within a single mock-server lifetime.
 */
async function unbindMockBinding(): Promise<void> {
  try {
    await mockHttp(http.RequestMethod.POST, '/api/v1/child/unbind', '{}', MOCK_DEVICE_TOKEN);
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Drive the manual short-code redeem flow against the mock to leave
 * the device in a `CloudCredentials.isBound() === true` state. The
 * UI-level path is preferred over poking `wordmagic_cloud`
 * preferences directly because:
 *   1. `CloudCredentials.init` runs async in `aboutToAppear` for both
 *      `PackManagerPage` and `ConfigPage`; pre-seeded preferences are
 *      visible to the *next* page that calls `getPreferences`, but not
 *      always to the in-flight `init()` call already kicked off.
 *      Driving the redeem from the UI guarantees `saveBinding` is
 *      called on the live `CloudCredentials` instance.
 *   2. It exercises the same code path real users hit, which means the
 *      family-pack sync that follows runs against a JWT minted exactly
 *      the same way as in production.
 *
 * Mirrors `BoundDeviceInfoFlow.bindViaShortCode` and shares the mock
 * server's redeem endpoint contract (any non-blacklisted 6-digit code
 * succeeds). Caller must already be on HomePage; helper leaves the
 * caller back on HomePage when done.
 */
async function bindViaShortCode(driver: Driver): Promise<void> {
  try {
    await clickByIdShared(driver, 'HomeConfigButton');
    await driver.delayMs(1500);
    for (let attempt: number = 0; attempt < 5; attempt++) {
      const bind: Component | null =
        await driver.findComponent(ON.id('ConfigBindParentButton'));
      const bound: Component | null =
        await driver.findComponent(ON.id('ConfigBoundDeviceInfoButton'));
      if (bind !== null || bound !== null) {
        break;
      }
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(400);
    }

    const alreadyBound: Component | null =
      await driver.findComponent(ON.id('ConfigBoundDeviceInfoButton'));
    if (alreadyBound !== null) {
      // Carry-over bound state from a prior dev session — no re-bind
      // needed; just navigate back to home.
      await driver.pressBack();
      await driver.delayMs(800);
      return;
    }

    await clickByIdShared(driver, 'ConfigBindParentButton');
    await driver.delayMs(1500);
    await clickByIdShared(driver, 'ScanBindingManualToggle');
    await driver.delayMs(600);
    await driver.assertComponentExist(ON.id('ScanBindingManualInput'));

    const input: Component =
      await driver.findComponent(ON.id('ScanBindingManualInput'));
    await input.inputText(MOCK_VALID_SHORT_CODE);
    await driver.delayMs(500);
    // Numeric IME hides ScanBindingManualSubmit; dismiss it first.
    await driver.pressBack();
    await driver.delayMs(600);

    await clickByIdShared(driver, 'ScanBindingManualSubmit');
    for (let i: number = 0; i < 16; i++) {
      const c: Component | null =
        await driver.findComponent(ON.id('ScanBindingSuccessLabel'));
      if (c !== null) {
        break;
      }
      await driver.delayMs(500);
    }
    await clickByIdShared(driver, 'ScanBindingSuccessBack');
    await driver.delayMs(1500);
    // ConfigPage now in bound state; pop back to home for the caller.
    await driver.pressBack();
    await driver.delayMs(800);
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Wipe the `wordmagic_cloud` (binding) keys so the device is left in
 * an unbound state for the next suite. Mirrors
 * `CloudCredentials.clearBinding` semantics: every key the snapshot
 * reads is overwritten with the empty string, then flushed. This is
 * preferred over `preferences.deletePreferences` because the test
 * process and the app share the in-process preferences cache, which
 * blocks `deletePreferences` from succeeding while any code path
 * still holds a handle.
 *
 * The pack caches (`wordmagic_global_packs`, `wordmagic_family_packs`)
 * are intentionally NOT wiped — leaving them populated does not
 * affect downstream suites because (a) the persisted pack-selection
 * blob still references the 5 builtins after our restore-to-defaults
 * toggle, and (b) the global pack cache being warm only adds an
 * extra inactive row to the picker, which the existing suites
 * tolerate.
 */
async function wipeBoundDeviceState(): Promise<void> {
  try {
    const ctx: common.Context = DELEGATOR.getAppContext();
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
    // Best-effort — if the preferences API throws (e.g. mid-shutdown)
    // we leave the device in whatever state it's in; the next suite
    // surfaces the issue if cleanup didn't complete.
  }
}

/**
 * Tap the 🔄 同步词包 button and wait for `PackManagerSyncToast` to
 * surface, which is the user-visible signal that both `ensureLatest`
 * promises have settled (regardless of updated/cached/cleared status).
 * Returns the raw toast text so callers can correlate against the
 * `formatPackSyncToast` matrix when needed.
 */
async function tapPackSyncAndWaitForToast(driver: Driver): Promise<string> {
  try {
    await clickByIdShared(driver, 'PackManagerSyncButton');
    for (let attempt: number = 0; attempt < 20; attempt++) {
      const toast: Component | null =
        await driver.findComponent(ON.id('PackManagerSyncToast'));
      if (toast !== null) {
        const text: string = await toast.getText();
        if (text.length > 0) {
          return text;
        }
      }
      await driver.delayMs(400);
    }
    return '';
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Toggle a pack's active state from inside an already-open
 * PackManagerPage, scrolling its row into view first. Caller is
 * responsible for the surrounding navigation (open / leave). Used by
 * the global / family activation tests where each scenario flips two
 * packs in sequence (one OFF to free a slot, one ON to fill it) and
 * doesn't want to bounce back to HomePage between flips.
 */
async function togglePackActiveInPlace(driver: Driver, packId: string): Promise<void> {
  try {
    await scrollPackRowIntoView(driver, packId);
    await clickByIdShared(driver, `PackToggle_${packId}`);
    await driver.delayMs(700);
  } catch (err) {
    throw err as Error;
  }
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
 * V0.6.7.3 / V0.6.7.6 acceptance for `pages/PackManagerPage.ets`:
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
 *   5. (V0.6.7.4) Toggling a NON-selected pack OFF removes its
 *      `RegionChip_<id>` from HomePage, leaves the AdventureCard
 *      unchanged, and toggling back ON restores the chip. Drives
 *      the `chipPacks = resolveActivePacks(...)` propagation from
 *      `services/PackSelectionService.setActiveIds` to
 *      `pages/HomePage.applyActivePacks`.
 *
 *   6. (V0.6.7.4) Toggling the CURRENTLY-SELECTED pack off forces
 *      HomePage to fall back to `chipPacks[0]`, observably swapping
 *      `AdventureCardTitle`. Toggling the same pack back on lets
 *      `TODAY_REGION_ID_KEY` resolve again and the title returns
 *      to its pre-toggle value. This is the "config change → battle
 *      scene reflects" smoke test the user requested.
 *
 *   7. (V0.6.7.6) The PackManagerSync button drives the THREE-LAYER
 *      pack stack against the local mock — built-in (rawfile) +
 *      global (`/api/v1/public/global-packs/latest.json`) + family
 *      (`/api/v1/child/family-packs/latest.json`, gated by the
 *      device JWT). After sync, the new pack rows render with
 *      English names + the matching source pill ("官方" / "家庭"),
 *      and activating either grows the HomePage `RegionChip_<id>`
 *      row to reflect the new active pack — the user-facing
 *      "config change → battle scene reflects" round-trip across
 *      ALL three pack sources, not just the built-in tier.
 *
 * All tests restore PackSelection state to default (5/5 active, no
 * pinned packs) before returning to HomePage so this suite is
 * order-independent vs everything below it in `List.test.ets`.
 *
 * The family-pack arm (case 7's second test) additionally pre-seeds
 * `wordmagic_cloud` preferences with the deterministic mock JWT and
 * `unbind`s + wipes those preferences in its `finally` block so the
 * device is left unbound — `ParentBindingFlow` runs after this
 * suite and depends on starting from a fresh-install bound state.
 */
export default function packManagerFlowUiTest(): void {
  describe('PackManagerFlow', () => {
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

    /**
     * V0.6.7.5: HomePage chip row anchors on the English `p.name`
     * (per `packChipLabel`) so it stays consistent with PackManager-
     * Page's English convention regardless of whether a global
     * override blanked out `labelZh`. Spot-check the default 5
     * builtin packs by comparing the chip's rendered text with the
     * expected English name; a regression that reverted to Chinese
     * `labelZh` (e.g. "水果森林") would fail this assertion.
     */
    it('homeRegionChipsRenderEnglishPackNames', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);

      // (id, expected English name) pairs taken from the builtin
      // rawfile JSONs (entry/src/main/resources/rawfile/data/builtin).
      const pairs: Array<[string, string]> = [
        ['fruit-forest', 'Fruit Forest'],
        ['school-castle', 'School Castle'],
        ['home-cottage', 'Home Cottage'],
        ['animal-safari', 'Animal Safari'],
        ['ocean-realm', 'Ocean Realm'],
      ];
      for (let i: number = 0; i < pairs.length; i++) {
        const id: string = pairs[i][0];
        const expected: string = pairs[i][1];
        const chip: Component | null =
          await driver.findComponent(ON.id(`RegionChip_${id}`));
        expect(chip !== null).assertTrue();
        if (chip !== null) {
          const txt: string = await chip.getText();
          expect(txt).assertEqual(expected);
        }
      }
      done();
    });

    /**
     * V0.6.7.4: toggling a non-selected pack OFF in PackManagerPage
     * must remove its chip from the HomePage `RegionChip_<id>` row
     * (driven by `chipPacks` = `resolveActivePacks(homeIntegration)`),
     * and the AdventureCard for the currently-selected pack stays
     * untouched. Toggling the same pack back ON must re-add the chip.
     *
     * Uses `home-cottage` (3rd built-in pack) — never the default
     * fruit-forest selection — so the AdventureCardTitle is a
     * negative control: it is recorded before / during / after the
     * round-trip and asserted to stay unchanged.
     */
    it('togglingNonSelectedPackOffRemovesItsHomeRegionChip', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);

      // We track whether the OFF toggle actually persisted so the
      // `finally` cleanup never tries to flip an already-on pack
      // back on (which would deactivate it and pollute downstream
      // tests / runs).
      let toggledOff: boolean = false;
      try {
        // Baseline: all 5 chips exist, AdventureCardTitle reflects
        // the default todayPack (fruit-forest → "Fruit Forest" since
        // V0.6.7.5 anchors HomePage labels on the English `p.name`).
        for (let i: number = 0; i < ALL_DEFAULT_PACK_IDS.length; i++) {
          await driver.assertComponentExist(
            ON.id(`RegionChip_${ALL_DEFAULT_PACK_IDS[i]}`));
        }
        const titleBefore: string =
          await getTextById(driver, 'AdventureCardTitle');
        expect(titleBefore.length > 0).assertTrue();

        // Toggle home-cottage OFF in PackManagerPage and return home.
        await togglePackAndReturnHome(driver, 'home-cottage');
        toggledOff = true;

        // home-cottage's chip is gone, the other 4 are still rendered.
        const removed: Component | null =
          await driver.findComponent(ON.id('RegionChip_home-cottage'));
        expect(removed === null).assertTrue();
        await driver.assertComponentExist(ON.id('RegionChip_fruit-forest'));
        await driver.assertComponentExist(ON.id('RegionChip_school-castle'));
        await driver.assertComponentExist(ON.id('RegionChip_animal-safari'));
        await driver.assertComponentExist(ON.id('RegionChip_ocean-realm'));

        // AdventureCardTitle is unchanged because the deselected pack
        // wasn't the currently-selected todayPack.
        const titleDuring: string =
          await getTextById(driver, 'AdventureCardTitle');
        expect(titleDuring).assertEqual(titleBefore);

        // Restore: toggle home-cottage back on. State should be
        // identical to the baseline.
        await togglePackAndReturnHome(driver, 'home-cottage');
        toggledOff = false;
        for (let i: number = 0; i < ALL_DEFAULT_PACK_IDS.length; i++) {
          await driver.assertComponentExist(
            ON.id(`RegionChip_${ALL_DEFAULT_PACK_IDS[i]}`));
        }
        const titleAfter: string =
          await getTextById(driver, 'AdventureCardTitle');
        expect(titleAfter).assertEqual(titleBefore);
      } finally {
        // Defensive restore: if any assertion failed after the OFF
        // toggle but before the ON toggle, flip home-cottage back so
        // the device's preferences blob is left in the canonical
        // 5/5-active state and downstream tests / runs aren't
        // poisoned by the failure.
        if (toggledOff) {
          try {
            await togglePackAndReturnHome(driver, 'home-cottage');
          } catch (_err) {
            // Swallow — we've already failed; cleanup best-effort.
          }
        }
      }
      done();
    });

    /**
     * V0.6.7.4: toggling the CURRENTLY-SELECTED pack off must reset
     * AdventureCardTitle to the new `chipPacks[0]` (HomePage's fall-
     * back when the persisted `TODAY_REGION_ID_KEY` no longer
     * resolves to an active pack — see `applyActivePacks`). Toggling
     * it back on lets the persisted id resolve again, restoring the
     * original selection without the user re-tapping the chip.
     *
     * This is the "config change → battle scene reflects" round-trip:
     * deactivating fruit-forest removes its WordEntry pool from
     * `TodayAdventureBuilder.buildFromPack` for the next battle, so
     * the visible AdventureCard MUST advertise the replacement pack.
     */
    it('togglingSelectedPackOffSwapsAdventureCardThenRestores', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);

      let toggledOff: boolean = false;
      try {
        // Default selection is fruit-forest (chip carries the
        // selected `#E63946` background); record the title for
        // comparison after the round-trip.
        const titleBefore: string =
          await getTextById(driver, 'AdventureCardTitle');
        expect(titleBefore.length > 0).assertTrue();
        await driver.assertComponentExist(ON.id('RegionChip_fruit-forest'));

        // Toggle fruit-forest OFF — chipPacks loses it, todayPack
        // falls back to the next active pack (school-castle on a
        // fresh suite run since BuiltinPackLoader's order is
        // [fruit-forest, school-castle, ...]).
        await togglePackAndReturnHome(driver, 'fruit-forest');
        toggledOff = true;

        const removed: Component | null =
          await driver.findComponent(ON.id('RegionChip_fruit-forest'));
        expect(removed === null).assertTrue();

        const titleDuring: string =
          await getTextById(driver, 'AdventureCardTitle');
        expect(titleDuring.length > 0).assertTrue();
        // The cascade is the contract: title MUST differ from the
        // pre-toggle value because the active pack changed under us.
        expect(titleDuring !== titleBefore).assertTrue();

        // Toggle ON again. `TODAY_REGION_ID_KEY` is still
        // `fruit-forest` from the launch defaults, so applyActivePacks
        // resolves it back to the original pack and the title
        // returns.
        await togglePackAndReturnHome(driver, 'fruit-forest');
        toggledOff = false;
        await driver.assertComponentExist(ON.id('RegionChip_fruit-forest'));
        const titleAfter: string =
          await getTextById(driver, 'AdventureCardTitle');
        expect(titleAfter).assertEqual(titleBefore);
      } finally {
        // Defensive restore — see togglingNonSelectedPackOff... for
        // the rationale. fruit-forest left OFF would also leave the
        // app's TODAY_REGION_ID_KEY pointing at a deactivated pack,
        // which is the worst-possible state to leak between runs.
        if (toggledOff) {
          try {
            await togglePackAndReturnHome(driver, 'fruit-forest');
          } catch (_err) {
            // Best-effort cleanup; swallow.
          }
        }
      }
      done();
    });

    /**
     * V0.6.7.6: drive the three-layer pack sync against the local mock
     * (`server/mock_ui_server.py`) and verify the synced GLOBAL pack
     *
     *   1) appears in PackManagerPage as a row with the English pack
     *      name (`Space Station`) and the "官方" source tag, and
     *   2) when activated (after deactivating one builtin to free a
     *      slot) propagates to HomePage's `RegionChip_<id>` row so the
     *      battle-scene chip strip reflects the new pack.
     *
     * Cleanup: restore the active set to the canonical 5 builtins
     * (toggle space-station OFF, toggle home-cottage back ON) so this
     * test is order-independent against everything below it.
     *
     * Anonymous endpoint: no binding required. The mock's
     * `/api/v1/public/global-packs/latest.json` always returns the same
     * fixture regardless of caller identity, mirroring prod's anonymous
     * contract.
     */
    it('syncedGlobalPackAppearsInListAndActivatingItGrowsHomeChipRow',
      0, async (done: Function) => {
        const driver: Driver = await launchApp();
        await returnToHome(driver);

        let toggledOffBuiltin: boolean = false;
        let toggledOnGlobal: boolean = false;
        try {
          await openPackManagerFromHome(driver);

          // Tap sync. The toast that surfaces afterwards is one of the
          // strings produced by `PackManagerPage.formatPackSyncToast` —
          // we accept any "synced global" variant here because the
          // family-pack arm's outcome depends on the (unknown) bound
          // state of the device under test.
          const toast: string = await tapPackSyncAndWaitForToast(driver);
          expect(toast.length > 0).assertTrue();
          expect(toast.indexOf('全局') >= 0).assertTrue();

          // Re-loaded library should now contain `space-station`.
          await scrollPackRowIntoView(driver, GLOBAL_PACK_ID);
          const tag: string = await getTextById(
            driver, `PackSourceTag_${GLOBAL_PACK_ID}`);
          expect(tag).assertEqual('官方');
          const label: string =
            await getTextById(driver, `PackLabel_${GLOBAL_PACK_ID}`);
          expect(label).assertEqual(GLOBAL_PACK_NAME);

          // Pack starts inactive (5 builtins fill the cap); free a slot
          // by deactivating `home-cottage` and then activate the global
          // pack. `togglePackActiveInPlace` polls for the row first.
          await togglePackActiveInPlace(driver, 'home-cottage');
          toggledOffBuiltin = true;
          await togglePackActiveInPlace(driver, GLOBAL_PACK_ID);
          toggledOnGlobal = true;

          // Status row should now read 已激活 5 / 5 again (one OFF +
          // one ON balances out).
          const status: string =
            await getTextById(driver, 'PackManagerStatus');
          expect(status.indexOf('5 / 5') >= 0).assertTrue();

          await leaveToHome(driver);

          // HomePage must reflect the new chipPacks composition: the
          // synced global pack is now visible, the deactivated builtin
          // is gone.
          const chip: Component | null =
            await driver.findComponent(ON.id(`RegionChip_${GLOBAL_PACK_ID}`));
          expect(chip !== null).assertTrue();
          if (chip !== null) {
            const chipTxt: string = await chip.getText();
            expect(chipTxt).assertEqual(GLOBAL_PACK_NAME);
          }
          const removed: Component | null =
            await driver.findComponent(ON.id('RegionChip_home-cottage'));
          expect(removed === null).assertTrue();
        } finally {
          // Defensive restore — independent of which assertion (if any)
          // tripped, we always want to leave the device in the canonical
          // "5 builtins active, 0 globals active" state so downstream
          // tests don't see leaked global packs in the chip row.
          if (toggledOnGlobal) {
            try {
              await openPackManagerFromHome(driver);
              await togglePackActiveInPlace(driver, GLOBAL_PACK_ID);
              if (toggledOffBuiltin) {
                await togglePackActiveInPlace(driver, 'home-cottage');
              }
              await leaveToHome(driver);
            } catch (_err) {
              // Best-effort cleanup; swallow.
            }
          } else if (toggledOffBuiltin) {
            try {
              await openPackManagerFromHome(driver);
              await togglePackActiveInPlace(driver, 'home-cottage');
              await leaveToHome(driver);
            } catch (_err) {
              // Best-effort cleanup.
            }
          }
        }
        done();
      });

    /**
     * V0.6.7.6: family-pack arm of the three-layer sync verification.
     * Pre-seeds the device's `wordmagic_cloud` preferences with the
     * deterministic mock JWT so `CloudCredentials.load().deviceToken`
     * is non-empty, which is the gate
     * `PackManagerPage.onPackSyncTap` reads before calling
     * `FamilyPackService.ensureLatest(token)`. The mock then returns
     * the `family-snacks` fixture on the corresponding HTTP GET.
     *
     * Test asserts the family pack
     *   1) renders as a row with English name "Family Snacks" and the
     *      "家庭" source tag, and
     *   2) when activated (after freeing a builtin slot) appears as a
     *      `RegionChip_family-snacks` on HomePage.
     *
     * Cleanup wipes `wordmagic_cloud`, `wordmagic_family_packs`, and
     * `wordmagic_global_packs` preferences plus the mock's
     * `_active_bindings` set so the device is left in an unbound,
     * empty-overlay state — exactly what the next suite
     * (`ParentBindingFlow.unboundConfigPageRendersBindEntryOnly`)
     * relies on.
     */
    it('boundDeviceSyncPullsFamilyPackAndAffectsHomeChipRow',
      0, async (done: Function) => {
        // Re-seed the mock-side `_active_bindings` set BEFORE we
        // launch — the mock restarts fresh on every UI run, so the
        // device's persisted JWT (if any from a prior session) would
        // be 401-rejected without this seed even though the redeem
        // ceremony is about to mint the same JWT again. Idempotent
        // on the mock.
        await seedMockBinding();

        let toggledOffBuiltin: boolean = false;
        let toggledOnFamily: boolean = false;
        const driver: Driver = await launchApp();
        try {
          await returnToHome(driver);
          // Drive UI-level bind so `CloudCredentials` is fully
          // populated on the live ability instance. Pre-seeding
          // preferences from the test process does not always
          // propagate into the in-flight `init()` call PackManagerPage
          // kicks off in `aboutToAppear`.
          await bindViaShortCode(driver);
          await openPackManagerFromHome(driver);

          const toast: string = await tapPackSyncAndWaitForToast(driver);
          expect(toast.length > 0).assertTrue();
          // The bound-device path of `formatPackSyncToast` always
          // includes the "家庭" token (either "已同步全局 + 家庭词包",
          // "✅ 已同步家庭词包", or the cached-no-update variant).
          const familyMentioned: boolean =
            toast.indexOf('家庭') >= 0 || toast.indexOf('已是最新') >= 0;
          expect(familyMentioned).assertTrue();

          // Family pack row exists with the expected metadata.
          await scrollPackRowIntoView(driver, FAMILY_PACK_ID);
          const tag: string = await getTextById(
            driver, `PackSourceTag_${FAMILY_PACK_ID}`);
          expect(tag).assertEqual('家庭');
          const label: string =
            await getTextById(driver, `PackLabel_${FAMILY_PACK_ID}`);
          expect(label).assertEqual(FAMILY_PACK_NAME);

          // Activate the family pack, free a slot first.
          await togglePackActiveInPlace(driver, 'animal-safari');
          toggledOffBuiltin = true;
          await togglePackActiveInPlace(driver, FAMILY_PACK_ID);
          toggledOnFamily = true;

          await leaveToHome(driver);

          // Home chip row must include the family pack's English name
          // and exclude the deactivated builtin.
          const chip: Component | null =
            await driver.findComponent(ON.id(`RegionChip_${FAMILY_PACK_ID}`));
          expect(chip !== null).assertTrue();
          if (chip !== null) {
            const chipTxt: string = await chip.getText();
            expect(chipTxt).assertEqual(FAMILY_PACK_NAME);
          }
          const removed: Component | null =
            await driver.findComponent(ON.id('RegionChip_animal-safari'));
          expect(removed === null).assertTrue();
        } finally {
          // Toggle state back to the all-builtin defaults BEFORE
          // wiping prefs so PackSelectionService persists a clean
          // active set (otherwise the wipe leaves
          // `wordmagic_word_pack_selection` referencing pack ids that
          // no longer exist after we drop the family-pack cache).
          if (toggledOnFamily) {
            try {
              await openPackManagerFromHome(driver);
              await togglePackActiveInPlace(driver, FAMILY_PACK_ID);
              if (toggledOffBuiltin) {
                await togglePackActiveInPlace(driver, 'animal-safari');
              }
              await leaveToHome(driver);
            } catch (_err) {
              // Cleanup is best-effort; the subsequent prefs wipe
              // still resets the device to a known state.
            }
          } else if (toggledOffBuiltin) {
            try {
              await openPackManagerFromHome(driver);
              await togglePackActiveInPlace(driver, 'animal-safari');
              await leaveToHome(driver);
            } catch (_err) {
              // Best-effort cleanup.
            }
          }
          await unbindMockBinding();
          await wipeBoundDeviceState();
        }
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
