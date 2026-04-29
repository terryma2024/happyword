import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { clickByIdShared } from './RoutingFlow.ui.test';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

async function launchApp(): Promise<Driver> {
  const want: Want = { bundleName: BUNDLE, abilityName: 'EntryAbility' };
  await DELEGATOR.startAbility(want);
  const driver: Driver = Driver.create();
  await driver.delayMs(1000);
  return driver;
}

/**
 * Mirrors the helper in HomeToolbarLocked.ui.test — press back up to
 * 5 times until HomeStartButton resolves so each `it` block starts
 * on the HomePage even if a previous suite left the app mid-flow.
 */
async function returnToHome(driver: Driver): Promise<void> {
  for (let i: number = 0; i < 5; i++) {
    const home: Component | null =
      await driver.findComponent(ON.id('HomeStartButton'));
    if (home !== null) {
      return;
    }
    await driver.pressBack();
    await driver.delayMs(500);
  }
}

async function openCodex(driver: Driver): Promise<void> {
  await clickByIdShared(driver, 'HomeCodexButton');
  await driver.delayMs(1500);
}

/**
 * V0.3.8 acceptance (extends V0.3.7):
 *  - HomePage toolbar surfaces 📖 HomeCodexButton (always enabled).
 *  - Codex page enters at index 0 (Slime), shows '1 / 10' indicator,
 *    CodexPrev disabled, CodexNext enabled.
 *  - Clicking CodexNext walks all 10 entries (Slime → Zombie → Dragon →
 *    Pumpkin King → Imp King → Phoenix → Witch → Snow Queen → Unicorn
 *    → Kraken) and disables at end; clicking CodexPrev walks back to
 *    start. Extra boundary taps are no-ops (do not crash, do not wrap).
 *  - Boss entries surface their fairy-tale Chinese subtitle labels
 *    (e.g. 「秋夜灯王」 for Pumpkin King).
 *  - CodexBackButton returns to HomePage; HomeStartButton is reachable.
 */
async function clickNextAndDelay(driver: Driver, ms: number): Promise<void> {
  await clickByIdShared(driver, 'CodexNext');
  await driver.delayMs(ms);
}

async function clickPrevAndDelay(driver: Driver, ms: number): Promise<void> {
  await clickByIdShared(driver, 'CodexPrev');
  await driver.delayMs(ms);
}

export default function monsterCodexFlowUiTest(): void {
  describe('MonsterCodexFlow', () => {
    it('homeCodexButtonOpensCodexPage', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openCodex(driver);
      await driver.assertComponentExist(ON.id('CodexAvatar'));
      await driver.assertComponentExist(ON.text('Slime'));
      await driver.assertComponentExist(ON.text('「普通怪物」'));
      await driver.assertComponentExist(ON.text('1 / 10'));
      done();
    });

    it('nextArrowWalksAllTenEntriesAndDisablesAtEnd', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openCodex(driver);
      // Slime is the entry; walk 9 next clicks to land on Kraken.
      // Sample mid-walk on Pumpkin King (4 / 10) and Witch (7 / 10) to
      // verify the boss block surfaces correctly without exploding the
      // total runtime with 10 separate full-state assertions.
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Zombie'));
      await driver.assertComponentExist(ON.text('2 / 10'));
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Dragon'));
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Pumpkin King'));
      await driver.assertComponentExist(ON.text('「秋夜灯王」'));
      await driver.assertComponentExist(ON.text('4 / 10'));
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Imp King'));
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Phoenix'));
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Witch'));
      await driver.assertComponentExist(ON.text('「夜空魔法师」'));
      await driver.assertComponentExist(ON.text('7 / 10'));
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Snow Queen'));
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Unicorn'));
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Kraken'));
      await driver.assertComponentExist(ON.text('10 / 10'));
      // Boundary: extra tap on disabled CodexNext is a no-op.
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Kraken'));
      await driver.assertComponentExist(ON.text('10 / 10'));
      done();
    });

    it('prevArrowGoesBackAndDisablesAtStart', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openCodex(driver);
      // Walk to the end (9 next clicks).
      for (let i: number = 0; i < 9; i++) {
        await clickNextAndDelay(driver, 250);
      }
      await driver.assertComponentExist(ON.text('Kraken'));
      // Walk back to the start.
      for (let i: number = 0; i < 9; i++) {
        await clickPrevAndDelay(driver, 250);
      }
      await driver.assertComponentExist(ON.text('Slime'));
      await driver.assertComponentExist(ON.text('1 / 10'));
      // Boundary: extra tap on disabled CodexPrev is a no-op.
      await clickPrevAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Slime'));
      done();
    });

    it('backButtonReturnsToHome', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openCodex(driver);
      await driver.assertComponentExist(ON.id('CodexAvatar'));
      await clickByIdShared(driver, 'CodexBackButton');
      await driver.delayMs(1500);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      const avatar: Component | null =
        await driver.findComponent(ON.id('CodexAvatar'));
      expect(avatar === null).assertTrue();
      done();
    });
  });
}
