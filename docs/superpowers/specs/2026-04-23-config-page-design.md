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
  customWordsRaw: string = '';   // raw multi-line '中文:英文' text (edited on CustomWordsPage)
}

export const GAME_CONFIG_STORAGE_KEY: string = 'gameConfig';

// Discrete timer values (seconds); order matches the chip UI.
export const TIMER_CHOICES: number[] = [3, 15, 30, 60, 120, 300, 600];

// Integer-stepper ranges (inclusive).
export const HP_MIN: number = 1;
export const HP_MAX: number = 10;
export const MONSTER_COUNT_MIN: number = 1;
export const MONSTER_COUNT_MAX: number = 10;

// Built-in category keys (data-driven, loaded from words_v1.json).
// The Custom category is NOT in this list; it is rendered separately.
export const KNOWN_CATEGORIES: string[] = ['fruit', 'place', 'home'];

// Sentinel category key for player-supplied custom words.
export const CUSTOM_CATEGORY_KEY: string = 'custom';

// QuestionGenerator requires >= 3 entries; duplicated here so ConfigPage
// validation can reason about "final pool" size without depending on
// internal engine constants.
export const MIN_POOL_SIZE: number = 3;
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
- `customWordsRaw` is stored as **raw text**, not pre-parsed entries,
  so CustomWordsPage round-trips the exact text the player typed
  (including ordering, casing, whitespace). `parseCustomWords` derives
  `WordEntry[]` on demand at battle start and at Save-time validation.

### 3.2 Custom-word parsing

Exported alongside `GameConfig`:

```typescript
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
    // Accept ASCII ':' or fullwidth '：'.
    let sep: number = trimmed.indexOf(':');
    if (sep < 0) {
      sep = trimmed.indexOf('：');
    }
    if (sep <= 0 || sep >= trimmed.length - 1) {
      continue; // Missing colon, empty left, or empty right.
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
```

Parsing rules (explicit):

1. Line separator is `\n` (also handles `\r\n` because `\r` ends up
   in `trimmed` and is removed by `.trim()`).
2. Accept `:` (ASCII) or `：` (fullwidth). First occurrence wins.
3. Lines with no colon, empty left-half, or empty right-half are
   silently skipped (not surfaced as error — keeps the editor tolerant).
4. IDs are assigned sequentially `custom-0`, `custom-1`, … across
   valid lines only. Duplicate IDs are impossible by construction.
5. Duplicate `meaningZh` entries are kept as-is (no dedup): letting
   the user intentionally repeat a Chinese word pointing to two
   English answers is harmless — QuestionGenerator's distractor logic
   works off the entry list regardless.

### 3.3 Final-pool composition

Battle-time word pool = built-in entries filtered by enabled built-in
categories **plus** custom entries iff `CUSTOM_CATEGORY_KEY` is enabled:

```typescript
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

Both ConfigPage's Save validation and BattlePage's `aboutToAppear` call
this single helper, guaranteeing parity between "what Save said the
pool would be" and "what BattlePage actually uses".

### 3.4 AppStorage contract

### 3.4 AppStorage contract

There is a single AppStorage key, `gameConfig`, holding the whole
`GameConfig` value object. Custom-word raw text is one field of that
object; there is **no** separate storage key for customs.

| Operation    | Where                               | Notes                                                       |
|--------------|-------------------------------------|-------------------------------------------------------------|
| Initialise   | `EntryAbility.onCreate`             | `AppStorage.setOrCreate(GAME_CONFIG_STORAGE_KEY, new GameConfig())` — guaranteed before any page renders. |
| Read (battle)| `BattlePage.aboutToAppear`          | `AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY)`, fallback to `new GameConfig()` if `undefined`. |
| Read (config)| `ConfigPage.aboutToAppear` / `onPageShow` | Same, copied into a local `@State draft`. `onPageShow` refreshes `draft.customWordsRaw` from AppStorage so returning from `CustomWordsPage` reflects its save. |
| Read (custom)| `CustomWordsPage.aboutToAppear`     | Reads `GameConfig.customWordsRaw` into a local `@State rawText`. |
| Write (config)| ConfigPage "保存" (validation-gated)| Build merged `GameConfig` by overlaying draft's stepper / timer / category fields onto a fresh read of the current `GameConfig` (so we never clobber a `customWordsRaw` written by a concurrent `CustomWordsPage` visit), then `AppStorage.set(...)` then `router.back()`. |
| Write (custom)| CustomWordsPage "保存" button      | Clones the current `GameConfig`, overwrites `customWordsRaw`, writes back, `router.back()`. |
| Cancel (both)| "取消" buttons                      | `router.back()` only; AppStorage untouched.                 |

Rationale for the read-merge-write on ConfigPage Save: ConfigPage's
draft doesn't own `customWordsRaw` (CustomWordsPage does). If
ConfigPage wrote its draft verbatim, it would overwrite any custom
edits the user made via the sub-page. The merge keeps each page's
edits independent — ConfigPage owns stepper/timer/category; the
sub-page owns raw custom text.

## 4. ConfigPage UI

Landscape, single-screen, no scrolling. Built with the same
`@Entry @Component` pattern as the other three pages.

### 4.1 Layout (landscape wireframe)

```
┌─── 游戏设置  (ConfigTitle) ────────────────────────────┐
│                                                        │
│  玩家血量      [ – ]  5  [ + ]                         │
│  怪物血量      [ – ]  3  [ + ]                         │
│  怪物数量      [ – ]  5  [ + ]                         │
│  倒计时    [3s][15s][30s][1m][2m][5m][10m]             │
│  词库类别  [水果 ✓][地点 ✓][家居 ✓][自定义  ✎]         │
│                                                        │
│  (hint, hidden unless save blocked)                    │
│  单词池太小（少于 3 个），请启用更多类别或添加自定义词  │
│                                                        │
│           [ 取消 ]        [ 保存 ]                     │
└────────────────────────────────────────────────────────┘
```

### 4.2 Controls

- **Integer steppers** (3 of them): `–` `value` `+`. At min the `–`
  button is disabled (`enabled(false)`, alpha 0.4); at max, `+` is
  disabled. Step = 1.
- **Timer chips**: 7 toggle buttons in a row. Exactly one is selected
  (highlighted fill). Tapping a different chip switches selection;
  tapping the already-selected chip is a no-op. Null/zero selection
  is impossible because `aboutToAppear` always seeds a valid choice.
- **Built-in category chips** (3 of them — 水果 / 地点 / 家居):
  toggle buttons. Selected = gold border, pale fill. Tapping toggles.
  **If tapping would leave zero *total* categories (built-in + custom)
  selected, the tap is a no-op** (silently ignored — per user choice
  in brainstorming).
- **Custom category chip** (`自定义`): 4th toggle in the same row,
  visually identical to the built-in chips. Tapping the chip body
  toggles the `'custom'` key in `enabledCategories` using the same
  "last one cannot be removed" guard that the other chips use.
- **Edit icon** (`✎`) next to the Custom chip: separate tappable
  Button with its own id. Tapping always navigates to
  `pages/CustomWordsPage` regardless of whether Custom is currently
  selected — the player can prepare custom words before opting into
  the category.
- **Validation hint text** (`ConfigValidationHint`): hidden (`Visibility.None`)
  while `draft` passes validation. When the user taps Save and the
  computed final pool (`computeFinalPool`) has fewer than
  `MIN_POOL_SIZE` (3) entries, the hint becomes visible in red, Save
  does NOT write to AppStorage, and the page stays open. Any subsequent
  edit that could conceivably fix the pool (toggling a category on,
  leaving the page to edit customs) re-hides the hint so it doesn't
  persist past its cause.
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

- `ConfigCategoryFruit`, `ConfigCategoryPlace`, `ConfigCategoryHome`,
  `ConfigCategoryCustom` (chip body), `ConfigCategoryCustomEdit`
  (the ✎ icon — navigates to CustomWordsPage)

Validation:

- `ConfigValidationHint` (`Text` node, conditionally visible)

### 4.5 `CustomWordsPage` (sub-page)

New file `entry/src/main/ets/pages/CustomWordsPage.ets`.

Landscape, single-screen, full page (not a modal). Reached only via
the Custom chip's `✎` icon on ConfigPage. Owns `customWordsRaw` end
to end — ConfigPage never mutates this field itself.

#### 4.5.1 Layout (landscape wireframe)

```
┌─── 自定义词表  (CustomWordsTitle) ─────────────────┐
│                                                    │
│  格式：中文:英文，每行一个                         │
│                                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │ 苹果:apple                                   │  │
│  │ 香蕉:banana                                  │  │
│  │ _                                            │  │
│  │                                              │  │
│  │                                              │  │
│  │                                              │  │
│  │                          (CustomWordsTextArea) │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│            [ 取消 ]        [ 保存 ]                │
└────────────────────────────────────────────────────┘
```

#### 4.5.2 Controls

- **TextArea** (`CustomWordsTextArea`): multiline, 80% width, 60% height,
  placeholder `'每行一条，例如：\n苹果:apple\n香蕉:banana'`. Accepts
  any characters; parse validation happens at Save.
- **Cancel button** (`CustomWordsCancelButton`): `router.back()` only.
- **Save button** (`CustomWordsSaveButton`): writes the raw text back
  to `GameConfig.customWordsRaw` via read-merge-write, then
  `router.back()`. **No** pool-size validation happens here — the
  player might save customs they intend to use alongside built-in
  categories, and CustomWordsPage doesn't know the enabled-category
  context. Validation is ConfigPage's job at its own Save.

#### 4.5.3 State management

```typescript
@Entry
@Component
struct CustomWordsPage {
  @State private rawText: string = '';

  aboutToAppear(): void {
    const cfg: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    this.rawText = (cfg !== undefined) ? cfg.customWordsRaw : '';
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
}
```

#### 4.5.4 IDs (test-stable)

`CustomWordsTitle`, `CustomWordsTextArea`, `CustomWordsSaveButton`,
`CustomWordsCancelButton`.

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

// Single helper computes the exact same pool ConfigPage validated at
// Save time — built-in entries filtered by enabled built-in categories,
// plus parsed custom entries when 'custom' is enabled.
const finalEntries: WordEntry[] =
  computeFinalPool(repo.all(), cfg.enabledCategories, cfg.customWordsRaw);
const finalRepo: WordRepository = new WordRepository();
finalRepo.setEntries(finalEntries);

const gen = new QuestionGenerator(finalRepo);

const bc = new BattleConfig();
bc.playerMaxHp = cfg.playerMaxHp;
bc.monsterMaxHp = cfg.monsterMaxHp;
bc.monstersTotal = cfg.monstersTotal;
bc.startingSeconds = cfg.startingSeconds;
const engine = new BattleEngine(gen, bc);
engine.start();
```

Using the shared `computeFinalPool` helper (instead of inlining the
filter like an earlier draft proposed) guarantees parity between
ConfigPage's validation and BattlePage's runtime pool — one function,
one source of truth. The existing `WordRepository.setEntries` test
hook is already public for exactly this kind of projection.

### 5.4 `main_pages.json`

Register the two new pages:

```json
{ "src": ["pages/HomePage", "pages/BattlePage", "pages/ResultPage", "pages/ConfigPage", "pages/CustomWordsPage"] }
```

### 5.5 Retry flow

ResultPage's "再来一局" button (`router.replaceUrl('pages/BattlePage')`)
requires no change: BattlePage's `aboutToAppear` re-reads AppStorage
on every entry, so retries honour the saved config.

### 5.6 Edge-case: tiny word pool

With built-in-only categories, the smallest filtered pool is 10 words
(one category) — still ≥ `MIN_POOL_SIZE`. The minimum-pool guard is
only needed because Custom can bring the pool arbitrarily small:

1. User enables ONLY Custom and the raw text parses to 0–2 valid lines.
2. User enables ONLY Custom, has 5 valid customs, then deletes most of
   them from the sub-page.

ConfigPage's Save-time validation catches both by calling
`computeFinalPool(repo.all(), draft.enabledCategories, currentCustomWordsRaw)`
and refusing to save when the result's length is `< MIN_POOL_SIZE`.
BattlePage therefore never starts a battle with an undersized pool —
the invalid state is unreachable in a legitimate UI flow.

### 5.7 Validation contract (ConfigPage Save)

```typescript
private onSave(): void {
  const storedNow: GameConfig | undefined =
    AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
  const currentCustomRaw: string =
    storedNow !== undefined ? storedNow.customWordsRaw : '';

  // `repo` is the already-loaded WordRepository held on HomePage's
  // module scope; if not loaded yet, Save is trivially valid
  // (defaults are all built-in, pool size ≫ 3).
  const builtin: WordEntry[] = this.loadedBuiltinEntries;
  const finalPool: WordEntry[] = computeFinalPool(
    builtin, this.draft.enabledCategories, currentCustomRaw);

  if (finalPool.length < MIN_POOL_SIZE) {
    this.showHint = true;
    this.forceRerender();
    return;
  }

  // Merge draft (stepper/timer/category) with stored (customWordsRaw).
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
```

The builtin entries are loaded once on ConfigPage `aboutToAppear` via
`WordRepository.loadFromRawfile(...)` — the same path HomePage already
uses — and cached on the page instance. Loading is fast (one JSON file)
and ConfigPage can render the form optimistically before load
completes, since validation only matters at Save time.

## 6. Testing

### 6.1 Existing tests: unaffected

`mainFlow_homeBattleResultHome`, `retryFlow_resultRetryReopensBattlePage`,
`winFlow_fifteenCorrectAnswersReachesVictory` never visit ConfigPage,
so AppStorage stays at its default `GameConfig()` — identical to the
engine's prior defaults. All three should continue to pass with no
edits. We will re-run them to confirm.

### 6.2 New unit tests (`entry/src/test/LocalUnit.test.ets`)

Additions, grouped by concern:

**Defaults / clone / filter:**

1. `GameConfig_defaultsMatchEngineDefaults`: newly-constructed
   `GameConfig` projects to a `BattleConfig` equal to current
   `DEFAULT_*` constants and `customWordsRaw === ''`.
2. `GameConfig_enabledCategoriesFilterProducesExpectedPool`: given a
   30-entry repository, `computeFinalPool(entries, ['fruit'], '')`
   yields 10 entries, all `category=='fruit'`.
3. `GameConfig_cloneIsDeepEnoughToIsolateDraft`: constructs a
   `GameConfig`, clones it, mutates every field on the clone
   (including `enabledCategories.push(...)` and `customWordsRaw`),
   asserts the original is still equal to its pre-clone snapshot.

**parseCustomWords:**

4. `parseCustomWords_emptyReturnsEmpty`: `parseCustomWords('')` and
   `parseCustomWords('\n\n  \n')` both return a zero-length array.
5. `parseCustomWords_acceptsAsciiAndFullwidthColon`: mixed input
   `'苹果:apple\n香蕉：banana'` parses to 2 entries, correct
   `meaningZh` / `word` mapping, both in `CUSTOM_CATEGORY_KEY`.
6. `parseCustomWords_skipsInvalidLines`: input with missing colons,
   empty-left-half, empty-right-half, and trailing whitespace yields
   only the well-formed lines. IDs `'custom-0'`, `'custom-1'` are
   sequential over valid lines only (no gaps).

**computeFinalPool (the BattlePage/ConfigPage shared helper):**

7. `computeFinalPool_customEnabledMergesCustoms`: with enabled
   `['fruit', 'custom']`, 10 fruit entries and raw `'你好:hello'`,
   result length is 11 and the last entry has `category==='custom'`.
8. `computeFinalPool_customDisabledIgnoresRaw`: with enabled
   `['fruit']` and raw `'你好:hello'`, result length is 10. Custom
   words are silently excluded when the category is off, even if
   the raw text has valid entries.
9. `computeFinalPool_customOnlyEmpty`: with enabled `['custom']`
   and raw `''`, result is `[]` (explicit — ConfigPage relies on
   this length for validation).

### 6.3 New UI tests (`entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`)

Four new `it` blocks, sharing helpers `openConfigAndApply(driver, cfg)`
and `openCustomWordsAndSave(driver, rawText)`.

**Helper data structure**

```typescript
class TestGameConfig {
  playerHp: number = 5;
  monsterHp: number = 3;
  monstersTotal: number = 5;
  timerChipId: string = 'ConfigTimer300s';
  categories: string[] = ['fruit']; // internal category keys (may include 'custom')
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
5. Walk the 4 category chips (Fruit / Place / Home / Custom); toggle
   any whose selected state differs from
   `cfg.categories.includes(catName)`. Ordering: toggle-on wanted
   categories FIRST, then toggle-off unwanted ones, so the
   "last-one-cannot-be-unselected" guard never fires mid-helper.
6. Tap `ConfigSaveButton`, wait 800ms — back on HomePage.

`openCustomWordsAndSave(driver, rawText)`:

1. From HomePage, tap `HomeConfigButton`, wait 800ms.
2. Tap `ConfigCategoryCustomEdit`, wait 800ms — driver now on
   CustomWordsPage.
3. Find `CustomWordsTextArea`, clear it (via `inputText('')` or
   tap-select-all-then-type), then `inputText(rawText)`.
4. Tap `CustomWordsSaveButton`, wait 800ms — back on ConfigPage.
5. Caller is now expected to enable the Custom chip (if not already)
   and hit `ConfigSaveButton`; the helper does NOT save ConfigPage
   itself.

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

**Test 4: `configCustomWordsOnly_oneShotVictory`**

- Raw custom text: `'一只狗:dog\n一只猫:cat\n太阳:sun'` (3 valid entries).
- Config after applying: `playerHp=5, monsterHp=1, monstersTotal=1,
  timer=60s, categories=['custom']`.
- Flow:
  1. `openCustomWordsAndSave(driver, '一只狗:dog\n一只猫:cat\n太阳:sun')`
     → returns to ConfigPage.
  2. Toggle Custom chip ON, toggle all built-in chips OFF (in that
     order — wanted category on first), step Player HP / Monster HP /
     Monsters Total / Timer as for Test 1, tap `ConfigSaveButton`.
  3. Tap `HomeStartButton`, wait for BattlePage.
  4. Assert `BattlePrompt` text is one of `'一只狗'`, `'一只猫'`, `'太阳'`
     — proving `parseCustomWords` + `computeFinalPool` + BattlePage
     wire custom text all the way to on-screen prompts.
  5. `tapCorrectAnswer(driver)` — the `WORD_MAP` used by that helper
     is augmented at the top of the test file with the three custom
     pairs so lookup succeeds.
  6. `delayMs(900)` → assert ResultPage + `胜利！` + `1 / 1`.
  7. Return home via `ResultHomeButton`.
- Secondary assertion (before Save): tap `ConfigSaveButton` while
  `categories==['custom']` and raw customs is empty (before step 1)
  to confirm the validation-hint path fires. This is implemented as
  a short initial probe inside the test:
  ```
  openConfigAndApply(driver, {custom-only, no customs yet}) → expect
  ConfigValidationHint visible → ConfigCancelButton → continue to
  the happy-path above.
  ```

**Helper `tapWrongAnswer(driver)`**: reads `BattlePrompt`, looks up the
**correct** English via `WORD_MAP`, then scans `BattleOptionA/B/C` and
clicks the first one whose text does NOT match. Throws if all three
happen to match (impossible with 3 unique options).

**`FRUIT_PROMPTS` set**: the 10 Chinese strings that MUST appear when
`categories=['fruit']`. The prompt-in-fruit assertion in tests 1 and 3
is the explicit contract that category filtering propagates from
AppStorage → BattlePage → QuestionGenerator.

**`CUSTOM_TEST_PROMPTS` set**: `['一只狗', '一只猫', '太阳']` —
asserted in Test 4 as the only legal prompts once `['custom']` is
the sole enabled category.

**Timing budget**

| Test                           | Steps                                                             | Budget |
|--------------------------------|-------------------------------------------------------------------|--------|
| configShortWin                 | 10 stepper taps + 4 chip taps + Save + 1 game tap                 | ~8s    |
| configTimerExpiry              | 1 timer-chip tap + 3 category taps + Save + 3.5s wait             | ~7s    |
| configHpZero                   | 4 stepper taps + 2 category taps + Save + 1 wrong tap             | ~6s    |
| configCustomWordsOnly          | edit-page round-trip + validation probe + steppers + Save + 1 tap | ~14s   |
| **Total new**                  |                                                                   | ~35s   |
| **Total suite (existing + new)**| 33s existing + 35s new                                           | ~68s   |

The suite-level wall-clock stays comfortably under hypium's 240s
global `-w` budget. Per-test, all four new tests fit inside
`-s timeout 60000` (Test 4 is the biggest at ~14s).

## 7. File change summary

| File                                                              | Action                                                                    |
|-------------------------------------------------------------------|---------------------------------------------------------------------------|
| `entry/src/main/ets/models/GameConfig.ets`                        | NEW — value object, constants, `cloneGameConfig`, `parseCustomWords`, `computeFinalPool` |
| `entry/src/main/ets/pages/ConfigPage.ets`                         | NEW — form page with validation                                           |
| `entry/src/main/ets/pages/CustomWordsPage.ets`                    | NEW — sub-page for raw custom-word text                                   |
| `entry/src/main/ets/entryability/EntryAbility.ets`                | seed AppStorage in `onCreate`                                             |
| `entry/src/main/ets/pages/HomePage.ets`                           | wrap in `Stack`, add gear-icon overlay                                    |
| `entry/src/main/ets/pages/BattlePage.ets`                         | read `GameConfig`, build pool via `computeFinalPool`                      |
| `entry/src/main/resources/base/profile/main_pages.json`           | register `pages/ConfigPage` and `pages/CustomWordsPage`                   |
| `entry/src/test/LocalUnit.test.ets`                               | 9 new unit tests (defaults/clone/filter/parse/pool)                       |
| `entry/src/ohosTest/ets/test/RoutingFlow.ui.test.ets`             | 4 new UI tests + `openConfigAndApply` + `openCustomWordsAndSave` + `tapWrongAnswer` |

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
- **Custom words clobber on concurrent edits**: ConfigPage's Save
  could overwrite a `customWordsRaw` written by a prior
  CustomWordsPage visit if it wrote its draft verbatim. Mitigated by
  the read-merge-write in §3.4 and §5.7.
- **Custom text crosses ArkTS 4KB string literal budget in tests**:
  UI Test 4's custom text is well under 100 bytes. If future tests
  use larger inputs, split across multiple `inputText` calls.
- **Hypium `inputText` not clearing prior content**: mitigated by
  explicitly clearing the TextArea before inserting test text (see
  §6.3 helper contract).
- **Fullwidth colon parse failures on non-CJK devices**: UTF-16
  handling in ArkTS is consistent across locales; `indexOf('：')`
  returns the correct byte offset. No mitigation needed but flagged.

## 9. Self-review checklist outcomes

- **Placeholders:** none.
- **Internal consistency:** §5.3 (BattlePage) and §5.7 (ConfigPage
  Save) both compute the battle pool via the single exported
  `computeFinalPool` helper, so Save-time validation and runtime
  never diverge.
- **Scope:** single implementation plan. The Custom-word feature is
  integrated into the same plan (not a separate deliverable) because
  it shares the ConfigPage / AppStorage surface.
- **Ambiguity:** the "last category chip click has no reaction" rule
  now applies to all 4 chips (Fruit / Place / Home / Custom) and is
  stated explicitly in §4.2 and §6.3.
- **Double-entry:** Custom-words raw text has exactly one owner
  (`GameConfig.customWordsRaw`) and one writer (CustomWordsPage).
  ConfigPage only reads it for validation; its Save merges the
  current stored value rather than its own draft field.

## 10. Open questions / follow-ups

None blocking. Future work (not this plan):

- Persistence across app restarts (`@ohos.data.preferences`).
- Difficulty presets shortcut.
- Category filter applied to distractor pool only (currently applied
  whole-repo, which is stricter and correct for v0.1).
- Inline per-line validation feedback on CustomWordsPage (current
  behaviour silently drops invalid lines — acceptable for v0.1).
- Custom-word difficulty selector (all currently pinned to 1).
