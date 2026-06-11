import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON } from '@kit.TestKit';
import { launchAppShared } from './RoutingFlow.ui.test';

/**
 * Navigate back to HomePage after a test. Each `it` block is required
 * to start AND end on HomePage so the next block (which may run in the
 * same app process) finds HomeStartButton / AdventureCard immediately.
 *
 * Strategy: press the system back button up to a few times until
 * HomeStartButton becomes visible. Cheaper than re-launching the app
 * and avoids the force-stop death spiral.
 */
async function returnToHome(driver: Driver): Promise<void> {
  try {
    for (let i = 0; i < 5; i++) {
      const home = await driver.findComponent(ON.id('HomeStartButton'));
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
 * Today-adventure UI suite. Smoke-tests the HomePage cluster
 * (adventure card, coin pill, wishlist button), the today-adventure
 * launch path (plan-driven battle starts with a prompt), the wishlist
 * page surface, and asserts the free-practice path is unbroken.
 */
export default function adventureFlowUiTest(): void {
  describe('AdventureFlow', () => {
    it('homePageShowsAdventureCardAndCoinPill', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();
      await returnToHome(driver);

      await driver.assertComponentExist(ON.id('AdventureCard'));
      await driver.assertComponentExist(ON.id('HomeCoinBalance'));
      await driver.assertComponentExist(ON.id('HomeWishlistButton'));

      expect(true).assertTrue();
      done();
    });

    it('todayAdventureLaunchesPlanBattleWithPrompt', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();
      await returnToHome(driver);

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      const cta = await driver.findComponent(ON.id('HomeStartButton'));
      await cta.click();
      await driver.delayMs(1500);

      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // Bail out via the [debug] end-battle escape hatch so the next
      // test starts on HomePage rather than mid-battle.
      const finish = await driver.findComponent(ON.id('BattleEscapeButton'));
      await finish.click();
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      const homeBtn = await driver.findComponent(ON.id('ResultHomeButton'));
      await homeBtn.click();
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });

    it('wishlistPageShowsThreeBuiltInWishes', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();
      await returnToHome(driver);

      await driver.assertComponentExist(ON.id('HomeWishlistButton'));
      const wishlistBtn = await driver.findComponent(ON.id('HomeWishlistButton'));
      await wishlistBtn.click();
      await driver.delayMs(800);

      await driver.assertComponentExist(ON.id('WishCard_wish-ipad-20min'));
      await driver.assertComponentExist(ON.id('WishCard_wish-watch-topup-10'));
      await driver.assertComponentExist(ON.id('WishCard_wish-small-gift'));

      // Return to HomePage so the next it() block lands on Home.
      await driver.pressBack();
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });

    /**
     * After v0.3.6 the HomeStartButton on HomePage opens today's
     * adventure (replacing the former normal-mode free-practice
     * path). This case smoke-tests that the tap reaches BattlePage
     * with a rendered title.
     */
    it('homeStartButtonOpensTodayAdventure', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();
      await returnToHome(driver);

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      const start = await driver.findComponent(ON.id('HomeStartButton'));
      await start.click();
      await driver.delayMs(1500);
      await driver.assertComponentExist(ON.id('BattleTitle'));

      // Bail out so the suite stays re-runnable.
      const finish = await driver.findComponent(ON.id('BattleEscapeButton'));
      await finish.click();
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      const homeBtn = await driver.findComponent(ON.id('ResultHomeButton'));
      await homeBtn.click();
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });

    it('homePageRegionPickerSwitchesPersistently', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();
      await returnToHome(driver);

      await driver.assertComponentExist(ON.id('RegionChip_fruit-forest'));
      await driver.assertComponentExist(ON.id('RegionChip_school-castle'));
      await driver.assertComponentExist(ON.id('RegionChip_home-cottage'));

      const schoolChip = await driver.findComponent(ON.id('RegionChip_school-castle'));
      await schoolChip.click();
      await driver.delayMs(400);

      const title = await driver.findComponent(ON.id('AdventureCardTitle'));
      const titleText: string = await title.getText();
      expect(titleText === 'School Castle').assertTrue();

      await returnToHome(driver);
      await driver.delayMs(300);
      const titleAfterReturn = await driver.findComponent(ON.id('AdventureCardTitle'));
      const titleTextAfter: string = await titleAfterReturn.getText();
      expect(titleTextAfter === 'School Castle').assertTrue();

      // Reset so subsequent suites start in fruit-forest.
      const fruitChip = await driver.findComponent(ON.id('RegionChip_fruit-forest'));
      await fruitChip.click();
      await driver.delayMs(300);

      done();
    });

    // Note: a v0.3.5-era `intermediateFillLetterAtomicFlow` case used
    // to live here, tapping options in A/B/C rotation while watching
    // for `'答对啦！下一空'`. That blind-tap policy was inherently
    // flaky (correct guess depended on RNG distractor placement) and
    // never asserted that the second step completes. The
    // FillLetterFlow suite (FillLetterFlow.ui.test.ets) supersedes
    // it with a deterministic answer policy that drives both step 0
    // and step 1 of FillLetterMedium plus the single-letter
    // FillLetter, so the legacy case has been removed to keep the
    // suite green.
  });
}
