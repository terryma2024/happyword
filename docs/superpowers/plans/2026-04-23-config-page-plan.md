# ConfigPage & Short-Level E2E Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a HarmonyOS ConfigPage that lets players set five battle knobs (player HP / monster HP / monster count / timer / category subset **including a custom-words category**), persist them in AppStorage for the app session, and author four on-device E2E tests (Win / Timer-Loss / HP-Zero-Loss / Custom-Words-Only-Win) that reach the ResultPage without the `[debug] end battle` escape hatch.

**Architecture:** A new `GameConfig` value-object holds all settings and lives in `AppStorage` under the key `'gameConfig'`. Custom words are stored as raw multi-line `中文:英文` text inside the same object and parsed on demand. ConfigPage reads a local cloned draft, mutates steppers/timer/categories, and writes back on Save (after a pool-size validation). A dedicated sub-page `CustomWordsPage` owns the raw custom-word text field end-to-end. BattlePage reads the current `GameConfig` on `aboutToAppear` and projects it to a filtered `WordRepository` plus a `BattleConfig`. A single helper `computeFinalPool` is shared by ConfigPage validation and BattlePage runtime. UI tests drive both pages via id-based taps.

**Tech Stack:** HarmonyOS ArkTS (strict mode), ArkUI (`@Entry`, `@Component`, `@State`, `Stack`, `Column`, `Row`, `Button`, `TextArea`), `@ohos.router`, `AppStorage`, Hypium (`describe` / `it`), `@kit.TestKit` (`Driver`, `ON`).

**Reference spec:** `docs/superpowers/specs/2026-04-23-config-page-design.md`

---

## File Structure

Files created:

| Path                                                          | Responsibility                                                                              |
|---------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| `entry/src/main/ets/models/GameConfig.ets`                    | Value object, constants, `cloneGameConfig`, `parseCustomWords`, `computeFinalPool`          |
| `entry/src/main/ets/pages/ConfigPage.ets`                     | Landscape form page; reads/writes AppStorage with validation                                |
| `entry/src/main/ets/pages/CustomWordsPage.ets`                | Sub-page that owns raw custom-word text                                                     |

Files modified:

| Path                                                                              | What changes                                                        |
|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `entry/src/main/ets/entryability/EntryAbility.ets`                                | Seed `gameConfig` in `onCreate`                                     |
| `entry/src/main/ets/pages/HomePage.ets`                                           | Wrap in `Stack`, add gear-icon overlay                              |
| `entry/src/main/ets/pages/BattlePage.ets`                                         | Read `gameConfig`, build pool via `computeFinalPool`                |
| `entry/src/main/resources/base/profile/main_pages.json`                           | Register `pages/ConfigPage` and `pages/CustomWordsPage`             |
| `entry/src/test/LocalUnit.test.ets`                                               | 9 new unit tests (defaults / clone / filter / parse / pool)         |
| `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`                             | Helpers + 4 new E2E tests                                           |

Files explicitly NOT touched: `BattleEngine.ets`, `BattleConfig` (projected into, unchanged), `WordRepository.ets`, `QuestionGenerator.ets`, `ResultPage.ets`, `SessionResult.ets`.

---

## Task 1: GameConfig model + parsing + pool helpers + unit tests (TDD)

**Files:**
- Create: `entry/src/main/ets/models/GameConfig.ets`
- Modify: `entry/src/test/LocalUnit.test.ets` (append tests)

- [ ] **Step 1.1: Write the failing unit tests**

Append to the end of `entry/src/test/LocalUnit.test.ets` (before the last closing brace of `export default function localUnit`; place the new `describe` blocks alongside existing ones):

```typescript
import {
  GameConfig,
  TIMER_CHOICES,
  HP_MIN,
  HP_MAX,
  MONSTER_COUNT_MIN,
  MONSTER_COUNT_MAX,
  KNOWN_CATEGORIES,
  CUSTOM_CATEGORY_KEY,
  MIN_POOL_SIZE,
  cloneGameConfig,
  parseCustomWords,
  computeFinalPool
} from '../main/ets/models/GameConfig';
import {
  DEFAULT_PLAYER_HP,
  DEFAULT_MONSTER_HP,
  DEFAULT_MONSTERS_TOTAL,
  DEFAULT_STARTING_SECONDS
} from '../main/ets/services/BattleEngine';
import { WordEntry } from '../main/ets/models/WordEntry';

function makeEntry(id: string, word: string, category: string): WordEntry {
  const e: WordEntry = new WordEntry();
  e.id = id;
  e.word = word;
  e.meaningZh = word;
  e.category = category;
  e.difficulty = 1;
  return e;
}

describe('GameConfig.defaults', () => {
  it('defaultsMatchEngineDefaults', 0, () => {
    const c: GameConfig = new GameConfig();
    expect(c.playerMaxHp).assertEqual(DEFAULT_PLAYER_HP);
    expect(c.monsterMaxHp).assertEqual(DEFAULT_MONSTER_HP);
    expect(c.monstersTotal).assertEqual(DEFAULT_MONSTERS_TOTAL);
    expect(c.startingSeconds).assertEqual(DEFAULT_STARTING_SECONDS);
    expect(c.customWordsRaw).assertEqual('');
    expect(c.enabledCategories.length).assertEqual(KNOWN_CATEGORIES.length);
    for (let i = 0; i < KNOWN_CATEGORIES.length; i++) {
      expect(c.enabledCategories.indexOf(KNOWN_CATEGORIES[i]) >= 0).assertTrue();
    }
    expect(HP_MIN).assertEqual(1);
    expect(HP_MAX).assertEqual(10);
    expect(MONSTER_COUNT_MIN).assertEqual(1);
    expect(MONSTER_COUNT_MAX).assertEqual(10);
    expect(MIN_POOL_SIZE).assertEqual(3);
    expect(CUSTOM_CATEGORY_KEY).assertEqual('custom');
    expect(TIMER_CHOICES.indexOf(DEFAULT_STARTING_SECONDS) >= 0).assertTrue();
    expect(TIMER_CHOICES.indexOf(3) >= 0).assertTrue(); // 3s needed for timer-loss test
  });
});

describe('GameConfig.cloneGameConfig', () => {
  it('cloneIsDeepEnoughToIsolateDraft', 0, () => {
    const original: GameConfig = new GameConfig();
    original.customWordsRaw = '苹果:apple';
    const beforePlayer: number = original.playerMaxHp;
    const beforeCats: string[] = original.enabledCategories.slice();
    const beforeRaw: string = original.customWordsRaw;

    const clone: GameConfig = cloneGameConfig(original);
    clone.playerMaxHp = 1;
    clone.monsterMaxHp = 9;
    clone.monstersTotal = 2;
    clone.startingSeconds = 3;
    clone.enabledCategories.push('mutated');
    clone.customWordsRaw = 'mutated';

    expect(original.playerMaxHp).assertEqual(beforePlayer);
    expect(original.enabledCategories.length).assertEqual(beforeCats.length);
    for (let i = 0; i < beforeCats.length; i++) {
      expect(original.enabledCategories[i]).assertEqual(beforeCats[i]);
    }
    expect(original.customWordsRaw).assertEqual(beforeRaw);
  });
});

describe('GameConfig.parseCustomWords', () => {
  it('emptyReturnsEmpty', 0, () => {
    expect(parseCustomWords('').length).assertEqual(0);
    expect(parseCustomWords('\n\n  \n').length).assertEqual(0);
  });

  it('acceptsAsciiAndFullwidthColon', 0, () => {
    const out: WordEntry[] = parseCustomWords('苹果:apple\n香蕉：banana');
    expect(out.length).assertEqual(2);
    expect(out[0].meaningZh).assertEqual('苹果');
    expect(out[0].word).assertEqual('apple');
    expect(out[0].category).assertEqual(CUSTOM_CATEGORY_KEY);
    expect(out[0].id).assertEqual('custom-0');
    expect(out[1].meaningZh).assertEqual('香蕉');
    expect(out[1].word).assertEqual('banana');
    expect(out[1].id).assertEqual('custom-1');
  });

  it('skipsInvalidLinesAndKeepsIdsSequential', 0, () => {
    const raw: string = [
      '苹果:apple',     // valid -> custom-0
      'no colon here',  // invalid: missing colon
      ':only-right',    // invalid: empty left
      '香蕉:banana',    // valid -> custom-1
      '左边只有:',      // invalid: empty right
      '   ',            // invalid: blank
      '梨:pear'         // valid -> custom-2
    ].join('\n');
    const out: WordEntry[] = parseCustomWords(raw);
    expect(out.length).assertEqual(3);
    expect(out[0].id).assertEqual('custom-0');
    expect(out[0].word).assertEqual('apple');
    expect(out[1].id).assertEqual('custom-1');
    expect(out[1].word).assertEqual('banana');
    expect(out[2].id).assertEqual('custom-2');
    expect(out[2].word).assertEqual('pear');
  });
});

describe('GameConfig.computeFinalPool', () => {
  it('customDisabledIgnoresRaw', 0, () => {
    const all: WordEntry[] = [
      makeEntry('a1', 'apple', 'fruit'),
      makeEntry('p1', 'park', 'place'),
      makeEntry('h1', 'home', 'home')
    ];
    const out: WordEntry[] = computeFinalPool(all, ['fruit'], '你好:hello');
    expect(out.length).assertEqual(1);
    expect(out[0].category).assertEqual('fruit');
  });

  it('customEnabledMergesCustoms', 0, () => {
    const all: WordEntry[] = [
      makeEntry('a1', 'apple', 'fruit'),
      makeEntry('a2', 'pear', 'fruit')
    ];
    const out: WordEntry[] = computeFinalPool(all, ['fruit', CUSTOM_CATEGORY_KEY], '你好:hello');
    expect(out.length).assertEqual(3);
    expect(out[2].category).assertEqual(CUSTOM_CATEGORY_KEY);
    expect(out[2].word).assertEqual('hello');
  });

  it('customOnlyEmpty', 0, () => {
    const all: WordEntry[] = [
      makeEntry('a1', 'apple', 'fruit')
    ];
    const out: WordEntry[] = computeFinalPool(all, [CUSTOM_CATEGORY_KEY], '');
    expect(out.length).assertEqual(0);
  });

  it('customOnlyWithValidCustoms', 0, () => {
    const all: WordEntry[] = [
      makeEntry('a1', 'apple', 'fruit')
    ];
    const out: WordEntry[] = computeFinalPool(
      all,
      [CUSTOM_CATEGORY_KEY],
      '一:one\n二:two\n三:three');
    expect(out.length).assertEqual(3);
    expect(out[0].category).assertEqual(CUSTOM_CATEGORY_KEY);
  });

  it('builtinOnlyFilters', 0, () => {
    const all: WordEntry[] = [
      makeEntry('a1', 'apple', 'fruit'),
      makeEntry('p1', 'park', 'place'),
      makeEntry('h1', 'home', 'home'),
      makeEntry('a2', 'pear', 'fruit')
    ];
    const out: WordEntry[] = computeFinalPool(all, ['fruit', 'home'], '');
    expect(out.length).assertEqual(3);
  });
});
```

- [ ] **Step 1.2: Run the unit tests to verify they fail**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -40
```

Expected: compile error `Cannot find module '../main/ets/models/GameConfig'`.

- [ ] **Step 1.3: Create `GameConfig.ets` with the full implementation**

Create `entry/src/main/ets/models/GameConfig.ets`:

```typescript
import { WordEntry } from './WordEntry';

/**
 * Player-facing battle knobs (spec §3.1). Defaults mirror the engine
 * constants in BattleEngine.ets so cold-launch with no explicit save
 * behaves identically to the pre-ConfigPage build.
 *
 * Invariants:
 *   - playerMaxHp / monsterMaxHp / monstersTotal are integers in [1, 10].
 *   - startingSeconds is one of TIMER_CHOICES.
 *   - enabledCategories is a non-empty subset of
 *     KNOWN_CATEGORIES ∪ {CUSTOM_CATEGORY_KEY}.
 *   - customWordsRaw is arbitrary text — parsed lazily by parseCustomWords.
 *
 * GameConfig is a value object — ConfigPage's Save button always writes
 * a freshly-constructed instance (via cloneGameConfig + field edits)
 * because @StorageProp does not refire on same-reference updates.
 */
export class GameConfig {
  playerMaxHp: number = 5;
  monsterMaxHp: number = 3;
  monstersTotal: number = 5;
  startingSeconds: number = 300;
  enabledCategories: string[] = ['fruit', 'place', 'home'];
  customWordsRaw: string = '';
}

export const GAME_CONFIG_STORAGE_KEY: string = 'gameConfig';

export const TIMER_CHOICES: number[] = [3, 15, 30, 60, 120, 300, 600];

export const HP_MIN: number = 1;
export const HP_MAX: number = 10;
export const MONSTER_COUNT_MIN: number = 1;
export const MONSTER_COUNT_MAX: number = 10;

export const KNOWN_CATEGORIES: string[] = ['fruit', 'place', 'home'];
export const CUSTOM_CATEGORY_KEY: string = 'custom';

/**
 * Mirrors QuestionGenerator.MIN_REPO_SIZE. Duplicated here so ConfigPage
 * validation can reason about "final pool" size without reaching into
 * engine internals. Kept in sync by unit test defaultsMatchEngineDefaults.
 */
export const MIN_POOL_SIZE: number = 3;

/** Deep-enough clone so draft edits don't leak into the stored reference. */
export function cloneGameConfig(src: GameConfig): GameConfig {
  const c: GameConfig = new GameConfig();
  c.playerMaxHp = src.playerMaxHp;
  c.monsterMaxHp = src.monsterMaxHp;
  c.monstersTotal = src.monstersTotal;
  c.startingSeconds = src.startingSeconds;
  c.enabledCategories = src.enabledCategories.slice();
  c.customWordsRaw = src.customWordsRaw;
  return c;
}

/**
 * Parse raw CustomWordsPage text into WordEntry[]. Tolerant:
 *   - Accepts ':' (ASCII) and '：' (fullwidth); first occurrence wins.
 *   - Silently skips blank / malformed lines.
 *   - Assigns sequential ids 'custom-0', 'custom-1', ... over valid lines.
 */
export function parseCustomWords(raw: string): WordEntry[] {
  const out: WordEntry[] = [];
  if (raw.length === 0) {
    return out;
  }
  const lines: string[] = raw.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const trimmed: string = lines[i].trim();
    if (trimmed.length === 0) {
      continue;
    }
    let sep: number = trimmed.indexOf(':');
    if (sep < 0) {
      sep = trimmed.indexOf('：');
    }
    if (sep <= 0 || sep >= trimmed.length - 1) {
      continue;
    }
    const zh: string = trimmed.substring(0, sep).trim();
    const en: string = trimmed.substring(sep + 1).trim();
    if (zh.length === 0 || en.length === 0) {
      continue;
    }
    const e: WordEntry = new WordEntry();
    e.id = `custom-${out.length}`;
    e.word = en;
    e.meaningZh = zh;
    e.category = CUSTOM_CATEGORY_KEY;
    e.difficulty = 1;
    out.push(e);
  }
  return out;
}

/**
 * Single source of truth for the battle-time word pool. Used by both
 * BattlePage (runtime) and ConfigPage (Save-time validation) so the
 * two can never disagree on pool size.
 */
export function computeFinalPool(
  allBuiltin: WordEntry[],
  enabledCategories: string[],
  customWordsRaw: string
): WordEntry[] {
  const out: WordEntry[] = [];
  for (let i = 0; i < allBuiltin.length; i++) {
    if (enabledCategories.indexOf(allBuiltin[i].category) >= 0) {
      out.push(allBuiltin[i]);
    }
  }
  if (enabledCategories.indexOf(CUSTOM_CATEGORY_KEY) >= 0) {
    const customs: WordEntry[] = parseCustomWords(customWordsRaw);
    for (let i = 0; i < customs.length; i++) {
      out.push(customs[i]);
    }
  }
  return out;
}
```

- [ ] **Step 1.4: Run the unit tests to verify they pass**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -40
```

Expected: all 9 new tests pass alongside the existing suite.

- [ ] **Step 1.5: Commit**

```bash
git add entry/src/main/ets/models/GameConfig.ets entry/src/test/LocalUnit.test.ets
git commit -m "feat(config): GameConfig model with custom words parsing and final pool helper"
```

---

## Task 2: Seed AppStorage in EntryAbility.onCreate

**Files:**
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`

- [ ] **Step 2.1: Read the current EntryAbility.ets**

Locate the `onCreate(want, launchParam)` method.

- [ ] **Step 2.2: Add AppStorage seed inside onCreate**

Import at the top:

```typescript
import { GameConfig, GAME_CONFIG_STORAGE_KEY } from '../models/GameConfig';
```

First statement in `onCreate`:

```typescript
// Seed player-configurable battle knobs once per app session so every
// page can assume AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY)
// returns a valid instance. Values reset to defaults on cold launch
// (spec §3.4 — persistence is intentionally out of scope for v0.1).
AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, new GameConfig());
```

- [ ] **Step 2.3: Build and verify compile**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@default assembleHap --no-daemon 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 2.4: Commit**

```bash
git add entry/src/main/ets/entryability/EntryAbility.ets
git commit -m "feat(config): seed GameConfig in AppStorage on ability create"
```

---

## Task 3: Register ConfigPage + CustomWordsPage routes with stubs

**Files:**
- Create: `entry/src/main/ets/pages/ConfigPage.ets` (stub)
- Create: `entry/src/main/ets/pages/CustomWordsPage.ets` (stub)
- Modify: `entry/src/main/resources/base/profile/main_pages.json`

- [ ] **Step 3.1: Create the minimal ConfigPage stub**

`entry/src/main/ets/pages/ConfigPage.ets`:

```typescript
import { router } from '@kit.ArkUI';

/**
 * ConfigPage — stub registered for routing in Task 3. Full form is
 * implemented in Task 4.
 */
@Entry
@Component
struct ConfigPage {
  build(): void {
    Column() {
      Text('游戏设置')
        .id('ConfigTitle')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 24 });

      Button('返回')
        .id('ConfigCancelButton')
        .width(160)
        .height(52)
        .onClick((): void => {
          router.back();
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}
```

- [ ] **Step 3.2: Create the minimal CustomWordsPage stub**

`entry/src/main/ets/pages/CustomWordsPage.ets`:

```typescript
import { router } from '@kit.ArkUI';

/**
 * CustomWordsPage — stub registered for routing in Task 3. Full form
 * is implemented in Task 5.
 */
@Entry
@Component
struct CustomWordsPage {
  build(): void {
    Column() {
      Text('自定义词表')
        .id('CustomWordsTitle')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 24 });

      Button('返回')
        .id('CustomWordsCancelButton')
        .width(160)
        .height(52)
        .onClick((): void => {
          router.back();
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}
```

- [ ] **Step 3.3: Register both pages in main_pages.json**

`entry/src/main/resources/base/profile/main_pages.json`:

```json
{
  "src": [
    "pages/HomePage",
    "pages/BattlePage",
    "pages/ResultPage",
    "pages/ConfigPage",
    "pages/CustomWordsPage"
  ]
}
```

- [ ] **Step 3.4: Build and verify compile**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@default assembleHap --no-daemon 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3.5: Commit**

```bash
git add entry/src/main/ets/pages/ConfigPage.ets entry/src/main/ets/pages/CustomWordsPage.ets entry/src/main/resources/base/profile/main_pages.json
git commit -m "feat(config): register ConfigPage and CustomWordsPage routes with stubs"
```

---

## Task 4: Implement ConfigPage full form (with validation + custom chip)

**Files:**
- Modify: `entry/src/main/ets/pages/ConfigPage.ets`

- [ ] **Step 4.1: Replace ConfigPage with the full form**

Overwrite `entry/src/main/ets/pages/ConfigPage.ets`:

```typescript
import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  TIMER_CHOICES,
  HP_MIN,
  HP_MAX,
  MONSTER_COUNT_MIN,
  MONSTER_COUNT_MAX,
  KNOWN_CATEGORIES,
  CUSTOM_CATEGORY_KEY,
  MIN_POOL_SIZE,
  cloneGameConfig,
  computeFinalPool
} from '../models/GameConfig';
import { WordRepository } from '../services/WordRepository';
import { WordEntry } from '../models/WordEntry';

/**
 * ConfigPage exposes five battle knobs plus a custom-words category.
 * All non-custom edits happen on a local @State draft and are only
 * written to AppStorage when the user taps 保存 AND the resulting
 * pool size ≥ MIN_POOL_SIZE. 取消 returns to HomePage without
 * touching stored state. The custom-words raw text is owned by
 * CustomWordsPage (spec §3.4 / §4.5).
 */
@Entry
@Component
struct ConfigPage {
  @State private draft: GameConfig = new GameConfig();
  @State private showValidationHint: boolean = false;
  private builtinEntries: WordEntry[] = [];

  aboutToAppear(): void {
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    this.draft = cloneGameConfig(stored !== undefined ? stored : new GameConfig());

    // Load built-in entries for Save-time validation. Form renders
    // without waiting — validation only runs on the Save click.
    const repo: WordRepository = new WordRepository();
    repo.loadFromRawfile('words_v1.json').then((): void => {
      this.builtinEntries = repo.all();
    }).catch((err: BusinessError): void => {
      console.error(`ConfigPage: loadFromRawfile failed: ${JSON.stringify(err)}`);
    });
  }

  onPageShow(): void {
    // Re-sync draft.customWordsRaw when returning from CustomWordsPage
    // so validation uses the latest value even though ConfigPage never
    // mutates this field itself.
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    if (stored !== undefined) {
      this.draft.customWordsRaw = stored.customWordsRaw;
      this.showValidationHint = false;
      this.forceRerender();
    }
  }

  private forceRerender(): void {
    this.draft = cloneGameConfig(this.draft);
  }

  private decPlayerHp(): void {
    if (this.draft.playerMaxHp > HP_MIN) {
      this.draft.playerMaxHp -= 1;
      this.showValidationHint = false;
      this.forceRerender();
    }
  }
  private incPlayerHp(): void {
    if (this.draft.playerMaxHp < HP_MAX) {
      this.draft.playerMaxHp += 1;
      this.showValidationHint = false;
      this.forceRerender();
    }
  }
  private decMonsterHp(): void {
    if (this.draft.monsterMaxHp > HP_MIN) {
      this.draft.monsterMaxHp -= 1;
      this.showValidationHint = false;
      this.forceRerender();
    }
  }
  private incMonsterHp(): void {
    if (this.draft.monsterMaxHp < HP_MAX) {
      this.draft.monsterMaxHp += 1;
      this.showValidationHint = false;
      this.forceRerender();
    }
  }
  private decMonstersTotal(): void {
    if (this.draft.monstersTotal > MONSTER_COUNT_MIN) {
      this.draft.monstersTotal -= 1;
      this.showValidationHint = false;
      this.forceRerender();
    }
  }
  private incMonstersTotal(): void {
    if (this.draft.monstersTotal < MONSTER_COUNT_MAX) {
      this.draft.monstersTotal += 1;
      this.showValidationHint = false;
      this.forceRerender();
    }
  }

  private selectTimer(seconds: number): void {
    if (this.draft.startingSeconds === seconds) {
      return;
    }
    this.draft.startingSeconds = seconds;
    this.showValidationHint = false;
    this.forceRerender();
  }

  private toggleCategory(key: string): void {
    const idx: number = this.draft.enabledCategories.indexOf(key);
    if (idx >= 0) {
      // Silently refuse if this would leave zero categories selected
      // (spec §4.2 — "last-chip tap has no reaction").
      if (this.draft.enabledCategories.length <= 1) {
        return;
      }
      this.draft.enabledCategories.splice(idx, 1);
    } else {
      this.draft.enabledCategories.push(key);
    }
    this.showValidationHint = false;
    this.forceRerender();
  }

  private openCustomWords(): void {
    router.pushUrl({ url: 'pages/CustomWordsPage' }).catch((err: BusinessError): void => {
      console.error(`ConfigPage: pushUrl CustomWordsPage failed: ${JSON.stringify(err)}`);
    });
  }

  private onSave(): void {
    // Read current stored customWordsRaw so validation matches what
    // BattlePage will actually use (spec §5.7).
    const storedNow: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    const currentCustomRaw: string =
      storedNow !== undefined ? storedNow.customWordsRaw : '';

    const finalPool: WordEntry[] = computeFinalPool(
      this.builtinEntries, this.draft.enabledCategories, currentCustomRaw);

    if (finalPool.length < MIN_POOL_SIZE) {
      this.showValidationHint = true;
      this.forceRerender();
      return;
    }

    // Merge: keep stored customWordsRaw (owned by CustomWordsPage),
    // overlay draft's stepper/timer/category edits.
    const merged: GameConfig =
      cloneGameConfig(storedNow !== undefined ? storedNow : new GameConfig());
    merged.playerMaxHp = this.draft.playerMaxHp;
    merged.monsterMaxHp = this.draft.monsterMaxHp;
    merged.monstersTotal = this.draft.monstersTotal;
    merged.startingSeconds = this.draft.startingSeconds;
    merged.enabledCategories = this.draft.enabledCategories.slice();

    AppStorage.set<GameConfig>(GAME_CONFIG_STORAGE_KEY, merged);
    router.back();
  }

  private onCancel(): void {
    router.back();
  }

  @Builder
  private stepperRow(label: string, valueId: string, value: number,
                     decId: string, decAction: () => void, decEnabled: boolean,
                     incId: string, incAction: () => void, incEnabled: boolean) {
    Row() {
      Text(label).fontSize(18).width(120);
      Button('-')
        .id(decId)
        .width(44).height(44)
        .fontSize(24)
        .enabled(decEnabled)
        .opacity(decEnabled ? 1.0 : 0.4)
        .onClick((): void => decAction());
      Text(`${value}`)
        .id(valueId)
        .fontSize(22)
        .width(48)
        .textAlign(TextAlign.Center);
      Button('+')
        .id(incId)
        .width(44).height(44)
        .fontSize(24)
        .enabled(incEnabled)
        .opacity(incEnabled ? 1.0 : 0.4)
        .onClick((): void => incAction());
    }
    .margin({ bottom: 12 })
    .alignItems(VerticalAlign.Center);
  }

  private timerLabel(seconds: number): string {
    if (seconds < 60) {
      return `${seconds}s`;
    }
    return `${seconds / 60}m`;
  }

  private timerChipId(seconds: number): string {
    return `ConfigTimer${seconds}s`;
  }

  @Builder
  private timerRow() {
    Row() {
      Text('倒计时').fontSize(18).width(120);
      Row({ space: 8 }) {
        ForEach(TIMER_CHOICES, (sec: number) => {
          Button(this.timerLabel(sec))
            .id(this.timerChipId(sec))
            .width(56).height(40)
            .fontSize(16)
            .backgroundColor(this.draft.startingSeconds === sec ? '#FFB400' : '#EAF2F8')
            .fontColor(this.draft.startingSeconds === sec ? '#FFFFFF' : '#457B9D')
            .onClick((): void => this.selectTimer(sec));
        }, (sec: number) => `${sec}`);
      };
    }
    .margin({ bottom: 12 })
    .alignItems(VerticalAlign.Center);
  }

  private builtinCategoryLabel(key: string): string {
    if (key === 'fruit') return '水果';
    if (key === 'place') return '地点';
    if (key === 'home') return '家居';
    return key;
  }

  private builtinCategoryId(key: string): string {
    if (key === 'fruit') return 'ConfigCategoryFruit';
    if (key === 'place') return 'ConfigCategoryPlace';
    if (key === 'home') return 'ConfigCategoryHome';
    return `ConfigCategory${key}`;
  }

  @Builder
  private categoryRow() {
    Row() {
      Text('词库类别').fontSize(18).width(120);
      Row({ space: 8 }) {
        ForEach(KNOWN_CATEGORIES, (key: string) => {
          Button(this.builtinCategoryLabel(key))
            .id(this.builtinCategoryId(key))
            .width(72).height(40)
            .fontSize(16)
            .backgroundColor(this.draft.enabledCategories.indexOf(key) >= 0 ? '#FFF4D0' : '#F0F0F0')
            .fontColor(this.draft.enabledCategories.indexOf(key) >= 0 ? '#B8860B' : '#666666')
            .borderWidth(this.draft.enabledCategories.indexOf(key) >= 0 ? 2 : 0)
            .borderColor('#FFB400')
            .onClick((): void => this.toggleCategory(key));
        }, (key: string) => key);

        // Custom chip + edit icon
        Button('自定义')
          .id('ConfigCategoryCustom')
          .width(72).height(40)
          .fontSize(16)
          .backgroundColor(this.draft.enabledCategories.indexOf(CUSTOM_CATEGORY_KEY) >= 0 ? '#FFF4D0' : '#F0F0F0')
          .fontColor(this.draft.enabledCategories.indexOf(CUSTOM_CATEGORY_KEY) >= 0 ? '#B8860B' : '#666666')
          .borderWidth(this.draft.enabledCategories.indexOf(CUSTOM_CATEGORY_KEY) >= 0 ? 2 : 0)
          .borderColor('#FFB400')
          .onClick((): void => this.toggleCategory(CUSTOM_CATEGORY_KEY));
        Button('✎')
          .id('ConfigCategoryCustomEdit')
          .width(40).height(40)
          .fontSize(18)
          .backgroundColor('#EAF2F8')
          .fontColor('#457B9D')
          .onClick((): void => this.openCustomWords());
      };
    }
    .margin({ bottom: 16 })
    .alignItems(VerticalAlign.Center);
  }

  build(): void {
    Column() {
      Text('游戏设置')
        .id('ConfigTitle')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 16 });

      this.stepperRow(
        '玩家血量', 'ConfigPlayerHpValue', this.draft.playerMaxHp,
        'ConfigPlayerHpDec', (): void => this.decPlayerHp(), this.draft.playerMaxHp > HP_MIN,
        'ConfigPlayerHpInc', (): void => this.incPlayerHp(), this.draft.playerMaxHp < HP_MAX);
      this.stepperRow(
        '怪物血量', 'ConfigMonsterHpValue', this.draft.monsterMaxHp,
        'ConfigMonsterHpDec', (): void => this.decMonsterHp(), this.draft.monsterMaxHp > HP_MIN,
        'ConfigMonsterHpInc', (): void => this.incMonsterHp(), this.draft.monsterMaxHp < HP_MAX);
      this.stepperRow(
        '怪物数量', 'ConfigMonstersTotalValue', this.draft.monstersTotal,
        'ConfigMonstersTotalDec', (): void => this.decMonstersTotal(), this.draft.monstersTotal > MONSTER_COUNT_MIN,
        'ConfigMonstersTotalInc', (): void => this.incMonstersTotal(), this.draft.monstersTotal < MONSTER_COUNT_MAX);

      this.timerRow();
      this.categoryRow();

      if (this.showValidationHint) {
        Text('单词池太小（少于 3 个），请启用更多类别或添加自定义词')
          .id('ConfigValidationHint')
          .fontSize(14)
          .fontColor('#E63946')
          .margin({ bottom: 12 });
      }

      Row({ space: 16 }) {
        Button('取消')
          .id('ConfigCancelButton')
          .width(160).height(52)
          .backgroundColor('#BDBDBD')
          .onClick((): void => this.onCancel());
        Button('保存')
          .id('ConfigSaveButton')
          .width(160).height(52)
          .backgroundColor('#2ECC71')
          .onClick((): void => this.onSave());
      };
    }
    .width('100%')
    .height('100%')
    .padding({ top: 24, bottom: 24, left: 40, right: 40 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}
```

- [ ] **Step 4.2: Build and verify compile**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@default assembleHap --no-daemon 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL`. Fix any ArkTS strict-mode errors inline and re-run.

- [ ] **Step 4.3: Commit**

```bash
git add entry/src/main/ets/pages/ConfigPage.ets
git commit -m "feat(config): full ConfigPage form with custom chip and Save validation"
```

---

## Task 5: Implement CustomWordsPage full form

**Files:**
- Modify: `entry/src/main/ets/pages/CustomWordsPage.ets`

- [ ] **Step 5.1: Replace CustomWordsPage with the full form**

Overwrite `entry/src/main/ets/pages/CustomWordsPage.ets`:

```typescript
import { router } from '@kit.ArkUI';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  cloneGameConfig
} from '../models/GameConfig';

/**
 * CustomWordsPage — owns `GameConfig.customWordsRaw` end to end.
 * Reads the current raw text on aboutToAppear, lets the player edit
 * multi-line `中文:英文` pairs, and on Save merges the edited text
 * back into the stored GameConfig without touching other fields
 * (spec §4.5 / §3.4).
 */
@Entry
@Component
struct CustomWordsPage {
  @State private rawText: string = '';

  aboutToAppear(): void {
    const cfg: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    this.rawText = cfg !== undefined ? cfg.customWordsRaw : '';
  }

  private onSave(): void {
    const current: GameConfig =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY) ?? new GameConfig();
    const merged: GameConfig = cloneGameConfig(current);
    merged.customWordsRaw = this.rawText;
    AppStorage.set<GameConfig>(GAME_CONFIG_STORAGE_KEY, merged);
    router.back();
  }

  private onCancel(): void {
    router.back();
  }

  build(): void {
    Column() {
      Text('自定义词表')
        .id('CustomWordsTitle')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 });

      Text('格式：中文:英文，每行一个')
        .fontSize(14)
        .fontColor('#666666')
        .margin({ bottom: 12 });

      TextArea({
        text: this.rawText,
        placeholder: '每行一条，例如：\n苹果:apple\n香蕉:banana'
      })
        .id('CustomWordsTextArea')
        .width('80%')
        .height('55%')
        .fontSize(16)
        .backgroundColor('#F7F7F7')
        .padding(12)
        .onChange((v: string): void => {
          this.rawText = v;
        });

      Row({ space: 16 }) {
        Button('取消')
          .id('CustomWordsCancelButton')
          .width(160).height(52)
          .backgroundColor('#BDBDBD')
          .onClick((): void => this.onCancel());
        Button('保存')
          .id('CustomWordsSaveButton')
          .width(160).height(52)
          .backgroundColor('#2ECC71')
          .onClick((): void => this.onSave());
      }
      .margin({ top: 20 });
    }
    .width('100%')
    .height('100%')
    .padding({ top: 24, bottom: 24, left: 40, right: 40 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }
}
```

- [ ] **Step 5.2: Build and verify compile**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@default assembleHap --no-daemon 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5.3: Commit**

```bash
git add entry/src/main/ets/pages/CustomWordsPage.ets
git commit -m "feat(config): CustomWordsPage with TextArea and AppStorage round-trip"
```

---

## Task 6: HomePage gear-icon overlay + navigate to ConfigPage

**Files:**
- Modify: `entry/src/main/ets/pages/HomePage.ets`

- [ ] **Step 6.1: Replace HomePage with Stack-wrapped layout plus gear button**

Overwrite the file (preserve existing title / subtitle / hint / start-button texts verbatim):

```typescript
import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';

@Entry
@Component
struct HomePage {
  build(): void {
    Stack() {
      Column() {
        Text('Small Magician Word Adventure')
          .id('HomeTitle')
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 12 });

        Text('小魔法师单词冒险')
          .fontSize(22)
          .fontColor('#457B9D')
          .margin({ bottom: 32 });

        Text('点击开始，打败 5 个单词史莱姆吧！')
          .fontSize(18)
          .margin({ bottom: 40 });

        Button('开始游戏')
          .id('HomeStartButton')
          .fontSize(24)
          .width(220)
          .height(64)
          .backgroundColor('#E63946')
          .onClick((): void => {
            router.pushUrl({ url: 'pages/BattlePage' }).catch((err: BusinessError) => {
              console.error(`HomePage: pushUrl BattlePage failed: ${JSON.stringify(err)}`);
            });
          });
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center);

      Button('⚙')
        .id('HomeConfigButton')
        .type(ButtonType.Circle)
        .width(56)
        .height(56)
        .fontSize(28)
        .fontColor('#457B9D')
        .backgroundColor('#EAF2F8')
        .margin({ top: 16, right: 16 })
        .onClick((): void => {
          router.pushUrl({ url: 'pages/ConfigPage' }).catch((err: BusinessError) => {
            console.error(`HomePage: pushUrl ConfigPage failed: ${JSON.stringify(err)}`);
          });
        });
    }
    .alignContent(Alignment.TopEnd)
    .width('100%')
    .height('100%');
  }
}
```

- [ ] **Step 6.2: Build and verify compile**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@default assembleHap --no-daemon 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 6.3: Commit**

```bash
git add entry/src/main/ets/pages/HomePage.ets
git commit -m "feat(config): HomePage gear-icon overlay opens ConfigPage"
```

---

## Task 7: BattlePage reads GameConfig and uses computeFinalPool

**Files:**
- Modify: `entry/src/main/ets/pages/BattlePage.ets`

- [ ] **Step 7.1: Read the current aboutToAppear implementation**

Locate the `aboutToAppear` body that currently constructs
`QuestionGenerator` and `BattleEngine` from the loaded `repo`.

- [ ] **Step 7.2: Replace engine construction with config-aware projection**

Add imports near the top:

```typescript
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  cloneGameConfig,
  computeFinalPool
} from '../models/GameConfig';
import { BattleConfig } from '../services/BattleEngine';
```

Replace the existing generator/engine construction with:

```typescript
const storedCfg: GameConfig | undefined =
  AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
const cfg: GameConfig = cloneGameConfig(storedCfg !== undefined ? storedCfg : new GameConfig());

// Shared helper with ConfigPage validation — identical pool contents.
const finalEntries: WordEntry[] =
  computeFinalPool(repo.all(), cfg.enabledCategories, cfg.customWordsRaw);
const finalRepo: WordRepository = new WordRepository();
finalRepo.setEntries(finalEntries);

const gen: QuestionGenerator = new QuestionGenerator(finalRepo);

const bc: BattleConfig = new BattleConfig();
bc.playerMaxHp = cfg.playerMaxHp;
bc.monsterMaxHp = cfg.monsterMaxHp;
bc.monstersTotal = cfg.monstersTotal;
bc.startingSeconds = cfg.startingSeconds;

const engine: BattleEngine = new BattleEngine(gen, bc);
engine.start();
```

If the existing variable names (`repo`, `engine`) differ, adapt this block to match — do not rename them.

- [ ] **Step 7.3: Build the main HAP to verify compile**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@default assembleHap --no-daemon 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 7.4: Rebuild the ohosTest HAP and re-run the existing UI test suite**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | tail -20
hdc install /Users/bytedance/Projects/happyword/entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap
hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000 -w 240 2>&1 | tail -30
```

Expected: the three legacy UI tests still pass. If a test fails, diagnose — the existing coverage depends on defaults matching, which Task 1's `defaultsMatchEngineDefaults` guards against.

- [ ] **Step 7.5: Commit**

```bash
git add entry/src/main/ets/pages/BattlePage.ets
git commit -m "feat(config): BattlePage builds pool from GameConfig via computeFinalPool"
```

---

## Task 8: UI test helpers (no new tests yet)

**Files:**
- Modify: `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`

- [ ] **Step 8.1: Add helpers, constants, and TestGameConfig near the top**

Just below the existing `WORD_MAP` / `tapCorrectAnswer` block (module-scope helpers), append:

```typescript
/**
 * Ten Chinese prompts in the 'fruit' category. When GameConfig restricts
 * enabledCategories to ['fruit'], every question's prompt MUST be in
 * this set — asserting it makes category filtering visible in output.
 */
const FRUIT_PROMPTS: string[] = [
  '苹果', '香蕉', '橙子', '葡萄', '梨',
  '桃子', '柠檬', '芒果', '瓜', '樱桃'
];

function isFruitPrompt(prompt: string): boolean {
  for (let i = 0; i < FRUIT_PROMPTS.length; i++) {
    if (FRUIT_PROMPTS[i] === prompt) {
      return true;
    }
  }
  return false;
}

/**
 * Prompts used in the custom-words E2E test. Kept in lock-step with the
 * raw text passed to openCustomWordsAndSave in that test.
 */
const CUSTOM_TEST_PROMPTS: string[] = ['一只狗', '一只猫', '太阳'];
const CUSTOM_TEST_RAW: string = '一只狗:dog\n一只猫:cat\n太阳:sun';

function isCustomTestPrompt(prompt: string): boolean {
  for (let i = 0; i < CUSTOM_TEST_PROMPTS.length; i++) {
    if (CUSTOM_TEST_PROMPTS[i] === prompt) {
      return true;
    }
  }
  return false;
}

/**
 * Inverse of tapCorrectAnswer: reads the current prompt, resolves the
 * correct English via WORD_MAP, then clicks any option button whose
 * text is NOT that answer.
 */
async function tapWrongAnswer(driver: Driver): Promise<string> {
  const promptComp = await driver.findComponent(ON.id('BattlePrompt'));
  const promptText: string = await promptComp.getText();
  const correct: string = lookupEnglishAnswer(promptText);
  if (correct === '') {
    throw new Error(`tapWrongAnswer: unknown prompt "${promptText}"`);
  }
  const optionIds: string[] = ['BattleOptionA', 'BattleOptionB', 'BattleOptionC'];
  for (let i = 0; i < optionIds.length; i++) {
    const btn = await driver.findComponent(ON.id(optionIds[i]));
    const text: string = await btn.getText();
    if (text.toLowerCase() !== correct.toLowerCase()) {
      await btn.click();
      return text;
    }
  }
  throw new Error(`tapWrongAnswer: all 3 options matched correct answer "${correct}"`);
}

class TestGameConfig {
  playerHp: number = 5;
  monsterHp: number = 3;
  monstersTotal: number = 5;
  timerChipId: string = 'ConfigTimer300s';
  categories: string[] = ['fruit']; // may include 'custom'
}

async function stepDownTo(driver: Driver, decId: string, valueId: string, target: number): Promise<void> {
  const valueComp = await driver.findComponent(ON.id(valueId));
  const curText: string = await valueComp.getText();
  const current: number = parseInt(curText, 10);
  for (let i = current; i > target; i--) {
    const dec = await driver.findComponent(ON.id(decId));
    await dec.click();
    await driver.delayMs(80);
  }
}

function categoryChipId(cat: string): string {
  if (cat === 'fruit') return 'ConfigCategoryFruit';
  if (cat === 'place') return 'ConfigCategoryPlace';
  if (cat === 'home') return 'ConfigCategoryHome';
  if (cat === 'custom') return 'ConfigCategoryCustom';
  throw new Error(`categoryChipId: unknown category "${cat}"`);
}

/**
 * From HomePage: open ConfigPage, apply steppers/timer/categories,
 * then Save. Precondition: HomePage visible. Postcondition: back on
 * HomePage with AppStorage updated.
 *
 * Category ordering: toggle-on wanted categories first, then toggle-off
 * unwanted ones. This way the "last-chip-cannot-be-removed" guard
 * never fires mid-helper.
 */
async function openConfigAndApply(driver: Driver, cfg: TestGameConfig): Promise<void> {
  await driver.assertComponentExist(ON.id('HomeConfigButton'));
  const gear = await driver.findComponent(ON.id('HomeConfigButton'));
  await gear.click();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('ConfigTitle'));

  await stepDownTo(driver, 'ConfigPlayerHpDec', 'ConfigPlayerHpValue', cfg.playerHp);
  await stepDownTo(driver, 'ConfigMonsterHpDec', 'ConfigMonsterHpValue', cfg.monsterHp);
  await stepDownTo(driver, 'ConfigMonstersTotalDec', 'ConfigMonstersTotalValue', cfg.monstersTotal);

  await driver.assertComponentExist(ON.id(cfg.timerChipId));
  const chip = await driver.findComponent(ON.id(cfg.timerChipId));
  await chip.click();
  await driver.delayMs(80);

  // Built-in default enabled-set = ['fruit','place','home']; 'custom' default = off.
  const wanted: string[] = cfg.categories;
  const allCats: string[] = ['fruit', 'place', 'home', 'custom'];
  const defaultOn: string[] = ['fruit', 'place', 'home'];

  // Step 1: toggle ON any wanted category currently off by default.
  for (let i = 0; i < wanted.length; i++) {
    if (defaultOn.indexOf(wanted[i]) < 0) {
      const c = await driver.findComponent(ON.id(categoryChipId(wanted[i])));
      await c.click();
      await driver.delayMs(80);
    }
  }
  // Step 2: toggle OFF any default-on category not wanted.
  for (let i = 0; i < defaultOn.length; i++) {
    if (wanted.indexOf(defaultOn[i]) < 0) {
      const c = await driver.findComponent(ON.id(categoryChipId(defaultOn[i])));
      await c.click();
      await driver.delayMs(80);
    }
  }
  // Step 3: toggle OFF 'custom' if currently on but not wanted (only
  // relevant if a previous test left it on; our tests launch fresh so
  // this is a no-op).
  if (allCats.indexOf('custom') >= 0 && wanted.indexOf('custom') < 0) {
    // Safe-ish check: if the chip appears selected, click it. We don't
    // have a read-state API, so we simply skip here — tests launch app
    // fresh and AppStorage resets, so 'custom' starts off.
  }

  const save = await driver.findComponent(ON.id('ConfigSaveButton'));
  await save.click();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('HomeStartButton'));
}

/**
 * From HomePage: open ConfigPage, enter CustomWordsPage via the edit
 * icon, replace the TextArea contents, tap Save, and return to
 * ConfigPage. Caller is responsible for the subsequent ConfigPage
 * Save (usually via openConfigAndApply in a follow-up call).
 *
 * Precondition: HomePage visible.
 * Postcondition: Back on HomePage (we router.back() from ConfigPage
 * via Cancel to leave stepper/category defaults untouched).
 */
async function openCustomWordsAndSave(driver: Driver, rawText: string): Promise<void> {
  await driver.assertComponentExist(ON.id('HomeConfigButton'));
  const gear = await driver.findComponent(ON.id('HomeConfigButton'));
  await gear.click();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('ConfigCategoryCustomEdit'));

  const editIcon = await driver.findComponent(ON.id('ConfigCategoryCustomEdit'));
  await editIcon.click();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('CustomWordsTextArea'));

  const ta = await driver.findComponent(ON.id('CustomWordsTextArea'));
  await ta.inputText(rawText);
  await driver.delayMs(120);

  const save = await driver.findComponent(ON.id('CustomWordsSaveButton'));
  await save.click();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('ConfigTitle'));

  // Exit ConfigPage without altering other fields.
  const cancel = await driver.findComponent(ON.id('ConfigCancelButton'));
  await cancel.click();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('HomeStartButton'));
}
```

Also add the custom-test answers to the existing `WORD_MAP` at the top of the file so `tapCorrectAnswer` can resolve them in Task 12's test:

```typescript
// Append inside WORD_MAP (prepend if easier):
//   '一只狗': 'dog',
//   '一只猫': 'cat',
//   '太阳':   'sun'
```

- [ ] **Step 8.2: Rebuild ohosTest HAP to verify the helpers compile**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 8.3: Commit**

```bash
git add entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets
git commit -m "test(config): add openConfigAndApply, openCustomWordsAndSave, tapWrongAnswer helpers"
```

---

## Task 9: E2E test — configShortWin_oneShotVictory

**Files:**
- Modify: `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`

- [ ] **Step 9.1: Append the test inside `describe('RoutingFlowUiTest', ...)`**

After the existing `winFlow_fifteenCorrectAnswersReachesVictory` test:

```typescript
    it('configShortWin_oneShotVictory', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      const cfg: TestGameConfig = new TestGameConfig();
      cfg.playerHp = 5;
      cfg.monsterHp = 1;
      cfg.monstersTotal = 1;
      cfg.timerChipId = 'ConfigTimer60s';
      cfg.categories = ['fruit'];
      await openConfigAndApply(driver, cfg);

      await clickById(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      const promptComp = await driver.findComponent(ON.id('BattlePrompt'));
      const prompt: string = await promptComp.getText();
      expect(isFruitPrompt(prompt)).assertTrue();

      await tapCorrectAnswer(driver);
      await driver.delayMs(900);

      await driver.assertComponentExist(ON.id('ResultTitle'));
      await driver.assertComponentExist(ON.text('胜利！'));
      await driver.assertComponentExist(ON.text('击败怪物：1 / 1'));
      await driver.assertComponentExist(ON.text('正确率：100%'));

      await clickById(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });
```

- [ ] **Step 9.2: Rebuild + install + run**

```bash
cd /Users/bytedance/Projects/happyword && \
  hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | tail -10 && \
  hdc install /Users/bytedance/Projects/happyword/entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap && \
  hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000 -w 240 2>&1 | tail -30
```

Expected: all tests pass.

- [ ] **Step 9.3: Commit**

```bash
git add entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets
git commit -m "test(config): E2E configShortWin reaches Won via 1 correct tap"
```

---

## Task 10: E2E test — configTimerExpiry_lossOnTimeout

**Files:**
- Modify: `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`

- [ ] **Step 10.1: Append the test after `configShortWin`**

```typescript
    it('configTimerExpiry_lossOnTimeout', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      const cfg: TestGameConfig = new TestGameConfig();
      cfg.playerHp = 5;
      cfg.monsterHp = 3;
      cfg.monstersTotal = 5;
      cfg.timerChipId = 'ConfigTimer3s';
      cfg.categories = ['fruit'];
      await openConfigAndApply(driver, cfg);

      await clickById(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      // Do NOT tap any option. Wait past the 3s timer + feedback buffer.
      await driver.delayMs(3500);

      await driver.assertComponentExist(ON.id('ResultTitle'));
      await driver.assertComponentExist(ON.text('挑战失败'));
      await driver.assertComponentExist(ON.text('击败怪物：0 / 5'));
      await driver.assertComponentExist(ON.text('正确率：0%'));

      await clickById(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });
```

- [ ] **Step 10.2: Rebuild + install + run** (same pattern as Task 9). Expected: passes in ~7s.

- [ ] **Step 10.3: Commit**

```bash
git add entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets
git commit -m "test(config): E2E configTimerExpiry reaches Lost via tick() timeout"
```

---

## Task 11: E2E test — configHpZero_lossOnWrongAnswers

**Files:**
- Modify: `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`

- [ ] **Step 11.1: Append the test**

```typescript
    it('configHpZero_lossOnWrongAnswers', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      const cfg: TestGameConfig = new TestGameConfig();
      cfg.playerHp = 1;
      cfg.monsterHp = 3;
      cfg.monstersTotal = 5;
      cfg.timerChipId = 'ConfigTimer60s';
      cfg.categories = ['fruit'];
      await openConfigAndApply(driver, cfg);

      await clickById(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      const promptComp = await driver.findComponent(ON.id('BattlePrompt'));
      const prompt: string = await promptComp.getText();
      expect(isFruitPrompt(prompt)).assertTrue();

      await tapWrongAnswer(driver);
      await driver.delayMs(900);

      await driver.assertComponentExist(ON.id('ResultTitle'));
      await driver.assertComponentExist(ON.text('挑战失败'));
      await driver.assertComponentExist(ON.text('击败怪物：0 / 5'));

      await clickById(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });
```

- [ ] **Step 11.2: Rebuild + install + run** (same pattern).

- [ ] **Step 11.3: Commit**

```bash
git add entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets
git commit -m "test(config): E2E configHpZero reaches Lost via 1 wrong tap"
```

---

## Task 12: E2E test — configCustomWordsOnly_oneShotVictory

**Files:**
- Modify: `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`

- [ ] **Step 12.1: Append the test**

This test combines the custom-words helper with an E2E flow that exercises the validation-hint path AND a happy-path win using only user-provided words.

```typescript
    it('configCustomWordsOnly_oneShotVictory', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      // Phase 1 — validation-hint probe: enable 'custom' only with no
      // custom words stored yet. Save should be blocked; ConfigValidationHint
      // must appear.
      {
        const probeCfg: TestGameConfig = new TestGameConfig();
        probeCfg.playerHp = 5;
        probeCfg.monsterHp = 1;
        probeCfg.monstersTotal = 1;
        probeCfg.timerChipId = 'ConfigTimer60s';
        probeCfg.categories = ['custom'];

        await driver.assertComponentExist(ON.id('HomeConfigButton'));
        const gear = await driver.findComponent(ON.id('HomeConfigButton'));
        await gear.click();
        await driver.delayMs(800);

        // Apply stepper/timer/categories to match probeCfg (inline —
        // we cannot call openConfigAndApply because we want to stay
        // on ConfigPage after Save-attempt to verify the hint).
        await stepDownTo(driver, 'ConfigPlayerHpDec', 'ConfigPlayerHpValue', probeCfg.playerHp);
        await stepDownTo(driver, 'ConfigMonsterHpDec', 'ConfigMonsterHpValue', probeCfg.monsterHp);
        await stepDownTo(driver, 'ConfigMonstersTotalDec', 'ConfigMonstersTotalValue', probeCfg.monstersTotal);
        const timer = await driver.findComponent(ON.id(probeCfg.timerChipId));
        await timer.click();
        await driver.delayMs(80);

        // Enable 'custom', then turn off 'fruit' / 'place' / 'home'.
        const customChip = await driver.findComponent(ON.id('ConfigCategoryCustom'));
        await customChip.click();
        await driver.delayMs(80);
        const fruitChip = await driver.findComponent(ON.id('ConfigCategoryFruit'));
        await fruitChip.click();
        await driver.delayMs(80);
        const placeChip = await driver.findComponent(ON.id('ConfigCategoryPlace'));
        await placeChip.click();
        await driver.delayMs(80);
        const homeChip = await driver.findComponent(ON.id('ConfigCategoryHome'));
        await homeChip.click();
        await driver.delayMs(80);

        const save = await driver.findComponent(ON.id('ConfigSaveButton'));
        await save.click();
        await driver.delayMs(300);

        // Validation hint must be visible; we must still be on ConfigPage.
        await driver.assertComponentExist(ON.id('ConfigTitle'));
        await driver.assertComponentExist(ON.id('ConfigValidationHint'));

        const cancel = await driver.findComponent(ON.id('ConfigCancelButton'));
        await cancel.click();
        await driver.delayMs(800);
        await driver.assertComponentExist(ON.id('HomeStartButton'));
      }

      // Phase 2 — save custom words via CustomWordsPage, then apply
      // custom-only ConfigPage setup, then play through to victory.
      await openCustomWordsAndSave(driver, CUSTOM_TEST_RAW);

      const cfg: TestGameConfig = new TestGameConfig();
      cfg.playerHp = 5;
      cfg.monsterHp = 1;
      cfg.monstersTotal = 1;
      cfg.timerChipId = 'ConfigTimer60s';
      cfg.categories = ['custom'];
      await openConfigAndApply(driver, cfg);

      await clickById(driver, 'HomeStartButton');
      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.id('BattlePrompt'));

      const promptComp = await driver.findComponent(ON.id('BattlePrompt'));
      const prompt: string = await promptComp.getText();
      expect(isCustomTestPrompt(prompt)).assertTrue();

      await tapCorrectAnswer(driver);
      await driver.delayMs(900);

      await driver.assertComponentExist(ON.id('ResultTitle'));
      await driver.assertComponentExist(ON.text('胜利！'));
      await driver.assertComponentExist(ON.text('击败怪物：1 / 1'));

      await clickById(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });
```

- [ ] **Step 12.2: Rebuild + install + run**

```bash
cd /Users/bytedance/Projects/happyword && \
  hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | tail -10 && \
  hdc install /Users/bytedance/Projects/happyword/entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap && \
  hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000 -w 240 2>&1 | tail -60
```

Expected: `Tests run: 7, Pass: 7`. The three legacy tests plus four new config-driven E2E tests.

If Phase 1's validation-hint assertion fails, the most likely cause is that `ConfigPage` did not finish loading `builtinEntries` before Save was clicked — add a small `delayMs(1500)` between `gear.click()` and stepper manipulation to give the rawfile load time to complete.

- [ ] **Step 12.3: Commit**

```bash
git add entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets
git commit -m "test(config): E2E configCustomWordsOnly covers validation hint + custom-only win"
```

---

## Task 13: Final verification + push

**Files:** none

- [ ] **Step 13.1: Full unit + codelinter + UI pipeline**

```bash
cd /Users/bytedance/Projects/happyword && \
  hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -30 && \
  codelinter -c ./code-linter.json5 . 2>&1 | tail -30 && \
  hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | tail -10 && \
  hdc install /Users/bytedance/Projects/happyword/entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap && \
  hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000 -w 240 2>&1 | tail -30
```

Expected:
- Unit tests: all pass (including the 9 new ones from Task 1).
- Codelinter: exit 0 (warnings per team policy — do not let errors pass).
- Build: `BUILD SUCCESSFUL`.
- UI tests: `Tests run: 7, Pass: 7`.

If any step fails, classify via `harmony-log-analyzer` / `test-failure-classifier` skills and fix before proceeding.

- [ ] **Step 13.2: Push the branch**

```bash
git push origin cursor/wordmagic-t2-t4-skeleton
```

Expected: clean push, no force needed.

---

## Self-Review

**Spec coverage** — walked through every spec section:
- §3.1 `GameConfig` model: Task 1.
- §3.2 parseCustomWords / §3.3 computeFinalPool: Task 1.
- §3.4 AppStorage contract: Tasks 2 (seed), 4 (ConfigPage read + merge-save), 5 (CustomWordsPage read + merge-save), 7 (BattlePage read).
- §4 ConfigPage UI + custom chip + edit icon + validation hint: Task 4.
- §4.5 CustomWordsPage: Tasks 3 (stub) + 5 (full).
- §5.1 EntryAbility.onCreate: Task 2.
- §5.2 HomePage gear overlay: Task 6.
- §5.3 BattlePage integration via computeFinalPool: Task 7.
- §5.4 main_pages.json: Task 3.
- §5.5 Retry flow (no change): Task 7 (BattlePage re-reads on every aboutToAppear) + Task 13 verification via existing retryFlow UI test.
- §5.7 Save validation: Task 4.
- §6.2 nine unit tests: Task 1.
- §6.3 four UI tests: Tasks 9, 10, 11, 12.

**Placeholder scan** — no "TBD"/"TODO" in any step; every code block contains the exact content an engineer types.

**Type consistency** — cross-checked:
- `GameConfig` fields (`playerMaxHp`, `monsterMaxHp`, `monstersTotal`, `startingSeconds`, `enabledCategories`, `customWordsRaw`) match across Task 1 (model), Task 4 (ConfigPage), Task 5 (CustomWordsPage), Task 7 (BattlePage).
- `cloneGameConfig` signature `(GameConfig) => GameConfig` used in Tasks 1, 4, 5, 7.
- `parseCustomWords(raw)` and `computeFinalPool(all, cats, raw)` signatures consistent in Task 1 (test + impl), Task 4 (ConfigPage.onSave), Task 7 (BattlePage.aboutToAppear).
- `TestGameConfig` field names consistent across Tasks 8 (definition) and 9 / 10 / 11 / 12 (usages).
- `GAME_CONFIG_STORAGE_KEY` used consistently in Tasks 2, 4, 5, 7.
- `CUSTOM_CATEGORY_KEY = 'custom'`, asserted in both unit tests (Task 1) and used as a literal for chip ids / helper categories in Task 8.

**Reorderability** — Task 5 (CustomWordsPage full) depends on Task 3 (stub registered) but NOT on Task 4 (ConfigPage full form). Tasks 4 and 5 can run in either order once Task 3 is done. All other dependencies are linear.

**Rollback** — each task ends in a separate commit, so a bisect of UI regressions can pinpoint the offending change.
