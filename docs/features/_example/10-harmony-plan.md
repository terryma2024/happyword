# Example Stable-ID Toggle — HarmonyOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
>
> **Run loop:** [`.cursor/skills/harmony-autofix-orchestrator/SKILL.md`](../../../.cursor/skills/harmony-autofix-orchestrator/SKILL.md) drives build → codelinter → unit → emulator → ohosTest. Commands come from [`.cursor/ohos-dev-commands.md`](../../../.cursor/ohos-dev-commands.md). Do not invent flags.

**Goal:** Add a `playWrongCue` boolean to `GameConfig`, expose a toggle on ConfigPage, and make `AudioService.playWrongCue` honor it.

**Architecture:** Add the field on `GameConfig`, sanitize in `GameConfigPersistence`, render a row on `ConfigPage`, branch in `AudioService.playWrongCue`. Render a hidden `BattleWrongCueSkippedMarker` when the cue is skipped so ohosTest can assert silence.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI, Hypium local tests, ohosTest UI automation.

---

### Task 1: GameConfig field and persistence

**Files:**
- Modify: `harmonyos/entry/src/main/ets/models/GameConfig.ets`
- Modify: `harmonyos/entry/src/main/ets/services/GameConfigPersistence.ets`
- Test: `harmonyos/entry/src/test/LocalUnit.test.ets`

- [x] Add `playWrongCue: boolean` field with default `true`. Update `clone()` and any equality helpers.
- [x] In `GameConfigPersistence`, sanitize a missing or non-boolean value to `true` on load.
- [x] Write unit cases: defaults match spec; sanitization collapses garbage to `true`; round-trip preserves user value.
- [x] Run `cd harmonyos && hvigorw -p module=entry@default test`; expect green.

### Task 2: AudioService branch and skip marker

**Files:**
- Modify: `harmonyos/entry/src/main/ets/services/AudioService.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`

- [x] Branch in `AudioService.playWrongCue` on `cfg.playWrongCue`. When `false`, emit a structured skip event consumed by BattlePage.
- [x] On BattlePage, render an empty `Stack` with `.id('BattleWrongCueSkippedMarker')` while a skip is pending; remove after one render frame so a second wrong answer re-shows it.

### Task 3: ConfigPage row

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/ConfigPage.ets`

- [x] Add the row using stable IDs from `00-design.md` §5: `ConfigWrongCueRow`, `ConfigWrongCueLabel`, `ConfigWrongCueSwitch`.
- [x] Wire the toggle to `GameConfig.playWrongCue`; persist via the existing save path.
- [x] Localized label in en + zh-CN per `00-design.md` §11.

### Task 4: ohosTest coverage

**Files:**
- Create: `harmonyos/entry/src/ohosTest/ets/test/WrongCueToggleFlow.ui.test.ets`
- Modify: `harmonyos/entry/src/ohosTest/ets/test/List.test.ets` (register new suite)

- [x] Test 1: open Config, toggle off, save, open Battle, force a wrong answer, assert `BattleWrongCueSkippedMarker` appears.
- [x] Test 2: toggle on, save, force a wrong answer, assert the marker does **not** appear.
- [x] Test 3: persistence round-trip across page re-entry.
- [x] Run `scripts/run_ui_tests.sh`; expect `TestFinished-ResultCode: 0`.

### Task 5: Verification

- [x] `cd harmonyos && hvigorw -p module=entry@default test` green.
- [x] `scripts/run_ui_tests.sh` green.
- [x] `cd harmonyos && hvigorw assembleHap` produces 0 `ArkTS:WARN` lines.
- [x] `cd harmonyos && codelinter -c ./code-linter.json5 . --fix` clean.
- [x] Bump [`harmonyos/AppScope/app.json5`](../../../harmonyos/AppScope/app.json5) `versionName` (e.g. `0.6.7.8` → `0.6.7.9`) and `versionCode`.
- [x] Refresh `assets/screenshots/harmonyos/config-part2.png` (the screen with the new row) via `python3 scripts/capture_harmony_screenshots.py`.
- [x] Move on to [`20-replication-trigger.md`](20-replication-trigger.md).
