# V0.9.3 Learning Plan + Review — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document gates iOS / Android replication. The human owner approved replication on 2026-05-26; remaining soft-gate gaps are listed explicitly so replica agents can proceed with eyes open rather than rediscovering them.

## 1. Soft Gate (machine-checkable)

- [ ] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: attempted on 2026-05-26. The new RED test was verified first, then the post-implementation command failed before business assertions because `@ohos/hypium` could not be resolved for all HarmonyOS test files in this worktree environment.
- [ ] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence: `scripts/run_ui_tests.sh --rebuild` on 2026-05-27 — `Tests run: 81, Failure: 0, Error: 0, Pass: 81, Ignore: 0`, `OHOS_REPORT_CODE: 0`, `TestFinished-ResultCode: 0`.
- [x] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: `hvigorw assembleHap` succeeded on 2026-05-26; `CompileArkTS` completed with no `ArkTS:WARN` lines. HAP was installed to simulator `127.0.0.1:5555`.
- [ ] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: not run for this slice.
- [x] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: `versionName=0.9.2` `versionCode=1009002`
  - To: `versionName=0.9.3` `versionCode=1009003`
- [ ] **Feature merged to main**
  - Commit: branch `codex/v0-9-3-learning-plan-roadmap`, implementation commit `3be4840`.
- [ ] **Screenshots refreshed** — for every screen this feature visibly changed
  - Files updated under `assets/screenshots/harmonyos/`: not refreshed in this slice; UI parity is covered by the three platform UI suites listed in [`50-parity-checklist.md`](50-parity-checklist.md).
- [x] **Server contracts up to date**
  - N/A: no server contract or shared fixture changes.

## 2. Delta Letter

### 2.1 New / changed code

| Layer | HarmonyOS files |
| --- | --- |
| Models | `harmonyos/entry/src/main/ets/services/WrongAnswerStore.ets` (`WordStat.lastOutcome`) |
| Services | `harmonyos/entry/src/main/ets/services/DailyLearningStateService.ets`, `harmonyos/entry/src/main/ets/services/LearningRecorder.ets` |
| Pages | `harmonyos/entry/src/main/ets/pages/HomePage.ets`, `harmonyos/entry/src/main/ets/pages/BattlePage.ets` |
| Tests | `harmonyos/entry/src/test/DailyLearningStateService.test.ets`, `harmonyos/entry/src/test/List.test.ets` |

### 2.2 Persistence keys (cross-platform; replicas must match semantics)

| Key | Type | Default | Migration notes |
| --- | --- | --- | --- |
| `daily_learning_state/snapshot_v1` | JSON object | empty `DailyLearningState` | Day key is local `YYYYMMDD`; regenerate review snapshot when stored day differs from today. |
| `wordmagic_learning/snapshot_v1.stats[].lastOutcome` | string enum: `correct`, `wrong`, `unknown` | `unknown` | Older snapshots infer from `consecutiveWrong > 0`, then `consecutiveCorrect > 0`, else `unknown`. |

### 2.3 Stable IDs introduced or changed

See [`00-design.md`](00-design.md) §5. Replicas should implement the parity IDs verbatim:

| ID | Where | Notes |
| --- | --- | --- |
| `AdventureCardDailyStatusLabel` | Home daily status label | Text renders the full state label, e.g. `请选择一个场景加战斗`, `请点击复习加战斗(n)`, `已完成`. HarmonyOS currently aliases this behavior through existing `AdventureCardBadge`; replicas should expose the new ID directly. |
| `HomeReviewButton` | Home toolbar review entry | Enabled only when today's stable review snapshot has remaining words. |
| `HomeStartButton` | Home pack battle entry | Only pack-battle entrance; winning this satisfies condition A. |
| `HomeReviewCountBadge` | Home review button or nearby badge | Visible when A is true and B is false; displays remaining required review count. |
| `HomeReviewEmptyToast` | Home toast | Shown when the review entry is unavailable because no required review remains. |
| `TodayPlanProgressText` | TodayPlanPage header | Shows A/B-aware daily progress copy. |
| `TodayPlanReviewRequiredSection` | TodayPlanPage | Lists today's stable required review words. |
| `TodayPlanReviewDone-<wordId>` | TodayPlanPage row | Indicates one daily review word has been reviewed today. |

### 2.4 Edge cases discovered during stabilization

- Same-day wrong answers must not enter today's generated review snapshot; snapshot cutoff is local midnight.
- Review battle must resolve words from active pack words as well as the bundled repository, otherwise family/global pack review words can be missing from battle.
- `reviewMonsterCount(0, ...)` returns 1 as a defensive BattleEngine minimum, although Home should not enter review mode with 0 remaining words.
- Existing `TODAY_LAST_COMPLETED_DAY_KEY` is still written for legacy home compatibility, but the new source of truth is `DailyLearningState.packBattleWon && reviewAllDone`.

### 2.5 Tests requiring parity counterparts

| HarmonyOS test | iOS counterpart (XCTest / XCUITest) | Android counterpart (JUnit / Compose UI / UIA) |
| --- | --- | --- |
| `DailyLearningStateService.test.ets` compact `YYYYMMDD` day key | Unit test local day formatter | JVM unit test local day formatter |
| Stable review snapshot excludes same-day wrong answers | Unit test review queue builder | JVM unit test review queue builder |
| Review queue priority: due review, recent wrong, weak word, cap 50 | Unit test review queue builder | JVM unit test review queue builder |
| A/B home label matrix | Unit test state reducer + UI assertion for label | JVM unit test state reducer + Compose UI assertion |
| Mark pack win + reviewed words | Unit test daily state service | JVM unit test daily state repository/service |
| Review monster count from words and HP | Unit test battle config helper | JVM unit test battle config helper |

### 2.6 Pitfalls / "do not repeat my mistakes"

- Do not base today's review button directly on all-time recent wrong ids; use the stable daily snapshot and remaining ids.
- Do not include answers from the current local day when generating today's snapshot.
- Do not treat check-in completion and adventure completion as the same thing: check-in is A or B, adventure completion is A and B.
- Do not depend only on the bundled word repository in review mode; merged active packs may contain the review words.
- Keep the review timer at 600 seconds even if normal battle config uses a different timer.

## 3. Open Questions for the Replicas

- [ ] iOS / Android should confirm whether to preserve any legacy "today completed" local keys for backward compatibility, mirroring HarmonyOS's temporary `TODAY_LAST_COMPLETED_DAY_KEY` write.
- [ ] iOS / Android should confirm current platform version-code mapping before bumping to `0.9.3`.

## 4. Human-Confirm Signature Block

> **iOS / Android agents:** if `replication_approved` is missing, blank, or `false`, refuse to start Stage 4 and ask the human owner. Do not proceed.

```yaml
approved_by: matianyi
approved_at: 2026-05-26
replication_approved: true
notes: "Human owner explicitly said: replication approved. Soft-gate exceptions are documented above."
```
