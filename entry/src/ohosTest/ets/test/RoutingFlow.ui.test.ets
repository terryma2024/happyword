import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';

/**
 * UI smoke test for the three-page routing skeleton (spec §6.1 / §6.2 / §6.3 /
 * §6.4): HomePage -> BattlePage -> ResultPage -> HomePage, plus the Retry loop
 * Result -> BattlePage -> ResultPage.
 *
 * Both tests are authored to START and END on HomePage, so the hypium runner
 * (which keeps the app foregrounded between `it` blocks and makes `startAbility`
 * a no-op) can execute them sequentially without state leaking across tests.
 *
 * HYPIUM TIMEOUT: `it(desc, filter, func)` does NOT accept an inline timeout —
 * hypium v1.0.25 forces a global 5s per-test timeout unless the runner is
 * invoked with `-s timeout <ms>`. Our flows exceed 5s (multiple 800ms settle
 * waits + findComponent polls), so the canonical command in
 * `.cursor/dev-commands.md` passes `-s timeout 30000`. When adding a new
 * describe/it, run with that flag or the test will report
 * `execute timeout 5000ms`.
 */

const delegator: abilityDelegatorRegistry.AbilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();

async function launchApp(): Promise<Driver> {
  const bundleName: string = abilityDelegatorRegistry.getArguments().bundleName;
  const want: Want = { bundleName, abilityName: 'EntryAbility' };
  await delegator.startAbility(want);
  const driver: Driver = Driver.create();
  // First cold launch needs ~1s for the window stage and HomePage build; use
  // the driver's own clock rather than a custom setTimeout so the wait is
  // reported in the hypium trace.
  await driver.delayMs(1000);
  return driver;
}

/**
 * Click the button with the given id after asserting it exists. `findComponent`
 * alone returns null when the component is missing and the subsequent `.click`
 * throws a confusing "Cannot read property click of null" — asserting first
 * gives a clear component-not-found error at the point of failure.
 */
async function clickById(driver: Driver, id: string): Promise<void> {
  await driver.assertComponentExist(ON.id(id));
  const comp = await driver.findComponent(ON.id(id));
  await comp.click();
}

export default function routingFlowUiTest(): void {
  describe('RoutingFlowUiTest', () => {
    /**
     * Main flow with content assertions and negative option-button coverage:
     *
     * 1. HomePage renders IDs + Chinese subtitle and hint text.
     * 2. Click Start -> BattlePage renders title, player HP, monster HP, combo.
     * 3. Clicking each of the three option buttons keeps us on BattlePage
     *    (they are skeleton stubs until QuestionGenerator wires up in T6).
     * 4. Click BattleFinishButton -> ResultPage renders title + all stat rows.
     * 5. Click ResultHomeButton -> back on HomePage.
     */
    it('mainFlow_homeBattleResultHome', 0, async (done: Function) => {
      const driver: Driver = await launchApp();

      // --- HomePage ---
      await driver.assertComponentExist(ON.id('HomeTitle'));
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      // Content: per spec §6.2 the home screen shows a Chinese subtitle and a
      // child-friendly hint. Asserting the text itself (not just IDs) catches
      // accidental copy changes and empty-text regressions.
      await driver.assertComponentExist(ON.text('小魔法师单词冒险'));
      await driver.assertComponentExist(ON.text('点击开始，打败 5 个单词史莱姆吧！'));
      await driver.assertComponentExist(ON.text('开始游戏'));

      await clickById(driver, 'HomeStartButton');
      await driver.delayMs(800);

      // --- BattlePage ---
      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('PlayerArea'));
      await driver.assertComponentExist(ON.id('MonsterArea'));
      await driver.assertComponentExist(ON.id('QuestionArea'));
      // T6 rationale: the engine loads `words_v1.json` asynchronously in
      // `aboutToAppear`, so this 800ms buffer (after the HomeStartButton
      // tap above) lets the first real question paint before assertions
      // that depend on engine state. On a cold emulator, the repo load
      // typically finishes within ~200ms.
      //
      // Content: player card renders full HP (5/5) and monster card shows
      // its own HP (3/3). These are engine-driven defaults
      // (DEFAULT_PLAYER_HP / DEFAULT_MONSTER_HP), asserted so a regression
      // that zeros out HP on boot is caught immediately.
      await driver.assertComponentExist(ON.text('HP 5 / 5'));
      await driver.assertComponentExist(ON.text('HP 3 / 3'));
      await driver.assertComponentExist(ON.text('Combo: 0'));
      // Static-T5 header labels still apply: combo counter and the static
      // timer readout (timer wiring is deferred past T6). "Time 05:00"
      // matches BattlePage.formatTime(DEFAULT_STARTING_SECONDS=300).
      await driver.assertComponentExist(ON.id('BattleComboLabel'));
      await driver.assertComponentExist(ON.id('BattleTimerLabel'));
      await driver.assertComponentExist(ON.text('Time 05:00'));
      await driver.assertComponentExist(ON.text('Monster 1 / 5'));
      // All three option buttons render. After T6 the texts are real
      // English words from words_v1.json (chosen by the engine's default
      // RNG, so we don't pin them here) — asserting ID existence is
      // sufficient to catch button regressions.
      await driver.assertComponentExist(ON.id('BattleOptionA'));
      await driver.assertComponentExist(ON.id('BattleOptionB'));
      await driver.assertComponentExist(ON.id('BattleOptionC'));
      // BattleFeedback is a dedicated Text slot that holds per-answer
      // feedback ("正确！" / "正确答案是 ..."). Asserting the ID exists even
      // when idle catches layout regressions that would otherwise only
      // surface mid-game.
      await driver.assertComponentExist(ON.id('BattleFeedback'));

      // Behavioural coverage: tapping an option must NOT immediately route
      // away from BattlePage. The engine handles win/lose transitions but
      // a single tap on a cold game cannot end the session (default config
      // is 5 monsters × 3 HP, player 5 HP), so we should stay on the
      // battle page after each tap. The 800ms delay covers the 650ms
      // reveal window plus a small margin.
      await clickById(driver, 'BattleOptionA');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('BattleTitle'));
      await clickById(driver, 'BattleOptionB');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('BattleTitle'));

      // Use the debug escape hatch to jump to ResultPage deterministically —
      // testing the full win/lose flow with random words would require
      // seeding the engine from outside the app, which is out of scope.
      await clickById(driver, 'BattleFinishButton');
      await driver.delayMs(800);

      // --- ResultPage ---
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await driver.assertComponentExist(ON.id('ResultRetryButton'));
      await driver.assertComponentExist(ON.id('ResultHomeButton'));
      // Content: all four stat rows per spec §6.4. Stats are static placeholders
      // in T2 (wired to SessionResult in T8) — asserting them now makes it
      // obvious when the wiring arrives by failing the test with a text diff.
      await driver.assertComponentExist(ON.text('本局结果（占位）'));
      await driver.assertComponentExist(ON.text('击败怪物：0 / 5'));
      await driver.assertComponentExist(ON.text('正确率：0%'));
      await driver.assertComponentExist(ON.text('学习单词：0'));
      await driver.assertComponentExist(ON.text('星级：☆☆☆'));
      await driver.assertComponentExist(ON.text('再来一局'));
      await driver.assertComponentExist(ON.text('返回首页'));

      await clickById(driver, 'ResultHomeButton');
      await driver.delayMs(800);

      // --- Back on HomePage ---
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      expect(true).assertTrue();
      done();
    });

    /**
     * Retry flow: verifies that the Result screen's "再来一局" button returns
     * the user to BattlePage (router.replaceUrl to pages/BattlePage) rather
     * than leaving them stuck on Result or routing them to HomePage.
     *
     * Walks Home -> Battle -> Result -> Retry -> Battle -> Finish -> Result
     * -> Home so that the test begins AND ends on HomePage, matching the
     * invariant required to run after the main-flow test.
     */
    it('retryFlow_resultRetryReopensBattlePage', 0, async (done: Function) => {
      const driver: Driver = await launchApp();

      // Prerequisite: we start on HomePage (previous test ended here).
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      await clickById(driver, 'HomeStartButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('BattleTitle'));

      await clickById(driver, 'BattleFinishButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await driver.assertComponentExist(ON.id('ResultRetryButton'));

      // The critical assertion: clicking Retry routes back to BattlePage, not
      // HomePage and not a stale ResultPage. This guards ResultPage.ets:40
      // which is the only place where router.replaceUrl('pages/BattlePage') is
      // invoked in the whole app.
      await clickById(driver, 'ResultRetryButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('BattleOptionA'));
      await driver.assertComponentExist(ON.id('BattleFinishButton'));

      // Return to HomePage so the suite remains re-runnable and any future
      // test added after this one can assume a clean HomePage starting state.
      await clickById(driver, 'BattleFinishButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await clickById(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });
  });
}
