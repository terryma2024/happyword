# V0.9.3 Learning Plan + Review — iOS Replication Plan

> Inputs: [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
>
> Gate: signed on 2026-05-26 by `matianyi`; `replication_approved: true`.

## Scope

Replicate the HarmonyOS daily learning state, stable daily review snapshot, A/B Home status, and review battle configuration on iOS. Do not modify Android.

## Tasks

- [x] Add XCTest coverage for compact day key, review snapshot generation, A/B status matrix, reviewed-word marking, and review monster count.
- [x] Extend iOS learning stats with review-planning fields and latest outcome.
- [x] Add daily learning state models, queue builder, status reducer, and local persistence.
- [x] Wire Home and Battle to ensure the daily snapshot, mark pack wins, mark reviewed words, and use the new review battle timer/monster count.
- [x] Update TodayPlan/Home stable identifiers and A/B-aware copy.
- [x] Bump iOS version metadata to `0.9.3` / `1009003` in `project.yml` and code constants.
- [x] Run focused unit tests, then iOS build/test commands from `.cursor/ios-dev-commands.md`.

## Verification

- `cd ios && xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameTests/LocalGrowthTests/testDailyLearningDayKeyUsesCompactLocalYYYYMMDD -only-testing:WordMagicGameTests/LocalGrowthTests/testReviewSnapshotUsesPreDayStatsAndReasonPriority -only-testing:WordMagicGameTests/LocalGrowthTests/testReviewSnapshotCapsAtFiftyWords -only-testing:WordMagicGameTests/LocalGrowthTests/testHomeDailyStatusUsesABMatrix -only-testing:WordMagicGameTests/LocalGrowthTests/testDailyLearningStateServiceMarksWinsAndReviewedWords -only-testing:WordMagicGameTests/LocalGrowthTests/testReviewMonsterCountUsesWordCountHpAndConfiguredCap -derivedDataPath /private/tmp/wordmagic-dd` — passed, 6 tests.
- `cd ios && xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameTests/BattleStartTests -derivedDataPath /private/tmp/wordmagic-dd` — passed, 5 tests.
- `cd ios && xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameTests -derivedDataPath /private/tmp/wordmagic-dd` — passed, 166 tests.
- `cd ios && xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameUITests/WordMagicGameUITests/testReviewToolbarShowsEmptyToastAndExcludesSameDayWrongWord -derivedDataPath /private/tmp/wordmagic-dd` — passed, 1 test.
- `cd ios && xcodebuild build -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/wordmagic-dd` — passed.
- `git diff --check` — passed.

## Follow-up

- `/opt/homebrew/bin/xcodegen` is unavailable on this machine, so `ios/WordMagicGame.xcodeproj/project.pbxproj` was not regenerated after `ios/project.yml` changed. The generated Xcode project still contains `MARKETING_VERSION = 0.9.2` and `CURRENT_PROJECT_VERSION = 1009002`; rerun XcodeGen or approve a manual project fallback before release packaging.
