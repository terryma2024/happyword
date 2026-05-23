# V0.8.4 — Battle Balance & Question Pacing — iOS Replication Plan

> **Inputs (frozen):** [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md) (`replication_approved: true`)
>
> **Run loop:** [`.cursor/ios-dev-commands.md`](../../../.cursor/ios-dev-commands.md)

**Goal:** Match Harmony V0.8.4 — default HP 10, Spell wrong-tap −1 HP, `BattleQuestionScheduler` in today/plan battles.

---

### Pre-flight

- [x] `replication_approved: true` in [`20-replication-trigger.md`](20-replication-trigger.md)

### Task 1: Domain

**Files:** `BattleQuestionScheduler.swift`, `BattleQuestionTypePolicy.swift`, `BattleEngine.swift`, `WordRepository.swift` (`PlanQuestionSource`), `GameConfig.swift`

- [x] `BattleQuestionScheduler` + `resolveQuestionTypeWithinPool`
- [x] `PlanQuestionSource` uses scheduler when `enabledQuestionTypes` passed
- [x] `applySpellLetterPenalty()` on `BattleEngine`
- [x] `GameConfig.playerMaxHp` default **10**
- [x] `WordMagicGameTests/Core/BattleQuestionSchedulerTests.swift`

### Task 2: UI

**Files:** `BattleView.swift`, `BattleAnimationEvent.swift`, `AppCoordinator.swift`

- [x] Wrong spell tap → `applySpellLetterPenaltyForAnimation()` + hurt feedback
- [x] Existing stable IDs unchanged (`BattleSpellArea`, HP on fighter card)

### Task 3: XCUITest

- [x] Optional XCUITest smokes explicitly deferred; not a V0.8.4 core parity blocker. Unit/domain parity plus stable runtime IDs cover this pass.

### Task 4: Version

**Files:** `ios/project.yml`

- [x] `MARKETING_VERSION` `0.8.4`; `CURRENT_PROJECT_VERSION` is now `1008006` after the iOS App Store review-fix release train.

### Task 5: Verification

- [x] `xcodebuild test -scheme WordMagicGame -only-testing:WordMagicGameTests/BattleQuestionSchedulerTests`
- [ ] Full `WordMagicGameTests` green (not rerun during 2026-05-23 roadmap hygiene; local Xcode is not active)
- [x] Update [`50-parity-checklist.md`](50-parity-checklist.md)
