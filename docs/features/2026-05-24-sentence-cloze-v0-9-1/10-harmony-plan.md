# V0.9.1 — Sentence Cloze — HarmonyOS Implementation Plan

> Inputs: [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md), [`50-parity-checklist.md`](50-parity-checklist.md)
>
> Status: **Done**. This file records the completed HarmonyOS implementation scope and verification evidence.

## Scope

- [x] Added `QuestionKind.SentenceCloze`.
- [x] Added `sentenceTemplate` and `sentenceZh` fields to `Question`.
- [x] Implemented `SentenceClozeGenerator` with whole-word matching, phrase matching, first-match replacement, substring rejection, option uniqueness, and fallback behavior.
- [x] Added `sentence-cloze` to question-type policy defaults, settings, eligibility, fallback chains, and the Challenge pool.
- [x] Changed Challenge scheduling to select uniformly over the enabled Challenge pool.
- [x] Wired `PlanQuestionSource` and battle generation to emit sentence-cloze questions when examples exist and fall back safely when they do not.
- [x] Rendered battle UI with `BattleSentenceClozePrompt`, `BattleSentenceClozeZh`, `BattleOptionsRow_SentenceCloze`, and `BattleSentenceClozeOption_0..2`.
- [x] Suppressed automatic answer-word pronunciation for sentence cloze while keeping manual speaker-button replay.
- [x] Backfilled `example.en` and `example.zh` for every word in all five built-in packs.
- [x] Bumped HarmonyOS metadata to `0.9.1 / 1009001`.

## Verification

- [x] `SentenceClozeGenerator` unit coverage passed for matching, phrases, first-match behavior, substring rejection, option uniqueness, and fallback.
- [x] Question-type policy, scheduler, plan-source, pronunciation, and built-in pack unit coverage passed.
- [x] `hvigorw -p module=entry@default test` passed.
- [x] `hvigorw assembleHap` passed with zero `ArkTS:WARN` lines.
- [x] CodeLinter passed with no defects.
- [x] Full ohosTest passed on 2026-05-25: 79/79.
- [x] Harmony parity rows in [`50-parity-checklist.md`](50-parity-checklist.md) are all green.
