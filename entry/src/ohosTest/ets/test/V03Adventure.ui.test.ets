import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

/**
 * Cold-launch helper. Mirrors RoutingFlow's launchApp so the V0.3 suite
 * shares the 1s settle window and avoids force-stopping the bundle —
 * force-stop kills the test runner alongside the app and surfaces as
 * "App died" in the runner output.
 */
async function launchApp(): Promise<Driver> {
  const want: Want = { bundleName: BUNDLE, abilityName: 'EntryAbility' };
  await DELEGATOR.startAbility(want);
  const driver: Driver = Driver.create();
  await driver.delayMs(1000);
  return driver;
}

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
  for (let i = 0; i < 5; i++) {
    const home = await driver.findComponent(ON.id('HomeStartButton'));
    if (home !== null) {
      return;
    }
    await driver.pressBack();
    await driver.delayMs(500);
  }
}

/**
 * V0.3 acceptance UI suite. Smoke-tests the new HomePage cluster
 * (adventure card, coin pill, wishlist button), the today-adventure
 * launch path (plan-driven battle starts with a prompt), the wishlist
 * page surface, and asserts the V0.2 free-practice path is unbroken.
 */
export default function v03AdventureUiTest(): void {
  describe('V0.3 today adventure flow', () => {
    it('homePageShowsAdventureCardAndCoinPill', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);

      await driver.assertComponentExist(ON.id('AdventureCard'));
      await driver.assertComponentExist(ON.id('HomeCoinBalance'));
      await driver.assertComponentExist(ON.id('HomeWishlistButton'));

      expect(true).assertTrue();
      done();
    });

    it('todayAdventureLaunchesPlanBattleWithPrompt', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);

      await driver.assertComponentExist(ON.id('AdventureCardCta'));
      const cta = await driver.findComponent(ON.id('AdventureCardCta'));
      await cta.click();
      await driver.delayMs(1500);

      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // Bail out via the [debug] end-battle escape hatch so the next
      // test starts on HomePage rather than mid-battle.
      const finish = await driver.findComponent(ON.id('BattleFinishButton'));
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
      const driver: Driver = await launchApp();
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

    it('freePracticeButtonStillStartsBattle', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      const start = await driver.findComponent(ON.id('HomeStartButton'));
      await start.click();
      await driver.delayMs(1500);
      await driver.assertComponentExist(ON.id('BattleTitle'));

      // Bail out so the suite stays re-runnable.
      const finish = await driver.findComponent(ON.id('BattleFinishButton'));
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
      const driver: Driver = await launchApp();
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

    it('intermediateFillLetterAtomicFlow', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);

      const fruitChip = await driver.findComponent(ON.id('RegionChip_fruit-forest'));
      await fruitChip.click();
      await driver.delayMs(300);

      const cta = await driver.findComponent(ON.id('AdventureCardCta'));
      await cta.click();
      await driver.delayMs(1500);

      const optionIds: string[] = ['BattleOptionA', 'BattleOptionB', 'BattleOptionC'];
      let stepAdvancedSeen: boolean = false;
      for (let turn = 0; turn < 12 && !stepAdvancedSeen; turn++) {
        const optId: string = optionIds[turn % 3];
        const btn = await driver.findComponent(ON.id(optId));
        if (btn === null) {
          break;
        }
        await btn.click();
        await driver.delayMs(250);
        const feedback = await driver.findComponent(ON.id('BattleFeedback'));
        if (feedback !== null) {
          const text: string = await feedback.getText();
          if (text === '答对啦！下一空') {
            stepAdvancedSeen = true;
          }
        }
        await driver.delayMs(550);
      }

      expect(stepAdvancedSeen).assertTrue();

      const finish = await driver.findComponent(ON.id('BattleFinishButton'));
      if (finish !== null) {
        await finish.click();
        await driver.delayMs(800);
      }
      await returnToHome(driver);

      done();
    });
  });
}
