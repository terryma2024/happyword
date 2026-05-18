import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON } from '@kit.TestKit';
import {
  launchAppShared,
  clickByIdShared,
  selectAllQuestionTypesShared,
  tapCorrectAnswerShared,
  tapWrongAnswerShared,
} from './RoutingFlow.ui.test';
import {
  assertPlayerHp,
  findPlayerFullHpLabel,
  parseHpLabel,
  returnToHome,
  startTodayBattleChoiceOnly,
} from './UiTestBattleHelpers.ets';

/**
 * MagicAttack UI test (BattlePage magic-projectile overhaul).
 *
 * The visual layers of the overhaul (forward / backward magic orbs,
 * shockwave rings, oversized damage number) all live at opacity 0 at
 * rest, which makes id-presence assertions inherently flaky on a cold
 * emulator (the same reason CritSpectacle.ui.test focuses on a state
 * invariant rather than the visuals themselves — see the doc-comment
 * there).
 *
 * Instead we lock the test to the ONE behavioural invariant the new
 * pulse pipeline must preserve: damage is still applied even though it
 * is now delayed by ~320 ms (one projectile travel) past the click.
 *
 *   - tapping a wrong answer must drop the player's HP from "HP 10 / 10"
 *     to "HP 9 / 10" within the 650 ms feedback window. This proves the
 *     backward-projectile path still routes through `playerHurtPulse`
 *     and the engine's `submitAnswer` still applied damage to the
 *     player despite the new `scheduleImpact` setTimeout split.
 *   - tapping a correct answer must drop the monster's HP from
 *     "HP 3 / 3" to "HP 2 / 3" within the same window — same proof for
 *     the forward-projectile path and `monsterHurtPulse`.
 *
 * The tests reset GameConfig to defaults at the top so a previous
 * RoutingFlow run cannot leak its 1-monster / 1-HP custom-words config
 * into ours and end the battle on a single correct tap. Each test
 * starts and ends on HomePage so the hypium runner can execute them
 * sequentially without state leaking across `it` blocks.
 *
 * Runner: shares the 30 s per-test timeout with RoutingFlow — see
 * `.cursor/ohos-dev-commands.md` for the canonical invocation.
 */
export default function magicAttackUiTest() {
  describe('MagicAttack', () => {
    /**
     * Wrong answer: monster's backward projectile must land and apply
     * exactly 1 damage to the player, taking HP 10 -> 9.
     */
    it('wrongAnswerDecreasesPlayerHpAfterProjectileImpact', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();
      await returnToHome(driver);
      await startTodayBattleChoiceOnly(driver);
      // Pre-tap baseline: player at full HP.
      const hpBefore: string = await findPlayerFullHpLabel(driver);
      expect(hpBefore !== '').assertTrue();
      const parsed = parseHpLabel(hpBefore);
      expect(parsed !== null).assertTrue();

      await tapWrongAnswerShared(driver);
      // Wait long enough for: scheduleImpact (320 ms) + the
      // playerHurtPulse animation start + the 650 ms feedback window
      // tail. 900 ms covers all of it on a cold emulator.
      await driver.delayMs(900);
      if (parsed !== null) {
        await assertPlayerHp(driver, parsed.current - 1, parsed.max);
      }

      // Return to HomePage so the suite stays re-runnable.
      await clickByIdShared(driver, 'BattleFinishButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      await selectAllQuestionTypesShared(driver);

      expect(true).assertTrue();
      done();
    });

    /**
     * Correct answer: mage's forward projectile must land and apply
     * exactly 1 damage to the monster, taking HP 3 -> 2.
     */
    it('correctAnswerDecreasesMonsterHpAfterProjectileImpact', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();
      await returnToHome(driver);
      await startTodayBattleChoiceOnly(driver);
      // Pre-tap baseline: monster at full HP. Both cards render an HP
      // label so we use the monster's "HP 3 / 3" string to disambiguate
      // from the player's "HP 10 / 10".
      await driver.assertComponentExist(ON.text('HP 3 / 3'));

      await tapCorrectAnswerShared(driver);
      await driver.delayMs(900);
      await driver.assertComponentExist(ON.text('HP 2 / 3'));

      await clickByIdShared(driver, 'BattleFinishButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      await selectAllQuestionTypesShared(driver);

      expect(true).assertTrue();
      done();
    });
  });
}
