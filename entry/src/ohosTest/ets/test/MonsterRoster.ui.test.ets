import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON } from '@kit.TestKit';
import {
  launchAppShared,
  clickByIdShared,
  tapCorrectAnswerShared,
  resetToDefaultConfigShared,
} from './RoutingFlow.ui.test';

/**
 * Monster Roster UI test (per-monster name + color overhaul).
 *
 * Locked to the ONE behavioural invariant the UI test layer can read
 * reliably: the monster card's name text. Verifying per-monster
 * colors is left to the unit test (the catalog) and the avatar shape
 * test (manual visual review during build) — UiTest cannot read fill
 * / stroke off rendered shape components, and the catalog test
 * already guarantees the colors are wired into the right entries.
 *
 *   - On entering the battle, the monster card must display
 *     "Lava Imp" (catalog entry 1).
 *   - After defeating the first monster (3 correct answers at default
 *     monsterHp = 3), the monster card must display "Frost Wisp"
 *     (catalog entry 2). This proves syncFromState is updating
 *     currentMonster from state.monsterIndex.
 *
 * Each test starts and ends on HomePage so the hypium runner can
 * execute the suite sequentially without state leaking across `it`
 * blocks. Default config (5 monsters, monsterHp=3, playerHp=5) is
 * reset at the top of each test to keep the 3-correct-tap defeat
 * sequence stable.
 *
 * Runner: shares the 30 s per-test timeout with RoutingFlow — see
 * `.cursor/dev-commands.md` for the canonical invocation.
 */
export default function monsterRosterUiTest() {
  describe('MonsterRosterUiTest', () => {
    it('firstMonsterIsLavaImp', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      await resetToDefaultConfigShared(driver);
      await clickByIdShared(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // The mage card always reads "Magician"; the monster card is
      // the only place "Lava Imp" can appear on this screen.
      await driver.assertComponentExist(ON.text('Lava Imp'));

      // Return to HomePage so the suite stays re-runnable.
      await clickByIdShared(driver, 'BattleFinishButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });

    it('secondMonsterIsFrostWispAfterFirstDefeat', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      await resetToDefaultConfigShared(driver);
      await clickByIdShared(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // Pre-tap baseline: monster #1 is Lava Imp.
      await driver.assertComponentExist(ON.text('Lava Imp'));

      // Defeat Lava Imp: 3 correct answers at default monsterHp = 3.
      // Each correct tap fires a forward projectile, takes ~320 ms
      // for the impact + ~650 ms feedback window before the next
      // question is rendered. 1100 ms cushion per tap matches what
      // CritSpectacle.ui.test uses.
      for (let i = 0; i < 3; i++) {
        await tapCorrectAnswerShared(driver);
        await driver.delayMs(1100);
      }

      // Monster card has now transitioned to monster #2.
      await driver.assertComponentExist(ON.text('Frost Wisp'));

      // Return to HomePage so the suite stays re-runnable.
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
