# V0.8.6 — 怪物等级积分金币 — iOS Replication Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Replication trigger (must carry `replication_approved: true`): [`20-replication-trigger.md`](20-replication-trigger.md)
>
> **Do not redesign.** If you find an ambiguity, file it in `20-replication-trigger.md` §3 and update `00-design.md` first. Then come back here.
>
> **Run loop:** Commands come from [`.cursor/ios-dev-commands.md`](../../../.cursor/ios-dev-commands.md). Use `xcodebuild` from `ios/` and the project's stable DerivedData path.

**Goal:** Replicate V0.8.6 monster-level coin reward semantics from HarmonyOS onto iOS native after the replication trigger is signed.

**Architecture:** SwiftUI views render state; pure Swift battle/domain code owns reward behavior. iOS consumes the frozen design plus the HarmonyOS delta letter and does not redesign the formula.

**Tech Stack:** Swift, SwiftUI, XCTest, XCUITest. Project generated from `ios/project.yml` via XcodeGen.

---

### Pre-flight: verify the trigger is signed

- [x] Open [`20-replication-trigger.md`](20-replication-trigger.md) and confirm `replication_approved: true` with a non-empty `approved_by` and `approved_at`.
  - Evidence: `approved_by: matianyi`, `approved_at: 2026-05-24`.
- [x] If missing, stop and ask the human owner. Do not proceed past this point.

### Task 1: Lock New Reward Semantics In XCTest

- [x] Add reward value tests for Beginner / Intermediate / Advanced / Super = 1 / 2 / 3 / 4.
- [x] Replace old Bonus `×1.3` expectation with “Bonus kill count remains, extra coin delta is 0.”
- [x] Add kill-time score accumulation coverage: catalog slots 1, 2, 8, 10 produce 1 + 2 + 3 + 4 = 10.
- [x] Add partial-loss coverage: one Advanced kill on a later loss awards 3 coins.

### Task 2: Implement iOS Core Logic

- [x] Add `BattleRewardCalc` helpers in `ios/WordMagicGame/Core/BattleEngine.swift`.
- [x] Add `BattleState.defeatedMonsterLevelScore` and `SessionResult.monsterLevelScore`.
- [x] Record monster level score at the moment a monster dies, using the catalog index selected for that battle monster.
- [x] Replace final `coinsEarned` with `BattleRewardCalc.coinAward(monsterLevelScore:)`.
- [x] Remove the retired Bonus extra-coin row from `ResultView`.

### Task 3: Version And Verification

- [x] Set iOS marketing version to `0.8.6` while keeping build `1008006`.
  - Note: XcodeGen is not installed at `/opt/homebrew/bin/xcodegen` on this machine, so `ios/WordMagicGame.xcodeproj/project.pbxproj` was narrowly synced for the `MARKETING_VERSION` value after `ios/project.yml`.
- [x] Run focused battle reward tests.
  - Evidence: `xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameTests/BattleEngineTests -derivedDataPath /private/tmp/wordmagic-dd` passed 12 tests on 2026-05-24.
- [x] Run simulator build.
  - Evidence: `xcodebuild build -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/wordmagic-dd` ended with `** BUILD SUCCEEDED **`; built app Info.plist reports `CFBundleShortVersionString=0.8.6`, `CFBundleVersion=1008006`.
