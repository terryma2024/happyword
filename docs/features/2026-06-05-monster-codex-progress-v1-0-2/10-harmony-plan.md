# Monster Codex Progress v1.0.2 — HarmonyOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
>
> **Run loop:** [`.cursor/skills/harmony-autofix-orchestrator/SKILL.md`](../../../.cursor/skills/harmony-autofix-orchestrator/SKILL.md) drives build -> codelinter -> unit -> emulator -> ohosTest. Commands come from [`.cursor/ohos-dev-commands.md`](../../../.cursor/ohos-dev-commands.md). Do not invent flags.

**Goal:** Implement local Monster Codex encounter, defeat, and milestone reward progress on HarmonyOS for v1.0.2.

**Architecture:** Add a `MonsterProgressStore` service for local persistence and pure display/reward helpers. Wire `BattlePage` / battle lifecycle to record encounter and defeat events, and wire `MonsterCodexPage` to render locked/revealed/reward states. Add a Recraft-generated mystery SVG rawfile and retain its design source under `assets/icons/`.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI, Hypium local tests, ohosTest UI automation.

---

### Task 1: Progress Store and Pure Rules

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/MonsterProgressStore.ets`
- Test: `harmonyos/entry/src/test/MonsterProgressStore.test.ets`
- Modify: `harmonyos/entry/src/test/List.test.ets`

- [ ] Write failing tests for parse defaults, invalid record filtering, encounter, defeat, milestone eligibility, catch-up claims, and duplicate claim prevention.
- [ ] Run focused local tests and confirm they fail for the expected reason.
- [ ] Implement `MonsterProgressStore` and pure helpers.
- [ ] Re-run local tests; expect green.

### Task 2: Codex Display Masking and Names

**Files:**
- Modify: `harmonyos/entry/src/main/ets/data/MonsterCodex.ets`
- Modify / create helper near: `harmonyos/entry/src/main/ets/pages/MonsterCodexPage.ets`
- Test: `harmonyos/entry/src/test/MonsterCodex.test.ets`

- [ ] Write failing tests for the first three Chinese display names and locked-string masking length.
- [ ] Implement display-name changes: `软泥小灵`, `书页僵僵`, `云眠巨龙`.
- [ ] Implement mask helpers that preserve source character counts.
- [ ] Re-run local tests; expect green.

### Task 3: Battle Event Wiring

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`
- Possibly modify: `harmonyos/entry/src/main/ets/services/BattleEngine.ets`
- Test: `harmonyos/entry/src/test/BattleEngine.test.ets` or a focused page-service test if available.

- [ ] Write failing tests or harness coverage proving spawn records encounter and HP-zero records defeat by catalog index.
- [ ] Wire the current monster catalog index into progress recording.
- [ ] Ensure defeated monsters are marked encountered even if encounter recording was missed.
- [ ] Re-run local tests; expect green.

### Task 4: Mystery Asset

**Files:**
- Create: `harmonyos/entry/src/main/resources/rawfile/character/monster-mystery-question.svg`
- Create: `assets/icons/monster-mystery-question.svg`
- Modify: `assets/icons/README.md`

- [ ] Generate the SVG using `tools/recraft/generate-v4-vector.mjs` per the design prompt.
- [ ] Validate output with `file` and `wc -c`.
- [ ] Copy the runtime asset to HarmonyOS rawfile and retained design source to `assets/icons/`.

### Task 5: Codex UI

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/MonsterCodexPage.ets`
- Modify: `harmonyos/entry/src/ohosTest/ets/test/...` for codex UI flow.

- [ ] Initialize and refresh `MonsterProgressStore` on page entry / reward claim.
- [ ] Implement locked state: mystery image, masked text, hidden defeat count, hidden reward buttons.
- [ ] Implement encountered state: defeat count plus always-visible 50/100 reward buttons.
- [ ] Add stable IDs from `00-design.md` §5.
- [ ] Add or update ohosTest cases for locked, disabled, claimable, and claimed states.

### Task 6: Cap-Free Coin Claim

**Files:**
- Modify: `harmonyos/entry/src/main/ets/services/CoinAccount.ets`
- Test: `harmonyos/entry/src/test/CoinAccount.test.ets`
- Test: `harmonyos/entry/src/test/MonsterProgressStore.test.ets`

- [ ] Write failing tests proving codex reward credits are not limited by the daily cap.
- [ ] Add a focused cap-free credit API or reuse external transaction semantics safely.
- [ ] Make progress milestone claim atomic from the user's perspective.
- [ ] Re-run local tests; expect green.

### Task 7: Versioning and Verification

**Files:**
- Modify: `harmonyos/AppScope/app.json5`
- Modify: `harmonyos/entry/oh-package.json5` if required by existing release metadata checks.
- Modify: screenshot assets after manual capture.

- [ ] Bump `versionName` to `1.0.2` and `versionCode` to `1020001`.
- [ ] `cd harmonyos && hvigorw -p module=entry@default test` green.
- [ ] `scripts/run_ui_tests.sh` green.
- [ ] `cd harmonyos && hvigorw assembleHap` produces 0 `ArkTS:WARN` lines.
- [ ] `cd harmonyos && codelinter -c ./code-linter.json5 . --fix` clean.
- [ ] Refresh `assets/screenshots/harmonyos/monster-codex-part1.png` and related codex screenshots.
- [ ] Move on to [`20-replication-trigger.md`](20-replication-trigger.md) and start filling in the gate evidence.
