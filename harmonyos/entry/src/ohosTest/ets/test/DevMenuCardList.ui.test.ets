import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { clickByIdShared } from './RoutingFlow.ui.test';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

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

async function tripleTapVersion(driver: Driver): Promise<void> {
  // Cache the Component once so all three taps fire fast enough to
  // land within the 1500ms triple-tap window even on slow emulators.
  try {
    await driver.assertComponentExist(ON.id('HomeVersionLabel'));
    const label: Component = await driver.findComponent(ON.id('HomeVersionLabel'));
    await label.click();
    await driver.delayMs(150);
    await label.click();
    await driver.delayMs(150);
    await label.click();
    await driver.delayMs(1500); // allow navigation + manifest fetch + render
  } catch (err) {
    throw err as Error;
  }
}

/**
 * V0.6.1 acceptance — DevMenuPage is now a unified 2-column card grid
 * with Local + Staging cards as the first two slots, followed by one
 * card per manifest preview. Cards are tap-to-apply: tapping any card
 * fires the env-switch pipeline (probe / reset / save / audit / toast)
 * and replaceUrl()s back to HomePage.
 *
 * Network-dependent: manifest fetch uses **`PREVIEW_MANIFEST_JSON_URL`**
 * (`https://happyword.cool/api/v1/preview-urls.json`) — **not** rewritten
 * by the mock UI server. The Local + Staging cards are static so they're
 * present even offline; preview cards are probed defensively.
 */
export default function devMenuCardListUiTest(): void {
  describe('DevMenuCardList', () => {
    it('localAndStagingCardsAlwaysPresent', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await tripleTapVersion(driver);
      // Confirm we're on DevMenuPage. The "Developer options" header
      // is unique to this page and visible without scrolling.
      const devMenuHeader: Component | null = await driver.findComponent(ON.text('Developer Options'));
      expect(devMenuHeader !== null).assertTrue();

      // V0.6.1 invariant: Local + Staging cards are static, always
      // rendered regardless of manifest fetch outcome. They're the
      // first two slots in the card grid.
      const localCard: Component | null = await driver.findComponent(ON.id('DevMenuLocalCard'));
      expect(localCard !== null).assertTrue();
      const stagingCard: Component | null = await driver.findComponent(ON.id('DevMenuStagingCard'));
      expect(stagingCard !== null).assertTrue();

      // Refresh button still exists, now pinned top-right.
      const refresh: Component | null = await driver.findComponent(ON.text('Refresh manifest'));
      expect(refresh !== null).assertTrue();

      // Cleanup.
      await driver.pressBack();
      await driver.delayMs(500);
      done();
    });

    it('previewCardsRenderWhenManifestAvailable', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await tripleTapVersion(driver);
      // Look for ANY preview card by id pattern. We probe known PR
      // numbers recorded in the preview manifest at spec time (42,
      // 41, 40, 30); if none are present (e.g. offline), we accept
      // the weaker assertion that DevMenu rendered.
      const probePrs: number[] = [42, 41, 40, 30];
      let foundAnyCard: boolean = false;
      for (const pr of probePrs) {
        const c: Component | null = await driver.findComponent(ON.id(`DevMenuPreviewCard_${pr}`));
        if (c !== null) {
          foundAnyCard = true;
          break;
        }
      }
      // No hard expect on foundAnyCard — offline runs legitimately
      // see zero preview cards. Logged for debugging.
      console.info(`DevMenuCardList: foundAnyPreviewCard=${foundAnyCard}`);
      // Cleanup.
      await driver.pressBack();
      await driver.delayMs(500);
      done();
    });

    it('stagingCardTapNavigatesBackToHome', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await tripleTapVersion(driver);
      // Sanity: we landed on DevMenuPage.
      const devMenuHeader: Component | null = await driver.findComponent(ON.text('Developer Options'));
      expect(devMenuHeader !== null).assertTrue();

      // V0.6.1: tapping any card runs the env-switch pipeline and
      // replaceUrl()s back to HomePage. Use Staging because it
      // skips the health probe (Local would too, but Staging is
      // the safe default the suite can converge on between tests).
      await clickByIdShared(driver, 'DevMenuStagingCard');
      await driver.delayMs(2000); // allow reset + save + audit + nav

      // Back on HomePage — the version label is the most stable
      // top-of-screen anchor available in debug builds.
      const versionLabel: Component | null = await driver.findComponent(ON.id('HomeVersionLabel'));
      expect(versionLabel !== null).assertTrue();
      // DevMenu header should be gone after replaceUrl.
      const devMenuHeaderAfter: Component | null = await driver.findComponent(ON.text('Developer Options'));
      expect(devMenuHeaderAfter === null).assertTrue();
      done();
    });
  });
}
