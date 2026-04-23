# ConfigPage & Short-Level E2E Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a HarmonyOS ConfigPage that lets players set five battle knobs (HP / HP / monster count / timer / category subset), persist them in AppStorage for the app session, and author three on-device E2E tests (Win / Timer-Loss / HP-Zero-Loss) that reach the ResultPage without the `[debug] end battle` escape hatch.

**Architecture:** A new `GameConfig` value-object holds all settings and lives in `AppStorage` under the key `'gameConfig'`. ConfigPage reads a local cloned draft, mutates it as the user taps, and writes it back to AppStorage on Save. BattlePage reads the current `GameConfig` on `aboutToAppear` and projects it to a filtered `WordRepository` plus a `BattleConfig`. UI tests drive the ConfigPage form via id-based taps.

**Tech Stack:** HarmonyOS ArkTS (strict mode), ArkUI (`@Entry`, `@Component`, `@State`, `Stack`, `Column`, `Row`, `Button`), `@ohos.router`, `AppStorage`, Hypium (`describe` / `it`), `@kit.TestKit` (`Driver`, `ON`).

**Reference spec:** `docs/superpowers/specs/2026-04-23-config-page-design.md`

---

## File Structure

Files created:

| Path                                                          | Responsibility                                                        |
|---------------------------------------------------------------|-----------------------------------------------------------------------|
| `entry/src/main/ets/models/GameConfig.ets`                    | Value object, constants (TIMER_CHOICES, HP_MIN/MAX, etc.), cloneGameConfig, filterEntriesByCategories |
| `entry/src/main/ets/pages/ConfigPage.ets`                     | Landscape form page; reads/writes AppStorage                          |

Files modified:

| Path                                                                              | What changes                                                        |
|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `entry/src/main/ets/entryability/EntryAbility.ets`                                | Seed `gameConfig` in `onCreate`                                     |
| `entry/src/main/ets/pages/HomePage.ets`                                           | Wrap in `Stack`, add gear-icon overlay                              |
| `entry/src/main/ets/pages/BattlePage.ets`                                         | Read `gameConfig`, build filtered repo + BattleConfig               |
| `entry/src/main/resources/base/profile/main_pages.json`                           | Register `pages/ConfigPage`                                         |
| `entry/src/test/LocalUnit.test.ets`                                               | 3 new unit tests covering defaults, clone, filter                   |
| `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`                             | `openConfigAndApply`, `tapWrongAnswer`, `FRUIT_PROMPTS` + 3 E2E tests |

Files explicitly NOT touched: `BattleEngine.ets`, `BattleConfig` (class is unchanged — we just project into it), `WordRepository.ets`, `QuestionGenerator.ets`, `ResultPage.ets`, `SessionResult.ets`.

---

## Task 1: GameConfig model + unit tests (TDD)

**Files:**
- Create: `entry/src/main/ets/models/GameConfig.ets`
- Modify: `entry/src/test/LocalUnit.test.ets` (append 3 tests)

- [ ] **Step 1.1: Write the failing unit tests**

Append to the end of `entry/src/test/LocalUnit.test.ets` (before the last closing brace of `export default function localUnit`; check the file structure first and place the new `describe` block alongside existing ones):

```typescript
import {
  GameConfig,
  TIMER_CHOICES,
  HP_MIN,
  HP_MAX,
  MONSTER_COUNT_MIN,
  MONSTER_COUNT_MAX,
  KNOWN_CATEGORIES,
  cloneGameConfig,
  filterEntriesByCategories
} from '../main/ets/models/GameConfig';
import {
  DEFAULT_PLAYER_HP,
  DEFAULT_MONSTER_HP,
  DEFAULT_MONSTERS_TOTAL,
  DEFAULT_STARTING_SECONDS
} from '../main/ets/services/BattleEngine';
import { WordEntry } from '../main/ets/models/WordEntry';

describe('GameConfig.defaults', () => {
  it('defaultsMatchEngineDefaults', 0, () => {
    const c: GameConfig = new GameConfig();
    expect(c.playerMaxHp).assertEqual(DEFAULT_PLAYER_HP);
    expect(c.monsterMaxHp).assertEqual(DEFAULT_MONSTER_HP);
    expect(c.monstersTotal).assertEqual(DEFAULT_MONSTERS_TOTAL);
    expect(c.startingSeconds).assertEqual(DEFAULT_STARTING_SECONDS);
    expect(c.enabledCategories.length).assertEqual(KNOWN_CATEGORIES.length);
    for (let i = 0; i < KNOWN_CATEGORIES.length; i++) {
      expect(c.enabledCategories.indexOf(KNOWN_CATEGORIES[i]) >= 0).assertTrue();
    }
    // Constants used by ConfigPage must be internally consistent.
    expect(HP_MIN).assertEqual(1);
    expect(HP_MAX).assertEqual(10);
    expect(MONSTER_COUNT_MIN).assertEqual(1);
    expect(MONSTER_COUNT_MAX).assertEqual(10);
    expect(TIMER_CHOICES.indexOf(DEFAULT_STARTING_SECONDS) >= 0).assertTrue();
    expect(TIMER_CHOICES.indexOf(3) >= 0).assertTrue(); // 3s needed for the timer-loss test
  });
});

describe('GameConfig.cloneGameConfig', () => {
  it('cloneIsDeepEnoughToIsolateDraft', 0, () => {
    const original: GameConfig = new GameConfig();
    const beforePlayer: number = original.playerMaxHp;
    const beforeMonster: number = original.monsterMaxHp;
    const beforeTotal: number = original.monstersTotal;
    const beforeSeconds: number = original.startingSeconds;
    const beforeCats: string[] = original.enabledCategories.slice();

    const clone: GameConfig = cloneGameConfig(original);
    clone.playerMaxHp = 1;
    clone.monsterMaxHp = 9;
    clone.monstersTotal = 2;
    clone.startingSeconds = 3;
    clone.enabledCategories.push('mutated');

    expect(original.playerMaxHp).assertEqual(beforePlayer);
    expect(original.monsterMaxHp).assertEqual(beforeMonster);
    expect(original.monstersTotal).assertEqual(beforeTotal);
    expect(original.startingSeconds).assertEqual(beforeSeconds);
    expect(original.enabledCategories.length).assertEqual(beforeCats.length);
    for (let i = 0; i < beforeCats.length; i++) {
      expect(original.enabledCategories[i]).assertEqual(beforeCats[i]);
    }
  });
});

function makeEntry(id: string, word: string, category: string): WordEntry {
  const e: WordEntry = new WordEntry();
  e.id = id;
  e.word = word;
  e.meaningZh = word;
  e.category = category;
  e.difficulty = 1;
  return e;
}

describe('GameConfig.filterEntriesByCategories', () => {
  it('emptyFilterReturnsACopyOfEverything', 0, () => {
    const all: WordEntry[] = [
      makeEntry('a1', 'apple', 'fruit'),
      makeEntry('p1', 'park', 'place')
    ];
    const out: WordEntry[] = filterEntriesByCategories(all, []);
    expect(out.length).assertEqual(2);
    // Must be a copy — mutating it should not affect the input.
    out.push(makeEntry('z', 'z', 'z'));
    expect(all.length).assertEqual(2);
  });

  it('keepsOnlyEntriesInEnabledCategories', 0, () => {
    const all: WordEntry[] = [
      makeEntry('a1', 'apple', 'fruit'),
      makeEntry('p1', 'park', 'place'),
      makeEntry('h1', 'home', 'home'),
      makeEntry('a2', 'pear', 'fruit')
    ];
    const out: WordEntry[] = filterEntriesByCategories(all, ['fruit']);
    expect(out.length).assertEqual(2);
    expect(out[0].category).assertEqual('fruit');
    expect(out[1].category).assertEqual('fruit');
  });

  it('acceptsMultipleCategories', 0, () => {
    const all: WordEntry[] = [
      makeEntry('a1', 'apple', 'fruit'),
      makeEntry('p1', 'park', 'place'),
      makeEntry('h1', 'home', 'home')
    ];
    const out: WordEntry[] = filterEntriesByCategories(all, ['fruit', 'home']);
    expect(out.length).assertEqual(2);
  });
});
```

Note: `WordEntry` default-constructed instances need all required fields populated to pass `isValid()`. If unit tests fail due to validation, relax the helper to set `difficulty = 1` and any missing fields explicitly (already done above).

- [ ] **Step 1.2: Run the unit tests to verify they fail**

Run:

```bash
hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -40
```

Expected: compile error `Cannot find module '../main/ets/models/GameConfig'`.

- [ ] **Step 1.3: Create `GameConfig.ets` with the minimal implementation**

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
 *   - enabledCategories is a non-empty subset of KNOWN_CATEGORIES.
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
}

export const GAME_CONFIG_STORAGE_KEY: string = 'gameConfig';

export const TIMER_CHOICES: number[] = [3, 15, 30, 60, 120, 300, 600];

export const HP_MIN: number = 1;
export const HP_MAX: number = 10;
export const MONSTER_COUNT_MIN: number = 1;
export const MONSTER_COUNT_MAX: number = 10;

export const KNOWN_CATEGORIES: string[] = ['fruit', 'place', 'home'];

/** Deep-enough clone so draft edits don't leak into the stored reference. */
export function cloneGameConfig(src: GameConfig): GameConfig {
  const c: GameConfig = new GameConfig();
  c.playerMaxHp = src.playerMaxHp;
  c.monsterMaxHp = src.monsterMaxHp;
  c.monstersTotal = src.monstersTotal;
  c.startingSeconds = src.startingSeconds;
  c.enabledCategories = src.enabledCategories.slice();
  return c;
}

/**
 * Subset the provided entries to those whose category is in `categories`.
 * Empty `categories` returns a defensive copy of the full list (useful as
 * a "no filter" sentinel; v0.1 never calls this with empty but we keep
 * the fallback for future safety).
 */
export function filterEntriesByCategories(
  entries: WordEntry[],
  categories: string[]
): WordEntry[] {
  if (categories.length === 0) {
    return entries.slice();
  }
  const out: WordEntry[] = [];
  for (let i = 0; i < entries.length; i++) {
    if (categories.indexOf(entries[i].category) >= 0) {
      out.push(entries[i]);
    }
  }
  return out;
}
```

- [ ] **Step 1.4: Run the unit tests to verify they pass**

Run:

```bash
hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -40
```

Expected: all tests pass, including the 5 new ones from Task 1.

- [ ] **Step 1.5: Commit**

```bash
git add entry/src/main/ets/models/GameConfig.ets entry/src/test/LocalUnit.test.ets
git commit -m "feat(config): GameConfig model with defaults, clone, category filter"
```

---

## Task 2: Seed AppStorage in EntryAbility.onCreate

**Files:**
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`

- [ ] **Step 2.1: Read the current EntryAbility.ets**

Run `Read` tool on `entry/src/main/ets/entryability/EntryAbility.ets` to locate the `onCreate(want, launchParam)` method.

- [ ] **Step 2.2: Add AppStorage seed inside onCreate**

At the top of the file, add:

```typescript
import { GameConfig, GAME_CONFIG_STORAGE_KEY } from '../models/GameConfig';
```

Inside `onCreate`, as the first statement (before any existing code):

```typescript
// Seed player-configurable battle knobs once per app session so every
// page can assume AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY)
// returns a valid instance. Values reset to defaults on cold launch
// (spec §3.2 — persistence is intentionally out of scope for v0.1).
AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, new GameConfig());
```

If the existing `onCreate` signature or body looks different, preserve the rest verbatim.

- [ ] **Step 2.3: Build and verify compile**

Run:

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

## Task 3: Register ConfigPage route + stub ConfigPage

**Files:**
- Create: `entry/src/main/ets/pages/ConfigPage.ets` (stub)
- Modify: `entry/src/main/resources/base/profile/main_pages.json`

- [ ] **Step 3.1: Create the minimal ConfigPage stub**

Create `entry/src/main/ets/pages/ConfigPage.ets`:

```typescript
import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';

/**
 * ConfigPage — stub registered for routing in Task 3. Full form is
 * implemented in Task 4. The stub is a real page (not a placeholder
 * string) so main_pages.json registration compiles cleanly and
 * `router.pushUrl('pages/ConfigPage')` succeeds from HomePage during
 * Task 5's verification.
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

- [ ] **Step 3.2: Register the page in main_pages.json**

Read `entry/src/main/resources/base/profile/main_pages.json`. Append `"pages/ConfigPage"` to the `src` array so it becomes:

```json
{
  "src": [
    "pages/HomePage",
    "pages/BattlePage",
    "pages/ResultPage",
    "pages/ConfigPage"
  ]
}
```

- [ ] **Step 3.3: Build and verify compile**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@default assembleHap --no-daemon 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3.4: Commit**

```bash
git add entry/src/main/ets/pages/ConfigPage.ets entry/src/main/resources/base/profile/main_pages.json
git commit -m "feat(config): register ConfigPage route with stub page"
```

---

## Task 4: Implement ConfigPage full form

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
  cloneGameConfig
} from '../models/GameConfig';

/**
 * ConfigPage exposes five battle knobs to the player. All edits
 * happen on a local @State draft and are only written to AppStorage
 * when the user taps "保存"; "取消" returns to HomePage without
 * touching stored state (spec §3.2 / §4.3).
 */
@Entry
@Component
struct ConfigPage {
  @State private draft: GameConfig = new GameConfig();

  aboutToAppear(): void {
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    this.draft = cloneGameConfig(stored !== undefined ? stored : new GameConfig());
  }

  private forceRerender(): void {
    this.draft = cloneGameConfig(this.draft);
  }

  private decPlayerHp(): void {
    if (this.draft.playerMaxHp > HP_MIN) {
      this.draft.playerMaxHp -= 1;
      this.forceRerender();
    }
  }
  private incPlayerHp(): void {
    if (this.draft.playerMaxHp < HP_MAX) {
      this.draft.playerMaxHp += 1;
      this.forceRerender();
    }
  }
  private decMonsterHp(): void {
    if (this.draft.monsterMaxHp > HP_MIN) {
      this.draft.monsterMaxHp -= 1;
      this.forceRerender();
    }
  }
  private incMonsterHp(): void {
    if (this.draft.monsterMaxHp < HP_MAX) {
      this.draft.monsterMaxHp += 1;
      this.forceRerender();
    }
  }
  private decMonstersTotal(): void {
    if (this.draft.monstersTotal > MONSTER_COUNT_MIN) {
      this.draft.monstersTotal -= 1;
      this.forceRerender();
    }
  }
  private incMonstersTotal(): void {
    if (this.draft.monstersTotal < MONSTER_COUNT_MAX) {
      this.draft.monstersTotal += 1;
      this.forceRerender();
    }
  }

  private selectTimer(seconds: number): void {
    if (this.draft.startingSeconds === seconds) {
      return;
    }
    this.draft.startingSeconds = seconds;
    this.forceRerender();
  }

  private toggleCategory(key: string): void {
    const idx: number = this.draft.enabledCategories.indexOf(key);
    if (idx >= 0) {
      // Silently refuse if this would leave zero categories enabled
      // (spec §4.2 — "last-chip tap has no reaction").
      if (this.draft.enabledCategories.length <= 1) {
        return;
      }
      this.draft.enabledCategories.splice(idx, 1);
    } else {
      this.draft.enabledCategories.push(key);
    }
    this.forceRerender();
  }

  private onSave(): void {
    AppStorage.set<GameConfig>(GAME_CONFIG_STORAGE_KEY, cloneGameConfig(this.draft));
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

  private categoryLabel(key: string): string {
    if (key === 'fruit') return '水果';
    if (key === 'place') return '地点';
    if (key === 'home') return '家居';
    return key;
  }

  private categoryId(key: string): string {
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
          Button(this.categoryLabel(key))
            .id(this.categoryId(key))
            .width(72).height(40)
            .fontSize(16)
            .backgroundColor(this.draft.enabledCategories.indexOf(key) >= 0 ? '#FFF4D0' : '#F0F0F0')
            .fontColor(this.draft.enabledCategories.indexOf(key) >= 0 ? '#B8860B' : '#666666')
            .borderWidth(this.draft.enabledCategories.indexOf(key) >= 0 ? 2 : 0)
            .borderColor('#FFB400')
            .onClick((): void => this.toggleCategory(key));
        }, (key: string) => key);
      };
    }
    .margin({ bottom: 24 })
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

Expected: `BUILD SUCCESSFUL`. If there are ArkTS strict-mode errors on `ForEach` or `@Builder` signatures, inline-fix them and re-run.

- [ ] **Step 4.3: Commit**

```bash
git add entry/src/main/ets/pages/ConfigPage.ets
git commit -m "feat(config): full ConfigPage form with steppers, timer chips, categories"
```

---

## Task 5: HomePage gear-icon overlay + navigate to ConfigPage

**Files:**
- Modify: `entry/src/main/ets/pages/HomePage.ets`

- [ ] **Step 5.1: Replace HomePage with Stack-wrapped layout plus gear button**

Overwrite the file (preserve existing title/subtitle/hint/start-button texts verbatim):

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

- [ ] **Step 5.2: Build and verify compile**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@default assembleHap --no-daemon 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5.3: Commit**

```bash
git add entry/src/main/ets/pages/HomePage.ets
git commit -m "feat(config): HomePage gear-icon overlay opens ConfigPage"
```

---

## Task 6: BattlePage reads GameConfig and applies it to engine

**Files:**
- Modify: `entry/src/main/ets/pages/BattlePage.ets`

- [ ] **Step 6.1: Read the current aboutToAppear implementation**

Open `entry/src/main/ets/pages/BattlePage.ets` and locate the `aboutToAppear` body that currently looks roughly like:

```typescript
const gen: QuestionGenerator = new QuestionGenerator(repo);
const engine: BattleEngine = new BattleEngine(gen);
engine.start();
```

- [ ] **Step 6.2: Replace the engine construction with config-aware projection**

Add imports near the top of the file (in the existing import block):

```typescript
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  cloneGameConfig,
  filterEntriesByCategories
} from '../models/GameConfig';
import { BattleConfig } from '../services/BattleEngine';
import { WordEntry } from '../models/WordEntry';
```

Replace the three lines shown above with:

```typescript
const storedCfg: GameConfig | undefined =
  AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
const cfg: GameConfig = cloneGameConfig(storedCfg !== undefined ? storedCfg : new GameConfig());

// Restrict the word pool to the enabled categories BEFORE handing it
// to QuestionGenerator so both the answer and same-category distractors
// come from the selected subset (spec §5.3).
const filteredEntries: WordEntry[] =
  filterEntriesByCategories(repo.all(), cfg.enabledCategories);
const filteredRepo: WordRepository = new WordRepository();
filteredRepo.setEntries(filteredEntries);

const gen: QuestionGenerator = new QuestionGenerator(filteredRepo);

const bc: BattleConfig = new BattleConfig();
bc.playerMaxHp = cfg.playerMaxHp;
bc.monsterMaxHp = cfg.monsterMaxHp;
bc.monstersTotal = cfg.monstersTotal;
bc.startingSeconds = cfg.startingSeconds;

const engine: BattleEngine = new BattleEngine(gen, bc);
engine.start();
```

If the surrounding variable names (`repo`, `engine`) differ, adapt this block to the exact existing identifiers — do not rename them.

- [ ] **Step 6.3: Build the main HAP to verify compile**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@default assembleHap --no-daemon 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 6.4: Rebuild the ohosTest HAP and re-run the existing UI test suite**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | tail -20
hdc install /Users/bytedance/Projects/happyword/entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap
hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000 -w 240 2>&1 | tail -30
```

Expected: the three existing UI tests (`mainFlow_homeBattleResultHome`, `retryFlow_resultRetryReopensBattlePage`, `winFlow_fifteenCorrectAnswersReachesVictory`) still pass. `Tests run: 3, Failure: 0, Error: 0, Pass: 3`.

If a test fails, diagnose before moving on — the existing coverage depends on defaults matching, which we verified at the unit level in Task 1 (`defaultsMatchEngineDefaults`). A mismatch here means the projection in Step 6.2 has a bug.

- [ ] **Step 6.5: Commit**

```bash
git add entry/src/main/ets/pages/BattlePage.ets
git commit -m "feat(config): BattlePage reads GameConfig and filters word pool"
```

---

## Task 7: UI test helpers (no new tests yet)

**Files:**
- Modify: `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`

- [ ] **Step 7.1: Add helpers and shared constants near the top of the file**

Just below the existing `WORD_MAP` / `tapCorrectAnswer` block (module-scope helpers), append:

```typescript
/**
 * Ten Chinese prompts belonging to the 'fruit' category. When the
 * GameConfig restricts enabledCategories to ['fruit'], every question's
 * prompt MUST be one of these — asserting so makes the category-filter
 * contract explicit and visible in test output.
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
 * Inverse of tapCorrectAnswer: reads the current prompt, resolves the
 * correct English answer via WORD_MAP, then clicks any option button
 * whose text is NOT that answer. QuestionGenerator guarantees three
 * distinct option strings, so a non-correct option always exists.
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

/**
 * Parameterised Config-page driver. Opens ConfigPage from HomePage,
 * steps every field down to target values, picks the timer chip,
 * toggles categories, then hits Save.
 *
 * Preconditions:
 *   - Driver is currently on HomePage (HomeConfigButton visible).
 *   - AppStorage['gameConfig'] still holds defaults (fresh session).
 *
 * Postconditions:
 *   - Driver is back on HomePage (HomeStartButton visible).
 *   - AppStorage['gameConfig'] reflects the passed-in TestGameConfig.
 */
class TestGameConfig {
  playerHp: number = 5;
  monsterHp: number = 3;
  monstersTotal: number = 5;
  timerChipId: string = 'ConfigTimer300s';
  categories: string[] = ['fruit'];
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

  // Categories default is all three enabled. Toggle off any NOT in
  // cfg.categories. Order matters: toggle the wanted category LAST so
  // the "last one cannot be removed" guard never fires during the
  // intermediate toggles (the wanted category stays on throughout).
  const toRemove: string[] = [];
  if (cfg.categories.indexOf('fruit') < 0) { toRemove.push('ConfigCategoryFruit'); }
  if (cfg.categories.indexOf('place') < 0) { toRemove.push('ConfigCategoryPlace'); }
  if (cfg.categories.indexOf('home') < 0) { toRemove.push('ConfigCategoryHome'); }
  for (let i = 0; i < toRemove.length; i++) {
    const c = await driver.findComponent(ON.id(toRemove[i]));
    await c.click();
    await driver.delayMs(80);
  }

  const save = await driver.findComponent(ON.id('ConfigSaveButton'));
  await save.click();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('HomeStartButton'));
}
```

- [ ] **Step 7.2: Rebuild ohosTest HAP to verify the helpers compile**

```bash
cd /Users/bytedance/Projects/happyword && hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL`. No new `it` blocks means the test count stays at 3.

- [ ] **Step 7.3: Commit**

```bash
git add entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets
git commit -m "test(config): add openConfigAndApply, tapWrongAnswer, FRUIT_PROMPTS helpers"
```

---

## Task 8: E2E test — configShortWin_oneShotVictory

**Files:**
- Modify: `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets` (append inside the `describe` block)

- [ ] **Step 8.1: Append the test**

Inside `describe('RoutingFlowUiTest', () => { ... })`, after the existing `winFlow_fifteenCorrectAnswersReachesVictory` test, add:

```typescript
    /**
     * Config-driven short battle that ends in a Win on the very first
     * correct answer: monstersTotal=1, monsterMaxHp=1 means a single
     * 1-damage hit defeats the only monster.
     *
     * Also verifies that GameConfig.enabledCategories propagates through
     * BattlePage into QuestionGenerator — with categories=['fruit'] the
     * prompt MUST be one of the 10 fruit strings; if the filter were
     * bypassed we could see a non-fruit prompt.
     */
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

- [ ] **Step 8.2: Rebuild + install + run**

```bash
cd /Users/bytedance/Projects/happyword && \
  hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | tail -10 && \
  hdc install /Users/bytedance/Projects/happyword/entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap && \
  hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -s class RoutingFlowUiTest#configShortWin_oneShotVictory -s timeout 60000 -w 240 2>&1 | tail -30
```

Expected: `Tests run: 1, Pass: 1`. If hypium does not support single-test filtering via `-s class`, run the full suite and confirm all four tests pass.

- [ ] **Step 8.3: Commit**

```bash
git add entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets
git commit -m "test(config): E2E configShortWin reaches Won via 1 correct tap"
```

---

## Task 9: E2E test — configTimerExpiry_lossOnTimeout

**Files:**
- Modify: `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`

- [ ] **Step 9.1: Append the test**

After the `configShortWin_oneShotVictory` test, add:

```typescript
    /**
     * Timer-driven loss without answering any questions: startingSeconds=3
     * means BattleEngine.tick() (called once per second by BattlePage)
     * transitions status to Lost after ~3 seconds, triggering navigation
     * to ResultPage showing "挑战失败" with 0 correct answers.
     *
     * This is the first on-device coverage of tick()-driven Loss; the
     * existing mainFlow/retryFlow tests use the [debug] end-battle button.
     */
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

      // Do NOT tap any option. Wait past the 3s timer + feedback/nav buffer.
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

- [ ] **Step 9.2: Rebuild + install + run**

Same command pattern as Task 8 Step 8.2, targeting `configTimerExpiry_lossOnTimeout`. Expected: passes in ~7s.

- [ ] **Step 9.3: Commit**

```bash
git add entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets
git commit -m "test(config): E2E configTimerExpiry reaches Lost via tick() timeout"
```

---

## Task 10: E2E test — configHpZero_lossOnWrongAnswers

**Files:**
- Modify: `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`

- [ ] **Step 10.1: Append the test**

After the `configTimerExpiry_lossOnTimeout` test, add:

```typescript
    /**
     * Player-HP-zero loss via one deliberately wrong answer:
     * playerMaxHp=1 means a single wrong tap drops HP to 0 and the
     * engine transitions to Lost on that submitAnswer call.
     *
     * This is the first on-device coverage of the "player HP drained"
     * loss path; prior UI tests end the battle via debug or timeout.
     */
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

- [ ] **Step 10.2: Rebuild + install + run the whole UI suite**

```bash
cd /Users/bytedance/Projects/happyword && \
  hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | tail -10 && \
  hdc install /Users/bytedance/Projects/happyword/entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap && \
  hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000 -w 240 2>&1 | tail -60
```

Expected: `Tests run: 6, Failure: 0, Error: 0, Pass: 6`. All three legacy tests plus the three new E2E tests pass.

- [ ] **Step 10.3: Commit**

```bash
git add entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets
git commit -m "test(config): E2E configHpZero reaches Lost via 1 wrong tap"
```

---

## Task 11: Final verification + push

**Files:** none

- [ ] **Step 11.1: Full unit + codelinter + UI pipeline**

```bash
cd /Users/bytedance/Projects/happyword && \
  hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -30 && \
  codelinter -c ./code-linter.json5 . 2>&1 | tail -30 && \
  hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | tail -10 && \
  hdc install /Users/bytedance/Projects/happyword/entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap && \
  hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000 -w 240 2>&1 | tail -30
```

Expected:
- Unit tests: all pass (including the 5 new ones from Task 1).
- Codelinter: exit 0 (warnings per team policy — do not let errors pass).
- Build: `BUILD SUCCESSFUL`.
- UI tests: `Tests run: 6, Pass: 6`.

If any step fails, classify via `harmony-log-analyzer` / `test-failure-classifier` skills and fix before proceeding.

- [ ] **Step 11.2: Push the branch**

```bash
git push origin cursor/wordmagic-t2-t4-skeleton
```

Expected: clean push, no force needed.

---

## Self-Review

**Spec coverage** — walked through every spec section:
- §3.1 `GameConfig` model: Task 1.
- §3.2 AppStorage contract: Task 2 (seed), Task 4 (ConfigPage reads/writes), Task 6 (BattlePage reads).
- §4 ConfigPage UI, IDs, chips, last-category guard: Task 4.
- §5.1 EntryAbility.onCreate: Task 2.
- §5.2 HomePage gear overlay: Task 5.
- §5.3 BattlePage integration: Task 6.
- §5.4 main_pages.json: Task 3.
- §5.5 Retry flow (no change): covered by Task 6 (BattlePage re-reads on every aboutToAppear) + Task 11 verification via existing retryFlow UI test.
- §6.2 three unit tests: Task 1 (all three authored as sub-assertions, not three `it` blocks — acceptable given they all hit GameConfig).
- §6.3 three UI tests: Tasks 8, 9, 10.

**Placeholder scan** — no "TBD"/"TODO" in any step; every code block contains the exact content an engineer types.

**Type consistency** — cross-checked:
- `GameConfig` fields (`playerMaxHp`, `monsterMaxHp`, `monstersTotal`, `startingSeconds`, `enabledCategories`) match across Task 1 (model), Task 4 (ConfigPage), Task 6 (BattlePage).
- `cloneGameConfig` signature `(GameConfig) => GameConfig` used in Tasks 1, 4, 6.
- `filterEntriesByCategories(entries, categories)` argument order consistent in Tasks 1 (test + impl) and Task 6 (call site).
- `TestGameConfig` field names (`playerHp`, `monsterHp`, `monstersTotal`, `timerChipId`, `categories`) consistent across Tasks 7 (definition/helper) and 8/9/10 (usages).
- `GAME_CONFIG_STORAGE_KEY` used consistently in Tasks 2, 4, 6.
