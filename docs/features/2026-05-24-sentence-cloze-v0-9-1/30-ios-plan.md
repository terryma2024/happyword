# V0.9.1 — Sentence Cloze — iOS Replication Plan

> Inputs: [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md), [`50-parity-checklist.md`](50-parity-checklist.md)
>
> Status: **Done**. This file records the completed iOS replication scope and verification evidence.

## Scope

- [x] Verified `replication_approved: true` before starting iOS replication.
- [x] Added `QuestionKind.sentenceCloze`.
- [x] Added sentence template fields and validity checks to the iOS question model.
- [x] Implemented Swift sentence-cloze generation with the HarmonyOS matching rules.
- [x] Added `sentence-cloze` to default policy, eligibility, labels, fallback chains, scheduler, and plan source.
- [x] Rendered settings and battle UI with the stable identifiers defined in [`00-design.md`](00-design.md).
- [x] Suppressed automatic answer-word pronunciation for sentence cloze while keeping manual speaker replay.
- [x] Copied approved built-in examples into all five iOS built-in packs.
- [x] Bumped iOS metadata to `0.9.1 / 1009001`.

## Verification

- [x] Focused XCTest coverage passed for generator, config, scheduler, pronunciation, and built-in packs.
- [x] Focused XCUITest passed for sentence-cloze Battle UI.
- [x] `WordMagicGameUITests` full UI suite passed on 2026-05-25: 28/28.
- [x] iOS parity rows in [`50-parity-checklist.md`](50-parity-checklist.md) are all green.
