import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
} from '../../../main/ets/models/GameConfig';
import {
  clickParentPinSetupCancelShared,
  clickByIdShared,
  scrollToQuestionTypeChipsShared,
  selectAllQuestionTypesShared,
  selectOnlyQuestionTypeShared,
  tapConfigCancelShared,
} from './RoutingFlow.ui.test';
import {
  bindMockParentViaShortCodeFromHome,
} from './UiTestBindingHelpers';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

// V0.6.7.7: timer-cleanup id used by the custom-dialog tests below
// to restore the canonical 5m default after touching the timer state.
// The corresponding chip preset ('5m' = 300s) is rendered by
// `pages/ConfigPage.timerRow` for every TIMER_CHOICES entry.
const DEFAULT_TIMER_CHIP_ID: string = 'ConfigTimer300s';
const STEPPER_MAX_VALUE: number = 10;
const CONFIG_SCROLL_X: number = 630;
const VALID_SHORT_CODE: string = '345678';

class StepperProbe {
  valueBeforeIncrement: number = 0;
  decrementedFromMax: boolean = false;
}

async function launchApp(): Promise<Driver> {
  // ArkTS strict mode flags direct @kit calls as may-throw — wrap the
  // helper body in try/catch+rethrow to silence the warning while
  // preserving propagation to hypium's per-`it` handler.
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

async function returnToHome(driver: Driver): Promise<void> {
  try {
    for (let i: number = 0; i < 5; i++) {
      const consent: Component | null =
        await driver.findComponent(ON.id('PrivacyConsentAgreeButton'));
      if (consent !== null) {
        await consent.click();
        await driver.delayMs(600);
      }
      const home: Component | null =
        await driver.findComponent(ON.id('HomeStartButton'));
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

async function openConfig(driver: Driver): Promise<void> {
  try {
    await clickByIdShared(driver, 'HomeConfigButton');
    await driver.delayMs(1500);
  } catch (err) {
    throw err as Error;
  }
}

async function scrollToConfigReportChannelButton(driver: Driver): Promise<void> {
  try {
    for (let attempt: number = 0; attempt < 6; attempt++) {
      const report: Component | null =
        await driver.findComponent(ON.id('ConfigReportChannelButton'));
      if (report !== null) {
        return;
      }
      await driver.swipe(CONFIG_SCROLL_X, 1100, CONFIG_SCROLL_X, 300, 600);
      await driver.delayMs(400);
    }
  } catch (err) {
    throw err as Error;
  }
}

async function readIntById(driver: Driver, id: string): Promise<number> {
  try {
    const c: Component = await driver.findComponent(ON.id(id));
    const text: string = await c.getText();
    return Number.parseInt(text, 10);
  } catch (err) {
    throw err as Error;
  }
}

async function ensureStepperCanIncrement(driver: Driver, valueId: string, decId: string): Promise<StepperProbe> {
  try {
    const probe: StepperProbe = new StepperProbe();
    let value: number = await readIntById(driver, valueId);
    if (value >= STEPPER_MAX_VALUE) {
      await clickByIdShared(driver, decId);
      await driver.delayMs(400);
      value = await readIntById(driver, valueId);
      probe.decrementedFromMax = true;
    }
    probe.valueBeforeIncrement = value;
    return probe;
  } catch (err) {
    throw err as Error;
  }
}

/**
 * V0.6.5.1: scroll iteratively until ConfigParentPinButton is on
 * screen. The packPickerSection between autoSpeak and parentPin can
 * require multiple swipes on the landscape emulator viewport.
 *
 * V0.6.7.7 — strengthen the visibility check. Pre-V0.6.7.7 this
 * helper exited on the first non-null `findComponent`, which on the
 * emulator returns the button even when its visible bounds are a
 * 25-pixel sliver at Y ≈ 1235 (the button is rendered, but most of
 * it is clipped by the Scroll viewport that ends at Y = 1260). Tap
 * coordinates derived from those clipped bounds land at the very
 * bottom of the screen and the system rejects them — every test
 * that depends on ConfigParentPinButton (the three pin-setup flows
 * below) then fails to navigate. We now keep swiping while the
 * button's reported bottom is within VIEWPORT_EDGE_PADDING of the
 * dump's vertical extent, which is robust against the leftover
 * cloud-sync-row state from prior pack-binding suites that pushes
 * the button further down.
 */
async function scrollToParentPinButton(driver: Driver): Promise<void> {
  // The OpenHarmony emulator dumps land button bounds as a 25-pixel
  // clipped slice (Y top = ~1235, Y bottom = 1260) when the row is
  // pinned to the very bottom of the visible Scroll. 100px padding
  // guarantees the button has enough hit-test margin.
  const VIEWPORT_EDGE_PADDING: number = 100;
  try {
    for (let attempt: number = 0; attempt < 6; attempt++) {
      const btn: Component | null =
        await driver.findComponent(ON.id('ConfigParentPinButton'));
      if (btn !== null) {
        const boundsRect = await btn.getBounds();
        // `getBounds` returns the in-tree (clipped) bounds; if the
        // bottom edge sits within the padding distance from the
        // dump's vertical extent (the visible viewport ends at the
        // largest reported Y), the button is partially clipped and
        // we need to keep scrolling. Use a generous heuristic — the
        // total clipped height — instead of a hard-coded viewport
        // height because the emulator size can shift across runs.
        const heightPx: number = boundsRect.bottom - boundsRect.top;
        if (heightPx >= VIEWPORT_EDGE_PADDING) {
          return;
        }
      }
      await driver.swipe(CONFIG_SCROLL_X, 1100, CONFIG_SCROLL_X, 300, 600);
      await driver.delayMs(400);
    }
  } catch (err) {
    throw err as Error;
  }
}

async function tapPinSetupKey(driver: Driver, key: string): Promise<void> {
  try {
    await clickByIdShared(driver, `ParentPinSetupKey_${key}`);
    await driver.delayMs(80);
  } catch (err) {
    throw err as Error;
  }
}

async function ensureBoundParentAccountFromHome(driver: Driver): Promise<void> {
  try {
    await bindMockParentViaShortCodeFromHome(driver, VALID_SHORT_CODE);
  } catch (err) {
    throw err as Error;
  }
}

/**
 * V0.6.7.7: drive the 自定义 timer dialog end-to-end. Caller is
 * responsible for already being on `ConfigPage` (the 自定义 button
 * lives in the timer row near the top of the form, so no scroll is
 * needed on the landscape emulator viewport). On return the page is
 * still ConfigPage with the chosen seconds applied and persisted.
 *
 * The numeric IME pops up over the 确定 button on the emulator the
 * same way it does for `ScanBindingPage` / `EditChildNicknameDialog`,
 * so we dismiss it with `pressBack()` after typing before clicking
 * the confirm button.
 */
async function setCustomTimerSeconds(driver: Driver, seconds: number): Promise<void> {
  try {
    await driver.assertComponentExist(ON.id('ConfigTimerCustom'));
    await clickByIdShared(driver, 'ConfigTimerCustom');
    await driver.delayMs(600);
    await driver.assertComponentExist(ON.id('CustomTimerDialog'));
    await driver.assertComponentExist(ON.id('CustomTimerDialogInput'));
    const input: Component =
      await driver.findComponent(ON.id('CustomTimerDialogInput'));
    // `inputText` replaces existing content per the platform
    // contract documented in CustomWishlistFlow.typeInto. The dialog
    // pre-populates the field with the live `draft.startingSeconds`
    // (e.g. "300" on a fresh launch), so a plain inputText call
    // overwrites that with the desired value.
    await input.inputText(`${seconds}`);
    await driver.delayMs(300);
    // Numeric IME hides the 确定 button on the narrow landscape
    // viewport — drop it before tapping confirm.
    await driver.pressBack();
    await driver.delayMs(500);
    await clickByIdShared(driver, 'CustomTimerDialogConfirmButton');
    await driver.delayMs(700);
    // Belt-and-suspenders: poll until the dialog is gone.
    for (let i: number = 0; i < 10; i++) {
      const dlg: Component | null =
        await driver.findComponent(ON.id('CustomTimerDialog'));
      if (dlg === null) {
        return;
      }
      await driver.delayMs(200);
    }
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Tap ConfigPage circular back (`ConfigBackButton`) with light scroll
 * nudges if the fixed chrome is temporarily off-screen.
 */
async function tapConfigSaveButton(driver: Driver): Promise<void> {
  try {
    for (let attempt: number = 0; attempt < 4; attempt++) {
      const comp: Component | null =
        await driver.findComponent(ON.id('ConfigBackButton'));
      if (comp !== null) {
        await comp.click();
        return;
      }
      await driver.swipe(CONFIG_SCROLL_X, 1100, CONFIG_SCROLL_X, 300, 600);
      await driver.delayMs(400);
    }
    throw new Error('ConfigBackButton remained unreachable after 4 swipes');
  } catch (err) {
    throw err as Error;
  }
}

/**
 * V0.6.7.7: cleanup helper. After a custom-timer test we restore the
 * canonical 5m chip (persisted on tap) and leave Config so subsequent
 * suites in the same `aa test` invocation see the expected default
 * battle length. Mirrors the defensive try/finally pattern in
 * PackManagerFlow's pack-toggle tests.
 *
 * Caller can be anywhere in the navigation tree; the helper drives
 * Home → Config → tap chip → back → Home itself, including IME
 * dismissal for emulator robustness.
 */
async function restoreDefaultTimerChip(driver: Driver): Promise<void> {
  try {
    await returnToHome(driver);
    await openConfig(driver);
    await driver.assertComponentExist(ON.id(DEFAULT_TIMER_CHIP_ID));
    await clickByIdShared(driver, DEFAULT_TIMER_CHIP_ID);
    await driver.delayMs(300);
    await tapConfigSaveButton(driver);
    await driver.delayMs(800);
    await returnToHome(driver);
  } catch (err) {
    throw err as Error;
  }
}

/**
 * V0.3.9 acceptance for the parent PIN configuration surface:
 *  - ConfigPage shows the new ConfigParentPinButton row after the
 *    test binds a mock parent account.
 *  - Tapping it lands on ParentPinSetupPage (the page exposes
 *    keypad keys ParentPinSetupKey_{0..9}, a delete key, and the
 *    step-1 / step-2 prompts).
 *  - Two-step setup: typing six digits twice persists the PIN and
 *    routes back; the ConfigParentPinButton label flips to include
 *    the 修改 prefix on return.
 *  - Mismatched second entry surfaces the
 *    ParentPinSetupMismatchHint and resets the buffer.
 *
 * Cleans up by setting the PIN back to a known canonical value at
 * the end of each non-mismatch test so subsequent runs can rely on
 * the AppStorage state.
 */
export default function configFlowUiTest(): void {
  describe('ConfigFlow', () => {
    it('configSteppersUpdateVisibleValuesImmediately', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfig(driver);

      const playerProbe: StepperProbe =
        await ensureStepperCanIncrement(driver, 'ConfigPlayerHpValue', 'ConfigPlayerHpDec');
      await clickByIdShared(driver, 'ConfigPlayerHpInc');
      await driver.delayMs(400);
      const playerAfter: number = await readIntById(driver, 'ConfigPlayerHpValue');
      expect(playerAfter === playerProbe.valueBeforeIncrement + 1).assertTrue();
      if (!playerProbe.decrementedFromMax) {
        await clickByIdShared(driver, 'ConfigPlayerHpDec');
      }

      const monsterHpProbe: StepperProbe =
        await ensureStepperCanIncrement(driver, 'ConfigMonsterHpValue', 'ConfigMonsterHpDec');
      await clickByIdShared(driver, 'ConfigMonsterHpInc');
      await driver.delayMs(400);
      const monsterHpAfter: number = await readIntById(driver, 'ConfigMonsterHpValue');
      expect(monsterHpAfter === monsterHpProbe.valueBeforeIncrement + 1).assertTrue();
      if (!monsterHpProbe.decrementedFromMax) {
        await clickByIdShared(driver, 'ConfigMonsterHpDec');
      }

      const monsterCountProbe: StepperProbe =
        await ensureStepperCanIncrement(driver, 'ConfigMonstersTotalValue', 'ConfigMonstersTotalDec');
      await clickByIdShared(driver, 'ConfigMonstersTotalInc');
      await driver.delayMs(400);
      const monsterCountAfter: number = await readIntById(driver, 'ConfigMonstersTotalValue');
      expect(monsterCountAfter === monsterCountProbe.valueBeforeIncrement + 1).assertTrue();
      if (!monsterCountProbe.decrementedFromMax) {
        await clickByIdShared(driver, 'ConfigMonstersTotalDec');
      }

      await tapConfigCancelShared(driver);
      await returnToHome(driver);
      done();
    });

    it('configPageShowsMinorReportChannel', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfig(driver);
      await scrollToConfigReportChannelButton(driver);

      await driver.assertComponentExist(ON.id('ConfigReportChannelButton'));

      await tapConfigCancelShared(driver);
      await returnToHome(driver);
      done();
    });

    it('questionTypeSectionRendersImplementedChineseSwitchesOnly', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfig(driver);
      await scrollToQuestionTypeChipsShared(driver);

      await driver.assertComponentExist(ON.id('ConfigQuestionType_choice'));
      await driver.assertComponentExist(ON.id('ConfigQuestionType_fill-letter'));
      await driver.assertComponentExist(ON.id('ConfigQuestionType_fill-letter-medium'));
      await driver.assertComponentExist(ON.id('ConfigQuestionType_spell'));
      await driver.assertComponentExist(ON.id('ConfigQuestionType_sentence-cloze'));
      await driver.assertComponentExist(ON.id('ConfigQuestionTypeLabel_choice'));
      await driver.assertComponentExist(ON.id('ConfigQuestionTypeLabel_sentence-cloze'));
      const choiceLabel: Component =
        await driver.findComponent(ON.id('ConfigQuestionTypeLabel_choice'));
      const choiceText: string = await choiceLabel.getText();
      expect(choiceText).assertEqual('中文选词');
      const choiceSwitch: Component =
        await driver.findComponent(ON.id('ConfigQuestionType_choice'));
      const choiceSwitchText: string = await choiceSwitch.getText();
      expect(choiceSwitchText.length).assertEqual(0);
      const sentenceClozeLabel: Component =
        await driver.findComponent(ON.id('ConfigQuestionTypeLabel_sentence-cloze'));
      const sentenceClozeText: string = await sentenceClozeLabel.getText();
      expect(sentenceClozeText).assertEqual('句子填词');
      const sentenceChip: Component | null =
        await driver.findComponent(ON.id('ConfigQuestionType_sentence-fill'));
      expect(sentenceChip === null).assertTrue();

      await tapConfigCancelShared(driver);
      await returnToHome(driver);
      done();
    });

    it('questionTypeSelectionPersistsAfterSave', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await selectOnlyQuestionTypeShared(driver, 'spell');
      await openConfig(driver);
      await scrollToQuestionTypeChipsShared(driver);

      const stored: GameConfig | undefined =
        AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
      expect(stored !== undefined).assertTrue();
      const selected: string[] = stored !== undefined
        ? stored.enabledQuestionTypes
        : [];
      expect(selected.length).assertEqual(1);
      expect(selected[0]).assertEqual('spell');

      await tapConfigCancelShared(driver);
      await returnToHome(driver);
      await selectAllQuestionTypesShared(driver);
      done();
    });

    it('configParentPinButtonNavigatesToSetupPage', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureBoundParentAccountFromHome(driver);
      await openConfig(driver);

      // V0.6.5.1: iterate scroll until the parent-PIN button is
      // visible — packPickerSection can push it below the fold on
      // the narrow landscape emulator viewport.
      await scrollToParentPinButton(driver);
      await driver.assertComponentExist(ON.id('ConfigParentPinButton'));

      await clickByIdShared(driver, 'ConfigParentPinButton');
      await driver.delayMs(1200);
      await driver.assertComponentExist(ON.id('ParentPinSetupTitle'));
      await driver.assertComponentExist(ON.id('ParentPinSetupStepLabel'));
      await driver.assertComponentExist(ON.id('ParentPinSetupKeypad'));
      // The cancel button sits below the keypad on a narrow landscape
      // viewport; swipe up so findComponent can resolve it.
      await driver.swipe(CONFIG_SCROLL_X, 1100, CONFIG_SCROLL_X, 300, 600);
      await driver.delayMs(300);
      // Cancel returns without persisting. ConfigPage owns a Scroll
      // wrapper whose scroll position is preserved across navigations,
      // so we anchor on ConfigParentPinButton (the row we swiped to)
      // instead of ConfigTitle (which sits at the top and may be off
      // screen).
      await clickParentPinSetupCancelShared(driver);
      await driver.delayMs(1200);
      await driver.assertComponentExist(ON.id('ConfigParentPinButton'));

      // Bail out of ConfigPage cleanly.
      await tapConfigCancelShared(driver);
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    it('twoStepMatchPersistsPinAndUpdatesButtonLabel', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureBoundParentAccountFromHome(driver);
      await openConfig(driver);
      await scrollToParentPinButton(driver);
      await clickByIdShared(driver, 'ConfigParentPinButton');
      await driver.delayMs(1200);

      // Step 1: 1 2 3 4 5 6
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '3');
      await tapPinSetupKey(driver, '4');
      await tapPinSetupKey(driver, '5');
      await tapPinSetupKey(driver, '6');
      await driver.delayMs(400);

      // Step 2: confirm with the same digits
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '3');
      await tapPinSetupKey(driver, '4');
      await tapPinSetupKey(driver, '5');
      await tapPinSetupKey(driver, '6');
      await driver.delayMs(1500);

      // After commitOrReset the page routes back to ConfigPage. The
      // outer Scroll keeps its position across navigations, so the
      // parent-pin row should still be in view (we already scrolled
      // there to click the button). Anchor on ConfigParentPinButton
      // rather than ConfigTitle which sits above the scroll fold.
      await driver.assertComponentExist(ON.id('ConfigParentPinButton'));
      const btn = await driver.findComponent(ON.id('ConfigParentPinButton'));
      const label: string = await btn.getText();
      expect(label.indexOf('修改') >= 0).assertTrue();

      await tapConfigCancelShared(driver);
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    /**
     * V0.6.7.7: 自定义 timer dialog flow — open the dialog from the
     * timer row, type a 3-second value, confirm, and verify that the
     * chip label flips to `✓自定义 (3s)`. Saves the config and re-
     * opens ConfigPage to confirm the value persisted into the
     * AppStorage / preferences layer (sanitizeTimer no longer
     * snap-rounds custom seconds to a TIMER_CHOICES preset post-
     * V0.6.7.7).
     *
     * Cleanup restores the default 5m chip in a `finally` so the test
     * is order-independent — without this, downstream battle suites
     * (RoutingFlow.mainFlow_homeBattleResultHome) would inherit the 3s
     * timer and time out before their first `BattleOptionA` tap.
     */
    it('customTimerDialogAcceptsThreeSecondsAndUpdatesChip', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);

      let didTouchTimer: boolean = false;
      try {
        await openConfig(driver);
        await setCustomTimerSeconds(driver, 3);
        didTouchTimer = true;

        // Custom button now reads `✓自定义 (3s)`.
        const customBtn: Component =
          await driver.findComponent(ON.id('ConfigTimerCustom'));
        const label: string = await customBtn.getText();
        expect(label.indexOf('✓自定义') >= 0).assertTrue();
        expect(label.indexOf('3s') >= 0).assertTrue();

        // Preset chips must NOT be highlighted; verify by reading the
        // 30s chip's text — without `✓` it was just `30s`.
        const chip30: Component =
          await driver.findComponent(ON.id('ConfigTimer30s'));
        const chip30Text: string = await chip30.getText();
        expect(chip30Text.indexOf('✓') < 0).assertTrue();

        // Persist is immediate; pop back to Home via ConfigBackButton
        // (same scroll helper as the old ConfigSaveButton path).
        await tapConfigSaveButton(driver);
        await driver.delayMs(800);
        await driver.assertComponentExist(ON.id('HomeStartButton'));

        // Re-open ConfigPage; the custom button should still show 3s
        // since `GameConfigPersistence.sanitizeTimer` now leaves
        // arbitrary values in `[TIMER_CUSTOM_MIN, TIMER_CUSTOM_MAX]`
        // alone. A regression that re-introduced the snap-to-chip
        // behaviour from <V0.6.7.7 would surface here as a "30s"
        // (nearest chip) label.
        await openConfig(driver);
        await driver.assertComponentExist(ON.id('ConfigTimerCustom'));
        const customBtn2: Component =
          await driver.findComponent(ON.id('ConfigTimerCustom'));
        const label2: string = await customBtn2.getText();
        expect(label2.indexOf('3s') >= 0).assertTrue();

        await tapConfigCancelShared(driver);
        await driver.delayMs(600);
        await driver.assertComponentExist(ON.id('HomeStartButton'));
      } finally {
        if (didTouchTimer) {
          try {
            await restoreDefaultTimerChip(driver);
          } catch (_err) {
            // Best-effort cleanup; if the suite is already failing
            // we don't want the cleanup itself to hide the original
            // assertion failure.
          }
        }
      }
      done();
    });

    /**
     * V0.6.7.7: validation path — typing a non-numeric value into the
     * custom dialog should surface `CustomTimerDialogError` and leave
     * the dialog open (no implicit close). Mirrors the validator unit
     * tests in `entry/src/test/CustomTimerDialog.test.ets` but ensures
     * the @State wiring inside the @CustomDialog struct surfaces the
     * error to the live UI (a regression where `errorMessage` was
     * cleared too eagerly would only surface here).
     *
     * Uses `0` as the rejected value rather than letters because the
     * numeric IME makes alphabetic input awkward; both still hit the
     * same error path (`'最少 1 秒'` / `'请输入正整数秒数'`).
     */
    it('customTimerDialogRejectsZeroAndKeepsDialogOpen', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);

      try {
        await openConfig(driver);
        await driver.assertComponentExist(ON.id('ConfigTimerCustom'));
        await clickByIdShared(driver, 'ConfigTimerCustom');
        await driver.delayMs(600);
        await driver.assertComponentExist(ON.id('CustomTimerDialog'));

        const input: Component =
          await driver.findComponent(ON.id('CustomTimerDialogInput'));
        await input.inputText('0');
        await driver.delayMs(300);
        await driver.pressBack();
        await driver.delayMs(500);
        await clickByIdShared(driver, 'CustomTimerDialogConfirmButton');
        await driver.delayMs(700);

        // The dialog must still be on screen (no close on validation
        // failure) and the error message must be visible.
        await driver.assertComponentExist(ON.id('CustomTimerDialog'));
        await driver.assertComponentExist(ON.id('CustomTimerDialogError'));

        // Cancel out of the dialog without submitting.
        await clickByIdShared(driver, 'CustomTimerDialogCancelButton');
        await driver.delayMs(500);
        const dialogGone: Component | null =
          await driver.findComponent(ON.id('CustomTimerDialog'));
        expect(dialogGone === null).assertTrue();

        // Cancel out of ConfigPage without saving so we don't
        // accidentally persist any previously-set value.
        await tapConfigCancelShared(driver);
        await driver.delayMs(600);
        await driver.assertComponentExist(ON.id('HomeStartButton'));
      } catch (err) {
        throw err as Error;
      }
      done();
    });

    /**
     * V1.1.0 (Task 1.4): the 战斗画面 / Cocos battle-scene switch must
     * exist in the Config form, accept two Toggle taps without crashing,
     * and leave the page in a usable state. isCocosRuntimeAvailable()
     * returns true unconditionally in Task 1.4 so the group is always
     * visible on the emulator / ohosTest HAP.
     */
    it('cocosBattleSwitchExistsAndIsToggleable', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfig(driver);

      // The switch lives near the top of the form (after 发音播放);
      // no scroll should be needed on the landscape viewport, but swipe
      // once defensively in case the timer row is taller than expected.
      for (let attempt: number = 0; attempt < 3; attempt++) {
        const sw: Component | null =
          await driver.findComponent(ON.id('ConfigCocosBattleSwitch'));
        if (sw !== null) {
          break;
        }
        await driver.swipe(CONFIG_SCROLL_X, 1100, CONFIG_SCROLL_X, 300, 600);
        await driver.delayMs(400);
      }

      await driver.assertComponentExist(ON.id('ConfigCocosBattleSwitch'));
      // Toggle off then back on — two taps must not throw or navigate away.
      await clickByIdShared(driver, 'ConfigCocosBattleSwitch');
      await driver.delayMs(300);
      await clickByIdShared(driver, 'ConfigCocosBattleSwitch');
      await driver.delayMs(300);
      // Config page must still be visible after both taps.
      await driver.assertComponentExist(ON.id('ConfigCocosBattleSwitch'));

      await tapConfigCancelShared(driver);
      await returnToHome(driver);
      done();
    });

    it('mismatchSurfacesHintAndResetsBuffer', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureBoundParentAccountFromHome(driver);
      await openConfig(driver);
      await scrollToParentPinButton(driver);
      await clickByIdShared(driver, 'ConfigParentPinButton');
      await driver.delayMs(1200);

      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await tapPinSetupKey(driver, '1');
      await driver.delayMs(400);

      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await tapPinSetupKey(driver, '2');
      await driver.delayMs(800);

      await driver.assertComponentExist(ON.id('ParentPinSetupMismatchHint'));
      // Step is reset to 1 (label re-shows the initial copy).
      await driver.assertComponentExist(ON.id('ParentPinSetupStepLabel'));

      // Cancel sits below the keypad on a narrow viewport; swipe up.
      await driver.swipe(CONFIG_SCROLL_X, 1100, CONFIG_SCROLL_X, 300, 600);
      await driver.delayMs(300);
      await clickParentPinSetupCancelShared(driver);
      await driver.delayMs(1200);
      // Anchor on ConfigParentPinButton (the row we already scrolled
      // to) rather than ConfigTitle to avoid Scroll-position artefacts.
      await driver.assertComponentExist(ON.id('ConfigParentPinButton'));

      await tapConfigCancelShared(driver);
      await driver.delayMs(600);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });
  });
}
