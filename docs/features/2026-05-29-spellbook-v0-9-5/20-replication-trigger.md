# V0.9.5 Spellbook Codex — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document gates iOS / Android replication. iOS and Android agents must verify the signature block at the bottom is filled in before starting any work in `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

- [x] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: Local Stage 3 run completed with `BUILD SUCCESSFUL`.
- [ ] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence: Not rerun for this trigger; excluded from the merge gate by human approval.
- [x] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: Local Stage 3 HAP build completed with `BUILD SUCCESSFUL`; no `ArkTS:WARN` lines observed.
- [x] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: Local Stage 3 CodeLinter run reported no defects.
- [x] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: `versionName=0.9.4` `versionCode=1009004`
  - To: `versionName=0.9.5` `versionCode=1009005`
- [x] **Feature merged to main**
  - Commit: `4c40843` (`Merge pull request #147 from terryma2024/codex/spellbook-v0-9-5`)
- [ ] **Screenshots refreshed**
  - Files updated under `assets/screenshots/harmonyos/`:
- [x] **Server contracts up to date**
  - Regenerated: N/A for the Harmony client merge; server-side cover generation remains tracked separately.
  - Tests: N/A for the Harmony client merge.
  - Fixture diffs: `scene.spellbookCoverUrl` is documented in `00-design.md`; client replicas must tolerate it.

## 2. Delta Letter

HarmonyOS shipped the Spellbook Codex first and froze these replica-relevant decisions:

- Entry point: home top-bar button `HomeSpellbookButton`.
- Home affordance: the selected pack card renders a 128x128 spellbook cover at `HomePackSpellbookCover`.
- Main route: `SpellbookPage`, opened from home, with `SpellbookBackButton` and `SpellbookTitle`.
- Pack cards: use `SpellbookPackCover_<packId>`, `SpellbookPackProgress_<packId>`, `SpellbookPackRewardButton_<packId>`, and `SpellbookPackRewardClaimed_<packId>`.
- Word cards: use `SpellbookCard_<packId>_<wordId>` plus locked/seen/mastered state identifiers from `00-design.md`.
- Completion rule: a pack with zero words is never complete; otherwise every word must have `memoryState == mastered`.
- Reward rule: claiming a complete pack grants 50 coins once per `packId`, persisted locally for V0.9.5.
- Cover rule: bundled pack cover first, then `scene.spellbookCoverUrl` if available, then bundled default cover.
- Asset source: copy the six Harmony cover PNGs from `harmonyos/entry/src/main/resources/rawfile/spellbook_covers/`.
- Version: replicas move to `0.9.5 / 1009005`.

## 3. Open Questions for the Replicas

No replica-specific questions are known during Stage 1. If HarmonyOS stabilization uncovers one, update `00-design.md` first and then record the resolved note here.

## 4. Human-Confirm Signature Block

```yaml
approved_by: matianyi
approved_at: 2026-05-29
replication_approved: true
notes: "Human confirmed after HarmonyOS client merged to main; proceed with iOS and Android replication."
```
