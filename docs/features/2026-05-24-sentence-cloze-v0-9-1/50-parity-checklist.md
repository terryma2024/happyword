# V0.9.1 — Sentence Cloze — Parity Checklist

> Source of truth: [`00-design.md`](00-design.md)
> Replication gate: [`20-replication-trigger.md`](20-replication-trigger.md)

**Status:** Done. HarmonyOS implemented; iOS / Android replication completed after [`20-replication-trigger.md`](20-replication-trigger.md) was signed with `replication_approved: true` on 2026-05-24. Full UI automation passed on all three platforms on 2026-05-25, and the available screenshot / visual verification evidence is accepted for V0.9.1 closeout.

| Parity item | HarmonyOS | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| `sentence-cloze` question type exists and validates. | [x] | [x] | [x] | iOS `QuestionKind.sentenceCloze`; Android `QuestionKind.SentenceCloze` |
| Default enabled question types include `sentence-cloze`. | [x] | [x] | [x] | Covered by iOS / Android config tests |
| Settings exposes `ConfigQuestionType_sentence-cloze`. | [x] | [x] | [x] | iOS XCUITest + Android Compose UI focused tests |
| Challenge scheduler can select sentence cloze and can disable it. | [x] | [x] | [x] | Challenge pool is now `fill-letter-medium` / `spell` / `sentence-cloze` |
| Sentence cloze generator supports word and phrase matching rules from design §6.2. | [x] | [x] | [x] | Word, phrase, first-match, substring rejection, unique distractors |
| Battle UI exposes `BattleSentenceClozePrompt`, `BattleSentenceClozeZh`, and sentence-cloze option row. | [x] | [x] | [x] | iOS also removed top-level `RootView` accessibility override so nested IDs are visible; iOS option visibility asserted by labels |
| Sentence cloze suppresses automatic answer-word pronunciation while keeping manual speaker replay. | [x] | [x] | [x] | iOS unit coverage; Android battle UI TTS gate mirrors policy |
| Correct and wrong answers use normal Choice damage semantics. | [x] | [x] | [x] | `SentenceCloze` uses existing 3-option answer path |
| All five built-in packs have examples for every word. | [x] | [x] | [x] | iOS JSON packs copied from Harmony rawfiles; Android built-ins populated |
| Sparse remote packs without examples fall back without blocking battle. | [x] | [x] | [x] | iOS / Android sentence-cloze-only fallback tests |
| Changed screenshots / visual checks completed for visible settings and battle screens. | [x] | [x] | [x] | HarmonyOS full UI gate and available refreshed captures accepted; iOS refreshed `sentence-cloze-battle.png`; Android refreshed config + sentence-cloze battle screenshots. |

## Sign-off

- [x] Owner verified all rows above are green.
- [x] Feature linked from [`docs/features/README.md`](../../features/README.md) is marked `Done`.

```yaml
done_by: matianyi / Codex
done_at: 2026-05-26
notes: V0.9.1 sentence cloze is complete across HarmonyOS, iOS, and Android. Screenshot refresh was accepted as visual verification evidence rather than a blocking artifact gate.
```
