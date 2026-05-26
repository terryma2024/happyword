import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON, Component } from '@kit.TestKit';
import {
  launchAppShared,
  clickByIdShared,
  resetBattleConfigForUiTestShared,
  selectAllQuestionTypesShared,
  selectOnlyQuestionTypeShared,
  tapCorrectAnswerShared,
  tapWrongAnswerShared,
} from './RoutingFlow.ui.test';
import {
  cloneGameConfig,
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
} from '../../../main/ets/models/GameConfig';

function setFastChoiceBattleConfig(): void {
  resetBattleConfigForUiTestShared(['choice']);
  const stored: GameConfig | undefined = AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
  const cfg: GameConfig = cloneGameConfig(stored !== undefined ? stored : new GameConfig());
  cfg.monsterMaxHp = 1;
  cfg.monstersTotal = 2;
  cfg.enabledQuestionTypes = ['choice'];
  AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, cfg);
}

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

    it('bossDialogueIntroAndDefeatOverlaysRender', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();
      setFastChoiceBattleConfig();

      await clickByIdShared(driver, 'HomeStartButton');
      await driver.delayMs(1500);

      await driver.assertComponentExist(ON.id('BattleBossIntroBubble'));
      await driver.assertComponentExist(ON.id('BattleBossIntroLineEn'));
      await driver.assertComponentExist(ON.id('BattleBossIntroLineZh'));
      const introBubble: Component =
        await driver.findComponent(ON.id('BattleBossIntroBubble'));
      const monsterArea: Component =
        await driver.findComponent(ON.id('MonsterArea'));
      const introBounds = await introBubble.getBounds();
      const monsterBounds = await monsterArea.getBounds();
      expect(introBounds.left < monsterBounds.left).assertTrue();
      expect(introBounds.right >= monsterBounds.left - 12).assertTrue();
      expect(introBounds.right <= monsterBounds.left + 220).assertTrue();

      await tapCorrectAnswerShared(driver);
      await driver.delayMs(420);
      await driver.assertComponentExist(ON.id('BattleBossDefeatBubble'));
      await driver.assertComponentExist(ON.id('BattleBossDefeatLineEn'));
      await driver.assertComponentExist(ON.id('BattleBossDefeatLineZh'));

      await clickByIdShared(driver, 'BattleEscapeButton');
      await driver.delayMs(800);
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await selectAllQuestionTypesShared(driver);
      done();
    });

    it('superBossIntroUsesOrdinaryBubbleAndAutoDismisses', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();
      await selectOnlyQuestionTypeShared(driver, 'spell');

      await clickByIdShared(driver, 'HomeStartButton');
      await driver.delayMs(1500);

      await driver.assertComponentExist(ON.id('BattleBossIntroBubble'));
      await driver.assertComponentExist(ON.id('BattleBossIntroLineEn'));
      await driver.assertComponentExist(ON.id('BattleBossIntroLineZh'));
      const bannerDuringIntro: Component | null =
        await driver.findComponent(ON.id('BattleSuperBossIntroBanner'));
      expect(bannerDuringIntro === null).assertTrue();
      await driver.delayMs(1500);
      const bubble: Component | null =
        await driver.findComponent(ON.id('BattleBossIntroBubble'));
      expect(bubble === null).assertTrue();

      await clickByIdShared(driver, 'BattleEscapeButton');
      await driver.delayMs(800);
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await selectAllQuestionTypesShared(driver);
      done();
    });
  });
}
