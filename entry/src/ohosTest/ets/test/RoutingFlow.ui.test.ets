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
 * Ensure a category chip ends in the requested selected state,
 * regardless of starting state. Reads chip selection from the chip's
 * text (ConfigPage prefixes active chips with "✓") so helpers are
 * idempotent across tests that share AppStorage.
 *
 * Button.selected() is not part of ButtonAttribute in this ArkTS
 * toolchain, so the ✓ prefix is the simplest introspection channel.
 *
 * Guard: toggleCategory silently refuses to turn off the last active
 * category. Callers must turn wanted chips ON before turning unwanted
 * ones OFF so the guard never fires mid-helper.
 */
async function setChipSelected(driver: Driver, chipId: string, wantSelected: boolean): Promise<void> {
  const chip = await driver.findComponent(ON.id(chipId));
  const text: string = await chip.getText();
  const isOn: boolean = text.indexOf('✓') === 0;
  if (isOn !== wantSelected) {
    await chip.click();
    await driver.delayMs(80);
  }
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
  { zh: '杯子', en: 'cup' },
  // Custom-word entries used by configCustomWordsOnly_oneShotVictory.
  // Kept in lock-step with CUSTOM_TEST_RAW below.
  { zh: '一只狗', en: 'dog' },
  { zh: '一只猫', en: 'cat' },
  { zh: '太阳', en: 'sun' }
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

/**
 * Ten Chinese prompts in the 'fruit' category. When GameConfig restricts
 * enabledCategories to ['fruit'], every question's prompt MUST be in
 * this set — asserting it makes category filtering visible in output.
 */
const FRUIT_PROMPTS: string[] = [
  '苹果', '香蕉', '橙子', '葡萄', '梨',
  '桃子', '柠檬', '芒果', '瓜', '樱桃'
];

function isFruitPrompt(prompt: string): boolean {
  for (let i = 0; i < FRUIT_PROMPTS.length; i++) {
    if (FRUIT_PROMPTS[i] === prompt) {
      return true;
    }
  }
  return false;
}

/**
 * Prompts used in the custom-words E2E test. Kept in lock-step with the
 * raw text passed to openCustomWordsAndSave in that test AND with the
 * WORD_MAP additions above so tapCorrectAnswer can resolve them.
 */
const CUSTOM_TEST_PROMPTS: string[] = ['一只狗', '一只猫', '太阳'];
const CUSTOM_TEST_RAW: string = '一只狗:dog\n一只猫:cat\n太阳:sun';

function isCustomTestPrompt(prompt: string): boolean {
  for (let i = 0; i < CUSTOM_TEST_PROMPTS.length; i++) {
    if (CUSTOM_TEST_PROMPTS[i] === prompt) {
      return true;
    }
  }
  return false;
}

/**
 * Inverse of tapCorrectAnswer: reads the current prompt, resolves the
 * correct English via WORD_MAP, then clicks any option button whose
 * text is NOT that answer. Returns the wrong-answer text that was
 * clicked (for diagnostic logging).
 */
async function tapWrongAnswer(driver: Driver): Promise<string> {
  const promptComp = await driver.findComponent(ON.id('BattlePrompt'));
  const promptText: string = await promptComp.getText();
  const correct: string = lookupEnglishAnswer(promptText);
  if (correct === '') {
    throw new Error(`tapWrongAnswer: unknown prompt "${promptText}"`);
  }
  const optionIds: string[] = ['BattleOptionA', 'BattleOptionB', 'BattleOptionC'];
  for (let i = 0; i < optionIds.length; i++) {
    const btn = await driver.findComponent(ON.id(optionIds[i]));
    const text: string = await btn.getText();
    if (text.toLowerCase() !== correct.toLowerCase()) {
      await btn.click();
      return text;
    }
  }
  throw new Error(`tapWrongAnswer: all 3 options matched correct answer "${correct}"`);
}

/**
 * Plain-old-data carrier passed to openConfigAndApply. Defaults mirror
 * the GameConfig defaults so tests only have to set the fields they
 * actually care about.
 */
class TestGameConfig {
  playerHp: number = 5;
  monsterHp: number = 3;
  monstersTotal: number = 5;
  timerChipId: string = 'ConfigTimer300s';
  categories: string[] = ['fruit']; // may include 'custom'
}

/**
 * Bidirectional stepper driver: reads the current value from the
 * stepper's value Text id, then taps either the "-" or "+" button
 * until the shown value matches target. Necessary because tests run
 * sequentially against a shared AppStorage — a test that wants a
 * higher value than the previous test cannot rely on decrementing.
 */
async function stepStepperTo(driver: Driver, decId: string, incId: string,
                             valueId: string, target: number): Promise<void> {
  const valueComp = await driver.findComponent(ON.id(valueId));
  const curText: string = await valueComp.getText();
  const current: number = parseInt(curText, 10);
  if (current > target) {
    for (let i = current; i > target; i--) {
      const dec = await driver.findComponent(ON.id(decId));
      await dec.click();
      await driver.delayMs(80);
    }
  } else if (current < target) {
    for (let i = current; i < target; i++) {
      const inc = await driver.findComponent(ON.id(incId));
      await inc.click();
      await driver.delayMs(80);
    }
  }
}

function categoryChipId(cat: string): string {
  if (cat === 'fruit') return 'ConfigCategoryFruit';
  if (cat === 'place') return 'ConfigCategoryPlace';
  if (cat === 'home') return 'ConfigCategoryHome';
  if (cat === 'custom') return 'ConfigCategoryCustom';
  throw new Error(`categoryChipId: unknown category "${cat}"`);
}

/**
 * From HomePage: open ConfigPage, apply steppers/timer/categories,
 * then Save. Precondition: HomePage visible. Postcondition: back on
 * HomePage with AppStorage updated.
 *
 * Category ordering: toggle-on wanted categories first, then toggle-off
 * unwanted ones. This way the "last-chip-cannot-be-removed" guard
 * never fires mid-helper.
 */
async function openConfigAndApply(driver: Driver, cfg: TestGameConfig): Promise<void> {
  await driver.assertComponentExist(ON.id('HomeConfigButton'));
  const gear = await driver.findComponent(ON.id('HomeConfigButton'));
  await gear.click();
  // Longer wait: ConfigPage loads words_v1.json asynchronously in
  // aboutToAppear and Save-time validation needs that list to be
  // populated. 1500ms gives the rawfile load headroom on a cold emu.
  await driver.delayMs(1500);
  await driver.assertComponentExist(ON.id('ConfigTitle'));

  await stepStepperTo(driver, 'ConfigPlayerHpDec', 'ConfigPlayerHpInc',
    'ConfigPlayerHpValue', cfg.playerHp);
  await stepStepperTo(driver, 'ConfigMonsterHpDec', 'ConfigMonsterHpInc',
    'ConfigMonsterHpValue', cfg.monsterHp);
  await stepStepperTo(driver, 'ConfigMonstersTotalDec', 'ConfigMonstersTotalInc',
    'ConfigMonstersTotalValue', cfg.monstersTotal);

  // Timer chip: clicking a chip that is already the active timer is a
  // no-op in ConfigPage.selectTimer, so we can safely click the wanted
  // chip without checking its current state.
  await driver.assertComponentExist(ON.id(cfg.timerChipId));
  const tchip = await driver.findComponent(ON.id(cfg.timerChipId));
  await tchip.click();
  await driver.delayMs(80);

  // Category chips: read actual chip state via isSelected() rather
  // than assuming the default-on set. State leaks across tests when
  // the previous test left enabledCategories != default, so assuming
  // defaults breaks the second config test onward.
  const wanted: string[] = cfg.categories;
  const allCats: string[] = ['fruit', 'place', 'home', 'custom'];

  // Step 1: turn ON every wanted chip first. This guarantees we never
  // hit the last-chip guard while turning off the unwanted ones.
  for (let i = 0; i < wanted.length; i++) {
    await setChipSelected(driver, categoryChipId(wanted[i]), true);
  }
  // Step 2: turn OFF every chip that isn't wanted.
  for (let i = 0; i < allCats.length; i++) {
    if (wanted.indexOf(allCats[i]) < 0) {
      await setChipSelected(driver, categoryChipId(allCats[i]), false);
    }
  }

  const save = await driver.findComponent(ON.id('ConfigSaveButton'));
  await save.click();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('HomeStartButton'));
}

/**
 * From HomePage: open ConfigPage, enter CustomWordsPage via the edit
 * icon, replace the TextArea contents, tap Save, and exit ConfigPage
 * via Cancel so stepper/category defaults stay untouched.
 *
 * Precondition: HomePage visible.
 * Postcondition: HomePage visible; only GameConfig.customWordsRaw
 *                has been mutated in AppStorage.
 */
async function openCustomWordsAndSave(driver: Driver, rawText: string): Promise<void> {
  await driver.assertComponentExist(ON.id('HomeConfigButton'));
  const gear = await driver.findComponent(ON.id('HomeConfigButton'));
  await gear.click();
  await driver.delayMs(1500);
  await driver.assertComponentExist(ON.id('ConfigCategoryCustomEdit'));

  const editIcon = await driver.findComponent(ON.id('ConfigCategoryCustomEdit'));
  await editIcon.click();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('CustomWordsTextArea'));

  const ta = await driver.findComponent(ON.id('CustomWordsTextArea'));
  await ta.inputText(rawText);
  await driver.delayMs(300);
  // inputText pops the soft keyboard on the emulator, which covers the
  // Save button and makes findComponent return null. pressBack
  // dismisses it so the Save button returns to the visible set.
  await driver.pressBack();
  await driver.delayMs(500);

  await driver.assertComponentExist(ON.id('CustomWordsSaveButton'));
  const save = await driver.findComponent(ON.id('CustomWordsSaveButton'));
  await save.click();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('ConfigTitle'));

  // Exit ConfigPage without altering other fields.
  const cancel = await driver.findComponent(ON.id('ConfigCancelButton'));
  await cancel.click();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('HomeStartButton'));
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

    /**
     * Config-driven short Win: configure a 1-monster / 1-HP battle on
     * the 'fruit' category only, then land the kill in a single correct
     * tap. Uses openConfigAndApply so the Save path (ConfigPage ->
     * HomePage with AppStorage mutated) is exercised end-to-end rather
     * than via the debug escape hatch.
     */
    it('configShortWin_oneShotVictory', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      const cfg: TestGameConfig = new TestGameConfig();
      cfg.playerHp = 5;
      cfg.monsterHp = 1;
      cfg.monstersTotal = 1;
      cfg.timerChipId = 'ConfigTimer60s';
      cfg.categories = ['fruit'];
      await openConfigAndApply(driver, cfg);

      await clickById(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // Confirm category filtering: prompt MUST be a fruit word since
      // we disabled 'place' and 'home' via openConfigAndApply.
      const promptComp = await driver.findComponent(ON.id('BattlePrompt'));
      const prompt: string = await promptComp.getText();
      expect(isFruitPrompt(prompt)).assertTrue();

      await tapCorrectAnswer(driver);
      await driver.delayMs(900);

      await driver.assertComponentExist(ON.id('ResultTitle'));
      await driver.assertComponentExist(ON.text('胜利！'));
      await driver.assertComponentExist(ON.text('击败怪物：1 / 1'));
      await driver.assertComponentExist(ON.text('正确率：100%'));

      await clickById(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });

    /**
     * Config-driven timeout loss: set the countdown to 3 seconds, start
     * the battle, and wait without tapping. After ~3s the engine's
     * tick loop pushes remainingSeconds to 0, flips status to Lost,
     * and BattlePage auto-navigates to ResultPage showing 挑战失败.
     *
     * Covers the spec §4.1 "倒计时结束" loss branch end-to-end
     * without touching the debug finish button.
     */
    it('configTimerExpiry_lossOnTimeout', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      const cfg: TestGameConfig = new TestGameConfig();
      cfg.playerHp = 5;
      cfg.monsterHp = 3;
      cfg.monstersTotal = 5;
      cfg.timerChipId = 'ConfigTimer3s';
      cfg.categories = ['fruit'];
      await openConfigAndApply(driver, cfg);

      await clickById(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // No taps — let the 3s timer run down. Five seconds covers the
      // three ticks, any jitter, the 650ms feedback window cleanup,
      // and the router.replaceUrl to ResultPage.
      await driver.delayMs(5000);

      await driver.assertComponentExist(ON.id('ResultTitle'));
      await driver.assertComponentExist(ON.text('挑战失败'));
      // Zero correct answers across the whole session -> 0 defeated.
      await driver.assertComponentExist(ON.text('击败怪物：0 / 5'));

      await clickById(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });

    /**
     * Config-driven HP-zero loss: set playerHp to the 1-HP minimum on
     * a long timer, then answer incorrectly once. Wrong answer deals 1
     * damage (spec §4.3), so the single miss drops HP to 0 and flips
     * the engine to Lost without a timeout.
     *
     * Covers the spec §4.1 "玩家 HP 为 0" loss branch end-to-end
     * without the debug finish button.
     */
    it('configHpZero_lossOnWrongAnswers', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      const cfg: TestGameConfig = new TestGameConfig();
      cfg.playerHp = 1;
      cfg.monsterHp = 3;
      cfg.monstersTotal = 5;
      cfg.timerChipId = 'ConfigTimer300s';
      cfg.categories = ['fruit'];
      await openConfigAndApply(driver, cfg);

      await clickById(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // Single wrong tap -> HP 0 -> Lost. 1000ms covers the 650ms
      // feedback reveal and the router replaceUrl to ResultPage.
      await tapWrongAnswer(driver);
      await driver.delayMs(1000);

      await driver.assertComponentExist(ON.id('ResultTitle'));
      await driver.assertComponentExist(ON.text('挑战失败'));
      // No monster was defeated (player died mid first encounter).
      await driver.assertComponentExist(ON.text('击败怪物：0 / 5'));

      await clickById(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });

    /**
     * Config-driven custom-words win: seed three custom words via
     * CustomWordsPage, switch the ConfigPage category chips to
     * 'custom' only, configure a 1-monster / 1-HP battle, then win in
     * a single correct tap against a custom prompt.
     *
     * Validates the whole custom-words flow:
     *   CustomWordsPage text input -> AppStorage.customWordsRaw
     *   ConfigPage 'custom' chip toggle + builtins off
     *   BattlePage computeFinalPool narrowing to CUSTOM_TEST_PROMPTS
     *   QuestionGenerator serving those prompts
     *   Win path reaches ResultPage with 胜利！
     *
     * Helper ordering note: custom words must be saved BEFORE enabling
     * the 'custom' chip exclusively in ConfigPage — otherwise save-time
     * validation would block with an empty pool.
     */
    it('configCustomWordsOnly_oneShotVictory', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      await openCustomWordsAndSave(driver, CUSTOM_TEST_RAW);

      const cfg: TestGameConfig = new TestGameConfig();
      cfg.playerHp = 5;
      cfg.monsterHp = 1;
      cfg.monstersTotal = 1;
      cfg.timerChipId = 'ConfigTimer60s';
      cfg.categories = ['custom'];
      await openConfigAndApply(driver, cfg);

      await clickById(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // Confirm the pool narrowed to custom: the prompt MUST be one of
      // the three CUSTOM_TEST_PROMPTS strings. Failing here would mean
      // computeFinalPool leaked a built-in category.
      const promptComp = await driver.findComponent(ON.id('BattlePrompt'));
      const prompt: string = await promptComp.getText();
      expect(isCustomTestPrompt(prompt)).assertTrue();

      await tapCorrectAnswer(driver);
      await driver.delayMs(900);

      await driver.assertComponentExist(ON.id('ResultTitle'));
      await driver.assertComponentExist(ON.text('胜利！'));
      await driver.assertComponentExist(ON.text('击败怪物：1 / 1'));
      await driver.assertComponentExist(ON.text('正确率：100%'));

      await clickById(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });
  });
}
