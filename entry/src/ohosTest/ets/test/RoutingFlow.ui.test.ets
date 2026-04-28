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

/**
 * Exported launcher for sibling UI test files (e.g. CritSpectacle) so
 * they can reuse the cold-launch delay without duplicating bundle name
 * lookup. Behavior matches the internal `launchApp` used by this suite.
 */
export async function launchAppShared(): Promise<Driver> {
  return launchApp();
}

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
export async function clickByIdShared(driver: Driver, id: string): Promise<void> {
  return clickById(driver, id);
}

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
export async function tapCorrectAnswerShared(driver: Driver): Promise<string> {
  return tapCorrectAnswer(driver);
}

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
export async function tapWrongAnswerShared(driver: Driver): Promise<string> {
  return tapWrongAnswer(driver);
}

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
 *
 * Exported so sibling UI test files can reset the shared AppStorage
 * config back to defaults at the start of their own `it` blocks —
 * necessary because the runner holds the app open between suites and
 * RoutingFlow's last test leaves the config pinned to a 1-monster /
 * 1-HP custom-words loop that would end a regular battle after a
 * single correct tap.
 */
export class TestGameConfig {
  playerHp: number = 5;
  monsterHp: number = 3;
  monstersTotal: number = 5;
  timerChipId: string = 'ConfigTimer300s';
  categories: string[] = ['fruit']; // may include 'custom'
}

/**
 * Shared wrapper around openConfigAndApply for sibling UI test files.
 * Call at the start of any test that needs the default battle shape
 * (5 HP / 3 HP / 5 monsters / 300 s / fruit) so RoutingFlow's final
 * custom-words test cannot leak its 1-monster config into us.
 */
export async function applyConfigShared(driver: Driver,
                                        cfg: TestGameConfig): Promise<void> {
  return openConfigAndApply(driver, cfg);
}

/**
 * Convenience helper used by every sibling V0.2 UI test. Resets the
 * shared AppStorage config to sensible defaults (5 HP / 3 HP /
 * 5 monsters / 300 s / fruit category) so a failing prior test or a
 * test ordering difference can't cause us to inherit a config where
 * one correct tap ends the battle.
 */
export async function resetToDefaultConfigShared(driver: Driver): Promise<void> {
  const cfg: TestGameConfig = new TestGameConfig();
  await openConfigAndApply(driver, cfg);
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

  // V0.2 note: ConfigPage grew the `ConfigAutoSpeakToggle` row (auto-
  // play pronunciation toggle), which on a narrow landscape emulator
  // pushes ConfigSaveButton below the viewport. Swipe up on the
  // Scroll container so Save is reachable. The swipe is idempotent
  // on already-in-view content and cheap (one gesture), so we always
  // perform it rather than gating on screen size.
  await driver.swipe(1400, 1100, 1400, 300, 600);
  await driver.delayMs(300);
  await driver.assertComponentExist(ON.id('ConfigSaveButton'));
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

  // V0.2 note: ConfigPage grew the `ConfigAutoSpeakToggle` row,
  // pushing Save/Cancel below the viewport on a narrow landscape
  // emulator. Swipe up once before looking for the Cancel button
  // so findComponent doesn't return null.
  await driver.swipe(1400, 1100, 1400, 300, 600);
  await driver.delayMs(300);
  await driver.assertComponentExist(ON.id('ConfigCancelButton'));
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
      await driver.assertComponentExist(ON.id('AdventureCard'));
      // Content: home still shows the Chinese subtitle. v0.3.6 deleted
      // the legacy "点击开始，打败 5 个单词史莱姆吧！" hint and
      // "开始游戏" button copy when the right column was removed; the
      // adventure card now carries the primary CTA copy
      // ("开始今日冒险" / "再战一局") as the single entry point.
      await driver.assertComponentExist(ON.text('小魔法师单词冒险'));

      await clickById(driver, 'HomeStartButton');
      // v0.3.6: HomeStartButton now opens today's adventure, which loads
      // WordRepository + LearningRecorder asynchronously before pushing
      // BattlePage. Bumped from 800ms to 1500ms so BattleTitle is on
      // screen before the next assertion.
      await driver.delayMs(1500);

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

    // v0.3.6 cleanup: retryFlow_resultRetryReopensBattlePage was removed
    // because ResultPage's retry button branches on isTodayAdventure
    // (ResultPage.ets:164): in today-mode it intentionally routes back
    // to HomePage so the next session plan can be rebuilt against
    // up-to-date memory states, instead of replaying the cached plan.
    // Since v0.3.6's HomeStartButton always starts today-mode, the
    // retry → BattlePage routing this test guarded no longer exists
    // from any HomePage entry. The replaceUrl('pages/BattlePage')
    // branch survives in ResultPage and is exercised whenever an
    // external normal-mode entry is reintroduced (out of scope for
    // v0.3.6).

    // v0.3.6 cleanup: winFlow_fifteenCorrectAnswersReachesVictory and the
    // four config-driven tests (configShortWin / configTimerExpiry /
    // configHpZero / configCustomWordsOnly) were removed because they
    // depend on the legacy normal-mode entry that v0.3.6 deleted.
    // Today's adventure ignores cfg.playerHp / monsterHp / monstersTotal
    // / timer / customWords (it consumes a TodaySessionPlan whose monster
    // shape and word pool are region-curated), so those flows can no
    // longer be exercised end-to-end from HomePage. Their engine-level
    // win/lose / timer / HP / custom-pool semantics remain covered by
    // the no-device unit tests under entry/src/test/.
  });
}
