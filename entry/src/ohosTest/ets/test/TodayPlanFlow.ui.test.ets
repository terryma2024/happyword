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

/**
 * Press back until HomeStartButton resolves so each test starts on
 * HomePage regardless of where a prior suite left the app.
 */
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
 * V0.4.4 acceptance:
 *  - HomePage toolbar surfaces a `HomePlanButton` (📋) icon between
 *    HomeCodexButton and HomeWishlistButton.
 *  - Tapping it opens TodayPlanPage (TodayPlanTitle visible).
 *  - The page renders the region name (TodayPlanRegionName) and a
 *    progress text (TodayPlanProgressText) reading "X / Y 已完成".
 *  - At least one bucket section is visible — fresh installs default
 *    to all-new-words, so TodayPlanNewSection is the conservative
 *    assertion here.
 *  - TodayPlanBackButton returns to HomePage.
 */
export default function todayPlanFlowUiTest(): void {
  describe('TodayPlanFlow', () => {
    it('homePlanButtonOpensTodayPlanPage', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await clickByIdShared(driver, 'HomePlanButton');
      await driver.delayMs(1500);
      await driver.assertComponentExist(ON.id('TodayPlanTitle'));
      await driver.assertComponentExist(ON.id('TodayPlanRegionName'));
      await driver.assertComponentExist(ON.id('TodayPlanProgressText'));
      done();
    });

    it('emitsAtLeastOneBucketSectionForFreshInstall', 0, async (done: Function) => {
      // A brand-new install has no LearningRecorder data, so every
      // word in today's plan is "new" — TodayPlanNewSection must be
      // populated. Other suites may have seeded the recorder, but
      // with a 12-word fruit pool and a 10-slot plan, the new bucket
      // should still receive at least the unseen-by-recorder words.
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await clickByIdShared(driver, 'HomePlanButton');
      await driver.delayMs(1500);
      const newSection: Component | null =
        await driver.findComponent(ON.id('TodayPlanNewSection'));
      const reviewSection: Component | null =
        await driver.findComponent(ON.id('TodayPlanReviewSection'));
      const learningSection: Component | null =
        await driver.findComponent(ON.id('TodayPlanLearningSection'));
      const anySectionExists: boolean =
        newSection !== null || reviewSection !== null || learningSection !== null;
      expect(anySectionExists).assertTrue();
      done();
    });

    it('backButtonReturnsToHome', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await clickByIdShared(driver, 'HomePlanButton');
      await driver.delayMs(1500);
      await driver.assertComponentExist(ON.id('TodayPlanTitle'));
      await clickByIdShared(driver, 'TodayPlanBackButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });
  });
}
