import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';

/**
 * UI suite for the FillLetter battle gameplay (single-letter and
 * two-letter variants). The pre-existing
 * V03Adventure/intermediateFillLetterAtomicFlow case taps options
 * in A/B/C rotation and only asserts the medium step-0 → step-1
 * transition; it has been a known flake since v0.3.5 because the
 * tap policy is blind to which option is correct and the question
 * may rotate before a correct guess lands.
 *
 * This suite drives the battle with a deterministic answer policy:
 *
 *   - Choice prompt (Normal / Review monsters): read the Chinese
 *     meaning from BattlePrompt, look up the English word in the
 *     known catalog, tap the option whose text matches.
 *   - FillLetter / FillLetterMedium prompt: read every
 *     LetterSlotText_* glyph, build a partial pattern with '_' for
 *     missing slots, identify the unique catalog word that fits,
 *     read off the missing letter(s), tap the option whose text
 *     matches.
 *
 * That keeps the suite reliable across plan re-shuffles (fruit-
 * forest plan order is RNG-driven) while still exercising the
 * production pipeline end-to-end (BattleEngine, PlanQuestionSource,
 * FillLetterGenerator, LetterTemplate row rendering, feedback text,
 * monster advancement).
 *
 * Both tests start on HomePage. Suite is registered in List.test.ets
 * so the LearningRecorder seeded by earlier suites doesn't matter —
 * we don't depend on specific words appearing in the plan, only on
 * the monster slot ordering (Normal → Spelling → Review → Elite →
 * Boss) which is region-defined and deterministic.
 */

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

// Known catalog words (mirrors entry/src/main/resources/rawfile/data/
// words_v1.json). Two parallel arrays are simpler than a class array
// to keep ArkTS literal-typing happy in test code; the only operation
// we need is zh → en lookup and pattern → en match.
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

/**
 * Find the unique catalog word that matches the rendered slot
 * pattern. `slots` carries the per-slot glyph as rendered by
 * BattlePage's LetterTemplateRow: lowercase letters for filled
 * slots and '_' for both isMissing and isPending slots (the
 * production pipeline lowercases word.word before splitting).
 *
 * Returns the catalog word in its original case (so 'TV' stays
 * 'TV') or '' when no unique match is found.
 */
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

/**
 * Tap whichever of the three option buttons currently shows the
 * given text. Returns true on a successful tap, false when no
 * match is found (which the caller treats as a fatal test error,
 * since the answer policy assumes the catalog covers every prompt
 * the plan can emit).
 */
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

/**
 * Bring up a fresh BattlePage on fruit-forest. Region click is
 * idempotent (already-selected chip is a no-op) and the start
 * button always launches today's adventure for the active region
 * after v0.3.6.
 */
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

export default function fillLetterFlowUiTest(): void {
  describe('FillLetterFlow', () => {
    /**
     * Reach the slot-2 Spelling monster (which always emits a
     * single-letter FillLetter), tap the correct letter, and
     * assert the green correct-answer feedback fires. This is the
     * happy-path coverage for the 1-letter variant the existing
     * V03 suite never asserts.
     */
    it('singleLetterFillAcceptsCorrectLetter', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await startFruitForestBattle(driver);

      let asserted: boolean = false;
      // Monster 1 (Normal) takes 3 correct answers; the very next
      // question on monster 2 (Spelling) is the FillLetter we want.
      // 12 turns leaves plenty of headroom for combos / re-prompts.
      for (let turn: number = 0; turn < 12 && !asserted; turn++) {
        const ltr: Component | null = await driver.findComponent(ON.id('LetterTemplateRow'));
        if (ltr !== null) {
          const slots: string[] = await readLetterSlots(driver);
          const blanks: number = countUnderscores(slots);
          if (blanks === 1) {
            const word: string = wordForPattern(slots);
            expect(word !== '').assertTrue();
            const missingIdx: number = slots.indexOf('_');
            const letter: string = word.toLowerCase().charAt(missingIdx);
            const tapped: boolean = await tapOptionWithText(driver, letter);
            expect(tapped).assertTrue();
            await driver.delayMs(250);
            const fb: string = await readFeedback(driver);
            // '正确！' (plain correct) or '连击 3！魔法爆发 ×N'
            // (combo burst) — both confirm the engine accepted the
            // tap as the right letter for the FillLetter step.
            expect(fb.indexOf('正确') >= 0 || fb.indexOf('魔法爆发') >= 0).assertTrue();
            asserted = true;
            await driver.delayMs(700);
            break;
          }
          // Two blanks → FillLetterMedium (slot 4/5). Not the
          // target for this case, but answer correctly so the
          // battle keeps progressing.
          const word: string = wordForPattern(slots);
          if (word === '') {
            break;
          }
          const missingIdx: number = slots.indexOf('_');
          const letter: string = word.toLowerCase().charAt(missingIdx);
          await tapOptionWithText(driver, letter);
          await driver.delayMs(900);
          continue;
        }
        const promptText: string = await getPromptText(driver);
        const en: string = enForZh(promptText);
        if (en === '') {
          break;
        }
        await tapOptionWithText(driver, en);
        await driver.delayMs(900);
      }

      expect(asserted).assertTrue();
      await exitToHome(driver);
      done();
    });

    /**
     * Reach the slot-4 Elite monster (FillLetterMedium with two
     * blanks) and complete both steps. Asserts the in-flight
     * '答对啦！下一空' transition after step 0 and the final
     * '正确！' / burst feedback after step 1, plus that the second
     * blank is filled in left-to-right after step 0 (only the
     * trailing blank should remain, mirroring
     * letterMissingIndex / pendingMissingIndex semantics).
     */
    it('mediumLetterFillCompletesBothSteps', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await startFruitForestBattle(driver);

      let stepAdvancedSeen: boolean = false;
      let stepOneCompleted: boolean = false;
      // Reaching the first Medium prompt requires defeating monsters
      // up to slot 4 (Elite). With combo bursts each monster takes
      // ~3 correct answers — slot 4's first Q is the target. The
      // 30-turn budget covers slow paint cycles and falls back to a
      // re-launch via "再来一局" once the boss is down without ever
      // having seen a Medium (rare but possible if every Elite/Boss
      // word ends up being too short to generate a Medium and falls
      // back to FillLetter).
      for (let turn: number = 0; turn < 30 && !stepOneCompleted; turn++) {
        // If the battle ended (ResultPage took over), restart it so
        // we keep searching for Medium until the budget is spent.
        const resultTitle: Component | null =
          await driver.findComponent(ON.id('ResultTitle'));
        if (resultTitle !== null) {
          const retry: Component | null =
            await driver.findComponent(ON.id('ResultRetryButton'));
          if (retry !== null) {
            await retry.click();
            await driver.delayMs(1500);
            continue;
          }
          break;
        }
        const ltr: Component | null = await driver.findComponent(ON.id('LetterTemplateRow'));
        if (ltr !== null) {
          const slots: string[] = await readLetterSlots(driver);
          const blanks: number = countUnderscores(slots);
          if (blanks === 2 && !stepAdvancedSeen) {
            // Initial state of FillLetterMedium. Tap step 0 (the
            // leftmost blank) with the correct letter.
            const word: string = wordForPattern(slots);
            expect(word !== '').assertTrue();
            const firstBlankIdx: number = slots.indexOf('_');
            const letter0: string = word.toLowerCase().charAt(firstBlankIdx);
            const tapped: boolean = await tapOptionWithText(driver, letter0);
            expect(tapped).assertTrue();
            await driver.delayMs(250);
            const fb: string = await readFeedback(driver);
            expect(fb).assertEqual('答对啦！下一空');
            stepAdvancedSeen = true;
            // Wait for the 650 ms feedback window to close so
            // BattlePage syncs to step-1 state (leftmost blank
            // filled, rightmost blank still '_').
            await driver.delayMs(800);

            const slots2: string[] = await readLetterSlots(driver);
            const blanks2: number = countUnderscores(slots2);
            expect(blanks2).assertEqual(1);
            // Step 0 is always the smaller of the two missing
            // indices (FillLetterGenerator enforces left-to-right
            // fill), so the previously-leftmost blank should now
            // hold the actual letter and the remaining blank
            // should sit further right.
            const remainingBlankIdx: number = slots2.indexOf('_');
            expect(remainingBlankIdx > firstBlankIdx).assertTrue();
            expect(slots2[firstBlankIdx]).assertEqual(letter0);

            const word2: string = wordForPattern(slots2);
            expect(word2 === word).assertTrue();
            const letter1: string = word.toLowerCase().charAt(remainingBlankIdx);
            const tapped1: boolean = await tapOptionWithText(driver, letter1);
            expect(tapped1).assertTrue();
            await driver.delayMs(250);
            const fb1: string = await readFeedback(driver);
            expect(fb1.indexOf('正确') >= 0 || fb1.indexOf('魔法爆发') >= 0).assertTrue();
            stepOneCompleted = true;
            await driver.delayMs(700);
            break;
          }
          if (blanks === 1 && !stepAdvancedSeen) {
            // Single-letter FillLetter on slot 2 (Spelling) before
            // we reached the Elite. Answer correctly to keep the
            // battle progressing toward slot 4.
            const word: string = wordForPattern(slots);
            if (word === '') {
              break;
            }
            const missingIdx: number = slots.indexOf('_');
            const letter: string = word.toLowerCase().charAt(missingIdx);
            await tapOptionWithText(driver, letter);
            await driver.delayMs(900);
            continue;
          }
          // Defensive: any other LetterTemplateRow shape just gets
          // a best-effort correct tap so the loop keeps moving.
          const word: string = wordForPattern(slots);
          if (word === '') {
            break;
          }
          const missingIdx: number = slots.indexOf('_');
          const letter: string = word.toLowerCase().charAt(missingIdx);
          await tapOptionWithText(driver, letter);
          await driver.delayMs(900);
          continue;
        }
        const promptText: string = await getPromptText(driver);
        const en: string = enForZh(promptText);
        if (en === '') {
          break;
        }
        await tapOptionWithText(driver, en);
        await driver.delayMs(900);
      }

      expect(stepAdvancedSeen).assertTrue();
      expect(stepOneCompleted).assertTrue();
      await exitToHome(driver);
      done();
    });
  });
}
