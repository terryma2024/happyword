# V0.9.3 Learning Plan + Review — Parity Checklist

> Source of truth: [`00-design.md`](00-design.md)
>
> Replication gate: [`20-replication-trigger.md`](20-replication-trigger.md)

## 1. Behavior Parity

| Parity item | HarmonyOS | iOS | Android | Evidence |
| --- | --- | --- | --- | --- |
| Daily state uses local `YYYYMMDD` day key. | [x] | [x] | [x] | Harmony unit coverage in `DailyLearningStateService.test.ets`; iOS `LocalGrowthTests`; Android `DailyLearningStateServiceTest`. |
| Today review snapshot is stable within a day and excludes same-day wrong answers. | [x] | [x] | [x] | Harmony UI `ReviewModeUiTest.sameDayWrongAnswerDoesNotUnlockReviewButton`; iOS XCUITest; Android Compose UI. |
| Review queue combines due review, recent wrong, and weak words with max 50. | [x] | [x] | [x] | Platform daily-state unit tests. |
| Home A/B label matrix matches `00-design.md`. | [x] | [x] | [x] | Platform daily-state tests plus Home UI tests. |
| Pack battle win satisfies A only after a win. | [x] | [x] | [x] | Platform coordinator / battle-start tests. |
| Review battle marks reviewed words toward B without treating same-day wrongs as required. | [x] | [x] | [x] | Platform daily-state tests and review UI tests. |
| Daily check-in completion is `A || B`; full adventure completion is `A && B`. | [x] | [x] | [x] | Platform state reducer tests. |
| Review battle uses 600 seconds and dynamic monster count. | [x] | [x] | [x] | Harmony helper tests; iOS `BattleStartTests`; Android unit tests. |

## 2. Stable IDs

| Stable ID | HarmonyOS | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| `AdventureCardDailyStatusLabel` | [x] | [x] | [x] | Home daily status label. |
| `HomeStartButton` | [x] | [x] | [x] | Pack battle entrance. |
| `HomeReviewButton` | [x] | [x] | [x] | Review battle entrance. |
| `HomeReviewCountBadge` | [x] | [x] | [x] | Remaining review count. |
| `HomeReviewEmptyToast` | [x] | [x] | [x] | No required review battle. |
| `TodayPlanProgressText` | [x] | [x] | [x] | A/B-aware progress copy. |
| `TodayPlanReviewRequiredSection` | [x] | [x] | [x] | Stable required review list. |
| `TodayPlanReviewDone-<wordId>` | [x] | [x] | [x] | Reviewed-row marker. |

## 3. Verification

| Platform | Command | Result |
| --- | --- | --- |
| HarmonyOS | `scripts/run_ui_tests.sh --rebuild` | Pass: `Tests run: 81, Failure: 0, Error: 0, Pass: 81, Ignore: 0`; `OHOS_REPORT_CODE: 0`; `TestFinished-ResultCode: 0`. |
| iOS | `cd ios && xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameUITests -derivedDataPath /private/tmp/wordmagic-dd` | Pass: `Executed 30 tests, with 0 failures (0 unexpected)`. |
| Android | `cd android && env GRADLE_USER_HOME=/Users/matianyi/.gradle ./gradlew connectedDebugAndroidTest` | Pass: `Finished 37 tests`; `37/37 passed, 0 skipped, 0 failed`. |

## 4. Residual Notes

- iOS `project.yml` is bumped to `0.9.3 / 1009003`, but this machine does not have `/opt/homebrew/bin/xcodegen`; regenerate `ios/WordMagicGame.xcodeproj` before release packaging.
- HarmonyOS no-device unit tests were blocked by local `@ohos/hypium` resolution in this worktree, but the full on-device UI suite rebuilt and passed.
- Server contracts were unchanged.
