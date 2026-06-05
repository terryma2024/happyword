import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { clickByIdShared } from './RoutingFlow.ui.test';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

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

/**
 * Mirrors the helper in HomeToolbarLocked.ui.test — press back up to
 * 5 times until HomeStartButton resolves so each `it` block starts
 * on the HomePage even if a previous suite left the app mid-flow.
 */
async function returnToHome(driver: Driver): Promise<void> {
  try {
    for (let i: number = 0; i < 5; i++) {
      const home: Component | null =
        await driver.findComponent(ON.id('HomeStartButton'));
      if (home !== null) {
        return;
      }
      const codexBack: Component | null =
        await driver.findComponent(ON.id('CodexBackButton'));
      if (codexBack !== null) {
        await codexBack.click();
        await driver.delayMs(800);
        continue;
      }
      await driver.pressBack();
      await driver.delayMs(500);
    }
  } catch (err) {
    throw err as Error;
  }
}

async function openCodex(driver: Driver): Promise<void> {
  try {
    await clickByIdShared(driver, 'HomeCodexButton');
    await driver.delayMs(1500);
  } catch (err) {
    throw err as Error;
  }
}

/**
 * V0.3.8 acceptance (extends V0.3.7):
 *  - HomePage toolbar surfaces the HomeCodexButton (📖 emoji in
 *    v0.3.7–v0.3.9, codex.svg from v0.3.10), always enabled.
 *  - Codex page enters at index 0 (Slime), shows '1 / 100' indicator,
 *    CodexPrev disabled, CodexNext enabled.
 *  - Clicking CodexNext preserves the original first-ten order and can
 *    walk to the expanded final entry before disabling at the end.
 *  - Boss entries surface their fairy-tale Chinese subtitle labels
 *    (e.g. 「秋夜灯王」 for Pumpkin King).
 *  - CodexBackButton returns to HomePage; HomeStartButton is reachable.
 */
async function clickNextAndDelay(driver: Driver, ms: number): Promise<void> {
  try {
    await clickByIdShared(driver, 'CodexNext');
    await driver.delayMs(ms);
  } catch (err) {
    throw err as Error;
  }
}

async function clickPrevAndDelay(driver: Driver, ms: number): Promise<void> {
  try {
    await clickByIdShared(driver, 'CodexPrev');
    await driver.delayMs(ms);
  } catch (err) {
    throw err as Error;
  }
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
      await driver.assertComponentExist(ON.text('1 / 100'));
      await clickByIdShared(driver, 'CodexBackButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    it('nextArrowPreservesFirstTenAndDisablesAtExpandedEnd', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openCodex(driver);
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Zombie'));
      await driver.assertComponentExist(ON.text('2 / 100'));
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Dragon'));
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Pumpkin King'));
      await driver.assertComponentExist(ON.text('「秋夜灯王」'));
      await driver.assertComponentExist(ON.text('4 / 100'));
      for (let i: number = 0; i < 7; i++) {
        await clickNextAndDelay(driver, 120);
      }
      await driver.assertComponentExist(ON.text('Jellyfish'));
      await driver.assertComponentExist(ON.text('11 / 100'));
      for (let i: number = 0; i < 89; i++) {
        await clickNextAndDelay(driver, 180);
      }
      await driver.assertComponentExist(ON.text('Music Box Fairy'));
      await driver.assertComponentExist(ON.text('100 / 100'));
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Music Box Fairy'));
      await driver.assertComponentExist(ON.text('100 / 100'));
      await clickByIdShared(driver, 'CodexBackButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    it('prevArrowGoesBackAndDisablesAtStart', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openCodex(driver);
      // Walk a few entries forward, then back to the start.
      for (let i: number = 0; i < 3; i++) {
        await clickNextAndDelay(driver, 250);
      }
      await driver.assertComponentExist(ON.text('Pumpkin King'));
      for (let i: number = 0; i < 3; i++) {
        await clickPrevAndDelay(driver, 250);
      }
      await driver.assertComponentExist(ON.text('Slime'));
      await driver.assertComponentExist(ON.text('1 / 100'));
      // Boundary: extra tap on disabled CodexPrev is a no-op.
      await clickPrevAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('Slime'));
      await clickByIdShared(driver, 'CodexBackButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
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
