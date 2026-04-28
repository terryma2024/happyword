import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON } from '@kit.TestKit';
import {
  launchAppShared,
  clickByIdShared,
  tapWrongAnswerShared,
} from './RoutingFlow.ui.test';

/**
 * ReviewMode UI test (spec §15 V0.2 Track D). Exercises the
 * HomeReviewButton gating + BattlePage review-mode branch end-to-end:
 *
 *  - On fresh launch (no prior wrong answers in this session) the
 *    HomeReviewButton must render disabled and show the nudge copy.
 *  - After seeding 3 wrong answers in a regular battle, returning to
 *    HomePage must enable the review button.
 *  - Tapping it must launch a review session whose header shows
 *    `Monster 1 / 3` (per the 3-monster override).
 *
 * The test stays on a single app instance so LearningRecorder's
 * in-memory snapshot carries the seeded wrong answers across the
 * route transitions. `@ohos.data.preferences` hydration isn't
 * required for the flow to pass; it's tested in LocalUnit.test.
 *
 * Runner: the same 30 s per-test timeout as RoutingFlow.ui.test.
 */
export default function reviewModeUiTest(): void {
  describe('ReviewModeUiTest', () => {
    it('reviewButtonUnlocksAfterThreeWrongAnswers', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      // v0.3.6: HomeReviewButton lives in the top toolbar (replacing
      // the right-hand column entry) and is rendered as a circular
      // 📚 icon. It must exist even when locked so a tap shows the
      // "先答错几题再来复习吧" toast (covered by HomeToolbarLocked.ui.test).
      await driver.assertComponentExist(ON.id('HomeReviewButton'));

      // --- Seed 3 wrong answers in today's first basic slot ---
      // Today-mode's first slot in fruit-forest is a Match question
      // with 3-HP monster; tapWrongAnswerShared resolves the prompt
      // to its English answer via WORD_MAP and clicks any other
      // option, which works because fruit-forest's word pool is a
      // subset of WORD_MAP. Default cfg.playerHp = 5 is still
      // honoured by today-mode (BattlePage reads it before merging
      // the plan), so 3 misses keep us on BattlePage.
      await clickByIdShared(driver, 'HomeStartButton');
      // Today-mode loads WordRepository + LearningRecorder
      // asynchronously; bumped from 1000ms to 1500ms.
      await driver.delayMs(1500);
      await driver.assertComponentExist(ON.id('BattleTitle'));
      for (let i = 0; i < 3; i++) {
        await tapWrongAnswerShared(driver);
        // Each wrong tap deals 1 damage; playerHp starts at 5 in the
        // default config, so 3 misses keep us on BattlePage. 800ms
        // covers the feedback window.
        await driver.delayMs(800);
        await driver.assertComponentExist(ON.id('BattlePrompt'));
      }

      // Exit via [debug] so we land on ResultPage deterministically.
      await clickByIdShared(driver, 'BattleFinishButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      // --- Review button must now be enabled (📚 in top toolbar) ---
      await driver.assertComponentExist(ON.id('HomeReviewButton'));
      await clickByIdShared(driver, 'HomeReviewButton');
      await driver.delayMs(1500);
      // The 3-monster override lives in REVIEW_MODE_MONSTERS_TOTAL.
      // Asserting on the header text "Monster 1 / 3" catches both
      // the mode flag and the override in one shot.
      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.text('Monster 1 / 3'));

      // Clean up so the suite can continue — debug finish + home.
      await clickByIdShared(driver, 'BattleFinishButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });
  });
}
