import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import {
  selectAllQuestionTypesShared,
  selectOnlyQuestionTypeShared,
} from './RoutingFlow.ui.test';
import {
  countUnderscores,
  readLetterSlots,
  tapOptionWithText,
  waitForLetterBlanks,
  wordForPattern,
} from './UiTestBattleHelpers.ets';

/**
 * FillLetter UI suite (V0.8.4).
 *
 * Config `selectOnlyQuestionTypeShared` forces 100% of today-battle
 * questions to the selected kind — no monster-slot ordering.
 */

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

async function launchApp(): Promise<Driver> {
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
      const home: Component | null = await driver.findComponent(ON.id('HomeStartButton'));
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

async function readFeedback(driver: Driver): Promise<string> {
  try {
    const fb: Component | null = await driver.findComponent(ON.id('BattleFeedback'));
    if (fb === null) {
      return '';
    }
    return await fb.getText();
  } catch (err) {
    throw err as Error;
  }
}

async function startFruitForestBattle(driver: Driver): Promise<void> {
  try {
    const fruit: Component | null = await driver.findComponent(ON.id('RegionChip_fruit-forest'));
    if (fruit !== null) {
      await fruit.click();
      await driver.delayMs(300);
    }
    const cta: Component | null = await driver.findComponent(ON.id('HomeStartButton'));
    expect(cta !== null).assertTrue();
    if (cta !== null) {
      await cta.click();
    }
    await driver.delayMs(1500);
    await driver.assertComponentExist(ON.id('BattleTitle'));
  } catch (err) {
    throw err as Error;
  }
}

async function exitToHome(driver: Driver): Promise<void> {
  try {
    const finish: Component | null = await driver.findComponent(ON.id('BattleFinishButton'));
    if (finish !== null) {
      await finish.click();
      await driver.delayMs(800);
    }
    const homeBtn: Component | null = await driver.findComponent(ON.id('ResultHomeButton'));
    if (homeBtn !== null) {
      await homeBtn.click();
      await driver.delayMs(800);
    }
    await returnToHome(driver);
  } catch (err) {
    throw err as Error;
  }
}

export default function fillLetterFlowUiTest(): void {
  describe('FillLetterFlow', () => {
    it('singleLetterFillAcceptsCorrectLetter', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await selectOnlyQuestionTypeShared(driver, 'fill-letter');
      await startFruitForestBattle(driver);

      const ready: boolean = await waitForLetterBlanks(driver, 1, 8);
      expect(ready).assertTrue();

      const slots: string[] = await readLetterSlots(driver);
      expect(countUnderscores(slots)).assertEqual(1);
      const word: string = wordForPattern(slots);
      expect(word !== '').assertTrue();
      const missingIdx: number = slots.indexOf('_');
      const letter: string = word.toLowerCase().charAt(missingIdx);
      const tapped: boolean = await tapOptionWithText(driver, letter);
      expect(tapped).assertTrue();
      await driver.delayMs(250);
      const fb: string = await readFeedback(driver);
      expect(fb.indexOf('正确') >= 0 || fb.indexOf('魔法爆发') >= 0).assertTrue();

      await exitToHome(driver);
      await selectAllQuestionTypesShared(driver);
      done();
    });

    it('mediumLetterFillCompletesBothSteps', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await selectOnlyQuestionTypeShared(driver, 'fill-letter-medium');
      await startFruitForestBattle(driver);

      const ready: boolean = await waitForLetterBlanks(driver, 2, 8);
      expect(ready).assertTrue();

      const slots: string[] = await readLetterSlots(driver);
      expect(countUnderscores(slots)).assertEqual(2);
      const word: string = wordForPattern(slots);
      expect(word !== '').assertTrue();
      const firstBlankIdx: number = slots.indexOf('_');
      const letter0: string = word.toLowerCase().charAt(firstBlankIdx);
      expect(await tapOptionWithText(driver, letter0)).assertTrue();
      await driver.delayMs(250);
      expect(await readFeedback(driver)).assertEqual('答对啦！下一空');
      await driver.delayMs(800);

      const slots2: string[] = await readLetterSlots(driver);
      expect(countUnderscores(slots2)).assertEqual(1);
      const remainingBlankIdx: number = slots2.indexOf('_');
      expect(remainingBlankIdx > firstBlankIdx).assertTrue();
      const letter1: string = word.toLowerCase().charAt(remainingBlankIdx);
      expect(await tapOptionWithText(driver, letter1)).assertTrue();
      await driver.delayMs(250);
      const fb1: string = await readFeedback(driver);
      expect(fb1.indexOf('正确') >= 0 || fb1.indexOf('魔法爆发') >= 0).assertTrue();

      await exitToHome(driver);
      await selectAllQuestionTypesShared(driver);
      done();
    });
  });
}
