import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';

/**
 * V0.4.1 SpellQuestionFlow — drives a Boss-monster Spell question
 * end-to-end on a real device. The fruit-forest region keeps a 5-slot
 * plan ending on a Boss whose word is sampled from the 'fruit'
 * category; every fruit word in the bundled dictionary fits within
 * SpellGenerator's [4, 9] gate, so the Boss reliably emits a Spell
 * question on this suite.
 *
 * Uses a static zh→en catalog (mirrors FillLetterFlow.ui.test) so the
 * suite stays deterministic regardless of the LearningRecorder state
 * left by earlier suites.
 *
 * Coverage:
 *   1. happy path — taps pool letters in correct order, the slot row
 *      fills left-to-right, and the green '正确！' / burst feedback
 *      fires once the last letter lands.
 *   2. wrong-tap rejection — taps a pool letter that does NOT match
 *      the next empty slot; slots row stays unchanged, no feedback
 *      text fires (the question is still in progress).
 */

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

const SPELL_AREA_ID: string = 'BattleSpellArea';
const MAX_SPELL_LEN: number = 9;
const MAX_POOL: number = 9;

const WORD_ZH: string[] = [
  '苹果', '香蕉', '橙子', '葡萄', '梨', '桃子', '柠檬', '芒果', '瓜', '樱桃',
  '学校', '医院', '公园', '超市', '图书馆', '动物园', '银行', '博物馆', '车站', '家',
  '电视', '椅子', '床', '桌子', '沙发', '台灯', '门', '窗户', '书', '杯子',
];
const WORD_EN: string[] = [
  'apple', 'banana', 'orange', 'grape', 'pear', 'peach', 'lemon', 'mango', 'melon', 'cherry',
  'school', 'hospital', 'park', 'supermarket', 'library', 'zoo', 'bank', 'museum', 'station', 'home',
  'TV', 'chair', 'bed', 'table', 'sofa', 'lamp', 'door', 'window', 'book', 'cup',
];

async function launchApp(): Promise<Driver> {
  const want: Want = { bundleName: BUNDLE, abilityName: 'EntryAbility' };
  await DELEGATOR.startAbility(want);
  const driver: Driver = Driver.create();
  await driver.delayMs(1000);
  return driver;
}

async function returnToHome(driver: Driver): Promise<void> {
  for (let i: number = 0; i < 5; i++) {
    const home: Component | null = await driver.findComponent(ON.id('HomeStartButton'));
    if (home !== null) {
      return;
    }
    await driver.pressBack();
    await driver.delayMs(500);
  }
}

function enForZh(zh: string): string {
  for (let i: number = 0; i < WORD_ZH.length; i++) {
    if (WORD_ZH[i] === zh) {
      return WORD_EN[i];
    }
  }
  return '';
}

async function getPromptText(driver: Driver): Promise<string> {
  const p: Component | null = await driver.findComponent(ON.id('BattlePrompt'));
  if (p === null) {
    return '';
  }
  return await p.getText();
}

async function readFeedback(driver: Driver): Promise<string> {
  const fb: Component | null = await driver.findComponent(ON.id('BattleFeedback'));
  if (fb === null) {
    return '';
  }
  return await fb.getText();
}

async function readLetterSlots(driver: Driver, max: number = 16): Promise<string[]> {
  const slots: string[] = [];
  for (let i: number = 0; i < max; i++) {
    const slot: Component | null = await driver.findComponent(ON.id(`LetterSlotText_${i}`));
    if (slot === null) {
      if (slots.length > 0) {
        break;
      }
      continue;
    }
    const text: string = await slot.getText();
    slots.push(text);
  }
  return slots;
}

function countUnderscores(slots: string[]): number {
  let n: number = 0;
  for (let i: number = 0; i < slots.length; i++) {
    if (slots[i] === '_') {
      n += 1;
    }
  }
  return n;
}

function wordForPattern(slots: string[]): string {
  for (let i: number = 0; i < WORD_EN.length; i++) {
    const w: string = WORD_EN[i].toLowerCase();
    if (w.length !== slots.length) {
      continue;
    }
    let ok: boolean = true;
    for (let j: number = 0; j < slots.length; j++) {
      const s: string = slots[j];
      if (s === '_') {
        continue;
      }
      if (s.toLowerCase() !== w.charAt(j)) {
        ok = false;
        break;
      }
    }
    if (ok) {
      return WORD_EN[i];
    }
  }
  return '';
}

async function tapOptionWithText(driver: Driver, target: string): Promise<boolean> {
  const ids: string[] = ['BattleOptionA', 'BattleOptionB', 'BattleOptionC'];
  for (let i: number = 0; i < ids.length; i++) {
    const btn: Component | null = await driver.findComponent(ON.id(ids[i]));
    if (btn === null) {
      continue;
    }
    const text: string = await btn.getText();
    if (text === target) {
      await btn.click();
      return true;
    }
  }
  return false;
}

async function startFruitForestBattle(driver: Driver): Promise<void> {
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
}

async function exitToHome(driver: Driver): Promise<void> {
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
}

/**
 * Read the SpellingArea slot row state, e.g. ['a', '_', '_', '_', '_'].
 * Returns an empty array when the area is not currently mounted.
 */
async function readSpellSlots(driver: Driver): Promise<string[]> {
  const out: string[] = [];
  for (let i: number = 0; i < MAX_SPELL_LEN; i++) {
    const slot: Component | null =
      await driver.findComponent(ON.id(`${SPELL_AREA_ID}_Slot_${i}`));
    if (slot === null) {
      break;
    }
    const text: string = await slot.getText();
    out.push(text);
  }
  return out;
}

async function readSpellPool(driver: Driver): Promise<string[]> {
  const out: string[] = [];
  for (let i: number = 0; i < MAX_POOL; i++) {
    const btn: Component | null =
      await driver.findComponent(ON.id(`${SPELL_AREA_ID}_Pool_${i}`));
    if (btn === null) {
      break;
    }
    const text: string = await btn.getText();
    out.push(text);
  }
  return out;
}

/**
 * Tap the first non-consumed pool button whose label matches `letter`.
 * Returns the pool index that was tapped, or -1 if no match was found.
 *
 * V0.4.8 follow-up: the BGM AVPlayer + parallel SFX (set to
 * INDEPENDENT_MODE so they don't silence each other) add non-zero
 * jitter to the emulator's UI thread, which occasionally pushes
 * the letter-find loop to its first frame before the pool buttons
 * have finished re-rendering after the previous tap. The function
 * retries the find up to ~1.5 s (10 × 150 ms) before giving up,
 * so a transient empty-pool moment doesn't become a -1.
 */
async function tapSpellPoolLetter(driver: Driver, letter: string): Promise<number> {
  for (let attempt: number = 0; attempt < 10; attempt++) {
    for (let i: number = 0; i < MAX_POOL; i++) {
      const btn: Component | null =
        await driver.findComponent(ON.id(`${SPELL_AREA_ID}_Pool_${i}`));
      if (btn === null) {
        break;
      }
      const text: string = await btn.getText();
      if (text === letter) {
        await btn.click();
        await driver.delayMs(150);
        return i;
      }
    }
    await driver.delayMs(150);
  }
  return -1;
}

/** Find the first pool index whose label is NOT `forbidden`. */
async function findWrongPoolIndex(driver: Driver, forbidden: string): Promise<number> {
  for (let i: number = 0; i < MAX_POOL; i++) {
    const btn: Component | null =
      await driver.findComponent(ON.id(`${SPELL_AREA_ID}_Pool_${i}`));
    if (btn === null) {
      break;
    }
    const text: string = await btn.getText();
    if (text !== forbidden) {
      return i;
    }
  }
  return -1;
}

async function tapPoolByIndex(driver: Driver, idx: number): Promise<void> {
  const btn: Component | null =
    await driver.findComponent(ON.id(`${SPELL_AREA_ID}_Pool_${idx}`));
  if (btn !== null) {
    await btn.click();
  }
}

/**
 * Drive the battle until the SpellingArea is on screen, answering
 * intermediate Choice / FillLetter / FillLetterMedium questions
 * correctly along the way. Returns the slots+answer when ready, or
 * empty slots when the budget was spent without ever reaching Spell.
 */
class SpellEntryState {
  slots: string[] = [];
  answer: string = '';
}

async function driveUntilSpell(driver: Driver, maxTurns: number): Promise<SpellEntryState> {
  const out: SpellEntryState = new SpellEntryState();
  // V0.4.4: add a small initial settle so BattlePage's first-question
  // render lands before we probe ids. After heavy-suite runs the
  // emulator can take >900ms to commit the first AppStorage-driven
  // frame, which previously surfaced as a Spell-never-arrives flake.
  await driver.delayMs(500);
  for (let turn: number = 0; turn < maxTurns; turn++) {
    // Already at Spell?
    const spellSlot0: Component | null =
      await driver.findComponent(ON.id(`${SPELL_AREA_ID}_Slot_0`));
    if (spellSlot0 !== null) {
      // Allow any in-flight pool/slot animation to settle before we
      // snapshot the row — readSpellSlots and readSpellPool race
      // against SpellingArea's reset path.
      await driver.delayMs(150);
      const slots: string[] = await readSpellSlots(driver);
      const pool: string[] = await readSpellPool(driver);
      const reconstructed: string[] = slots.slice();
      for (let i: number = 0; i < reconstructed.length; i++) {
        if (reconstructed[i] === '_') {
          reconstructed[i] = '_';
        }
      }
      const answer: string = wordForPattern(reconstructed);
      out.slots = slots;
      out.answer = answer;
      // Sanity: pool size = slots.length - 1, only slot 0 revealed.
      expect(pool.length === slots.length - 1).assertTrue();
      return out;
    }
    // FillLetter / FillLetterMedium step?
    const ltr: Component | null = await driver.findComponent(ON.id('LetterTemplateRow'));
    if (ltr !== null) {
      const slots: string[] = await readLetterSlots(driver);
      const word: string = wordForPattern(slots);
      if (word === '') {
        return out;
      }
      const missingIdx: number = slots.indexOf('_');
      const letter: string = word.toLowerCase().charAt(missingIdx);
      await tapOptionWithText(driver, letter);
      await driver.delayMs(900);
      continue;
    }
    // Choice prompt.
    const promptText: string = await getPromptText(driver);
    const en: string = enForZh(promptText);
    if (en === '') {
      return out;
    }
    await tapOptionWithText(driver, en);
    await driver.delayMs(900);
  }
  return out;
}

export default function spellQuestionFlowUiTest(): void {
  describe('SpellQuestionFlow', () => {
    /**
     * Walk to the Boss-slot Spell question, tap pool letters in
     * the correct order, and assert the slot row fills + green
     * feedback fires when the last letter lands.
     */
    it('fillsSpellSlotsByTappingCorrectPoolLetters', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await startFruitForestBattle(driver);

      const entry: SpellEntryState = await driveUntilSpell(driver, 50);
      expect(entry.slots.length >= 4).assertTrue();
      expect(entry.answer !== '').assertTrue();
      // First slot is pre-revealed, every other slot starts as '_'.
      expect(entry.slots[0]).assertEqual(entry.answer.toLowerCase().charAt(0));
      for (let i: number = 1; i < entry.slots.length; i++) {
        expect(entry.slots[i]).assertEqual('_');
      }

      // Tap pool letters in left-to-right order, asserting after each
      // tap that the slot row advanced one position. After V0.4.8
      // added BGM + parallel SFX (INDEPENDENT_MODE), slot read polls
      // up to ~1.5 s so a brief UI-thread pause from the AVPlayer
      // mixing doesn't read the pre-tap snapshot and fail.
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
      // SpellingArea's 200 ms reveal flash fires onSpellComplete →
      // handleSpellSubmit, which sets feedbackText synchronously.
      // BattlePage then keeps that text for FEEDBACK_MS (650 ms)
      // before clearing it, so we must read inside that window.
      // Reading at +350 ms catches the green "正确！" / burst label
      // with comfortable margin on either side.
      await driver.delayMs(350);
      const fb: string = await readFeedback(driver);
      expect(fb.indexOf('正确') >= 0 || fb.indexOf('魔法爆发') >= 0).assertTrue();

      await exitToHome(driver);
      done();
    });

    /**
     * Tapping a pool letter that does not match the next empty slot
     * leaves the slot row unchanged (the wrong tap must not advance
     * the spell). The first-letter slot is still revealed; every
     * other slot is still '_'.
     */
    it('rejectsTapsThatDoNotMatchTheNextSlot', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await startFruitForestBattle(driver);

      const entry: SpellEntryState = await driveUntilSpell(driver, 50);
      expect(entry.slots.length >= 4).assertTrue();
      expect(entry.answer !== '').assertTrue();

      const lower: string = entry.answer.toLowerCase();
      const expectedNextLetter: string = lower.charAt(1);
      const wrongIdx: number = await findWrongPoolIndex(driver, expectedNextLetter);
      // If every pool chip happens to share the expected letter (e.g.
      // a word like 'hooo' that doesn't exist), skip the wrong-tap
      // assertion gracefully — the happy path test covers correctness.
      if (wrongIdx >= 0) {
        await tapPoolByIndex(driver, wrongIdx);
        await driver.delayMs(300);
        const slotsAfter: string[] = await readSpellSlots(driver);
        // First slot still revealed; everything past slot 0 still blank.
        expect(slotsAfter[0]).assertEqual(lower.charAt(0));
        for (let i: number = 1; i < slotsAfter.length; i++) {
          expect(slotsAfter[i]).assertEqual('_');
        }
      }
      await exitToHome(driver);
      done();
    });
  });
}
