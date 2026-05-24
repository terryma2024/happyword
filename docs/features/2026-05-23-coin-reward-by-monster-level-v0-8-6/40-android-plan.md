# V0.8.6 — 怪物等级积分金币 — Android Replication Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Replication trigger (must carry `replication_approved: true`): [`20-replication-trigger.md`](20-replication-trigger.md)
>
> **Do not redesign.** If you find an ambiguity, file it in `20-replication-trigger.md` §3 and update `00-design.md` first. Then come back here.
>
> **Run loop:** Commands come from [`.cursor/android-dev-commands.md`](../../../.cursor/android-dev-commands.md). Use `./gradlew` from `android/`.

**Goal:** Replicate V0.8.6 monster-level coin reward semantics from HarmonyOS onto Android native after the replication trigger is signed.

**Architecture:** Compose screens render state; pure Kotlin battle/domain code owns reward behavior. Android consumes the frozen design plus the HarmonyOS delta letter and does not redesign the formula.

**Tech Stack:** Kotlin, Jetpack Compose, JUnit, Compose UI tests, UI Automator + adb scripting where Compose tests cannot reach.

---

### Pre-flight: verify the trigger is signed

- [x] Open [`20-replication-trigger.md`](20-replication-trigger.md) and confirm `replication_approved: true` with a non-empty `approved_by` and `approved_at`.
  - Evidence: `approved_by: matianyi`, `approved_at: 2026-05-24`.
- [x] If missing, stop and ask the human owner. Do not proceed past this point.

### Task 1: Lock New Reward Semantics In JUnit

- [x] Add reward value tests for Beginner / Intermediate / Advanced / Super = 1 / 2 / 3 / 4.
- [x] Replace old Bonus `×1.3` expectation with “Bonus kill count remains, extra coin delta is 0.”
- [x] Add kill-time score accumulation coverage: catalog slots 1, 2, 8, 10 produce 1 + 2 + 3 + 4 = 10.
- [x] Add partial-loss coverage: one Advanced kill on a later loss awards 3 coins.

### Task 2: Implement Android Core Logic

- [x] Add `BattleRewardCalc` helpers in `android/app/src/main/java/cool/happyword/wordmagic/core/BattleEngine.kt`.
- [x] Add `BattleState.defeatedMonsterLevelScore` and `SessionResult.monsterLevelScore`.
- [x] Record monster level score at the moment a monster dies, using the catalog index selected for that battle monster.
- [x] Replace final `coinDelta` with `BattleRewardCalc.coinAward(monsterLevelScore)`.
- [x] Remove the retired Bonus extra-coin row from `ResultScreen`.

### Task 3: Version And Verification

- [x] Set Android `versionName=0.8.6` and `versionCode=1008006`.
- [x] Run focused battle reward tests.
  - Evidence: `GRADLE_USER_HOME=/Users/matianyi/.gradle JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.BattleEngineTest` ended with `BUILD SUCCESSFUL` on 2026-05-24.
- [x] Run debug APK build.
  - Evidence: `GRADLE_USER_HOME=/Users/matianyi/.gradle JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ./gradlew assembleDebug` ended with `BUILD SUCCESSFUL` on 2026-05-24.
