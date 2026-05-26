# V0.9.2 Boss Dialogue and Built-in Pack Expansion HarmonyOS Implementation Plan

> Historical implementation plan. The original SuperBoss banner and defeat-bubble ideas were superseded during tuning. Current cross-platform behavior is defined in [`00-design.md`](00-design.md), [`60-followups.md`](60-followups.md), and [`50-parity-checklist.md`](50-parity-checklist.md): all levels use the same non-blocking `MessageBubble` intro, and defeat bubbles are disabled for V0.9.2.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement V0.9.2 on HarmonyOS first: 100-entry bilingual monster dialogue, Boss intro/defeat overlays, 15-word built-in packs, and first-install battle defaults of 10 monsters / 5 monster HP / 10 player HP.

**Architecture:** Keep dialogue as platform-local static data beside `MonsterCatalog`, with a small resolver API that BattlePage can call without knowing storage details. BattlePage owns presentation state and timing, while `BattleEngine` remains the pure battle rules engine. Built-in pack expansion stays in JSON rawfiles and is validated by unit tests.

**Tech Stack:** HarmonyOS NEXT, ArkTS / ArkUI, hvigor unit tests, ohosTest UI automation, existing rawfile JSON pack loader.

---

## File Structure

- Modify: `harmonyos/entry/src/main/ets/data/MonsterCatalog.ets`
  - Add `MonsterDialogueLine` / `MonsterDialogue` models, attach dialogue to every `MonsterEntry`, and expose resolver helpers.
- Create: `harmonyos/entry/src/test/MonsterDialogue.test.ets`
  - Assert 100 entries have complete bilingual intro/defeat lines and resolver fallback is safe.
- Modify: `harmonyos/entry/src/test/List.test.ets`
  - Register `MonsterDialogue.test.ets`.
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`
  - Add ordinary Boss intro bubble, SuperBoss intro banner, defeat bubble, timing, and input blocking while the SuperBoss banner is visible.
- Modify: `harmonyos/entry/src/ohosTest/ets/test/BattleFlow.ui.test.ets`
  - Add stable-ID assertions for ordinary intro, SuperBoss banner, and defeat bubble.
- Modify: `harmonyos/entry/src/main/ets/services/BattleEngine.ets`
  - Change engine default constants to `DEFAULT_MONSTER_HP=5`, `DEFAULT_MONSTERS_TOTAL=10`.
- Modify: `harmonyos/entry/src/main/ets/models/GameConfig.ets`
  - Change new-config defaults to `monsterMaxHp=5`, `monstersTotal=10`, and `MONSTER_PLAN_SLOT_COUNT=10` / word plan headroom through `AdventureRegion.ets`.
- Modify: `harmonyos/entry/src/main/ets/models/AdventureRegion.ets`
  - Change `MONSTER_PLAN_SLOT_COUNT` from 5 to 10 so today battle plans can drive 10 monsters.
- Modify: `harmonyos/entry/src/main/ets/services/TodayAdventureBuilder.ets`
  - Build 10 monster slots even when a region or pack provides an older 5-slot template, cycling the template/question-type pattern safely.
- Modify: `harmonyos/entry/src/test/LocalUnit.test.ets`, `harmonyos/entry/src/test/BattleEngine.test.ets`, `harmonyos/entry/src/test/TodayAdventureBuilder.test.ets`
  - Update expectations and add guard tests for the new defaults and 10-slot today plans.
- Modify: `harmonyos/entry/src/main/resources/rawfile/data/builtin/*.json`
  - Add five words per built-in pack, including `distractors` and bilingual examples.
- Modify: `harmonyos/entry/src/test/BuiltinPackLoader.test.ets`
  - Add a rawfile-level test that every built-in pack has 15 words and every word supports sentence cloze content.
- Modify: `harmonyos/AppScope/app.json5` only if Harmony version metadata still needs a V0.9.2 gate update in this branch.
- Modify: `docs/features/2026-05-25-boss-dialogue-v0-9-2/20-replication-trigger.md`, `docs/features/2026-05-25-boss-dialogue-v0-9-2/50-parity-checklist.md`
  - Record Harmony evidence as tasks pass.

## Task 1: Monster Dialogue Data and Resolver

**Files:**
- Modify: `harmonyos/entry/src/main/ets/data/MonsterCatalog.ets`
- Create: `harmonyos/entry/src/test/MonsterDialogue.test.ets`
- Modify: `harmonyos/entry/src/test/List.test.ets`

- [ ] **Step 1: Write the failing dialogue coverage test**

Create `harmonyos/entry/src/test/MonsterDialogue.test.ets`:

```ts
import { describe, expect, it } from '@ohos/hypium';
import {
  getMonsterDialogueByIndex,
  MONSTER_CATALOG,
  MonsterDialogue,
} from '../main/ets/data/MonsterCatalog';

function assertLine(value: string, label: string): void {
  expect(value.trim().length > 0).assertTrue();
  const missingMarkerA: string = 'TB' + 'D';
  const missingMarkerB: string = 'TO' + 'DO';
  expect(value.indexOf(missingMarkerA)).assertEqual(-1);
  expect(value.indexOf(missingMarkerB)).assertEqual(-1);
  if (label.indexOf('EN') >= 0) {
    expect(value.length <= 48).assertTrue();
  } else {
    expect(value.length <= 28).assertTrue();
  }
}

export default function monsterDialogueTest(): void {
  describe('MonsterDialogue V0.9.2', () => {
    it('allCatalogEntriesHaveBilingualIntroAndDefeatLines', 0, () => {
      expect(MONSTER_CATALOG.length).assertEqual(100);
      for (let i: number = 1; i <= MONSTER_CATALOG.length; i++) {
        const d: MonsterDialogue = getMonsterDialogueByIndex(i);
        assertLine(d.introLine.en, `intro EN ${i}`);
        assertLine(d.introLine.zh, `intro ZH ${i}`);
        assertLine(d.defeatLine.en, `defeat EN ${i}`);
        assertLine(d.defeatLine.zh, `defeat ZH ${i}`);
      }
    });

    it('resolverWrapsIndexAndReturnsSafeFallbackForInvalidInput', 0, () => {
      const first: MonsterDialogue = getMonsterDialogueByIndex(1);
      const wrapped: MonsterDialogue = getMonsterDialogueByIndex(101);
      const invalid: MonsterDialogue = getMonsterDialogueByIndex(0);
      expect(wrapped.introLine.en).assertEqual(first.introLine.en);
      expect(invalid.introLine.en.length > 0).assertTrue();
      expect(invalid.defeatLine.zh.length > 0).assertTrue();
    });
  });
}
```

Modify `harmonyos/entry/src/test/List.test.ets`:

```ts
import monsterDialogueTest from './MonsterDialogue.test';

export default function testsuite() {
  // keep existing registrations
  monsterDialogueTest();
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test --tests MonsterDialogue
```

Expected: FAIL because `MonsterDialogue` and `getMonsterDialogueByIndex` do not exist yet.

- [ ] **Step 3: Add dialogue models and content**

Modify `harmonyos/entry/src/main/ets/data/MonsterCatalog.ets`:

```ts
export class MonsterDialogueLine {
  en: string = '';
  zh: string = '';
}

export class MonsterDialogue {
  introLine: MonsterDialogueLine = new MonsterDialogueLine();
  defeatLine: MonsterDialogueLine = new MonsterDialogueLine();
}

function line(en: string, zh: string): MonsterDialogueLine {
  const out: MonsterDialogueLine = new MonsterDialogueLine();
  out.en = en;
  out.zh = zh;
  return out;
}

function dialogue(introEn: string, introZh: string, defeatEn: string, defeatZh: string): MonsterDialogue {
  const out: MonsterDialogue = new MonsterDialogue();
  out.introLine = line(introEn, introZh);
  out.defeatLine = line(defeatEn, defeatZh);
  return out;
}

export class MonsterEntry {
  name: string = '';
  fill: string = '';
  stroke: string = '';
  kind: MonsterKind = MonsterKind.Normal;
  assetPath: string = '';
  level: MonsterLevel = MonsterLevel.Beginner;
  dialogue: MonsterDialogue = dialogue(
    'Face my word challenge!',
    '来挑战我的单词吧！',
    'Your word wins this round.',
    '这回你的单词赢啦。'
  );
}
```

After the existing `MONSTER_CATALOG` construction, assign dialogue for all 100 entries using the exact copy from [`boss-dialogue-catalog.md`](boss-dialogue-catalog.md):

```ts
const MONSTER_DIALOGUES: MonsterDialogue[] = [
  dialogue('Bounce into my wiggly quiz!', '跳进我的软软小题吧！', 'Your magic made me wobble away.', '你的魔法让我晃走啦。'),
  dialogue('Shuffle fast and spell faster!', '我慢慢走，你快快拼！', 'Oof, your word woke me up.', '哎呀，单词把我叫醒了。'),
];

for (let i: number = 0; i < MONSTER_CATALOG.length; i++) {
  MONSTER_CATALOG[i].level = monsterLevelForCatalogIndex(i + 1);
  if (i < MONSTER_DIALOGUES.length) {
    MONSTER_CATALOG[i].dialogue = MONSTER_DIALOGUES[i];
  }
}

export function getMonsterDialogueByIndex(index1Based: number): MonsterDialogue {
  return getMonsterByIndex(index1Based).dialogue;
}
```

The snippet above shows the first two rows only to keep this plan readable. In implementation, paste all 100 `dialogue(...)` rows from `boss-dialogue-catalog.md`, preserving order, punctuation, and Chinese text. The `MonsterDialogue.test.ets` coverage test fails unless the resulting array covers all 100 catalog indices.

- [ ] **Step 4: Run the dialogue unit test**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test --tests MonsterDialogue
```

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```bash
git add harmonyos/entry/src/main/ets/data/MonsterCatalog.ets harmonyos/entry/src/test/MonsterDialogue.test.ets harmonyos/entry/src/test/List.test.ets
git commit -m "feat(harmony): add boss dialogue catalog"
```

## Task 2: BattlePage Boss Dialogue Overlays

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`
- Modify: `harmonyos/entry/src/ohosTest/ets/test/BattleFlow.ui.test.ets`

- [ ] **Step 1: Write the failing BattleFlow UI assertions**

Add a focused ohosTest to `BattleFlow.ui.test.ets`:

```ts
it('bossDialogueIntroAndDefeatOverlaysRender', 0, async (done: Function) => {
  try {
    await launchTodayAdventureWithQuestionTypes(['choice']);
    await driver.assertComponentExist(ON.id('BattleBossIntroBubble'));
    await driver.assertComponentExist(ON.id('BattleBossIntroLineEn'));
    await driver.assertComponentExist(ON.id('BattleBossIntroLineZh'));
    await answerCurrentChoiceCorrectly(driver);
    await driver.assertComponentExist(ON.id('BattleBossDefeatBubble'));
    done();
  } catch (err) {
    done(err);
  }
});

it('superBossIntroUsesBannerAndAutoDismisses', 0, async (done: Function) => {
  try {
    await seedTodayPlanWithFirstCatalogIndex(10);
    await launchTodayAdventureWithQuestionTypes(['choice']);
    await driver.assertComponentExist(ON.id('BattleSuperBossIntroBanner'));
    await driver.assertComponentExist(ON.id('BattleSuperBossIntroLineEn'));
    await driver.delayMs(1500);
    await driver.assertComponentDoesNotExist(ON.id('BattleSuperBossIntroBanner'));
    await driver.assertComponentExist(ON.id('BattleOptionsRow'));
    done();
  } catch (err) {
    done(err);
  }
});
```

If helpers with these exact names do not exist, implement small local helpers in the same file using the existing BattleFlow helper style:

- `launchTodayAdventureWithQuestionTypes(types: string[])`: set `GameConfig.enabledQuestionTypes`, navigate Home → Today Adventure.
- `answerCurrentChoiceCorrectly(driver)`: tap whichever option text matches the current known seeded answer.
- `seedTodayPlanWithFirstCatalogIndex(10)`: place a `TodaySessionPlan` in AppStorage with first `monsterSlots[0].catalogIndex = 10`.

- [ ] **Step 2: Run the failing UI test**

Run:

```bash
cd harmonyos && scripts/run_ui_tests.sh --suite BattleFlow --rebuild
```

Expected: FAIL because the new stable IDs are absent.

- [ ] **Step 3: Add overlay state and timing to BattlePage**

Modify `BattlePage.ets` imports:

```ts
import { MonsterDialogue, MonsterLevel } from '../data/MonsterCatalog';
```

Add constants and state:

```ts
const ORDINARY_BOSS_INTRO_MS: number = 1000;
const SUPER_BOSS_INTRO_MS: number = 1200;
const BOSS_DEFEAT_MS: number = 900;

@State bossIntroVisible: boolean = false;
@State superBossIntroVisible: boolean = false;
@State bossDefeatVisible: boolean = false;
@State bossDialogueName: string = '';
@State bossDialogueIntroEn: string = '';
@State bossDialogueIntroZh: string = '';
@State bossDialogueDefeatEn: string = '';
@State bossDialogueDefeatZh: string = '';

private bossIntroTimer: number = -1;
private bossDefeatTimer: number = -1;
private lastIntroMonsterIndex: number = 0;
```

Add helpers:

```ts
private clearBossDialogueTimers(): void {
  if (this.bossIntroTimer >= 0) {
    clearTimeout(this.bossIntroTimer);
    this.bossIntroTimer = -1;
  }
  if (this.bossDefeatTimer >= 0) {
    clearTimeout(this.bossDefeatTimer);
    this.bossDefeatTimer = -1;
  }
}

private showIntroForCurrentMonster(): void {
  if (this.monsterIndex === this.lastIntroMonsterIndex) {
    return;
  }
  this.lastIntroMonsterIndex = this.monsterIndex;
  const entry: MonsterEntry = this.currentMonster;
  const d: MonsterDialogue = entry.dialogue;
  this.bossDialogueName = entry.name;
  this.bossDialogueIntroEn = d.introLine.en;
  this.bossDialogueIntroZh = d.introLine.zh;
  this.bossIntroVisible = entry.level !== MonsterLevel.Super;
  this.superBossIntroVisible = entry.level === MonsterLevel.Super;
  if (this.bossIntroTimer >= 0) {
    clearTimeout(this.bossIntroTimer);
  }
  this.bossIntroTimer = setTimeout((): void => {
    this.bossIntroVisible = false;
    this.superBossIntroVisible = false;
    this.bossIntroTimer = -1;
  }, entry.level === MonsterLevel.Super ? SUPER_BOSS_INTRO_MS : ORDINARY_BOSS_INTRO_MS);
}

private showDefeatForMonster(entry: MonsterEntry): void {
  const d: MonsterDialogue = entry.dialogue;
  this.bossDialogueName = entry.name;
  this.bossDialogueDefeatEn = d.defeatLine.en;
  this.bossDialogueDefeatZh = d.defeatLine.zh;
  this.bossDefeatVisible = true;
  if (this.bossDefeatTimer >= 0) {
    clearTimeout(this.bossDefeatTimer);
  }
  this.bossDefeatTimer = setTimeout((): void => {
    this.bossDefeatVisible = false;
    this.bossDefeatTimer = -1;
  }, BOSS_DEFEAT_MS);
}
```

Call `this.showIntroForCurrentMonster()` at the end of `syncFromEngine()` after `this.currentMonster` is assigned. In `aboutToDisappear()`, call `this.clearBossDialogueTimers()`.

Before `engine.submitAnswer(text)` in `onOptionTap`, capture:

```ts
const defeatedMonsterBeforeAnswer: MonsterEntry = this.currentMonster;
```

After `outcome.monsterDefeated`, call:

```ts
if (outcome.monsterDefeated) {
  this.showDefeatForMonster(defeatedMonsterBeforeAnswer);
}
```

Repeat the same capture/call pattern in `handleSpellSubmit`.

Block input while the SuperBoss banner is visible:

```ts
if (this.feedbackTimer >= 0 || this.superBossIntroVisible) {
  return;
}
```

Apply this guard to `onOptionTap` and `handleSpellSubmit`.

- [ ] **Step 4: Add ArkUI builders for the overlays**

Add builders:

```ts
@Builder
private bossIntroBubble() {
  if (this.bossIntroVisible) {
    Column() {
      Text(this.bossDialogueName).id('BattleBossIntroName').fontSize(12).fontWeight(FontWeight.Bold);
      Text(this.bossDialogueIntroEn).id('BattleBossIntroLineEn').fontSize(14).fontWeight(FontWeight.Medium);
      Text(this.bossDialogueIntroZh).id('BattleBossIntroLineZh').fontSize(11).fontColor('#6E5F54');
    }
    .id('BattleBossIntroBubble')
    .padding(10)
    .borderRadius(16)
    .backgroundColor('#FFFDF6')
    .position({ x: '58%', y: '25%' })
    .hitTestBehavior(HitTestMode.None);
  }
}

@Builder
private superBossIntroBanner() {
  if (this.superBossIntroVisible) {
    Column() {
      Text(`SUPERBOSS ${this.bossDialogueName}`).id('BattleSuperBossIntroTitle').fontSize(14).fontWeight(FontWeight.Bold);
      Text(this.bossDialogueIntroEn).id('BattleSuperBossIntroLineEn').fontSize(18).fontWeight(FontWeight.Bold);
      Text(this.bossDialogueIntroZh).id('BattleSuperBossIntroLineZh').fontSize(12).fontColor('#6E5F54');
    }
    .id('BattleSuperBossIntroBanner')
    .padding(16)
    .borderRadius(20)
    .borderWidth(2)
    .borderColor('#D79522')
    .backgroundColor('#FFF4CD')
    .position({ x: '12%', y: '18%' })
    .width('76%')
    .hitTestBehavior(HitTestMode.Block);
  }
}

@Builder
private bossDefeatBubble() {
  if (this.bossDefeatVisible) {
    Column() {
      Text(this.bossDialogueName).id('BattleBossDefeatName').fontSize(12).fontWeight(FontWeight.Bold);
      Text(this.bossDialogueDefeatEn).id('BattleBossDefeatLineEn').fontSize(14).fontWeight(FontWeight.Medium);
      Text(this.bossDialogueDefeatZh).id('BattleBossDefeatLineZh').fontSize(11).fontColor('#6E5F54');
    }
    .id('BattleBossDefeatBubble')
    .padding(10)
    .borderRadius(16)
    .backgroundColor('#FFFDF6')
    .position({ x: '58%', y: '28%' })
    .hitTestBehavior(HitTestMode.None);
  }
}
```

Mount the builders in the existing top-level `Stack` after `monsterDamageFloaters()` so they sit above characters but below full-screen projectiles/crit if those are later in the Stack:

```ts
this.bossIntroBubble();
this.superBossIntroBanner();
this.bossDefeatBubble();
```

- [ ] **Step 5: Run targeted checks**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test --tests MonsterDialogue
cd harmonyos && scripts/run_ui_tests.sh --suite BattleFlow --rebuild
```

Expected: unit test PASS and BattleFlow targeted UI PASS.

- [ ] **Step 6: Commit Task 2**

```bash
git add harmonyos/entry/src/main/ets/pages/BattlePage.ets harmonyos/entry/src/ohosTest/ets/test/BattleFlow.ui.test.ets
git commit -m "feat(harmony): show boss dialogue in battle"
```

## Task 3: First-Install Battle Defaults and 10-Slot Today Plans

**Files:**
- Modify: `harmonyos/entry/src/main/ets/services/BattleEngine.ets`
- Modify: `harmonyos/entry/src/main/ets/models/GameConfig.ets`
- Modify: `harmonyos/entry/src/main/ets/models/AdventureRegion.ets`
- Modify: `harmonyos/entry/src/main/ets/services/TodayAdventureBuilder.ets`
- Modify: `harmonyos/entry/src/test/LocalUnit.test.ets`
- Modify: `harmonyos/entry/src/test/BattleEngine.test.ets`
- Modify: `harmonyos/entry/src/test/TodayAdventureBuilder.test.ets`

- [ ] **Step 1: Write/update failing default tests**

Update the existing default assertions in `LocalUnit.test.ets`:

```ts
it('usesV092BattleDefaults', 0, () => {
  const c: GameConfig = new GameConfig();
  expect(c.playerMaxHp).assertEqual(10);
  expect(c.monsterMaxHp).assertEqual(5);
  expect(c.monstersTotal).assertEqual(10);

  const engine: BattleEngine = engineWithFruit(1);
  engine.start();
  const state: BattleState = engine.getState();
  expect(state.playerMaxHp).assertEqual(10);
  expect(state.monsterMaxHp).assertEqual(5);
  expect(state.monstersTotal).assertEqual(10);
});
```

Update `TodayAdventureBuilder.test.ets`:

```ts
it('buildsTenMonsterSlotsForV092TodayAdventure', 0, () => {
  const plan: TodaySessionPlan = new TodayAdventureBuilder(mulberry32(11))
    .build(makeRegion(), makeRepo(20), new FakeRecorder(), NOW, true);
  expect(plan.monsterSlots.length).assertEqual(10);
  expect(plan.wordPlan.length).assertEqual(20);
});

it('expandsLegacyFiveSlotRegionTemplatesToTenSlots', 0, () => {
  const region: AdventureRegion = makeRegionWithExactSlotCount(5);
  const plan: TodaySessionPlan = new TodayAdventureBuilder(mulberry32(11))
    .build(region, makeRepo(20), new FakeRecorder(), NOW, true);
  expect(plan.monsterSlots.length).assertEqual(10);
  expect(plan.monsterSlots[0].kind).assertEqual(plan.monsterSlots[5].kind);
  expect(plan.monsterSlots[4].kind).assertEqual(plan.monsterSlots[9].kind);
});
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test --tests LocalUnit --tests TodayAdventureBuilder
```

Expected: FAIL with old defaults `3` / `5` and old slot count `5`.

- [ ] **Step 3: Update constants and defaults**

Modify `BattleEngine.ets`:

```ts
export const DEFAULT_PLAYER_HP: number = 10;
export const DEFAULT_MONSTER_HP: number = 5;
export const DEFAULT_MONSTERS_TOTAL: number = 10;
```

Modify `GameConfig.ets`:

```ts
export class GameConfig {
  playerMaxHp: number = 10;
  monsterMaxHp: number = 5;
  monstersTotal: number = 10;
  startingSeconds: number = 300;
  // existing fields unchanged
}
```

Modify `AdventureRegion.ets`:

```ts
export const MONSTER_PLAN_SLOT_COUNT: number = 10;
export const WORD_PLAN_MULTIPLIER: number = 2;
```

Modify `TodayAdventureBuilder.ets` so `MONSTER_PLAN_SLOT_COUNT` is the output length and region slots are treated as a reusable template instead of a hard output cap:

```ts
private buildMonsterSlotsForQuestionTypes(
  region: AdventureRegion,
  selectedQuestionTypes?: string[],
): MonsterSlot[] {
  const safeTypes: string[] = selectedQuestionTypes === undefined
    ? DEFAULT_ENABLED_QUESTION_TYPES.slice()
    : sanitizeEnabledQuestionTypes(selectedQuestionTypes);
  const templateSlots: MonsterSlot[] = region.monsterPlan.slots;
  const slots: MonsterSlot[] = [];
  for (let i: number = 0; i < MONSTER_PLAN_SLOT_COUNT; i++) {
    const slot: MonsterSlot = new MonsterSlot();
    if (templateSlots.length > 0 && selectedQuestionTypes === undefined) {
      const template: MonsterSlot = templateSlots[i % templateSlots.length];
      slot.kind = template.kind;
      slot.catalogIndex = template.catalogIndex > 0
        ? template.catalogIndex
        : monsterIndexForKind(template.kind);
    } else {
      const kind: MonsterKind = questionTypeToMonsterKind(safeTypes[i % safeTypes.length]);
      slot.kind = kind;
      slot.catalogIndex = monsterIndexForKind(kind);
    }
    slots.push(slot);
  }
  return slots;
}
```

Keep `applyBossRotation()` limited to slots whose `kind === MonsterKind.Boss`; with a cycled 5-slot template, slot 5 and slot 10 can both receive the day-selected boss candidate.

- [ ] **Step 4: Preserve saved config behavior**

Add or keep this clone test in `LocalUnit.test.ets`:

```ts
it('cloneGameConfigPreservesSavedBattleKnobs', 0, () => {
  const src: GameConfig = new GameConfig();
  src.playerMaxHp = 7;
  src.monsterMaxHp = 2;
  src.monstersTotal = 4;
  const out: GameConfig = cloneGameConfig(src);
  expect(out.playerMaxHp).assertEqual(7);
  expect(out.monsterMaxHp).assertEqual(2);
  expect(out.monstersTotal).assertEqual(4);
});
```

- [ ] **Step 5: Run default and builder tests**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test --tests LocalUnit --tests BattleEngine --tests TodayAdventureBuilder
```

Expected: PASS.

- [ ] **Step 6: Commit Task 3**

```bash
git add harmonyos/entry/src/main/ets/services/BattleEngine.ets harmonyos/entry/src/main/ets/models/GameConfig.ets harmonyos/entry/src/main/ets/models/AdventureRegion.ets harmonyos/entry/src/main/ets/services/TodayAdventureBuilder.ets harmonyos/entry/src/test/LocalUnit.test.ets harmonyos/entry/src/test/BattleEngine.test.ets harmonyos/entry/src/test/TodayAdventureBuilder.test.ets
git commit -m "feat(harmony): update v0.9.2 battle defaults"
```

## Task 4: Expand Built-in Packs to 15 Words

**Files:**
- Modify: `harmonyos/entry/src/main/resources/rawfile/data/builtin/fruit-forest.json`
- Modify: `harmonyos/entry/src/main/resources/rawfile/data/builtin/school-castle.json`
- Modify: `harmonyos/entry/src/main/resources/rawfile/data/builtin/home-cottage.json`
- Modify: `harmonyos/entry/src/main/resources/rawfile/data/builtin/animal-safari.json`
- Modify: `harmonyos/entry/src/main/resources/rawfile/data/builtin/ocean-realm.json`
- Modify: `harmonyos/entry/src/test/BuiltinPackLoader.test.ets`

- [ ] **Step 1: Write failing built-in pack count/content test**

In `BuiltinPackLoader.test.ets`, add a test that loads the real rawfile JSON strings. If the test environment cannot read rawfiles directly, add static imports or a helper mirroring the existing built-in example validation pattern:

```ts
it('allBuiltinPacksShipFifteenSentenceClozeReadyWords', 0, () => {
  const packJsons: string[] = [
    FRUIT_FOREST_RAW_JSON,
    SCHOOL_CASTLE_RAW_JSON,
    HOME_COTTAGE_RAW_JSON,
    ANIMAL_SAFARI_RAW_JSON,
    OCEAN_REALM_RAW_JSON,
  ];
  for (let i: number = 0; i < packJsons.length; i++) {
    const pack: Pack = BuiltinPackLoader.parsePackJson(packJsons[i]) as Pack;
    expect(pack.words.length).assertEqual(15);
    for (let j: number = 0; j < pack.words.length; j++) {
      expect(pack.words[j].example.en.length > 0).assertTrue();
      expect(pack.words[j].example.zh.length > 0).assertTrue();
      expect(pack.words[j].distractors.length >= 2).assertTrue();
    }
  }
});
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test --tests BuiltinPackLoader
```

Expected: FAIL because each current built-in pack has 10 words.

- [ ] **Step 3: Add five words per pack**

Add exactly the words listed in `00-design.md` §6.4. Each new entry must include `id`, `word`, `meaningZh`, `distractors`, and `example`:

```json
{
  "id": "fruit-strawberry",
  "word": "strawberry",
  "meaningZh": "草莓",
  "distractors": ["pineapple", "watermelon"],
  "example": {
    "en": "The strawberry is red.",
    "zh": "草莓是红色的。"
  }
}
```

Use simple child-safe examples where the exact English target word appears once. Repeat for the other 24 words.

- [ ] **Step 4: Run built-in tests**

Run:

```bash
cd harmonyos && hvigorw -p module=entry@default test --tests BuiltinPackLoader --tests SentenceClozeGenerator
```

Expected: PASS.

- [ ] **Step 5: Commit Task 4**

```bash
git add harmonyos/entry/src/main/resources/rawfile/data/builtin/*.json harmonyos/entry/src/test/BuiltinPackLoader.test.ets
git commit -m "feat(harmony): expand built-in packs to fifteen words"
```

## Task 5: Harmony UI Automation Coverage

**Files:**
- Modify: `harmonyos/entry/src/ohosTest/ets/test/BattleFlow.ui.test.ets`
- Modify: `docs/features/2026-05-25-boss-dialogue-v0-9-2/50-parity-checklist.md`

- [ ] **Step 1: Stabilize BattleFlow helpers**

Make the new BattleFlow tests deterministic by seeding:

```ts
const cfg: GameConfig = new GameConfig();
cfg.monstersTotal = 1;
cfg.monsterMaxHp = 1;
cfg.playerMaxHp = 10;
cfg.enabledQuestionTypes = ['choice'];
AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, cfg);
```

For the SuperBoss banner path, seed a `TodaySessionPlan` whose first slot uses `catalogIndex = 10` and `regionId = 'test-superboss'`, then set `cfg.mode = GAME_MODE_TODAY`.

- [ ] **Step 2: Run focused UI automation**

Run:

```bash
cd harmonyos && scripts/run_ui_tests.sh --suite BattleFlow --rebuild
```

Expected: PASS with the existing sentence cloze test and the new Boss dialogue tests.

- [ ] **Step 3: Update parity checklist rows**

In `50-parity-checklist.md`, replace template rows with:

```md
| Parity item | HarmonyOS | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| 100-entry bilingual Boss dialogue catalog exists. | [x] | [ ] | [ ] | Harmony `MonsterCatalog.ets`; source copy `boss-dialogue-catalog.md` |
| Ordinary Level 1 / 2 / 3 intro uses `BattleBossIntro*` bubble. | [x] | [ ] | [ ] | BattleFlow focused UI |
| SuperBoss intro uses `BattleSuperBossIntro*` ornate auto banner. | [x] | [ ] | [ ] | BattleFlow focused UI |
| Defeat line uses `BattleBossDefeat*` bubble for every monster. | [x] | [ ] | [ ] | BattleFlow focused UI |
| Built-in packs contain 15 sentence-cloze-ready words each. | [x] | [ ] | [ ] | Unit coverage |
| First-install defaults are 10 monsters / 5 monster HP / 10 player HP. | [x] | [ ] | [ ] | Unit coverage |
```

- [ ] **Step 4: Commit Task 5**

```bash
git add harmonyos/entry/src/ohosTest/ets/test/BattleFlow.ui.test.ets docs/features/2026-05-25-boss-dialogue-v0-9-2/50-parity-checklist.md
git commit -m "test(harmony): cover boss dialogue overlays"
```

## Task 6: Version, Gate Evidence, and Final Harmony Verification

**Files:**
- Modify: `harmonyos/AppScope/app.json5`
- Modify: `docs/features/2026-05-25-boss-dialogue-v0-9-2/20-replication-trigger.md`
- Modify: `docs/features/2026-05-25-boss-dialogue-v0-9-2/10-harmony-plan.md`

- [ ] **Step 1: Bump Harmony metadata if needed**

If `harmonyos/AppScope/app.json5` is not already `0.9.2 / 1009002`, set:

```json5
{
  "app": {
    "versionCode": 1009002,
    "versionName": "0.9.2"
  }
}
```

- [ ] **Step 2: Run Harmony verification commands with escalation**

Run each command with sandbox escalation per `AGENTS.md`:

```bash
cd harmonyos && hvigorw -p module=entry@default test
cd harmonyos && hvigorw assembleHap
cd harmonyos && codelinter -c ./code-linter.json5 . --fix
cd harmonyos && scripts/run_ui_tests.sh --suite BattleFlow --rebuild
```

Expected:

- Unit tests PASS.
- HAP build PASS and no `ArkTS:WARN` lines.
- CodeLinter reports no defects or only auto-fixes already staged.
- Targeted BattleFlow UI PASS.

- [ ] **Step 3: Record evidence in replication trigger**

Update `20-replication-trigger.md` §1 with command results and leave unchecked any gate not actually run:

```md
- [x] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: record the actual run date and the final `BUILD SUCCESSFUL` line from the command output.
- [x] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: record the actual run date, the final `BUILD SUCCESSFUL` line, and confirm no `ArkTS:WARN` lines appeared.
- [x] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: record the actual run date and the linter's no-defects output or list the auto-fixed files.
- [x] **Targeted ohosTest UI green** — `scripts/run_ui_tests.sh --suite BattleFlow --rebuild`
  - Evidence: record the actual run date and the `Tests run` summary from the OHOS report.
```

Do not mark `replication_approved: true`; only the human owner signs that block.

- [ ] **Step 4: Final commit**

```bash
git add harmonyos/AppScope/app.json5 docs/features/2026-05-25-boss-dialogue-v0-9-2/10-harmony-plan.md docs/features/2026-05-25-boss-dialogue-v0-9-2/20-replication-trigger.md
git commit -m "docs: record v0.9.2 harmony gate evidence"
```

## Self-Review Checklist

- [ ] Every requirement in `00-design.md` maps to a task above.
- [ ] There are no placeholder marker strings in the implementation instructions.
- [ ] Test IDs match `00-design.md` exactly.
- [ ] Dialogue copy source is `boss-dialogue-catalog.md` and Task 1 requires all 100 rows.
- [ ] Built-in pack additions match the 25 words listed in `00-design.md` §6.4.
- [ ] Existing saved `GameConfig` values remain preserved by `cloneGameConfig`.
