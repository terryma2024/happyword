# ConfigPage & UI-driven Short-Level E2E Tests — Design Spec

- **Date:** 2026-04-23
- **Branch target:** `cursor/wordmagic-t2-t4-skeleton` (extends T8)
- **Status:** Draft, pending user sign-off before writing-plans

## 1. Problem statement

Players (and UI tests) cannot change battle parameters without editing
source. Three consequences:

1. No way to tailor session length for younger players or repeat play.
2. The only route to the `Lost` ResultPage in UI tests is the
   `[debug] end battle` escape hatch. On-device coverage of `tick()`
   timing out, and of player-HP-reaching-zero loss, does not exist.
3. Category filtering (spec §5.1) is technically supported by
   `WordRepository.byCategory` but never exposed.

Goal: add a ConfigPage reachable from HomePage that lets the player
edit five battle knobs, persist them for the current app session,
and use that wiring to author three on-device E2E tests that exercise
Win / Timer-Loss / HP-Zero-Loss end-to-end **without** the debug button.

## 2. Scope

In scope:

- New `GameConfig` model holding five fields.
- New `pages/ConfigPage.ets` with a single-screen landscape form.
- HomePage gains a gear-icon entry to ConfigPage (top-right overlay).
- `AppStorage`-backed read/write path (in-memory, per app-session).
- `BattlePage` reads `GameConfig` on `aboutToAppear` and projects it to
  `BattleConfig` + a category-filtered `WordRepository`.
- Three new UI tests in `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`.

Explicitly out of scope (YAGNI):

- Cross-launch persistence (`@ohos.data.preferences`). AppStorage
  reset-on-kill is acceptable per Q3.
- Per-difficulty presets (easy/normal/hard).
- Category filtering for `QuestionGenerator`'s distractor pool beyond
  what `byCategory` already does internally.
- Combo-burst tuning knobs.

## 3. Data model

### 3.1 `GameConfig`

New file `entry/src/main/ets/models/GameConfig.ets`:

```typescript
export class GameConfig {
  playerMaxHp: number = 5;       // integer, range [1, 10]
  monsterMaxHp: number = 3;      // integer, range [1, 10]
  monstersTotal: number = 5;     // integer, range [1, 10]
  startingSeconds: number = 300; // allowed: 3, 15, 30, 60, 120, 300, 600
  enabledCategories: string[] = ['fruit', 'place', 'home']; // non-empty subset
}

export const GAME_CONFIG_STORAGE_KEY: string = 'gameConfig';

// Discrete timer values (seconds); order matches the chip UI.
export const TIMER_CHOICES: number[] = [3, 15, 30, 60, 120, 300, 600];

// Integer-stepper ranges (inclusive).
export const HP_MIN: number = 1;
export const HP_MAX: number = 10;
export const MONSTER_COUNT_MIN: number = 1;
export const MONSTER_COUNT_MAX: number = 10;

// Known category keys. The first element is the default displayed first.
export const KNOWN_CATEGORIES: string[] = ['fruit', 'place', 'home'];
```

Rationale:

- `GameConfig` is a **value object**. ConfigPage's Save button always
  constructs a brand-new instance, avoiding the ArkUI pitfall where
  `@StorageProp` does not refire when the same object reference is
  re-stored with mutated fields.
- Discrete `TIMER_CHOICES` (not a numeric stepper): ~3s is needed for
  the Timer-Loss test while ~5min is the default full game; a stepper
  traversing that range would require dozens of taps. Seven presets
  cover both extremes with one tap per change.
- All range/choice constants exported so tests and ConfigPage share
  the same truth.

### 3.2 AppStorage contract

| Operation    | Where                               | Notes                                                       |
|--------------|-------------------------------------|-------------------------------------------------------------|
| Initialise   | `EntryAbility.onCreate`             | `AppStorage.setOrCreate(GAME_CONFIG_STORAGE_KEY, new GameConfig())` — guaranteed before any page renders. |
| Read (battle)| `BattlePage.aboutToAppear`          | `AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY)`, fallback to `new GameConfig()` if `undefined`. |
| Read (config)| `ConfigPage.aboutToAppear`          | Same, copied into a local `@State draft` so cancellations don't leak. |
| Write        | ConfigPage "保存" button only       | `AppStorage.set(GAME_CONFIG_STORAGE_KEY, this.draft)` then `router.back()`. |
| Cancel       | ConfigPage "取消" button            | `router.back()` only; AppStorage untouched.                 |

## 4. ConfigPage UI

Landscape, single-screen, no scrolling. Built with the same
`@Entry @Component` pattern as the other three pages.

### 4.1 Layout (landscape wireframe)

```
┌─── 游戏设置  (ConfigTitle) ───────────────────────┐
│                                                   │
│  玩家血量      [ – ]  5  [ + ]                    │
│  怪物血量      [ – ]  3  [ + ]                    │
│  怪物数量      [ – ]  5  [ + ]                    │
│  倒计时    [3s][15s][30s][1m][2m][5m][10m]        │
│  词库类别  [水果 ✓][地点 ✓][家居 ✓]               │
│                                                   │
│           [ 取消 ]        [ 保存 ]                │
└───────────────────────────────────────────────────┘
```

### 4.2 Controls

- **Integer steppers** (3 of them): `–` `value` `+`. At min the `–`
  button is disabled (`enabled(false)`, alpha 0.4); at max, `+` is
  disabled. Step = 1.
- **Timer chips**: 7 toggle buttons in a row. Exactly one is selected
  (highlighted fill). Tapping a different chip switches selection;
  tapping the already-selected chip is a no-op. Null/zero selection
  is impossible because `aboutToAppear` always seeds a valid choice.
- **Category chips**: 3 toggle buttons. Selected = gold border, pale
  fill. Tapping toggles. **If tapping would result in zero selected
  categories, the tap is a no-op** (silently ignored — per user
  choice in brainstorming).
- **Save / Cancel buttons**: 160vp × 52vp, side-by-side, bottom-center.

### 4.3 State management

```typescript
@Entry @Component struct ConfigPage {
  @State private draft: GameConfig = new GameConfig();

  aboutToAppear(): void {
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    this.draft = this.cloneConfig(stored ?? new GameConfig());
  }

  private cloneConfig(src: GameConfig): GameConfig {
    const c = new GameConfig();
    c.playerMaxHp = src.playerMaxHp;
    c.monsterMaxHp = src.monsterMaxHp;
    c.monstersTotal = src.monstersTotal;
    c.startingSeconds = src.startingSeconds;
    c.enabledCategories = src.enabledCategories.slice();
    return c;
  }
}
```

Each UI control mutates `this.draft.xxx` and forces a re-render by
re-assigning `this.draft = this.cloneConfig(this.draft)`. This keeps
the simple-object-identity contract that `@State` depends on.

### 4.4 IDs (test-stable)

Page skeleton:

- `ConfigTitle`, `ConfigSaveButton`, `ConfigCancelButton`

Steppers (one `*Dec` / `*Inc` / `*Value` trio each):

- `ConfigPlayerHpDec` / `ConfigPlayerHpInc` / `ConfigPlayerHpValue`
- `ConfigMonsterHpDec` / `ConfigMonsterHpInc` / `ConfigMonsterHpValue`
- `ConfigMonstersTotalDec` / `ConfigMonstersTotalInc` / `ConfigMonstersTotalValue`

Timer chips:

- `ConfigTimer3s`, `ConfigTimer15s`, `ConfigTimer30s`, `ConfigTimer60s`,
  `ConfigTimer120s`, `ConfigTimer300s`, `ConfigTimer600s`

Category chips:

- `ConfigCategoryFruit`, `ConfigCategoryPlace`, `ConfigCategoryHome`

## 5. Integration points

### 5.1 `EntryAbility.onCreate`

Seed AppStorage once at ability creation so every page can assume a
value exists. Place immediately after window-stage setup:

```typescript
AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, new GameConfig());
```

### 5.2 `pages/HomePage.ets`

Rewrap the existing centred content in a `Stack` with
`alignContent(Alignment.TopEnd)`, and add a gear button overlay:

```typescript
Stack() {
  Column() { /* existing title + subtitle + hint + start button */ }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);

  Button('⚙')
    .id('HomeConfigButton')
    .type(ButtonType.Circle)
    .width(56).height(56)
    .fontSize(28)
    .fontColor('#457B9D')
    .backgroundColor('#EAF2F8')
    .margin({ top: 16, right: 16 })
    .onClick((): void => {
      router.pushUrl({ url: 'pages/ConfigPage' }).catch(...);
    });
}
.alignContent(Alignment.TopEnd)
.width('100%').height('100%');
```

HomePage does not subscribe to `gameConfig`; it displays no
config values.

### 5.3 `pages/BattlePage.aboutToAppear`

Replace the current constructor trio:

```typescript
const cfg: GameConfig =
  AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY) ?? new GameConfig();

// Build a sub-repository limited to the enabled categories so the
// generator's same-category distractor pool respects the filter.
const all: WordEntry[] = repo.all();
const filtered: WordEntry[] = [];
for (let i = 0; i < all.length; i++) {
  if (cfg.enabledCategories.indexOf(all[i].category) >= 0) {
    filtered.push(all[i]);
  }
}
const filteredRepo: WordRepository = new WordRepository();
filteredRepo.setEntries(filtered);

const gen = new QuestionGenerator(filteredRepo);

const bc = new BattleConfig();
bc.playerMaxHp = cfg.playerMaxHp;
bc.monsterMaxHp = cfg.monsterMaxHp;
bc.monstersTotal = cfg.monstersTotal;
bc.startingSeconds = cfg.startingSeconds;
const engine = new BattleEngine(gen, bc);
engine.start();
```

Filtering inline (instead of adding `WordRepository.filterByCategories`)
keeps the change small and self-contained in BattlePage. The existing
`setEntries` test hook is already public for this purpose.

### 5.4 `main_pages.json`

Register the new page:

```json
{ "src": ["pages/HomePage", "pages/BattlePage", "pages/ResultPage", "pages/ConfigPage"] }
```

### 5.5 Retry flow

ResultPage's "再来一局" button (`router.replaceUrl('pages/BattlePage')`)
requires no change: BattlePage's `aboutToAppear` re-reads AppStorage
on every entry, so retries honour the saved config.

### 5.6 Edge-case: tiny word pool

When only one category is enabled the filtered pool is 10 words —
still ≥ 3, so `QuestionGenerator` works. No guard required for v0.1.
If a future change shrinks a category below 3 words, the generator
will throw from `nextQuestion`; a fallback path is out-of-scope here
but noted for the spec log.

## 6. Testing

### 6.1 Existing tests: unaffected

`mainFlow_homeBattleResultHome`, `retryFlow_resultRetryReopensBattlePage`,
`winFlow_fifteenCorrectAnswersReachesVictory` never visit ConfigPage,
so AppStorage stays at its default `GameConfig()` — identical to the
engine's prior defaults. All three should continue to pass with no
edits. We will re-run them to confirm.

### 6.2 New unit tests (`entry/src/test/LocalUnit.test.ets`)

Three additions:

1. `GameConfig_defaultsMatchEngineDefaults`: asserts that a
   newly-constructed `GameConfig` projects to a `BattleConfig` equal
   to current `DEFAULT_*` constants. Protects against divergent
   defaults.
2. `GameConfig_enabledCategoriesFilterProducesExpectedPool`: given a
   fake 30-entry repository, calling the Battlepage-style inline
   filter with `['fruit']` yields 10 entries, all `category=='fruit'`.
3. `GameConfig_cloneIsDeepEnoughToIsolateDraft`: constructs a
   `GameConfig`, clones it via the same helper ConfigPage uses,
   mutates every field on the clone (including
   `enabledCategories.push(...)`), then asserts that the original is
   still equal to its pre-clone snapshot. Guards against accidentally
   sharing the `enabledCategories` array reference, which would make
   "Cancel" leak draft edits into AppStorage.

### 6.3 New UI tests (`entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`)

Three new `it` blocks, sharing a helper `openConfigAndApply(driver, cfg)`.

**Helper data structure**

```typescript
class TestGameConfig {
  playerHp: number = 5;
  monsterHp: number = 3;
  monstersTotal: number = 5;
  timerChipId: string = 'ConfigTimer300s';
  categories: string[] = ['fruit']; // internal category keys
}
```

**Helper contract**

`openConfigAndApply(driver, cfg)`:

1. From HomePage, tap `HomeConfigButton`, wait 800ms.
2. Step `ConfigPlayerHpValue` from 5 down to `cfg.playerHp` by tapping
   `ConfigPlayerHpDec` the right number of times.
3. Same for monster HP and monsters total, starting from current
   AppStorage defaults.
4. Tap the chip `cfg.timerChipId`.
5. Walk the 3 category chips; toggle any whose selected state differs
   from `cfg.categories.includes(catName)`. Respect the "last one
   cannot be unselected" rule by ordering toggles such that at least
   one stays on throughout (toggle on the wanted category first).
6. Tap `ConfigSaveButton`, wait 800ms — back on HomePage.

**Test 1: `configShortWin_oneShotVictory`**

- Config: `playerHp=5, monsterHp=1, monstersTotal=1, timer=60s, categories=['fruit']`.
- Flow: `openConfigAndApply` → tap `HomeStartButton` → wait for
  BattlePage → assert the prompt is one of the 10 fruit Chinese
  strings (proves category filter is live) →
  `tapCorrectAnswer(driver)` once → `delayMs(900)` → assert
  ResultPage.
- Asserts:
  - `ON.text('胜利！')`
  - `ON.text('击败怪物：1 / 1')`
  - `ON.text('正确率：100%')`
- Return home via `ResultHomeButton` and assert `HomeStartButton`.

**Test 2: `configTimerExpiry_lossOnTimeout`**

- Config: `playerHp=5, monsterHp=3, monstersTotal=5, timer=3s, categories=['fruit']`.
- Flow: `openConfigAndApply` → tap `HomeStartButton` → wait for
  BattlePage → do NOT tap any option → `delayMs(3500)` (3s timer +
  navigation buffer) → assert ResultPage.
- Asserts:
  - `ON.text('挑战失败')`
  - `ON.text('击败怪物：0 / 5')`
  - `ON.text('正确率：0%')` (Math.round(0 × 100) = 0)
- Return home via `ResultHomeButton`.

**Test 3: `configHpZero_lossOnWrongAnswers`**

- Config: `playerHp=1, monsterHp=3, monstersTotal=5, timer=60s, categories=['fruit']`.
- Flow: `openConfigAndApply` → tap `HomeStartButton` → wait for
  BattlePage → assert prompt is a fruit word → `tapWrongAnswer(driver)`
  once → `delayMs(900)` → assert ResultPage.
- Asserts:
  - `ON.text('挑战失败')`
  - `ON.text('击败怪物：0 / 5')`
- Return home via `ResultHomeButton`.

**Helper `tapWrongAnswer(driver)`**: reads `BattlePrompt`, looks up the
**correct** English via `WORD_MAP`, then scans `BattleOptionA/B/C` and
clicks the first one whose text does NOT match. Throws if all three
happen to match (impossible with 3 unique options).

**`FRUIT_PROMPTS` set**: the 10 Chinese strings that MUST appear when
`categories=['fruit']`. The prompt-in-fruit assertion in tests 1 and 3
is the explicit contract that category filtering propagates from
AppStorage → BattlePage → QuestionGenerator.

**Timing budget**

| Test                           | Steps                                                         | Budget |
|--------------------------------|---------------------------------------------------------------|--------|
| configShortWin                 | 10 stepper taps + 3 chip taps + Save + 1 game tap             | ~8s    |
| configTimerExpiry              | 1 timer-chip tap + 2 category taps + Save + 3.5s wait         | ~7s    |
| configHpZero                   | 4 stepper taps + 1 category tap + Save + 1 wrong tap          | ~6s    |
| **Total new**                  |                                                               | ~21s   |
| **Total suite (existing + new)**| 33s existing + 21s new                                       | ~54s   |

All tests complete within the current `-s timeout 60000` per-test
budget and the suite stays well under any reasonable wall-clock cap.

## 7. File change summary

| File                                                              | Action                                                  |
|-------------------------------------------------------------------|---------------------------------------------------------|
| `entry/src/main/ets/models/GameConfig.ets`                        | NEW                                                     |
| `entry/src/main/ets/pages/ConfigPage.ets`                         | NEW                                                     |
| `entry/src/main/ets/entryability/EntryAbility.ets`                | seed AppStorage in `onCreate`                           |
| `entry/src/main/ets/pages/HomePage.ets`                           | wrap in `Stack`, add gear-icon overlay                  |
| `entry/src/main/ets/pages/BattlePage.ets`                         | read `GameConfig`, filter repo, build `BattleConfig`    |
| `entry/src/main/resources/base/profile/main_pages.json`           | register `pages/ConfigPage`                             |
| `entry/src/test/LocalUnit.test.ets`                               | 3 new unit tests                                        |
| `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`             | 3 new UI tests + `openConfigAndApply` + `tapWrongAnswer`|

No changes required to `BattleEngine`, `BattleConfig`, `WordRepository`,
`QuestionGenerator`, `ResultPage`, `SessionResult`.

## 8. Risks and mitigations

- **ArkUI `@State` not refiring on mutated object**: always replace
  `this.draft` with a fresh clone on each mutation.
- **AppStorage type-erasure**: `AppStorage.get<GameConfig>` can return
  `undefined` if the key has not been seeded. `EntryAbility.onCreate`
  guarantees seeding, but callers still guard with a default.
- **Stepper repeat-tap slowness in tests**: HP range is 10, so the
  worst case is 9 dec taps per field; well within latency budget.
- **Category filter bypass regression**: if a future change forgets
  to build the filtered repo in BattlePage, Tests 1 and 3 catch it
  via the fruit-prompt assertion.
- **Combo burst on 1-HP monster**: damage 1 still defeats 1-HP monster
  in one hit (no burst needed). Verified by spec §4.3 and existing
  unit tests.

## 9. Self-review checklist outcomes

- **Placeholders:** none.
- **Internal consistency:** Section 5.3 and Section 6.3 agree on
  inline category filter in BattlePage.
- **Scope:** single implementation plan.
- **Ambiguity:** the "last category chip click has no reaction" rule
  is stated explicitly and shown in both UI spec (§4.2) and test
  helper (§6.3).

## 10. Open questions / follow-ups

None blocking. Future work (not this plan):

- Persistence across app restarts (`@ohos.data.preferences`).
- Difficulty presets shortcut.
- Category filter applied to distractor pool only (currently applied
  whole-repo, which is stricter and correct for v0.1).
