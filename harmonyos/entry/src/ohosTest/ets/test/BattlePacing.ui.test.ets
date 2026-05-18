import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import {
  selectAllQuestionTypesShared,
  selectQuestionTypesShared,
} from './RoutingFlow.ui.test';
import {
  advanceBattleTurnCorrect,
  detectQuestionSurface,
  isBattlePageActive,
  isChallengeSurface,
  QuestionSurfaceKind,
} from './UiTestBattleHelpers.ets';

/**
 * V0.8.4 schedule-mode smokes — multi-type Config drives
 * BattleQuestionScheduler (two_phase / intro_only / challenge_only).
 */

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

/** Enough turns to see both intro kinds; full plan may end battle before challenge. */
const MAX_INTRO_OBSERVE_TURNS: number = 16;

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

async function detectSurfaceSettled(driver: Driver): Promise<QuestionSurfaceKind> {
  try {
    for (let attempt: number = 0; attempt < 6; attempt++) {
      const surface: QuestionSurfaceKind = await detectQuestionSurface(driver);
      if (surface !== 'unknown') {
        return surface;
      }
      await driver.delayMs(350);
    }
    return 'unknown';
  } catch (err) {
    throw err as Error;
  }
}

function recordSurface(
  surface: QuestionSurfaceKind,
  seenChoice: boolean[],
  seenFillLetter: boolean[],
  seenChallenge: boolean[],
): void {
  if (surface === 'choice') {
    seenChoice[0] = true;
  }
  if (surface === 'fill-letter') {
    seenFillLetter[0] = true;
  }
  if (isChallengeSurface(surface)) {
    seenChallenge[0] = true;
  }
}

export default function battlePacingUiTest(): void {
  describe('BattlePacing', () => {
    it('twoPhaseOpensOnIntroAndShowsBothIntroKinds', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await selectAllQuestionTypesShared(driver);
      await startFruitForestBattle(driver);
      await driver.delayMs(500);

      const firstSurface: QuestionSurfaceKind = await detectSurfaceSettled(driver);
      expect(isChallengeSurface(firstSurface)).assertFalse();

      const seenChoice: boolean[] = [false];
      const seenFillLetter: boolean[] = [false];
      const seenChallenge: boolean[] = [false];

      recordSurface(firstSurface, seenChoice, seenFillLetter, seenChallenge);

      for (let turn: number = 0; turn < MAX_INTRO_OBSERVE_TURNS; turn++) {
        if (!(await isBattlePageActive(driver))) {
          break;
        }
        const surface: QuestionSurfaceKind = await detectSurfaceSettled(driver);
        recordSurface(surface, seenChoice, seenFillLetter, seenChallenge);
        await advanceBattleTurnCorrect(driver);
        if (seenChoice[0] && seenFillLetter[0]) {
          break;
        }
      }

      expect(seenChoice[0]).assertTrue();
      expect(seenFillLetter[0]).assertTrue();

      await exitToHome(driver);
      await selectAllQuestionTypesShared(driver);
      done();
    });

    it('introOnlyNeverShowsChallengeSurfaces', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await selectQuestionTypesShared(driver, ['choice', 'fill-letter']);
      await startFruitForestBattle(driver);
      await driver.delayMs(500);

      for (let turn: number = 0; turn < 8; turn++) {
        if (!(await isBattlePageActive(driver))) {
          break;
        }
        const surface: QuestionSurfaceKind = await detectSurfaceSettled(driver);
        expect(isChallengeSurface(surface)).assertFalse();
        expect(surface === 'choice' || surface === 'fill-letter' || surface === 'unknown')
          .assertTrue();
        if (surface === 'unknown') {
          await driver.delayMs(400);
          continue;
        }
        await advanceBattleTurnCorrect(driver);
      }

      await exitToHome(driver);
      await selectAllQuestionTypesShared(driver);
      done();
    });

    it('challengeOnlyOpensOnChallengeSurface', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await selectQuestionTypesShared(driver, ['fill-letter-medium', 'spell']);
      await startFruitForestBattle(driver);
      await driver.delayMs(600);

      // Rare words may degrade to Choice once; skip until a challenge surface appears.
      let sawChallenge: boolean = false;
      for (let turn: number = 0; turn < 15; turn++) {
        if (!(await isBattlePageActive(driver))) {
          break;
        }
        const surface: QuestionSurfaceKind = await detectSurfaceSettled(driver);
        if (isChallengeSurface(surface)) {
          sawChallenge = true;
          break;
        }
        if (surface === 'choice' || surface === 'fill-letter') {
          await advanceBattleTurnCorrect(driver);
        } else if (surface === 'unknown') {
          await driver.delayMs(400);
        }
      }
      expect(sawChallenge).assertTrue();

      await exitToHome(driver);
      await selectAllQuestionTypesShared(driver);
      done();
    });
  });
}
