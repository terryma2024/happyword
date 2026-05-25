# <Feature Name> — HarmonyOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
>
> **Run loop:** [`.cursor/skills/harmony-autofix-orchestrator/SKILL.md`](../../../.cursor/skills/harmony-autofix-orchestrator/SKILL.md) drives build → codelinter → unit → emulator → ohosTest. Commands come from [`.cursor/ohos-dev-commands.md`](../../../.cursor/ohos-dev-commands.md). Do not invent flags.

**Goal:** <one sentence>

**Architecture:** <2-3 sentences naming the new services/components and how they slot into existing HarmonyOS code.>

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI, Hypium local tests, ohosTest UI automation.

---

### Task 1: <name>

**Files:**
- Create: `harmonyos/entry/src/main/ets/...`
- Modify: `harmonyos/entry/src/main/ets/...`
- Test: `harmonyos/entry/src/test/...`

- [ ] Write or update failing tests that pin the behavior in the design doc.
- [ ] Run local tests and confirm they fail for the expected reason.
- [ ] Implement the smallest change that makes the new tests pass.
- [ ] Re-run local tests; expect green.

### Task 2: <name>

**Files:**
- Modify: ...
- Test: ...

- [ ] ...
- [ ] ...

### Task N: Wire the UI

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/<Page>.ets`
- Modify: `harmonyos/entry/src/ohosTest/ets/test/<Flow>.ui.test.ets`

- [ ] Implement the page changes using the stable IDs from `00-design.md` §5.
- [ ] Add or update ohosTest cases that drive those IDs.
- [ ] Run `scripts/run_ui_tests.sh`; expect `TestFinished-ResultCode: 0`.

### Task N+1: Verification

**Files:**
- Validate the changed HarmonyOS source and tests.

- [ ] `cd harmonyos && hvigorw -p module=entry@default test` green.
- [ ] `scripts/run_ui_tests.sh` green.
- [ ] `cd harmonyos && hvigorw assembleHap` produces 0 `ArkTS:WARN` lines.
- [ ] `cd harmonyos && codelinter -c ./code-linter.json5 . --fix` clean.
- [ ] Bump [`harmonyos/AppScope/app.json5`](../../../harmonyos/AppScope/app.json5) `versionName` and `versionCode`.
- [ ] Refresh affected screens via `python3 scripts/capture_harmony_screenshots.py`.
- [ ] If server contract changed: run [`tools/contracts/export_openapi.py`](../../../tools/contracts/export_openapi.py) and `pytest tests/test_shared_contracts.py`.
- [ ] Move on to [`20-replication-trigger.md`](20-replication-trigger.md) and start filling in the gate evidence.
