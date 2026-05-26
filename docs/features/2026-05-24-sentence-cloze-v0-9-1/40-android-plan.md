# V0.9.1 — Sentence Cloze — Android Replication Plan

> Inputs: [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md), [`50-parity-checklist.md`](50-parity-checklist.md)
>
> Status: **Done**. This file records the completed Android replication scope and verification evidence.

## Scope

- [x] Verified `replication_approved: true` before starting Android replication.
- [x] Added `QuestionKind.SentenceCloze`.
- [x] Added sentence template fields and validity checks to the Android question model.
- [x] Implemented Kotlin sentence-cloze generation with the HarmonyOS matching rules.
- [x] Added `sentence-cloze` to default policy, eligibility, labels, fallback chains, scheduler, and battle generation.
- [x] Rendered settings and battle UI with the stable test tags defined in [`00-design.md`](00-design.md).
- [x] Suppressed automatic TTS for sentence cloze while keeping manual speaker replay.
- [x] Added approved examples to every Android built-in word entry.
- [x] Bumped Android metadata to `0.9.1 / 1009001`.

## Verification

- [x] `testDebugUnitTest` passed.
- [x] `assembleDebug` passed.
- [x] `assembleDebugAndroidTest` passed.
- [x] Focused `connectedDebugAndroidTest` passed for sentence-cloze Battle UI and config.
- [x] Android full connected UI suite passed on 2026-05-25: 34/34.
- [x] Android parity rows in [`50-parity-checklist.md`](50-parity-checklist.md) are all green.
