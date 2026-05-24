# V0.9.1 — Sentence Cloze — Parity Checklist

> Source of truth: [`00-design.md`](00-design.md)
> Replication gate: [`20-replication-trigger.md`](20-replication-trigger.md)

**Status:** HarmonyOS implemented; iOS / Android replication is blocked until [`20-replication-trigger.md`](20-replication-trigger.md) is fully gated and signed.

| Parity item | HarmonyOS | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| `sentence-cloze` question type exists and validates. | [x] | [ ] | [ ] | `QuestionKind.SentenceCloze`, `Question.isValidSentenceCloze()`, `SentenceClozeGenerator.test.ets` |
| Default enabled question types include `sentence-cloze`. | [x] | [ ] | [ ] | `BattleQuestionTypePolicy.test.ets` |
| Settings exposes `ConfigQuestionType_sentence-cloze`. | [x] | [ ] | [ ] | `ConfigFlow.ui.test.ets` updated; full UI suite still pending |
| Challenge scheduler can select sentence cloze and can disable it. | [x] | [ ] | [ ] | `BattleQuestionScheduler.test.ets` |
| Sentence cloze generator supports word and phrase matching rules from design §6.2. | [x] | [ ] | [ ] | `SentenceClozeGenerator.test.ets` |
| Battle UI exposes `BattleSentenceClozePrompt`, `BattleSentenceClozeZh`, and option IDs. | [x] | [ ] | [ ] | `BattleFlow.ui.test.ets` targeted suite passed |
| Correct and wrong answers use normal Choice damage semantics. | [x] | [ ] | [ ] | `SentenceCloze` uses the existing 3-option `BattleEngine.submitAnswer` path |
| All five built-in packs have examples for every word. | [x] | [ ] | [ ] | `scripts/validate-builtin-examples.mjs` passed |
| Sparse remote packs without examples fall back without blocking battle. | [x] | [ ] | [ ] | `PlanQuestionSource.test.ets` fallback coverage |
| Changed screenshots refreshed for visible settings and battle screens. | [ ] | [ ] | [ ] | |
