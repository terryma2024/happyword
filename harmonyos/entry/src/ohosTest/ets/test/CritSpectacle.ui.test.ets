import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON } from '@kit.TestKit';
import {
  launchAppShared,
  clickByIdShared,
  tapCorrectAnswerShared,
} from './RoutingFlow.ui.test';

/**
 * CritSpectacle UI test (spec §4.3 V0.2). The burst visuals themselves
 * (CritGoldFlash Column, CritDamageNumber Text, CritCastGlow Circle)
 * are always-mounted but spend their life at opacity 0 — HarmonyOS
 * UiTest's `visible:true` self-matcher rejects opacity-0 components,
 * which made an id-presence assertion an inherently flaky race with
 * the 120/180 ms fade-in curves on a cold emulator.
 *
 * So this suite focuses on the ONE behavioural invariant the burst
 * can't hide: BattleEngine resets `comboCount` to 0 inside
 * submitAnswer when comboTriggered fires. Therefore after 3
 * consecutive correct taps the visible `Combo: N` label must read
 * `Combo: 0` — not `Combo: 3`.
 *
 *   - Warmup taps 1 and 2 must walk comboCount 0 → 1 → 2.
 *   - Tap 3 is the burst: comboCount 2 → (3, fires) → 0.
 *   - After the 650 ms feedback window the state remains at 0.
 *
 * The visual spectacle (gold flash, big damage number, cast glow) is
 * verified manually on the emulator as part of the V0.2 acceptance
 * pass — see docs/superpowers/specs/2026-04-24-v0.2-design.md.
 *
 * Runner: uses the same 30 s per-test timeout as RoutingFlow.ui.test —
 * see .cursor/dev-commands.md for the invocation.
 */
export default function critSpectacleUiTest() {
  describe('CritSpectacleUiTest', () => {
    it('comboResetsToZeroOnThirdCorrectTap', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      // v0.3.6: HomeStartButton routes to today's adventure (the
      // legacy normal-mode entry was deleted along with the right-
      // hand HomePage column). Today's first slot in the default
      // fruit-forest region is a basic Match question with 3 HP and
      // English fruit options drawn from WORD_MAP, so 3 correct taps
      // still trigger the combo burst exactly as the old normal-mode
      // 5×3 free-practice flow did. resetToDefaultConfigShared is no
      // longer needed (today-mode ignores cfg.playerHp / monsterHp /
      // monstersTotal / customWords).
      await clickByIdShared(driver, 'HomeStartButton');
      // Today-mode loads WordRepository + LearningRecorder
      // asynchronously before pushing BattlePage; bumped from 1000ms
      // to 1500ms so the first prompt is painted before the assert.
      await driver.delayMs(1500);
      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('BattlePrompt'));
      // Rest-state: no taps yet, combo must be 0.
      await driver.assertComponentExist(ON.text('Combo: 0'));

      // Warmup taps 1 and 2 — combo goes 0 → 1 → 2. 800 ms covers
      // the 650 ms feedback window plus a small settle gap.
      await tapCorrectAnswerShared(driver);
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('BattlePrompt'));
      await driver.assertComponentExist(ON.text('Combo: 1'));

      await tapCorrectAnswerShared(driver);
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.text('Combo: 2'));

      // Tap 3 — burst fires inside submitAnswer: comboCount 2 → 3
      // → reset to 0 atomically. 900 ms covers the feedback window
      // plus the 700 ms crit animation timeline so the next sample
      // is taken after the overlay tear-down callbacks have landed.
      await tapCorrectAnswerShared(driver);
      await driver.delayMs(900);
      await driver.assertComponentExist(ON.id('BattlePrompt'));
      await driver.assertComponentExist(ON.text('Combo: 0'));

      // Return to HomePage so the suite remains re-runnable.
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
