import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON, Component } from '@kit.TestKit';
import {
  launchAppShared,
  clickByIdShared,
  resetBattleConfigForUiTestShared,
  selectAllQuestionTypesShared,
  selectOnlyQuestionTypeShared,
  tapWrongAnswerShared,
} from './RoutingFlow.ui.test';

/**
 * V0.8.3 — BattlePage damage floater smoke (§6.5).
 * Wrong-answer path applies player damage when the backward projectile lands.
 */
export default function battleFlowUiTest() {
  describe('BattleFlow', () => {
    it('damageFloaterAppearsAndDisappearsOnHit', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();
      resetBattleConfigForUiTestShared();
      await clickByIdShared(driver, 'HomeStartButton');
      await driver.delayMs(1500);
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      await tapWrongAnswerShared(driver);
      // Impact at ~320 ms; wait through fade-in (opacity > 0 for UiTest).
      await driver.delayMs(550);
      await driver.assertComponentExist(ON.id('BattleDamageFloaterLabel_player'));
      const label: Component =
        await driver.findComponent(ON.id('BattleDamageFloaterLabel_player'));
      const text: string = await label.getText();
      expect(text === '-1' || text === '-2').assertTrue();

      let floaterGone: boolean = false;
      for (let i: number = 0; i < 16; i++) {
        const stillThere: Component | null =
          await driver.findComponent(ON.id('BattleDamageFloaterLabel_player'));
        if (stillThere === null) {
          floaterGone = true;
          break;
        }
        await driver.delayMs(250);
      }
      expect(floaterGone).assertTrue();

      await clickByIdShared(driver, 'BattleEscapeButton');
      await driver.delayMs(800);
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    it('sentenceClozeQuestionRendersExamplePromptAndOptions', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();
      await selectOnlyQuestionTypeShared(driver, 'sentence-cloze');

      await clickByIdShared(driver, 'HomeStartButton');
      await driver.delayMs(1500);

      await driver.assertComponentExist(ON.id('BattleSentenceClozePrompt'));
      await driver.assertComponentExist(ON.id('BattleSentenceClozeZh'));
      await driver.assertComponentExist(ON.id('BattleOptionsRow_SentenceCloze'));
      await driver.assertComponentExist(ON.id('BattleSentenceClozeOption_0'));
      await driver.assertComponentExist(ON.id('BattleSentenceClozeOption_1'));
      await driver.assertComponentExist(ON.id('BattleSentenceClozeOption_2'));

      const prompt: Component =
        await driver.findComponent(ON.id('BattleSentenceClozePrompt'));
      const promptText: string = await prompt.getText();
      expect(promptText.indexOf('____') >= 0).assertTrue();

      await clickByIdShared(driver, 'BattleEscapeButton');
      await driver.delayMs(800);
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await selectAllQuestionTypesShared(driver);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });
  });
}
