import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON } from '@kit.TestKit';
import {
  launchAppShared,
  clickByIdShared,
  selectAllQuestionTypesShared,
  tapWrongAnswerShared,
} from './RoutingFlow.ui.test';
import {
  returnToHome,
  startTodayBattleChoiceOnly,
} from './UiTestBattleHelpers.ets';

/**
 * ReviewMode UI test. Exercises the v0.9.3 same-day exclusion:
 *
 *  - HomeReviewButton remains visible on the toolbar.
 *  - After seeding 1 wrong answer in a same-day regular battle, returning
 *    to HomePage must NOT enable review because today's stable review
 *    snapshot was computed from data before local midnight.
 *  - Tapping review shows the empty-review toast and stays on HomePage.
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
    it('sameDayWrongAnswerDoesNotUnlockReviewButton', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();
      await returnToHome(driver);

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      // v0.3.6: HomeReviewButton lives in the top toolbar (replacing
      // the right-hand column entry) and is rendered as a circular
      // icon button (📚 emoji in v0.3.6–v0.3.9, replaced by the
      // warm-parchment review.svg in v0.3.10). It must exist even
      // when locked so a tap shows the "先答错几题再来复习吧" toast
      // (covered by HomeToolbarLocked.ui.test).
      await driver.assertComponentExist(ON.id('HomeReviewButton'));

      // --- Seed 1 wrong answer in today's first basic slot ---
      // Today-mode's first slot in fruit-forest is a Match question
      // with 3-HP monster; tapWrongAnswerShared resolves the prompt
      // to its English answer via WORD_MAP and clicks any other
      // option, which works because fruit-forest's word pool is a
      // subset of WORD_MAP. Default cfg.playerHp = 10 is still
      // honoured by today-mode (BattlePage reads it before merging
      // the plan), so one miss keeps us on BattlePage.
      await startTodayBattleChoiceOnly(driver);
      await tapWrongAnswerShared(driver);
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // Exit via [debug] so we land on ResultPage deterministically.
      await clickByIdShared(driver, 'BattleEscapeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      // --- Same-day wrong answer is excluded from today's stable review list. ---
      await driver.assertComponentExist(ON.id('HomeReviewButton'));
      await clickByIdShared(driver, 'HomeReviewButton');
      await driver.delayMs(300);
      await driver.assertComponentExist(ON.id('HomeReviewEmptyToast'));
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      await selectAllQuestionTypesShared(driver);

      expect(true).assertTrue();
      done();
    });
  });
}
