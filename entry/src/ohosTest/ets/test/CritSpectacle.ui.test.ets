import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON } from '@kit.TestKit';
import {
  launchAppShared,
  clickByIdShared,
  tapCorrectAnswerShared,
} from './RoutingFlow.ui.test';

/**
 * CritSpectacle UI test (spec §4.3 V0.2). Triggering a crit requires
 * three consecutive correct answers — the BattleEngine fires the
 * combo burst on the answer that pushes comboCount to 3. After that
 * answer the CritOverlay component should mount two ids on the tree:
 *
 *   - CritGoldFlash — the full-bleed 450 ms gold flash layer.
 *   - CritDamageNumber — the 72 vp "-${damage}!" floating number.
 *
 * Plus on the player card:
 *   - CritCastGlow — the gold glow ring behind the mage avatar.
 *
 * These ids must be ABSENT during the initial rest state (before any
 * taps) and ABSENT again after the CritOverlay's ~700 ms timeline
 * completes. They must be PRESENT immediately after the 3rd correct
 * tap, inside the 650 ms feedback window.
 *
 * Runner: uses the same 30s per-test timeout as RoutingFlow.ui.test —
 * see .cursor/dev-commands.md for the invocation.
 */
export default function critSpectacleUiTest() {
  describe('CritSpectacleUiTest', () => {
    it('crit_fires_overlay_and_castGlow_on_third_correct_tap', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      await clickByIdShared(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // Rest-state assertions: CritOverlay renders an empty Stack at
      // opacity 0 when critPulse is 0, so the id tree should NOT
      // include the crit-specific ids yet.
      const restFlash = await driver.findComponent(ON.id('CritGoldFlash'));
      expect(restFlash === null || restFlash === undefined).assertTrue();
      const restNumber = await driver.findComponent(ON.id('CritDamageNumber'));
      expect(restNumber === null || restNumber === undefined).assertTrue();

      // Two warmup correct taps — combo goes 0 -> 1 -> 2. Neither
      // fires the burst. delayMs(800) covers the 650 ms feedback
      // window plus a small settle gap.
      await tapCorrectAnswerShared(driver);
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('BattlePrompt'));
      // Combo label mirrors BattleState.comboCount after syncFromEngine
      // fires in onOptionTap, so "Combo: 1" must be visible before
      // the next tap.
      await driver.assertComponentExist(ON.text('Combo: 1'));

      await tapCorrectAnswerShared(driver);
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.text('Combo: 2'));

      // Third correct tap — burst fires inside submitAnswer, so the
      // CritOverlay ids mount right after click. delayMs(120) lands
      // well inside the 450 ms gold-flash window (and well inside the
      // 700 ms floating-number window).
      await tapCorrectAnswerShared(driver);
      await driver.delayMs(120);

      await driver.assertComponentExist(ON.id('CritGoldFlash'));
      await driver.assertComponentExist(ON.id('CritDamageNumber'));
      await driver.assertComponentExist(ON.id('CritCastGlow'));

      // Wait past the CritOverlay's ~700 ms timeline + 40 ms
      // tear-down. After this the overlay hides its visible=true
      // branch and the ids vanish from the tree again.
      await driver.delayMs(800);
      const afterFlash = await driver.findComponent(ON.id('CritGoldFlash'));
      expect(afterFlash === null || afterFlash === undefined).assertTrue();

      // Combo resets to 0 right after the burst (spec §4.3). Verifying
      // this guards against future regressions where the spectacle
      // fires but the engine forgets to reset combo.
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
