# V0.9.1 — Sentence Cloze — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document is the single gate that controls when iOS / Android replication may begin. iOS and Android agents must verify the signature block at the bottom is filled in before starting any work in `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

Paste evidence (paths to logs, commit SHAs, screenshot folders) next to each item before checking it.

- [x] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: 2026-05-25 local run passed, `hvigorw -p module=entry@default test`, `BUILD SUCCESSFUL in 6 s 678 ms`.
- [x] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence: 2026-05-25 local run passed, `scripts/run_ui_tests.sh --rebuild`, `OHOS_REPORT_RESULT: Tests run: 79, Failure: 0, Error: 0, Pass: 79, Ignore: 0`, `OHOS_REPORT_CODE: 0`. Includes `BattleFlow.sentenceClozeQuestionRendersExamplePromptAndOptions` pass in the full suite.
- [x] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: 2026-05-25 local run passed, `hvigorw assembleHap --no-daemon`, `BUILD SUCCESSFUL in 5 s 493 ms`; no `ArkTS:WARN` lines observed.
- [x] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: 2026-05-25 local run: `No defects found in your code.`
- [x] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: `versionName=0.8.8` `versionCode=1008008`
  - To: `versionName=0.9.1` `versionCode=1009001`
- [x] **Feature merged to main**
  - Commit: merged before V0.9.2 closeout; V0.9.2 main commits include V0.9.1 as the preceding baseline.
- [x] **Visual verification complete** — for every screen this feature visibly changed
  - Evidence: 2026-05-25 full UI automation passed on all three platforms; available screenshot assets include `assets/screenshots/ios/sentence-cloze-battle.png`, `assets/screenshots/android/sentence-cloze-battle.png`, and refreshed HarmonyOS screenshots where capture was stable.
  - Note: the HarmonyOS broad screenshot script had unrelated failed/skipped capture steps for non-sentence-cloze states; those are no longer considered a blocker for V0.9.1 completion.
- [x] **Server contracts up to date** — N/A unless implementation changes server schemas.
  - Explanation: No server/OpenAPI/shared contract changes; V0.9.1 reuses existing `example.en` / `example.zh` fields.

## 2. Delta Letter

This section is filled after HarmonyOS implementation and stabilization.

### 2.1 New / changed code

| Layer | HarmonyOS files |
| --- | --- |
| Models | `harmonyos/entry/src/main/ets/models/Question.ets` |
| Services | `SentenceClozeGenerator.ets`, `BattleQuestionTypePolicy.ets`, `BattleQuestionScheduler.ets`, `PlanQuestionSource.ets`, `PronunciationService.ets` |
| Pages / components | `ConfigPage.ets`, `BattlePage.ets`, `ChoiceButton.ets` |
| Tests | `SentenceClozeGenerator.test.ets`, `BattleQuestionTypePolicy.test.ets`, `BattleQuestionScheduler.test.ets`, `PlanQuestionSource.test.ets`, `PronunciationService.test.ets`, `ConfigFlow.ui.test.ets`, `RoutingFlow.ui.test.ets`, `BattleFlow.ui.test.ets` |
| Assets / data | five `harmonyos/entry/src/main/resources/rawfile/data/builtin/*.json` packs; `scripts/validate-builtin-examples.mjs` |

### 2.2 Persistence keys (cross-platform; replicas must match semantics)

| Key | Type | Default | Migration notes |
| --- | --- | --- | --- |
| Existing question-type config | `string[]` | includes `sentence-cloze` when missing/empty | Existing saved non-empty configs are not forcibly migrated. |

### 2.3 Stable IDs introduced or changed

- `ConfigQuestionType_sentence-cloze`
- `BattleSentenceClozePrompt`
- `BattleSentenceClozeZh`
- `BattleOptionsRow_SentenceCloze`
- `BattleSentenceClozeOption_0`
- `BattleSentenceClozeOption_1`
- `BattleSentenceClozeOption_2`

### 2.4 Edge cases discovered during stabilization

- `ChoiceButton.choiceId` must be a `@Prop` when changing option IDs by question kind; otherwise `@Reusable` component reuse can keep stale button IDs.
- `sentence-cloze` must not auto-speak the answer word on question load or transition. Manual `BattleSpeakerButton` replay still speaks the answer when tapped.
- Earlier full ohosTest attempts could hang without an OHOS report on the local runner; after the 2026-05-25 UI-test stabilization pass, the full suite produced `OHOS_REPORT_CODE: 0` with 79/79 passing.

### 2.5 Tests requiring parity counterparts

| HarmonyOS test | iOS counterpart (XCTest / XCUITest) | Android counterpart (JUnit / Compose UI / UIA) |
| --- | --- | --- |
| `SentenceClozeGenerator.test.ets` | Unit tests for matching / validation / fallback | Unit tests for matching / validation / fallback |
| `BattleQuestionTypePolicy.test.ets` | Unit tests for default type policy and eligibility | Unit tests for default type policy and eligibility |
| `BattleQuestionScheduler.test.ets` | Scheduler unit tests for Challenge pool selection and disabling | Scheduler unit tests for Challenge pool selection and disabling |
| `PlanQuestionSource.test.ets` | Plan-source unit tests for sentence-only and fallback behavior | Plan-source unit tests for sentence-only and fallback behavior |
| `PronunciationService.test.ets` | Unit test that sentence cloze suppresses auto-speak while other kinds retain it | Unit test that sentence cloze suppresses auto-speak while other kinds retain it |
| `ConfigFlow.ui.test.ets` | Settings UI test for `sentence-cloze` chip | Settings UI test for `sentence-cloze` chip |
| `BattleFlow.ui.test.ets` | Battle UI test for cloze prompt / Chinese example / options | Battle UI test for cloze prompt / Chinese example / options |

### 2.6 Pitfalls / "do not repeat my mistakes"

- Built-in examples are content, not generator defaults. Replicas should preserve the fallback behavior for remote/family packs without examples rather than requiring every pack to be sentence-cloze-ready.
- Do not route sentence cloze through the generic auto-speak path; it reveals the target word before the learner answers. Keep the speaker button manual-only.
- Do not start iOS / Android replication until full Harmony soft gate and the signature block below are complete.

## 3. Open Questions for the Replicas

None yet. Resolving new questions updates [`00-design.md`](00-design.md) first.

## 4. Human-Confirm Signature Block

> **iOS / Android agents:** if `replication_approved` is missing, blank, or `false`, refuse to start Stage 4 and ask the human owner. Do not proceed.

```yaml
approved_by: matianyi
approved_at: 2026-05-24
replication_approved: true
notes: Human owner confirmed replication_approved true in the Codex thread.
```
