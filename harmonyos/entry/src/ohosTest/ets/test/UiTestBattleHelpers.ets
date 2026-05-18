import { Driver, ON, Component } from '@kit.TestKit';
import {
  clickByIdShared,
  selectOnlyQuestionTypeShared,
  tapCorrectAnswerShared,
} from './RoutingFlow.ui.test';

/** V0.8.4 default player max HP on fresh config. */
export const DEFAULT_PLAYER_HP_UI: number = 10;

export const SPELL_AREA_ID: string = 'BattleSpellArea';
const MAX_SPELL_LEN: number = 9;
const MAX_POOL: number = 9;

export type QuestionSurfaceKind =
  | 'choice'
  | 'fill-letter'
  | 'fill-letter-medium'
  | 'spell'
  | 'unknown';

const WORD_ZH: string[] = [
  '苹果', '香蕉', '橙子', '葡萄', '梨', '桃子', '柠檬', '芒果', '瓜', '樱桃',
  '学校', '医院', '公园', '超市', '图书馆', '动物园', '银行', '博物馆', '车站', '家',
  '电视', '椅子', '床', '桌子', '沙发', '台灯', '门', '窗户', '书', '杯子',
  '猫', '狗', '狮子', '老虎', '熊', '青蛙', '鸭子', '老鼠', '绵羊', '马',
  '鱼', '鲸鱼', '鲨鱼', '螃蟹', '海豚', '章鱼', '海豹', '海龟', '海星', '水母',
];
const WORD_EN: string[] = [
  'apple', 'banana', 'orange', 'grape', 'pear', 'peach', 'lemon', 'mango', 'melon', 'cherry',
  'school', 'hospital', 'park', 'supermarket', 'library', 'zoo', 'bank', 'museum', 'station', 'home',
  'TV', 'chair', 'bed', 'table', 'sofa', 'lamp', 'door', 'window', 'book', 'cup',
  'cat', 'dog', 'lion', 'tiger', 'bear', 'frog', 'duck', 'mouse', 'sheep', 'horse',
  'fish', 'whale', 'shark', 'crab', 'dolphin', 'octopus', 'seal', 'turtle', 'starfish', 'jellyfish',
];

export async function assertPlayerHp(
  driver: Driver,
  current: number,
  max: number,
): Promise<void> {
  try {
    await driver.assertComponentExist(ON.text(`HP ${current} / ${max}`));
  } catch (err) {
    throw err as Error;
  }
}

/** Full-HP label on the player card (V0.8.4 default 10; legacy saves may be 5). */
export async function findPlayerFullHpLabel(driver: Driver): Promise<string> {
  try {
    const maxCandidates: number[] = [DEFAULT_PLAYER_HP_UI, 5];
    for (let i: number = 0; i < maxCandidates.length; i++) {
      const max: number = maxCandidates[i];
      const label: string = `HP ${max} / ${max}`;
      const comp: Component | null = await driver.findComponent(ON.text(label));
      if (comp !== null) {
        return label;
      }
    }
    return '';
  } catch (err) {
    throw err as Error;
  }
}

export class PlayerHpValues {
  current: number = 0;
  max: number = 0;
}

export function parseHpLabel(label: string): PlayerHpValues | null {
  const parts: string[] = label.split(' ');
  if (parts.length !== 4 || parts[0] !== 'HP' || parts[2] !== '/') {
    return null;
  }
  const current: number = parseInt(parts[1], 10);
  const max: number = parseInt(parts[3], 10);
  if (isNaN(current) || isNaN(max)) {
    return null;
  }
  const out: PlayerHpValues = new PlayerHpValues();
  out.current = current;
  out.max = max;
  return out;
}

export async function detectQuestionSurface(driver: Driver): Promise<QuestionSurfaceKind> {
  try {
    const spellSlot: Component | null =
      await driver.findComponent(ON.id(`${SPELL_AREA_ID}_Slot_0`));
    if (spellSlot !== null) {
      return 'spell';
    }
    const ltr: Component | null = await driver.findComponent(ON.id('LetterTemplateRow'));
    if (ltr !== null) {
      const slots: string[] = await readLetterSlots(driver);
      const blanks: number = countUnderscores(slots);
      if (blanks === 2) {
        return 'fill-letter-medium';
      }
      if (blanks === 1) {
        return 'fill-letter';
      }
      return 'fill-letter';
    }
    const opt: Component | null = await driver.findComponent(ON.id('BattleOptionA'));
    if (opt !== null) {
      return 'choice';
    }
    return 'unknown';
  } catch (err) {
    throw err as Error;
  }
}

export function enForZh(zh: string): string {
  for (let i: number = 0; i < WORD_ZH.length; i++) {
    if (WORD_ZH[i] === zh) {
      return WORD_EN[i];
    }
  }
  return '';
}

export function wordForPattern(slots: string[]): string {
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

export async function readLetterSlots(driver: Driver, max: number = 16): Promise<string[]> {
  try {
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
  } catch (err) {
    throw err as Error;
  }
}

export function countUnderscores(slots: string[]): number {
  let n: number = 0;
  for (let i: number = 0; i < slots.length; i++) {
    if (slots[i] === '_') {
      n += 1;
    }
  }
  return n;
}

export async function getPromptText(driver: Driver): Promise<string> {
  try {
    const p: Component | null = await driver.findComponent(ON.id('BattlePrompt'));
    if (p === null) {
      return '';
    }
    return await p.getText();
  } catch (err) {
    throw err as Error;
  }
}

export async function tapOptionWithText(driver: Driver, target: string): Promise<boolean> {
  try {
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
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Poll until LetterTemplateRow shows exactly `blankCount` underscores.
 */
export async function waitForLetterBlanks(
  driver: Driver,
  blankCount: number,
  maxAttempts: number = 12,
): Promise<boolean> {
  try {
    for (let attempt: number = 0; attempt < maxAttempts; attempt++) {
      const row: Component | null = await driver.findComponent(ON.id('LetterTemplateRow'));
      if (row !== null) {
        const slots: string[] = await readLetterSlots(driver);
        if (countUnderscores(slots) === blankCount) {
          return true;
        }
      }
      await driver.delayMs(400);
    }
    return false;
  } catch (err) {
    throw err as Error;
  }
}

export async function waitForSpellArea(
  driver: Driver,
  maxAttempts: number = 12,
): Promise<boolean> {
  try {
    for (let attempt: number = 0; attempt < maxAttempts; attempt++) {
      const slot: Component | null =
        await driver.findComponent(ON.id(`${SPELL_AREA_ID}_Slot_0`));
      if (slot !== null) {
        await driver.delayMs(150);
        return true;
      }
      await driver.delayMs(400);
    }
    return false;
  } catch (err) {
    throw err as Error;
  }
}

export async function readSpellSlots(driver: Driver): Promise<string[]> {
  try {
    const out: string[] = [];
    for (let i: number = 0; i < MAX_SPELL_LEN; i++) {
      const slot: Component | null =
        await driver.findComponent(ON.id(`${SPELL_AREA_ID}_Slot_${i}`));
      if (slot === null) {
        break;
      }
      out.push(await slot.getText());
    }
    return out;
  } catch (err) {
    throw err as Error;
  }
}

export async function readSpellPool(driver: Driver): Promise<string[]> {
  try {
    const out: string[] = [];
    for (let i: number = 0; i < MAX_POOL; i++) {
      const btn: Component | null =
        await driver.findComponent(ON.id(`${SPELL_AREA_ID}_Pool_${i}`));
      if (btn === null) {
        break;
      }
      out.push(await btn.getText());
    }
    return out;
  } catch (err) {
    throw err as Error;
  }
}

function sameLetterMultiset(left: string[], right: string[]): boolean {
  if (left.length !== right.length) {
    return false;
  }
  const remaining: string[] = right.slice();
  for (let i: number = 0; i < left.length; i++) {
    const idx: number = remaining.indexOf(left[i]);
    if (idx < 0) {
      return false;
    }
    remaining.splice(idx, 1);
  }
  return remaining.length === 0;
}

export function wordForSpellState(slots: string[], pool: string[]): string {
  const poolLetters: string[] = [];
  for (let i: number = 0; i < pool.length; i++) {
    poolLetters.push(pool[i].toLowerCase());
  }
  for (let i: number = 0; i < WORD_EN.length; i++) {
    const w: string = WORD_EN[i].toLowerCase();
    if (w.length !== slots.length) {
      continue;
    }
    const missingLetters: string[] = [];
    let ok: boolean = true;
    for (let j: number = 0; j < slots.length; j++) {
      const s: string = slots[j];
      if (s === '_') {
        missingLetters.push(w.charAt(j));
        continue;
      }
      if (s.toLowerCase() !== w.charAt(j)) {
        ok = false;
        break;
      }
    }
    if (ok && sameLetterMultiset(missingLetters, poolLetters)) {
      return WORD_EN[i];
    }
  }
  return wordForPattern(slots);
}

export class SpellEntryState {
  slots: string[] = [];
  answer: string = '';
}

export async function readSpellEntryState(driver: Driver): Promise<SpellEntryState> {
  const out: SpellEntryState = new SpellEntryState();
  out.slots = await readSpellSlots(driver);
  const pool: string[] = await readSpellPool(driver);
  out.answer = wordForSpellState(out.slots, pool);
  return out;
}

export async function tapSpellPoolLetter(driver: Driver, letter: string): Promise<number> {
  try {
    for (let attempt: number = 0; attempt < 10; attempt++) {
      for (let i: number = 0; i < MAX_POOL; i++) {
        const btn: Component | null =
          await driver.findComponent(ON.id(`${SPELL_AREA_ID}_Pool_${i}`));
        if (btn === null) {
          break;
        }
        const text: string = await btn.getText();
        const enabled: boolean = await btn.isEnabled();
        if (text === letter && enabled) {
          await btn.click();
          await driver.delayMs(150);
          return i;
        }
      }
      await driver.delayMs(150);
    }
    return -1;
  } catch (err) {
    throw err as Error;
  }
}

export async function findWrongPoolIndex(driver: Driver, forbidden: string): Promise<number> {
  try {
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
  } catch (err) {
    throw err as Error;
  }
}

export async function tapPoolByIndex(driver: Driver, idx: number): Promise<void> {
  try {
    const btn: Component | null =
      await driver.findComponent(ON.id(`${SPELL_AREA_ID}_Pool_${idx}`));
    if (btn !== null) {
      await btn.click();
    }
  } catch (err) {
    throw err as Error;
  }
}

export function isChallengeSurface(surface: QuestionSurfaceKind): boolean {
  return surface === 'fill-letter-medium' || surface === 'spell';
}

async function tapCurrentFillLetterStep(driver: Driver): Promise<void> {
  const slots: string[] = await readLetterSlots(driver);
  const word: string = wordForPattern(slots);
  if (word === '') {
    throw new Error('tapCurrentFillLetterStep: could not resolve word');
  }
  const missingIdx: number = slots.indexOf('_');
  const letter: string = word.toLowerCase().charAt(missingIdx);
  const tapped: boolean = await tapOptionWithText(driver, letter);
  if (!tapped) {
    throw new Error('tapCurrentFillLetterStep: option not found');
  }
}

/**
 * Complete the current Spell question by tapping pool letters in order.
 */
export async function completeSpellQuestion(driver: Driver): Promise<void> {
  try {
    const entry: SpellEntryState = await readSpellEntryState(driver);
    if (entry.answer === '') {
      throw new Error('completeSpellQuestion: empty answer');
    }
    const lower: string = entry.answer.toLowerCase();
    for (let pos: number = 1; pos < lower.length; pos++) {
      const letter: string = lower.charAt(pos);
      const tappedIdx: number = await tapSpellPoolLetter(driver, letter);
      if (tappedIdx < 0) {
        throw new Error(`completeSpellQuestion: pool letter ${letter} not found`);
      }
      await driver.delayMs(150);
    }
    await driver.delayMs(750);
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Answer one question correctly for Choice or FillLetter surfaces.
 * Spell completion is not handled here (use advanceBattleTurnCorrect).
 */
export async function advanceOneCorrect(driver: Driver): Promise<void> {
  try {
    const surface: QuestionSurfaceKind = await detectQuestionSurface(driver);
    if (surface === 'choice') {
      await tapCorrectAnswerShared(driver);
      await driver.delayMs(900);
      return;
    }
    if (surface === 'fill-letter' || surface === 'fill-letter-medium') {
      await tapCurrentFillLetterStep(driver);
      await driver.delayMs(900);
      return;
    }
    throw new Error(`advanceOneCorrect: unsupported surface ${surface}`);
  } catch (err) {
    throw err as Error;
  }
}

async function tapCorrectChoice(driver: Driver): Promise<void> {
  const zh: string = await getPromptText(driver);
  const en: string = enForZh(zh);
  if (en.length > 0) {
    const tapped: boolean = await tapOptionWithText(driver, en);
    if (tapped) {
      return;
    }
  }
  await tapCorrectAnswerShared(driver);
}

/** Correctly answer the current battle question for any supported surface. */
export async function advanceBattleTurnCorrect(driver: Driver): Promise<void> {
  try {
    const surface: QuestionSurfaceKind = await detectQuestionSurface(driver);
    if (surface === 'choice') {
      await tapCorrectChoice(driver);
      await driver.delayMs(900);
      return;
    }
    if (surface === 'fill-letter') {
      await tapCurrentFillLetterStep(driver);
      await driver.delayMs(900);
      return;
    }
    if (surface === 'fill-letter-medium') {
      for (let step: number = 0; step < 2; step++) {
        const again: QuestionSurfaceKind = await detectQuestionSurface(driver);
        if (again !== 'fill-letter-medium') {
          break;
        }
        const slots: string[] = await readLetterSlots(driver);
        if (countUnderscores(slots) === 0) {
          break;
        }
        await tapCurrentFillLetterStep(driver);
        await driver.delayMs(800);
      }
      return;
    }
    if (surface === 'spell') {
      await completeSpellQuestion(driver);
      return;
    }
    throw new Error(`advanceBattleTurnCorrect: unsupported surface ${surface}`);
  } catch (err) {
    throw err as Error;
  }
}

export async function isBattlePageActive(driver: Driver): Promise<boolean> {
  try {
    const title: Component | null = await driver.findComponent(ON.id('BattleTitle'));
    return title !== null;
  } catch (err) {
    throw err as Error;
  }
}

/** Press back until HomeStartButton is visible (ohosTest suite hygiene). */
export async function returnToHome(driver: Driver, maxBackPresses: number = 8): Promise<void> {
  try {
    for (let i: number = 0; i < maxBackPresses; i++) {
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

/** Poll until BattlePage title is mounted (today-mode async load). */
export async function waitForBattlePage(driver: Driver, maxAttempts: number = 15): Promise<void> {
  try {
    for (let attempt: number = 0; attempt < maxAttempts; attempt++) {
      const title: Component | null = await driver.findComponent(ON.id('BattleTitle'));
      if (title !== null) {
        await driver.delayMs(200);
        return;
      }
      await driver.delayMs(400);
    }
    await driver.assertComponentExist(ON.id('BattleTitle'));
  } catch (err) {
    throw err as Error;
  }
}

/**
 * Home → today's adventure with Config forced to Choice-only (V0.8.4
 * schedule single_type). Callers that tap BattleOption* require this.
 */
export async function startTodayBattleChoiceOnly(driver: Driver): Promise<void> {
  try {
    await selectOnlyQuestionTypeShared(driver, 'choice');
    await clickByIdShared(driver, 'HomeStartButton');
    await waitForBattlePage(driver);
    await driver.assertComponentExist(ON.id('BattlePrompt'));
  } catch (err) {
    throw err as Error;
  }
}
