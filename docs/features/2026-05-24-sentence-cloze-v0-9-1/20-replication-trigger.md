# V0.9.1 — Sentence Cloze — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document is the single gate that controls when iOS / Android replication may begin. iOS and Android agents must verify the signature block at the bottom is filled in before starting any work in `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

Paste evidence (paths to logs, commit SHAs, screenshot folders) next to each item before checking it.

- [x] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: 2026-05-24 local run passed, `BUILD SUCCESSFUL in 2 s 362 ms`.
- [ ] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence: Targeted `scripts/run_ui_tests.sh --suite BattleFlow --rebuild` passed on 2026-05-24 (`Tests run: 2, Failure: 0, Error: 0, Pass: 2`), covering `sentenceClozeQuestionRendersExamplePromptAndOptions`. Full `scripts/run_ui_tests.sh --rebuild` was attempted but produced no OHOS report after ~18 minutes and was interrupted; keep this full-suite gate unchecked.
- [x] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: 2026-05-24 local run passed, `BUILD SUCCESSFUL in 2 s 718 ms`; no `ArkTS:WARN` lines observed. Hvigor emitted a toolchain `sun.misc.Unsafe` warning, not an ArkTS warning.
- [x] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: 2026-05-24 local run: `No defects found in your code.`
- [x] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: `versionName=0.8.8` `versionCode=1008008`
  - To: `versionName=0.9.1` `versionCode=1009001`
- [ ] **Feature merged to main**
  - Commit: Pending final integration; local feature commits include generator, scheduler, settings, examples, Battle UI, and version/gate updates.
- [ ] **Screenshots refreshed** — for every screen this feature visibly changed
  - Files updated under `assets/screenshots/harmonyos/`: Not refreshed in this implementation pass.
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
- Full ohosTest suite may hang without an OHOS report on the current local runner; use targeted suite evidence for the sentence-cloze path until the broader runner is repaired.

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
approved_by:
approved_at:
replication_approved: false
notes:
```
