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
 * V0.3.7 acceptance:
 *  - HomePage toolbar surfaces 📖 HomeCodexButton (always enabled).
 *  - Codex page enters at index 0 (Slime), shows '1 / 3' indicator,
 *    CodexPrev disabled, CodexNext enabled.
 *  - Clicking CodexNext walks Slime → Zombie → Dragon and disables at
 *    end; clicking CodexPrev walks back and disables at start. Extra
 *    boundary clicks are no-ops (do not crash, do not wrap).
 *  - CodexBackButton returns to HomePage; HomeStartButton is reachable.
 */
export default function monsterCodexFlowUiTest(): void {
  describe('MonsterCodexFlow', () => {
    it('homeCodexButtonOpensCodexPage', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openCodex(driver);
      await driver.assertComponentExist(ON.id('CodexAvatar'));
      await driver.assertComponentExist(ON.text('Slime'));
      await driver.assertComponentExist(ON.text('「普通怪物」'));
      await driver.assertComponentExist(ON.text('1 / 3'));
      done();
    });

    it('nextArrowAdvancesAndDisablesAtEnd', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openCodex(driver);
      await clickByIdShared(driver, 'CodexNext');
      await driver.delayMs(300);
      await driver.assertComponentExist(ON.text('Zombie'));
      await driver.assertComponentExist(ON.text('2 / 3'));
      await clickByIdShared(driver, 'CodexNext');
      await driver.delayMs(300);
      await driver.assertComponentExist(ON.text('Dragon'));
      await driver.assertComponentExist(ON.text('3 / 3'));
      // Boundary: extra tap on disabled CodexNext is a no-op.
      await clickByIdShared(driver, 'CodexNext');
      await driver.delayMs(300);
      await driver.assertComponentExist(ON.text('Dragon'));
      await driver.assertComponentExist(ON.text('3 / 3'));
      done();
    });

    it('prevArrowGoesBackAndDisablesAtStart', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openCodex(driver);
      await clickByIdShared(driver, 'CodexNext');
      await driver.delayMs(300);
      await clickByIdShared(driver, 'CodexNext');
      await driver.delayMs(300);
      await driver.assertComponentExist(ON.text('Dragon'));
      await clickByIdShared(driver, 'CodexPrev');
      await driver.delayMs(300);
      await driver.assertComponentExist(ON.text('Zombie'));
      await clickByIdShared(driver, 'CodexPrev');
      await driver.delayMs(300);
      await driver.assertComponentExist(ON.text('Slime'));
      await driver.assertComponentExist(ON.text('1 / 3'));
      // Boundary: extra tap on disabled CodexPrev is a no-op.
      await clickByIdShared(driver, 'CodexPrev');
      await driver.delayMs(300);
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
