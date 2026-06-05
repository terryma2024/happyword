# Monster Codex Progress v1.0.2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build HarmonyOS v1.0.2 Monster Codex progress: locked entries, encounter/defeat tracking, 50/100 cap-free coin milestones, mystery asset, and first-three Chinese display names.

**Architecture:** `MonsterProgressStore` owns local persistence and pure reward state. `BattlePage` records encounters and defeats by one-based catalog index. `MonsterCodexPage` renders locked/revealed states and claims rewards through a new cap-free `CoinAccount.creditCapFree` API.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI, Hypium unit tests, Recraft V4 Vector SVG asset generation, Hvigor / CodeLinter.

---

### Task 1: Monster Progress Store

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/MonsterProgressStore.ets`
- Create: `harmonyos/entry/src/test/MonsterProgressStore.test.ets`
- Modify: `harmonyos/entry/src/test/List.test.ets`

- [x] **Step 1: Write failing tests**

Add tests that import `MonsterProgressStore`, `parseMonsterProgressSnapshot`, `maskedQuestionMarks`, and `rewardStateForMilestone`. Cover empty parse, invalid record filtering, encounter, defeat, skipped 50-claim catch-up at 100, and duplicate claim prevention.

- [x] **Step 2: Run red test**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: compile failure because `MonsterProgressStore.ets` does not exist.

- [x] **Step 3: Implement minimal store**

Create snapshot and record classes, parser, serializer, in-memory mutation methods, async init/flush using the existing `StringPreferencesLike` test seam, and reward helper methods:

```text
recordEncounter(catalogIndex)
recordDefeat(catalogIndex)
canClaim(catalogIndex, milestone)
markClaimed(catalogIndex, milestone)
rewardStateForMilestone(defeatCount, claimed, milestone)
maskedQuestionMarks(source)
```

- [x] **Step 4: Run green test**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: new progress tests pass with no new failures.

### Task 2: Cap-Free Coin Credit

**Files:**
- Modify: `harmonyos/entry/src/main/ets/services/CoinAccount.ets`
- Modify: `harmonyos/entry/src/test/CoinAccount.test.ets`

- [x] **Step 1: Write failing test**

Add a test that fills the daily cap with `earn`, then calls `creditCapFree('monster-codex:50:1', 50, NOW + 1)` and asserts balance increases by 50 while `todayCoinsEarned` remains at `DAILY_CAP`.

- [x] **Step 2: Run red test**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: compile failure because `creditCapFree` does not exist.

- [x] **Step 3: Implement cap-free credit**

Add `creditCapFree(reason: string, amount: number, nowMs: number): number` to `CoinAccount`. It rejects non-positive amounts, increments `totalCoins`, appends a positive transaction with the reason, schedules save, and does not change `todayCoinsEarned`.

- [x] **Step 4: Run green test**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: coin tests pass with no new failures.

### Task 3: Codex Names and Display Helpers

**Files:**
- Modify: `harmonyos/entry/src/main/ets/data/MonsterCodex.ets`
- Modify: `harmonyos/entry/src/test/MonsterCodex.test.ets`

- [x] **Step 1: Write failing tests**

Change `EXPECTED_FIRST_NAMES` to `['软泥小灵', '书页僵僵', '云眠巨龙']`. Add assertions that first three descriptions use the new names and that keys/assets still match the original catalog.

- [x] **Step 2: Run red test**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: assertion failure because current names are `Slime`, `Zombie`, `Dragon`.

- [x] **Step 3: Implement names**

Update only display name and description text for the first three `MONSTER_CODEX` entries. Keep keys, asset paths, and catalog order unchanged.

- [x] **Step 4: Run green test**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: Monster Codex tests pass.

### Task 4: Codex UI Wiring

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/MonsterCodexPage.ets`
- Test: existing unit helpers from Task 1; ohosTest coverage can follow after manual UI harness setup.

- [x] **Step 1: Initialize progress and coins**

Import `getMonsterProgressStore`, `MonsterProgressStore`, `MonsterRewardState`, and `getCoinAccount`. Initialize both stores in `aboutToAppear`.

- [x] **Step 2: Render locked state**

When `progress.encountered` is false, use `character/monster-mystery-question.svg`, masked name/kind/description, hide `CodexDefeatCount`, and hide both reward buttons.

- [x] **Step 3: Render encountered state**

When encountered, show normal image/name/kind/description, show `CodexDefeatCount`, and always render `CodexReward50Button` and `CodexReward100Button` with disabled, enabled, or claimed labels from reward helpers.

- [x] **Step 4: Claim rewards**

On enabled reward click, call `coinAccount.creditCapFree`, then mark the milestone claimed and flush both stores. Refresh local page state.

- [x] **Step 5: Run unit test verification**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: unit tests remain green.

### Task 5: Battle Encounter and Defeat Wiring

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`
- Modify: `harmonyos/entry/src/main/ets/services/MonsterProgressStore.ets` if a convenience method is useful.

- [x] **Step 1: Initialize progress store**

Add a `MonsterProgressStore` field and initialize it with the page context in `aboutToAppear`.

- [x] **Step 2: Record current monster encounters**

After each `syncFromEngine()` resolves a new `currentMonsterCatalogIndex`, call a guard method that records encounter once per visible catalog transition.

- [x] **Step 3: Record defeats**

In both `onOptionTap` and `handleSpellSubmit`, when `outcome.monsterDefeated` is true, call `recordDefeat(defeatedMonsterCatalogBeforeAnswer)` before or immediately after `showDefeatForMonster`.

- [x] **Step 4: Persist progress**

Flush progress when battle ends and fire-and-forget save after encounter/defeat mutations.

- [x] **Step 5: Run unit test verification**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: unit tests remain green.

### Task 6: Mystery SVG Asset

**Files:**
- Create: `harmonyos/entry/src/main/resources/rawfile/character/monster-mystery-question.svg`
- Create: `assets/icons/monster-mystery-question.svg`
- Modify: `assets/icons/README.md`

- [x] **Step 1: Generate vector**

Run: `node tools/recraft/generate-v4-vector.mjs --prompt "original mysterious magical question mark silhouette for a children's monster codex, transparent background, clean SVG vector game asset, soft blue grey glow, whimsical, no text" --out assets/icons/monster-mystery-question.svg --json generated/recraft/monster-mystery-question.json`

- [x] **Step 2: Validate asset**

Run: `file assets/icons/monster-mystery-question.svg` and `wc -c assets/icons/monster-mystery-question.svg`.

- [x] **Step 3: Copy runtime rawfile**

Copy the retained design source to `harmonyos/entry/src/main/resources/rawfile/character/monster-mystery-question.svg`.

- [x] **Step 4: Update README**

Add an `assets/icons/README.md` entry noting the mystery codex question mark source.

### Task 7: Version and Final Verification

**Files:**
- Modify: `harmonyos/AppScope/app.json5`
- Modify: `harmonyos/entry/oh-package.json5`
- Modify: `harmonyos/release-pre.md` if the existing release checklist must match the new app version.

- [x] **Step 1: Bump version**

Set HarmonyOS `versionName` to `1.0.2`, `versionCode` to `1020001`, and entry package version to `1.0.2`.

- [x] **Step 2: Run no-device unit tests**

Run with sandbox escalation: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: green.

- [x] **Step 3: Run build**

Run with sandbox escalation: `cd harmonyos && hvigorw assembleHap`

Expected: build succeeds and log contains zero `ArkTS:WARN` lines.

- [x] **Step 4: Run CodeLinter**

Run with sandbox escalation: `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`

Expected: no remaining findings in changed files.

- [x] **Step 5: Update trigger evidence**

Fill the successful evidence in `docs/features/2026-06-05-monster-codex-progress-v1-0-2/20-replication-trigger.md` and leave `replication_approved: false` for human sign-off.
