# Example Stable-ID Toggle — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document is the single gate that controls when iOS / Android replication may begin. iOS and Android agents must verify the signature block at the bottom is filled in before starting any work in `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

- [x] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: `harmonyos/entry/build/.../reports/test/TEST-LocalUnit.xml` (3 new cases under `WrongAnswerCue` describe block)
- [x] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence: `TestFinished-ResultCode: 0`, `OHOS_REPORT_CODE: 0` (3 new cases in `WrongCueToggleFlow`)
- [x] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: `grep 'ArkTS:WARN' build.log` returns no lines
- [x] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: exit 0, no diagnostics in changed files
- [x] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: `versionName=0.6.7.8` `versionCode=1006016`
  - To: `versionName=0.6.7.9` `versionCode=1006017`
- [x] **Feature merged to main**
  - Commit: `<example-merge-sha>`
- [x] **Screenshots refreshed**
  - `assets/screenshots/harmonyos/config-part2.png` (added `ConfigWrongCueRow`)
- [x] **Server contracts up to date** — `N/A` (this feature is device-local; no server change).

## 2. Delta Letter

### 2.1 New / changed code

| Layer | HarmonyOS files |
| --- | --- |
| Models | `models/GameConfig.ets` (added `playWrongCue: boolean`, default `true`; clone updated) |
| Services | `services/GameConfigPersistence.ets` (sanitize non-boolean → `true`); `services/AudioService.ets` (branch on `cfg.playWrongCue`) |
| Pages | `pages/ConfigPage.ets` (new row); `pages/BattlePage.ets` (mounts `BattleWrongCueSkippedMarker`) |
| Tests | `entry/src/test/LocalUnit.test.ets` (3 cases); `entry/src/ohosTest/ets/test/WrongCueToggleFlow.ui.test.ets` (3 cases) |

### 2.2 Persistence keys

| Key | Type | Default | Migration notes |
| --- | --- | --- | --- |
| `playWrongCue` | `boolean` | `true` | Missing key on upgrade ⇒ `true`. No snapshot version bump. Sanitize non-boolean to `true`. |

### 2.3 Stable IDs introduced or changed

| ID | Where | Notes |
| --- | --- | --- |
| `ConfigWrongCueRow` | ConfigPage row container | Container only; not a tap target itself. |
| `ConfigWrongCueLabel` | Inside the row | Holds localized label; assert text per locale. |
| `ConfigWrongCueSwitch` | Inside the row | Tap target for UI tests. |
| `BattleWrongCueSkippedMarker` | BattlePage transient view | Mounted for one render frame whenever `playWrongCue` is asked but skipped. |

### 2.4 Edge cases discovered during stabilization

- The marker had to be a transient view (one frame) so a second wrong answer re-mounts it; otherwise UI tests cannot distinguish "two skips" from "one skip". iOS and Android must replicate the same one-frame semantics.
- Mid-battle toggle change is honored on the next call; this required reading `cfg.playWrongCue` lazily inside `AudioService.playWrongCue`, not capturing the value at battle start.

### 2.5 Tests requiring parity counterparts

| HarmonyOS test | iOS counterpart | Android counterpart |
| --- | --- | --- |
| `LocalUnit.test.ets > WrongAnswerCue > defaults to true` | `GameConfigTests.testPlayWrongCueDefaultsToTrue` | `GameConfigTest.playWrongCueDefaultsToTrue` |
| `LocalUnit.test.ets > WrongAnswerCue > sanitizes non-boolean to true` | `GameConfigTests.testSanitizePlayWrongCue` | `GameConfigTest.sanitizePlayWrongCue` |
| `WrongCueToggleFlow > skips marker when toggle off` | `WrongCueUITests.testTogglesSkipMarker` | `WrongCueUITest.togglesSkipMarker` |
| `WrongCueToggleFlow > shows marker absent when toggle on` | `WrongCueUITests.testNoMarkerWhenOn` | `WrongCueUITest.noMarkerWhenOn` |
| `WrongCueToggleFlow > persistence round-trip` | `GameConfigTests.testPersistsAcrossLaunch` | `GameConfigTest.persistsAcrossLaunch` |

### 2.6 Pitfalls / "do not repeat my mistakes"

- Do not capture `cfg.playWrongCue` at battle start; read it inside `playWrongCue` for mid-battle changes to take effect.
- The marker must be unmounted after one frame; otherwise repeated wrong answers do not re-trigger it and tests pass under wrong assumptions.

## 3. Open Questions for the Replicas

None.

## 4. Human-Confirm Signature Block

```yaml
approved_by: SOP authors
approved_at: 2026-05-12
replication_approved: true
notes: Worked-through example for the SOP; not a real shipping feature.
```
