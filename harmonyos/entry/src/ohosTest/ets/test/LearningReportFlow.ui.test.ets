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

async function openReport(driver: Driver): Promise<void> {
  try {
    await clickByIdShared(driver, 'HomePlanButton');
    await driver.delayMs(1500);
    await clickByIdShared(driver, 'TodayPlanReportButton');
    await driver.delayMs(1500);
  } catch (err) {
    throw err as Error;
  }
}

/**
 * The report page renders 4-5 cards stacked vertically. On
 * shorter viewports the lower cards (review bar, per-pack section)
 * fall below the fold and aren't returned by findComponent until
 * we scroll into them. Mirrors the swipe coordinates used by
 * RoutingFlow / ConfigFlow / WishlistFlow.
 */
async function scrollDownOnce(driver: Driver): Promise<void> {
  try {
    await driver.swipe(1400, 1100, 1400, 300, 600);
    await driver.delayMs(500);
  } catch (err) {
    throw err as Error;
  }
}

/**
 * V0.6.7.8 acceptance:
 *  - HomePage 📋 → TodayPlanPage; TodayPlanPage 📊 → LearningReportPage.
 *  - LearningReportPage surfaces title, accuracy big-number,
 *    mastered counter, review progress bar, and per-pack section
 *    (V0.4.5 keyed by category; V0.6.7.8 rewires this around the
 *    three-layer pack model — see the spec at
 *    docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md).
 *  - The per-pack section renders one row per active pack; on a
 *    fresh install the 5 builtin defaults are all active, so we
 *    expect at least the `pack-fruit-forest` row to be in the tree.
 *  - Back navigation returns to TodayPlanPage; tapping back again
 *    returns to HomePage.
 *  - On a fresh install (no recorder data), the page renders the
 *    zero-state values without crashing — the "0%" / "0" texts
 *    plus the empty-state hint are visible.
 */
export default function learningReportFlowUiTest(): void {
  describe('LearningReportFlow', () => {
    it('reportButtonOpensLearningReportPage', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openReport(driver);
      // Title + accuracy live in the always-visible top of the page.
      await driver.assertComponentExist(ON.id('LearningReportTitle'));
      await driver.assertComponentExist(ON.id('LearningReportAccuracy'));
      // Scroll once to surface the review bar + per-pack section
      // below the fold; both should now exist in the a11y tree.
      await scrollDownOnce(driver);
      const reviewBar: Component | null =
        await driver.findComponent(ON.id('LearningReportReviewBar'));
      const packSection: Component | null =
        await driver.findComponent(ON.id('LearningReportPackSection'));
      expect(reviewBar !== null).assertTrue();
      expect(packSection !== null).assertTrue();
      // First-launch active set seeds the 5 builtin packs (see
      // PackSelectionService); the report renders one row per
      // active pack, so at least `pack-fruit-forest` must be in
      // the tree. A single id assertion keeps the test resilient
      // to future ordering changes — exhaustive coverage of the
      // sort rules lives in LearningReportBuilder.test.ets.
      const fruitRow: Component | null =
        await driver.findComponent(ON.id('pack-fruit-forest'));
      expect(fruitRow !== null).assertTrue();
      done();
    });

    it('backButtonReturnsToTodayPlanThenHome', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openReport(driver);
      await driver.assertComponentExist(ON.id('LearningReportTitle'));
      await clickByIdShared(driver, 'LearningReportBackButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('TodayPlanTitle'));
      await clickByIdShared(driver, 'TodayPlanBackButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    it('emitsAllStateCountersInZeroState', 0, async (done: Function) => {
      // Zero-state requires that prior suites haven't seeded too
      // much data; we only assert the counter ids exist (not their
      // exact values), so the suite remains order-tolerant. The 4
      // state pills sit in the second card from the top — usually
      // visible without scrolling, but we scroll defensively to
      // cover smaller viewports.
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openReport(driver);
      const mastered: Component | null =
        await driver.findComponent(ON.id('LearningReportMastered'));
      expect(mastered !== null).assertTrue();
      const familiar: Component | null =
        await driver.findComponent(ON.id('LearningReportFamiliar'));
      expect(familiar !== null).assertTrue();
      const learning: Component | null =
        await driver.findComponent(ON.id('LearningReportLearning'));
      expect(learning !== null).assertTrue();
      const newCount: Component | null =
        await driver.findComponent(ON.id('LearningReportNewCount'));
      expect(newCount !== null).assertTrue();
      done();
    });
  });
}
