import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { common, Want } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import display from '@ohos.display';
import { clickByIdShared } from './RoutingFlow.ui.test';
import {
  __resetMonsterProgressStoreForTest,
  MONSTER_PROGRESS_PREFS_KEY,
  MONSTER_PROGRESS_PREFS_NAME,
} from '../../../main/ets/services/MonsterProgressStore';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();
const TOTAL_CODEX_COUNT: number = 100;

class UiMonsterProgressRecord {
  catalogIndex: number = 0;
  encountered: boolean = false;
  defeatCount: number = 0;
  claimedMilestones: number[] = [];
}

class UiMonsterProgressSnapshot {
  version: number = 1;
  records: UiMonsterProgressRecord[] = [];
}

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

function progressRecord(catalogIndex: number, defeatCount: number, claimedMilestones: number[] = []): UiMonsterProgressRecord {
  const rec: UiMonsterProgressRecord = new UiMonsterProgressRecord();
  rec.catalogIndex = catalogIndex;
  rec.encountered = true;
  rec.defeatCount = defeatCount;
  rec.claimedMilestones = claimedMilestones.slice();
  return rec;
}

function allEncounteredSnapshot(): UiMonsterProgressSnapshot {
  const snap: UiMonsterProgressSnapshot = new UiMonsterProgressSnapshot();
  for (let i: number = 1; i <= TOTAL_CODEX_COUNT; i++) {
    snap.records.push(progressRecord(i, 0));
  }
  return snap;
}

async function seedMonsterProgress(snapshot: UiMonsterProgressSnapshot): Promise<void> {
  try {
    const ability = await DELEGATOR.getCurrentTopAbility();
    const ctx: common.UIAbilityContext = ability.context as common.UIAbilityContext;
    const handle: preferences.Preferences =
      await preferences.getPreferences(ctx, MONSTER_PROGRESS_PREFS_NAME);
    await handle.put(MONSTER_PROGRESS_PREFS_KEY, JSON.stringify(snapshot));
    await handle.flush();
    __resetMonsterProgressStoreForTest();
  } catch (err) {
    throw err as Error;
  }
}

async function seedLockedCodex(driver: Driver): Promise<void> {
  try {
    await seedMonsterProgress(new UiMonsterProgressSnapshot());
    await driver.delayMs(300);
  } catch (err) {
    throw err as Error;
  }
}

async function seedFirstMonsterEncountered(driver: Driver, defeatCount: number): Promise<void> {
  try {
    const snap: UiMonsterProgressSnapshot = new UiMonsterProgressSnapshot();
    snap.records.push(progressRecord(1, defeatCount));
    await seedMonsterProgress(snap);
    await driver.delayMs(300);
  } catch (err) {
    throw err as Error;
  }
}

async function seedAllMonstersEncountered(driver: Driver): Promise<void> {
  try {
    await seedMonsterProgress(allEncounteredSnapshot());
    await driver.delayMs(300);
  } catch (err) {
    throw err as Error;
  }
}

async function findById(driver: Driver, id: string): Promise<Component | null> {
  try {
    return await driver.findComponent(ON.id(id));
  } catch (err) {
    throw err as Error;
  }
}

async function assertMissingById(driver: Driver, id: string): Promise<void> {
  const comp: Component | null = await findById(driver, id);
  expect(comp === null).assertTrue();
}

async function assertButtonDisabled(driver: Driver, id: string, label: string): Promise<void> {
  try {
    const comp: Component | null = await findById(driver, id);
    expect(comp !== null).assertTrue();
    if (comp !== null) {
      const text: string = await comp.getText();
      const enabled: boolean = await comp.isEnabled();
      expect(text).assertEqual(label);
      expect(enabled).assertFalse();
    }
  } catch (err) {
    throw err as Error;
  }
}

async function assertDescriptionVisibleInViewport(driver: Driver): Promise<void> {
  try {
    const desc: Component | null = await findById(driver, 'CodexDescription');
    expect(desc !== null).assertTrue();
    if (desc !== null) {
      const text: string = await desc.getText();
      const bounds = await desc.getBounds();
      const d: display.Display = display.getDefaultDisplaySync();
      expect(text.length > 0).assertTrue();
      expect(bounds.top >= 0).assertTrue();
      expect(bounds.bottom <= d.height).assertTrue();
    }
  } catch (err) {
    throw err as Error;
  }
}

/**
 * V1.0.2 acceptance (extends V0.3.8):
 *  - HomePage toolbar surfaces the HomeCodexButton (📖 emoji in
 *    v0.3.7–v0.3.9, codex.svg from v0.3.10), always enabled.
 *  - Codex page enters at index 0. A monster with no local encounter
 *    record shows masked name/kind/description, hides defeat count,
 *    and hides both reward buttons.
 *  - An encountered monster shows normal text, defeat count, and both
 *    disabled reward buttons until the 50 / 100 thresholds are reached.
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
      await seedLockedCodex(driver);
      await openCodex(driver);
      await driver.assertComponentExist(ON.id('CodexAvatar'));
      await driver.assertComponentExist(ON.text('????'));
      await driver.assertComponentExist(ON.text('「????」'));
      await driver.assertComponentExist(ON.text('1 / 100'));
      await assertMissingById(driver, 'CodexDefeatCount');
      await assertMissingById(driver, 'CodexReward50Button');
      await assertMissingById(driver, 'CodexReward100Button');
      await assertDescriptionVisibleInViewport(driver);
      await clickByIdShared(driver, 'CodexBackButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    it('encounteredMonsterShowsDisabledRewardsAndVisibleDescription', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await seedFirstMonsterEncountered(driver, 1);
      await openCodex(driver);
      await driver.assertComponentExist(ON.text('软泥小灵'));
      await driver.assertComponentExist(ON.text('「普通怪物」'));
      await driver.assertComponentExist(ON.text('击败 1 次'));
      await assertButtonDisabled(driver, 'CodexReward50Button', '50 金币 1/50');
      await assertButtonDisabled(driver, 'CodexReward100Button', '100 金币 1/100');
      await assertDescriptionVisibleInViewport(driver);
      await clickByIdShared(driver, 'CodexBackButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    it('nextArrowPreservesFirstTenAndDisablesAtExpandedEnd', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await seedAllMonstersEncountered(driver);
      await openCodex(driver);
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('书页僵僵'));
      await driver.assertComponentExist(ON.text('2 / 100'));
      await clickNextAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('云眠巨龙'));
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
      await seedAllMonstersEncountered(driver);
      await openCodex(driver);
      // Walk a few entries forward, then back to the start.
      for (let i: number = 0; i < 3; i++) {
        await clickNextAndDelay(driver, 250);
      }
      await driver.assertComponentExist(ON.text('Pumpkin King'));
      for (let i: number = 0; i < 3; i++) {
        await clickPrevAndDelay(driver, 250);
      }
      await driver.assertComponentExist(ON.text('软泥小灵'));
      await driver.assertComponentExist(ON.text('1 / 100'));
      // Boundary: extra tap on disabled CodexPrev is a no-op.
      await clickPrevAndDelay(driver, 300);
      await driver.assertComponentExist(ON.text('软泥小灵'));
      await clickByIdShared(driver, 'CodexBackButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    it('backButtonReturnsToHome', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await seedLockedCodex(driver);
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
