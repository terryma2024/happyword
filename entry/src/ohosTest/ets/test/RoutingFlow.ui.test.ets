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

/**
 * zh -> en word mapping, mirrored from words_v1.json. Duplicated here
 * on purpose: the ohosTest HAP is a separate module and resolving the
 * main module's rawfile from a test would mean standing up a
 * ResourceManager context just for this flow. The source list is small
 * (30 entries) and stable, and any drift from words_v1.json will
 * surface as the win-flow test timing out on an unknown prompt — loud
 * and easy to diagnose.
 */
class WordMapEntry {
  zh: string = '';
  en: string = '';
}

const WORD_MAP: WordMapEntry[] = [
  { zh: '苹果', en: 'apple' },
  { zh: '香蕉', en: 'banana' },
  { zh: '橙子', en: 'orange' },
  { zh: '葡萄', en: 'grape' },
  { zh: '梨', en: 'pear' },
  { zh: '桃子', en: 'peach' },
  { zh: '柠檬', en: 'lemon' },
  { zh: '芒果', en: 'mango' },
  { zh: '瓜', en: 'melon' },
  { zh: '樱桃', en: 'cherry' },
  { zh: '学校', en: 'school' },
  { zh: '医院', en: 'hospital' },
  { zh: '公园', en: 'park' },
  { zh: '超市', en: 'supermarket' },
  { zh: '图书馆', en: 'library' },
  { zh: '动物园', en: 'zoo' },
  { zh: '银行', en: 'bank' },
  { zh: '博物馆', en: 'museum' },
  { zh: '车站', en: 'station' },
  { zh: '家', en: 'home' },
  { zh: '电视', en: 'TV' },
  { zh: '椅子', en: 'chair' },
  { zh: '床', en: 'bed' },
  { zh: '桌子', en: 'table' },
  { zh: '沙发', en: 'sofa' },
  { zh: '台灯', en: 'lamp' },
  { zh: '门', en: 'door' },
  { zh: '窗户', en: 'window' },
  { zh: '书', en: 'book' },
  { zh: '杯子', en: 'cup' }
];

function lookupEnglishAnswer(zhPrompt: string): string {
  for (let i = 0; i < WORD_MAP.length; i++) {
    if (WORD_MAP[i].zh === zhPrompt) {
      return WORD_MAP[i].en;
    }
  }
  return '';
}

/**
 * Read the current question's Chinese prompt, resolve it to the
 * expected English answer via WORD_MAP, find whichever of the three
 * option buttons has that text, and click it. Returns the English
 * answer that was clicked (useful for logging; the winFlow test uses
 * it to distinguish "no match" from successful clicks).
 */
async function tapCorrectAnswer(driver: Driver): Promise<string> {
  const promptComp = await driver.findComponent(ON.id('BattlePrompt'));
  const promptText: string = await promptComp.getText();
  const answer: string = lookupEnglishAnswer(promptText);
  if (answer === '') {
    throw new Error(`tapCorrectAnswer: unknown prompt "${promptText}"`);
  }
  // Options are rendered as child Text nodes of each button. Walking
  // the three button IDs lets us find the matching option without
  // scanning the whole tree.
  const optionIds: string[] = ['BattleOptionA', 'BattleOptionB', 'BattleOptionC'];
  for (let i = 0; i < optionIds.length; i++) {
    const btn = await driver.findComponent(ON.id(optionIds[i]));
    const text: string = await btn.getText();
    if (text.toLowerCase() === answer.toLowerCase()) {
      await btn.click();
      return answer;
    }
  }
  throw new Error(`tapCorrectAnswer: no option button matches answer "${answer}" for prompt "${promptText}"`);
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
      // Header labels: combo counter + timer. T8 wires a live 1Hz
      // countdown so the timer text changes during the test's delays;
      // we assert the ID exists (structural) rather than pinning the
      // exact text — tick correctness is covered in LocalUnit.test.ets.
      await driver.assertComponentExist(ON.id('BattleComboLabel'));
      await driver.assertComponentExist(ON.id('BattleTimerLabel'));
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
      // T8: ResultPage renders a real SessionResult. The debug [debug]
      // end-battle path forces the engine to Lost by ticking past the
      // countdown, so the headline is always "挑战失败". Stat numbers
      // depend on how many taps happened before the debug button was
      // pressed, so we assert the row IDs exist rather than pinning
      // specific numbers (that churn would fight the engine's RNG).
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await driver.assertComponentExist(ON.id('ResultStars'));
      await driver.assertComponentExist(ON.id('ResultDefeated'));
      await driver.assertComponentExist(ON.id('ResultAnswers'));
      await driver.assertComponentExist(ON.id('ResultAccuracy'));
      await driver.assertComponentExist(ON.id('ResultLearned'));
      await driver.assertComponentExist(ON.id('ResultRetryButton'));
      await driver.assertComponentExist(ON.id('ResultHomeButton'));
      await driver.assertComponentExist(ON.text('挑战失败'));
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

    /**
     * Win flow: play a full battle through to victory and verify the
     * ResultPage shows "胜利！" (spec §2.2). Counterpart to the two Lost
     * flows above, which exit via the debug [debug] end-battle button
     * and always produce a loss.
     *
     * Damage arithmetic (BattleEngine defaults: monster 3 HP, combo
     * threshold = 3, burst damage = 2):
     *   corr 1 -> dmg 1, mon 2/3 (combo 1)
     *   corr 2 -> dmg 1, mon 1/3 (combo 2)
     *   corr 3 -> BURST dmg 2, mon 0/3 defeat, combo reset
     * So exactly 3 correct answers defeat each monster, and 5 x 3 = 15
     * correct answers in a row clear all 5 monsters. The engine picks a
     * fresh (different-word) question after each submit, so every tap
     * can be resolved by zh->en lookup against WORD_MAP.
     *
     * On the 15th correct tap the engine enters Won inside the 650ms
     * feedback window and BattlePage navigates to ResultPage when it
     * fires. A single 900ms wait after the final click covers that
     * window plus the router transition.
     */
    it('winFlow_fifteenCorrectAnswersReachesVictory', 0, async (done: Function) => {
      const driver: Driver = await launchApp();

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      await clickById(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // 14 taps while BattlePage is still live — each loop reads the
      // current prompt, picks the matching option, then waits past the
      // feedback window for the next question to paint.
      for (let i = 0; i < 14; i++) {
        await tapCorrectAnswer(driver);
        await driver.delayMs(800);
        await driver.assertComponentExist(ON.id('BattlePrompt'));
      }

      // Final tap — this one ends the battle. Don't assert
      // BattlePrompt after: the reveal window will auto-navigate to
      // ResultPage. A slightly longer wait covers feedback + replaceUrl.
      await tapCorrectAnswer(driver);
      await driver.delayMs(900);

      // --- ResultPage (Won) ---
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await driver.assertComponentExist(ON.id('ResultStars'));
      await driver.assertComponentExist(ON.id('ResultDefeated'));
      await driver.assertComponentExist(ON.id('ResultAnswers'));
      await driver.assertComponentExist(ON.id('ResultAccuracy'));
      await driver.assertComponentExist(ON.id('ResultLearned'));
      await driver.assertComponentExist(ON.id('ResultRetryButton'));
      await driver.assertComponentExist(ON.id('ResultHomeButton'));
      // The critical assertion — victory headline. 100% correct with
      // all monsters defeated yields the Won path and 3 stars; we don't
      // pin the star count here (spec tiers are covered by
      // LocalUnit.test.ets) but the headline text IS the win contract.
      await driver.assertComponentExist(ON.text('胜利！'));
      await driver.assertComponentExist(ON.text('击败怪物：5 / 5'));
      await driver.assertComponentExist(ON.text('正确率：100%'));

      await clickById(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      expect(true).assertTrue();
      done();
    });
  });
}
