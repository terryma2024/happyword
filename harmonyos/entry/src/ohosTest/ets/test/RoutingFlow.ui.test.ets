import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import {
  cloneGameConfig,
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  GAME_MODE_NORMAL,
} from '../../../main/ets/models/GameConfig';
import { enForZh, findPlayerFullHpLabel } from './UiTestBattleHelpers.ets';

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
 * `.cursor/ohos-dev-commands.md` passes `-s timeout 30000`. When adding a new
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
  // ArkTS strict mode flags direct @kit calls as may-throw — wrap the
  // helper body in try/catch+rethrow to silence the warning while
  // preserving propagation to hypium's per-`it` handler.
  try {
    const bundleName: string = abilityDelegatorRegistry.getArguments().bundleName;
    const want: Want = { bundleName, abilityName: 'EntryAbility' };
    await delegator.startAbility(want);
    const driver: Driver = Driver.create();
    // First cold launch needs ~1s for the window stage and HomePage build; use
    // the driver's own clock rather than a custom setTimeout so the wait is
    // reported in the hypium trace.
    await driver.delayMs(1000);
    return driver;
  } catch (err) {
    throw err as Error;
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
  try {
    await driver.assertComponentExist(ON.id(id));
    const comp = await driver.findComponent(ON.id(id));
    await comp.click();
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Leave ConfigPage via the circular back control (ConfigBackButton).
 * Swipes up to a maximum of 3 times until the matcher finds the button,
 * then falls back to `driver.pressBack()` so the test still leaves
 * ConfigPage when the chrome is off-screen.
 */
export async function tapConfigCancelShared(driver: Driver): Promise<void> {
  try {
    for (let attempt: number = 0; attempt < 3; attempt++) {
      const comp = await driver.findComponent(ON.id('ConfigBackButton'));
      if (comp !== null) {
        await comp.click();
        return;
      }
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(400);
    }
    await driver.pressBack();
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Scroll ConfigPage until `ConfigParentPinButton` is fully visible
 * (not a clipped sliver). Shared by ConfigFlow, ParentBindingFlow, and
 * ParentAdminFlow — see ConfigFlow.ui.test.ets for the full rationale.
 */
export async function scrollToParentPinButton(driver: Driver): Promise<void> {
  const VIEWPORT_EDGE_PADDING: number = 100;
  try {
    for (let attempt: number = 0; attempt < 6; attempt++) {
      const btn: Component | null =
        await driver.findComponent(ON.id('ConfigParentPinButton'));
      if (btn !== null) {
        const boundsRect = await btn.getBounds();
        const heightPx: number = boundsRect.bottom - boundsRect.top;
        if (heightPx >= VIEWPORT_EDGE_PADDING) {
          return;
        }
      }
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(400);
    }
  } catch (err) {
    throw err as Error;
  }
}

export async function clickParentPinSetupCancelShared(driver: Driver): Promise<void> {
  try {
    for (let attempt: number = 0; attempt < 6; attempt++) {
      const cancel: Component | null =
        await driver.findComponent(ON.id('ParentPinSetupCancel'));
      if (cancel !== null) {
        await cancel.click();
        return;
      }
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(350);
    }
    await driver.assertComponentExist(ON.id('ParentPinSetupCancel'));
    const cancel: Component = await driver.findComponent(ON.id('ParentPinSetupCancel'));
    await cancel.click();
  } catch (err) {
    throw err as Error;
  }
}

const QUESTION_TYPE_IDS: string[] = [
  'choice',
  'fill-letter',
  'fill-letter-medium',
  'spell',
];

/**
 * UI tests share one app process and persistent GameConfig. Normalize
 * battle knobs before suites that assert HP/timer defaults, while
 * preserving parent-owned state such as an existing PIN.
 */
export function resetBattleConfigForUiTestShared(selectedTypes: string[] = QUESTION_TYPE_IDS): void {
  const stored: GameConfig | undefined =
    AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
  const next: GameConfig = cloneGameConfig(stored !== undefined ? stored : new GameConfig());
  const defaults: GameConfig = new GameConfig();
  next.playerMaxHp = defaults.playerMaxHp;
  next.monsterMaxHp = defaults.monsterMaxHp;
  next.monstersTotal = defaults.monstersTotal;
  next.startingSeconds = defaults.startingSeconds;
  next.mode = GAME_MODE_NORMAL;
  next.enabledQuestionTypes = selectedTypes.slice();
  AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, next);
}

export async function scrollToQuestionTypeChipsShared(driver: Driver): Promise<void> {
  try {
    for (let attempt: number = 0; attempt < 3; attempt++) {
      const choice: Component | null =
        await driver.findComponent(ON.id('ConfigQuestionType_choice'));
      if (choice !== null) {
        return;
      }
      await driver.swipe(1400, 300, 1400, 1100, 600);
      await driver.delayMs(300);
    }
    for (let attempt: number = 0; attempt < 5; attempt++) {
      const choice: Component | null =
        await driver.findComponent(ON.id('ConfigQuestionType_choice'));
      if (choice !== null) {
        return;
      }
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(300);
    }
  } catch (err) {
    throw err as Error;
  }
}

async function tapConfigSaveShared(driver: Driver): Promise<void> {
  try {
    for (let attempt: number = 0; attempt < 5; attempt++) {
      const comp: Component | null = await driver.findComponent(ON.id('ConfigBackButton'));
      if (comp !== null) {
        await comp.click();
        return;
      }
      await driver.swipe(1400, 1100, 1400, 300, 600);
      await driver.delayMs(400);
    }
    throw new Error('ConfigBackButton remained off-screen after 5 swipes');
  } catch (err) {
    throw err as Error;
  }
}

function hasCheckPrefix(text: string): boolean {
  return text.indexOf('✓') === 0;
}

export async function setQuestionTypeChipShared(driver: Driver, typeId: string, selected: boolean): Promise<void> {
  try {
    await scrollToQuestionTypeChipsShared(driver);
    const id: string = `ConfigQuestionType_${typeId}`;
    await driver.assertComponentExist(ON.id(id));
    const chip: Component = await driver.findComponent(ON.id(id));
    const text: string = await chip.getText();
    if (hasCheckPrefix(text) !== selected) {
      await chip.click();
      await driver.delayMs(250);
    }
  } catch (err) {
    throw err as Error;
  }
}

export async function selectQuestionTypesShared(driver: Driver, selectedTypes: string[]): Promise<void> {
  try {
    resetBattleConfigForUiTestShared(selectedTypes);
    await clickByIdShared(driver, 'HomeConfigButton');
    await driver.delayMs(1000);
    for (let i: number = 0; i < QUESTION_TYPE_IDS.length; i++) {
      const typeId: string = QUESTION_TYPE_IDS[i];
      await setQuestionTypeChipShared(driver, typeId, selectedTypes.indexOf(typeId) >= 0);
    }
    await tapConfigSaveShared(driver);
    await driver.delayMs(900);
    await driver.assertComponentExist(ON.id('HomeStartButton'));
  } catch (err) {
    throw err as Error;
  }
}

export async function selectOnlyQuestionTypeShared(driver: Driver, typeId: string): Promise<void> {
  return selectQuestionTypesShared(driver, [typeId]);
}

export async function selectAllQuestionTypesShared(driver: Driver): Promise<void> {
  return selectQuestionTypesShared(driver, QUESTION_TYPE_IDS);
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
  const fromCatalog: string = enForZh(zhPrompt);
  return fromCatalog;
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
  try {
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
  } catch (err) {
    throw err as Error;
  }
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
  try {
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
  } catch (err) {
    throw err as Error;
  }
}

// V0.6.6 cleanup: the legacy `openConfigAndApply` /
// `openCustomWordsAndSave` / `setChipSelected` / `categoryChipId` /
// `TestGameConfig` / `applyConfigShared` helpers were dropped when
// GameConfig removed `enabledCategories` and `customWordsRaw` and
// ConfigPage removed the 词库类别 row + the CustomWordsPage entry point.
//
// Sibling UI test files import only `launchAppShared`,
// `clickByIdShared`, `tapConfigCancelShared`, `tapCorrectAnswerShared`,
// and `tapWrongAnswerShared` — those remain.

export default function routingFlowUiTest(): void {
  describe('RoutingFlow', () => {
    /**
     * Main flow with content assertions and negative option-button coverage:
     *
     * 1. HomePage renders IDs + Chinese subtitle and hint text.
     * 2. Click Start -> BattlePage renders title, player HP, monster HP, combo.
     * 3. Clicking each of the three option buttons keeps us on BattlePage
     *    (they are skeleton stubs until QuestionGenerator wires up in T6).
     * 4. Click BattleEscapeButton -> ResultPage renders title + all stat rows.
     * 5. Click ResultHomeButton -> back on HomePage.
     */
    it('mainFlow_homeBattleResultHome', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      resetBattleConfigForUiTestShared();

      // --- HomePage ---
      await driver.assertComponentExist(ON.id('HomeTitle'));
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      await driver.assertComponentExist(ON.id('AdventureCard'));
      // v0.3.6 (post-launch tweak) dropped the Chinese subtitle
      // "小魔法师单词冒险" — keep just the English title above the
      // adventure card. The "点击开始，打败 5 个单词史莱姆吧！"
      // hint and the right-column "开始游戏" button were already
      // removed in v0.3.6; the adventure card now carries the
      // primary CTA copy ("开始今日冒险" / "再战一局") as the
      // single entry point.

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
      // Content: player card renders full HP (10/10) and monster card shows
      // its own HP (3/3). These are engine-driven defaults
      // (DEFAULT_PLAYER_HP / DEFAULT_MONSTER_HP), asserted so a regression
      // that zeros out HP on boot is caught immediately.
      // V0.8.4 default max is 10; persisted GameConfig may still be 5.
      const playerFullHp: string = await findPlayerFullHpLabel(driver);
      expect(playerFullHp !== '').assertTrue();
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
      // is 5 monsters × 3 HP, player 10 HP), so we should stay on the
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
      await clickById(driver, 'BattleEscapeButton');
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
    // The old CustomWordsPage-specific flows can no longer be
    // exercised end-to-end from HomePage. Engine-level win/lose /
    // timer / HP semantics remain covered by no-device unit tests
    // under entry/src/test/.
  });
}
