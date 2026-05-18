import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import {
  selectAllQuestionTypesShared,
  selectOnlyQuestionTypeShared,
} from './RoutingFlow.ui.test';
import {
  assertPlayerHp,
  findPlayerFullHpLabel,
  findWrongPoolIndex,
  parseHpLabel,
  readSpellEntryState,
  readSpellSlots,
  SpellEntryState,
  tapPoolByIndex,
  tapSpellPoolLetter,
  waitForSpellArea,
} from './UiTestBattleHelpers.ets';

/**
 * Spell UI suite (V0.8.4).
 *
 * `selectOnlyQuestionTypeShared('spell')` → first question is Spell
 * (100% single-type mode). No Boss-slot walk required.
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

async function readFeedbackLocal(driver: Driver): Promise<string> {
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

export default function spellQuestionFlowUiTest(): void {
  describe('SpellQuestionFlow', () => {
    it('fillsSpellSlotsByTappingCorrectPoolLetters', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await selectOnlyQuestionTypeShared(driver, 'spell');
      await startFruitForestBattle(driver);

      expect(await waitForSpellArea(driver, 10)).assertTrue();
      const entry: SpellEntryState = await readSpellEntryState(driver);
      expect(entry.slots.length >= 4).assertTrue();
      expect(entry.answer !== '').assertTrue();
      expect(entry.slots[0]).assertEqual(entry.answer.toLowerCase().charAt(0));
      for (let i: number = 1; i < entry.slots.length; i++) {
        expect(entry.slots[i]).assertEqual('_');
      }
      await driver.delayMs(300);

      const lower: string = entry.answer.toLowerCase();
      for (let pos: number = 1; pos < lower.length; pos++) {
        const letter: string = lower.charAt(pos);
        const tappedIdx: number = await tapSpellPoolLetter(driver, letter);
        expect(tappedIdx >= 0).assertTrue();
        let slotsNow: string[] = [];
        for (let attempt: number = 0; attempt < 10; attempt++) {
          await driver.delayMs(150);
          slotsNow = await readSpellSlots(driver);
          if (slotsNow.length > pos && slotsNow[pos] === letter) {
            break;
          }
        }
        expect(slotsNow[pos]).assertEqual(letter);
      }

      let fbHit: boolean = false;
      for (let attempt: number = 0; attempt < 8; attempt++) {
        await driver.delayMs(80);
        const fb: string = await readFeedbackLocal(driver);
        if (fb.indexOf('正确') >= 0 || fb.indexOf('魔法爆发') >= 0) {
          fbHit = true;
          break;
        }
      }
      expect(fbHit).assertTrue();

      await exitToHome(driver);
      await selectAllQuestionTypesShared(driver);
      done();
    });

    it('spellWrongTapDecreasesPlayerHp', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await selectOnlyQuestionTypeShared(driver, 'spell');
      await startFruitForestBattle(driver);

      expect(await waitForSpellArea(driver, 10)).assertTrue();
      const entry: SpellEntryState = await readSpellEntryState(driver);
      expect(entry.answer !== '').assertTrue();

      const hpBefore: string = await findPlayerFullHpLabel(driver);
      expect(hpBefore !== '').assertTrue();
      const parsed = parseHpLabel(hpBefore);
      expect(parsed !== null).assertTrue();

      const lower: string = entry.answer.toLowerCase();
      const expectedNextLetter: string = lower.charAt(1);
      const wrongIdx: number = await findWrongPoolIndex(driver, expectedNextLetter);
      expect(wrongIdx >= 0).assertTrue();

      await tapPoolByIndex(driver, wrongIdx);
      await driver.delayMs(900);
      if (parsed !== null) {
        await assertPlayerHp(driver, parsed.current - 1, parsed.max);
      }

      const slotsAfter: string[] = await readSpellSlots(driver);
      expect(slotsAfter[0]).assertEqual(lower.charAt(0));
      for (let i: number = 1; i < slotsAfter.length; i++) {
        expect(slotsAfter[i]).assertEqual('_');
      }

      await exitToHome(driver);
      await selectAllQuestionTypesShared(driver);
      done();
    });
  });
}
