# V0.8.8 — Daily Check-in Rewards — iOS Replication Plan

> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Replication trigger (must carry `replication_approved: true`): [`20-replication-trigger.md`](20-replication-trigger.md)
>
> **Do not redesign.** If the trigger is unsigned, stop.

## Pre-flight: verify the trigger is signed

- [x] Open [`20-replication-trigger.md`](20-replication-trigger.md) and confirm `replication_approved: true` with a non-empty `approved_by` and `approved_at`.
- [x] If missing, stop and ask the human owner. Do not edit iOS source.

## Scope After Signature

- [x] Translate `CheckInSnapshot`, local store, cloud sync, result-row, Home entry, and calendar UI from the signed Harmony delta letter.
- [x] Preserve all stable IDs from `00-design.md` §5 as SwiftUI `accessibilityIdentifier` strings.
- [x] Add XCTest counterparts for trigger §2.5.

## Verification

- [x] `xcodebuild build -project ios/WordMagicGame.xcodeproj -scheme WordMagicGame -destination generic/platform=iOS -derivedDataPath /private/tmp/happyword-ios-dd CODE_SIGNING_ALLOWED=NO`
  - Evidence: 2026-05-24 `** BUILD SUCCEEDED **`.
- [x] `xcodebuild test -project ios/WordMagicGame.xcodeproj -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' -derivedDataPath /private/tmp/happyword-ios-dd -only-testing:WordMagicGameTests/LocalGrowthTests/testCheckInStoreAwardsWeeklyBonusOnceAfterSevenDayStreak -only-testing:WordMagicGameTests/LocalGrowthTests/testCheckInCalendarWeeksRebuildForVisibleMonth -only-testing:WordMagicGameTests/CloudSyncTests/testCheckInSyncPayloadMatchesContractShape`
  - Evidence: 2026-05-24 `Executed 3 tests, with 0 failures`.
