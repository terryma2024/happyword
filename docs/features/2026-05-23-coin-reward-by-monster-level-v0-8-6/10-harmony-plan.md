# V0.8.6 Monster-Level Coin Reward Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace HarmonyOS battle coin rewards with defeated-monster level score while preserving stars, Bonus monster combat behavior, and existing wallet caps.

**Architecture:** `BattleRewardCalc.ets` becomes the pure level-to-coin helper. `BattleEngine` records `defeatedMonsterLevelScore` at the monster-kill moment and copies it into `SessionResult`; `BattlePage` awards that score instead of stars or Bonus-adjusted stars; `ResultPage` stops showing retired Bonus coin math. Version, feature docs, and roadmap are updated after verification.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI, Hypium local tests, ohosTest UI automation.

---

### Task 1: Pure Reward Helper

**Files:**
- Modify: `harmonyos/entry/src/main/ets/services/BattleRewardCalc.ets`
- Modify: `harmonyos/entry/src/test/BattleRewardCalc.test.ets`

- [x] **Step 1: Write failing tests for level values and retired Bonus multiplier**

```typescript
import { MonsterLevel } from '../main/ets/data/MonsterCatalog';
import {
  coinValueForMonsterLevel,
  computeMonsterLevelCoinAward,
  computeRetiredBonusCoinDelta,
} from '../main/ets/services/BattleRewardCalc';

it('mapsMonsterLevelsToCoinValues', 0, () => {
  expect(coinValueForMonsterLevel(MonsterLevel.Beginner)).assertEqual(1);
  expect(coinValueForMonsterLevel(MonsterLevel.Intermediate)).assertEqual(2);
  expect(coinValueForMonsterLevel(MonsterLevel.Advanced)).assertEqual(3);
  expect(coinValueForMonsterLevel(MonsterLevel.Super)).assertEqual(4);
});

it('usesMonsterLevelScoreAsTheFinalAward', 0, () => {
  expect(computeMonsterLevelCoinAward(9)).assertEqual(9);
  expect(computeMonsterLevelCoinAward(0)).assertEqual(0);
});

it('retiredBonusMultiplierNeverAddsCoins', 0, () => {
  expect(computeRetiredBonusCoinDelta(9, 2, true)).assertEqual(0);
  expect(computeRetiredBonusCoinDelta(9, 2, false)).assertEqual(0);
});
```

- [x] **Step 2: Run tests to verify they fail**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: FAIL because `coinValueForMonsterLevel`, `computeMonsterLevelCoinAward`, and `computeRetiredBonusCoinDelta` do not exist yet.

- [x] **Step 3: Implement the helper**

```typescript
import { MonsterLevel } from '../data/MonsterCatalog';

export function coinValueForMonsterLevel(level: MonsterLevel): number {
  if (level === MonsterLevel.Intermediate) {
    return 2;
  }
  if (level === MonsterLevel.Advanced) {
    return 3;
  }
  if (level === MonsterLevel.Super) {
    return 4;
  }
  return 1;
}

export function computeMonsterLevelCoinAward(monsterLevelScore: number): number {
  if (monsterLevelScore <= 0) {
    return 0;
  }
  return Math.floor(monsterLevelScore);
}

export function computeRetiredBonusCoinDelta(
  _monsterLevelScore: number,
  _bonusKillCount: number,
  _won: boolean,
): number {
  return 0;
}
```

- [x] **Step 4: Run tests to verify green**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: PASS for `BattleRewardCalc`.

### Task 2: Engine Records Monster-Level Score

**Files:**
- Modify: `harmonyos/entry/src/main/ets/models/BattleState.ets`
- Modify: `harmonyos/entry/src/main/ets/models/SessionResult.ets`
- Modify: `harmonyos/entry/src/main/ets/services/BattleEngine.ets`
- Modify: `harmonyos/entry/src/test/LocalUnit.test.ets`

- [x] **Step 1: Write failing engine tests**

```typescript
it('recordsMonsterLevelScoreAtKillTime', 0, () => {
  const cfg: BattleConfig = new BattleConfig();
  cfg.monsterMaxHp = 1;
  cfg.monstersTotal = 4;
  let catalogIndex: number = 1;
  cfg.catalogIndexProvider = (): number => catalogIndex;
  const engine: BattleEngine = engineWithFruit(1, cfg);

  catalogIndex = 1;
  engine.submitAnswer(engine.getState().currentQuestion!.answer);
  catalogIndex = 2;
  engine.submitAnswer(engine.getState().currentQuestion!.answer);
  catalogIndex = 8;
  engine.submitAnswer(engine.getState().currentQuestion!.answer);
  catalogIndex = 10;
  engine.submitAnswer(engine.getState().currentQuestion!.answer);

  const result: SessionResult = engine.buildSessionResult();
  expect(result.monsterLevelScore).assertEqual(10);
});

it('partialLossKeepsOnlyDefeatedMonsterLevelScore', 0, () => {
  const cfg: BattleConfig = new BattleConfig();
  cfg.monsterMaxHp = 1;
  cfg.monstersTotal = 5;
  cfg.playerMaxHp = 1;
  cfg.catalogIndexProvider = (): number => 8;
  const engine: BattleEngine = engineWithFruit(1, cfg);

  engine.submitAnswer(engine.getState().currentQuestion!.answer);
  engine.submitAnswer(pickWrongOption(engine.getState().currentQuestion!));

  const result: SessionResult = engine.buildSessionResult();
  expect(result.status).assertEqual(BattleStatus.Lost);
  expect(result.monsterLevelScore).assertEqual(3);
});
```

- [x] **Step 2: Run tests to verify they fail**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: FAIL because `monsterLevelScore` is not present or remains 0.

- [x] **Step 3: Add state/result fields and increment at kill time**

```typescript
// BattleState.ets
defeatedMonsterLevelScore: number = 0;

// SessionResult.ets
monsterLevelScore: number = 0;

// BattleEngine.ets imports
import { coinValueForMonsterLevel } from './BattleRewardCalc';

// Inside the monsterHp <= 0 block, before spawning the next monster:
const defeatedLevel: MonsterLevel = this.currentMonsterLevel();
this.state_.defeatedMonsterLevelScore += coinValueForMonsterLevel(defeatedLevel);

// buildSessionResult()
r.monsterLevelScore = this.state_.defeatedMonsterLevelScore;
```

- [x] **Step 4: Run tests to verify green**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: PASS for the new engine tests.

### Task 3: Settlement and Result Page

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/ResultPage.ets`
- Modify: `harmonyos/entry/src/main/ets/models/SessionResult.ets`

- [x] **Step 1: Write or update failing tests**

Use the Task 1/2 tests as the safety net for pure logic. No direct `BattlePage` unit seam exists for `applyTodayAdventureRewards`, so implementation must be manually inspected and verified through the full HarmonyOS test suite after code changes.

- [x] **Step 2: Switch settlement to monster-level award**

```typescript
// BattlePage.ets
import { computeMonsterLevelCoinAward } from '../services/BattleRewardCalc';

const awardAmount: number = computeMonsterLevelCoinAward(result.monsterLevelScore);
result.coinsBaseFromStars = awardAmount;
```

Remove the old `computeFinalCoinAward(stars, bonusKillCount, won)` call. Keep `COIN_REASON_TODAY_FIRST` and `'stars'` reason routing unchanged so existing today-completion behavior stays stable.

- [x] **Step 3: Merge the new result field and remove retired Bonus coin UI**

```typescript
// ResultPage.aboutToAppear()
merged.monsterLevelScore = incoming.monsterLevelScore !== undefined
  ? incoming.monsterLevelScore
  : merged.monsterLevelScore;
```

Delete `bonusCoinDelta()`, `bonusCoinRowText()`, and the `BattleResultBonusCoinRow` rendering branch. The result page should still show `ResultCoinsEarned` and `ResultCoinsTotal`.

- [x] **Step 4: Run tests to verify green**

Run: `cd harmonyos && hvigorw -p module=entry@default test`

Expected: PASS with no ArkTS errors in modified files.

### Task 4: Version, Gate Docs, and Roadmap

**Files:**
- Modify: `harmonyos/AppScope/app.json5`
- Modify: `docs/features/2026-05-23-coin-reward-by-monster-level-v0-8-6/20-replication-trigger.md`
- Modify: `docs/features/2026-05-23-coin-reward-by-monster-level-v0-8-6/50-parity-checklist.md`
- Modify: `docs/features/README.md`
- Modify: `docs/WordMagicGame_roadmap.md`

- [x] **Step 1: Bump HarmonyOS version**

```json5
"versionCode": 1008006,
"versionName": "0.8.6"
```

- [x] **Step 2: Update feature docs**

Mark HarmonyOS implementation rows truthfully after test evidence is available. Keep `replication_approved: false` until the human owner signs the trigger.

- [x] **Step 3: Update roadmap after completion**

Add V0.8.6 to `docs/WordMagicGame_roadmap.md` as a new client-only reward-rule feature. State that HarmonyOS is implemented first and iOS/Android remain gated by the signed replication trigger unless they have also been completed.

- [x] **Step 4: Verification commands**

Run:

```sh
cd harmonyos && hvigorw -p module=entry@default test
cd harmonyos && hvigorw assembleHap
cd harmonyos && codelinter -c ./code-linter.json5 . --fix
```

Expected: unit tests green, HAP build has 0 `ArkTS:WARN`, codelinter clean or only applies formatting that is included in the commit.
