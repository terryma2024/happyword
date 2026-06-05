import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { common, Want } from '@kit.AbilityKit';
import {
  clickByIdShared,
  resetBattleConfigForUiTestShared,
  selectOnlyQuestionTypeShared,
  tapWrongAnswerShared,
} from './RoutingFlow.ui.test';
import { waitForBattlePage } from './UiTestBattleHelpers.ets';
import { getLearningRecorder } from '../../../main/ets/services/LearningRecorder';
import { getDailyLearningStateService } from '../../../main/ets/services/DailyLearningStateService';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

async function launchApp(): Promise<Driver> {
  // ArkTS strict mode flags any direct @kit call as "Function may throw
  // exceptions. Special handling is required." — wrap the body in
  // try/catch+rethrow so the warning is silenced while preserving the
  // test failure semantics (a thrown ability-launch / driver-delay
  // error still propagates up to hypium's per-`it` handler).
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

/**
 * Navigate back to HomePage after a previous suite left the app
 * mid-flow. Mirrors AdventureFlow.ui.test's returnToHome — press
 * back up to 5 times until HomeStartButton resolves. Each `it`
 * block in this suite must start on HomePage so HomeReviewButton
 * is reachable; without this, the suite is order-dependent on
 * whoever ran before us in List.test.ets.
 */
async function returnToHome(driver: Driver): Promise<void> {
  // See `launchApp` rationale for why the body is wrapped in try/catch.
  try {
    for (let i = 0; i < 5; i++) {
      const home: Component | null =
        await driver.findComponent(ON.id('HomeStartButton'));
      if (home !== null) {
        return;
      }
      const codexBack: Component | null =
        await driver.findComponent(ON.id('CodexBackButton'));
      if (codexBack !== null) {
        await codexBack.click();
        await driver.delayMs(800);
        continue;
      }
      await driver.pressBack();
      await driver.delayMs(500);
    }
  } catch (err) {
    throw err as Error;
  }
}

async function clearLearningRecordsAndRefreshHome(driver: Driver): Promise<void> {
  try {
    const ability = await DELEGATOR.getCurrentTopAbility();
    const ctx: common.UIAbilityContext = ability.context as common.UIAbilityContext;
    const recorder = getLearningRecorder();
    await recorder.init(ctx);
    await recorder.clear();
    const daily = getDailyLearningStateService();
    await daily.init(ctx);
    await daily.clearForTest();

    // HomePage caches `recentWrongCount` in @State and refreshes it from
    // LearningRecorder in `onPageShow`. Bounce through a lightweight page so
    // the visible HomeReviewButton state reflects the cleared persistent
    // `wordmagic_learning` snapshot before the locked-toast assertion.
    await driver.assertComponentExist(ON.id('HomeCodexButton'));
    await clickByIdShared(driver, 'HomeCodexButton');
    await driver.delayMs(800);
    await clickByIdShared(driver, 'CodexBackButton');
    await driver.delayMs(800);
    await driver.assertComponentExist(ON.id('HomeStartButton'));
  } catch (err) {
    throw err as Error;
  }
}

async function seedOneWrongAnswerViaBattle(driver: Driver): Promise<string> {
  try {
    await selectOnlyQuestionTypeShared(driver, 'choice');
    await clickByIdShared(driver, 'HomeStartButton');
    await waitForBattlePage(driver);
    await driver.assertComponentExist(ON.id('BattlePrompt'));
    const prompt: Component | null =
      await driver.findComponent(ON.id('BattlePrompt'));
    const promptText: string = prompt !== null ? await prompt.getText() : '';
    await tapWrongAnswerShared(driver);
    await driver.delayMs(800);
    await driver.assertComponentExist(ON.id('BattlePrompt'));
    await clickByIdShared(driver, 'BattleEscapeButton');
    await driver.delayMs(800);
    await driver.assertComponentExist(ON.id('ResultTitle'));
    await clickByIdShared(driver, 'ResultHomeButton');
    await driver.delayMs(800);
    await driver.assertComponentExist(ON.id('HomeStartButton'));
    return promptText;
  } catch (err) {
    throw err as Error;
  }
}

/**
 * v0.3.6 toolbar acceptance:
 *  - HomeReviewButton (📚 emoji in v0.3.6–v0.3.9, review.svg from
 *    v0.3.10) lives in the top toolbar (not the deleted right
 *    column), and the dev-only 🧪 HomeTtsTestButton is gone.
 *  - The review button has two stateful modes backed by the persisted
 *    `wordmagic_learning` snapshot:
 *      1. clear learning records → review is locked → tapping shows
 *         HomeReviewEmptyToast and stays on HomePage.
 *      2. make one wrong answer in a same-day real battle → review
 *         stays locked because v0.9.3 excludes same-day wrong words
 *         from today's stable review snapshot.
 *
 * Keep those two checks in this order. Splitting or reordering them makes
 * the suite depend on whatever learning records the device had from a
 * previous manual session or UI run, which is exactly the flake this suite
 * is meant to prevent.
 */
export default function homeToolbarLockedUiTest(): void {
  describe('HomeToolbarLocked', () => {
    it('topToolbarHasReviewNotTts', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await driver.assertComponentExist(ON.id('HomeReviewButton'));
      const tts: Component | null =
        await driver.findComponent(ON.id('HomeTtsTestButton'));
      expect(tts === null).assertTrue();
      done();
    });

    it('lockedReviewShowsToastAndStays', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await clearLearningRecordsAndRefreshHome(driver);

      try {
        await clickByIdShared(driver, 'HomeReviewButton');
        await driver.delayMs(300);
        await driver.assertComponentExist(ON.id('HomeReviewEmptyToast'));
        await driver.assertComponentExist(ON.id('HomeStartButton'));
        await driver.delayMs(1800);
        const toast: Component | null =
          await driver.findComponent(ON.id('HomeReviewEmptyToast'));
        expect(toast === null).assertTrue();

        const seededWrongPrompt: string = await seedOneWrongAnswerViaBattle(driver);
        expect(seededWrongPrompt.length > 0).assertTrue();

        await clickByIdShared(driver, 'HomeReviewButton');
        await driver.delayMs(300);
        await driver.assertComponentExist(ON.id('HomeReviewEmptyToast'));
        await driver.assertComponentExist(ON.id('HomeStartButton'));
      } finally {
        await clearLearningRecordsAndRefreshHome(driver);
        resetBattleConfigForUiTestShared();
      }
      done();
    });
  });
}
