---
name: harmony-unit-test
description: Runs no-device local unit tests for the HarmonyOS entry module using manifest commands. Use after a successful build and **codelinter** (in a full loop) and before starting the simulator in an autofix loop, or when fixing Local test failures under entry/src/test.
---

# harmony-unit-test

**Scope:** **No device.** `entry/src/test/**` and Local/ unit targets only. No `hdc`, no `ohosTest` / full UI automation in this step.

## Before running

1. **Build must have succeeded** and, in a full **autofix** pipeline, **`harmony-codelinter`** should have passed (or user explicitly re-runs tests only / skips lint with explicit instruction).
2. **Verify `oh_modules/` exists at project root.** If absent (fresh clone or new git worktree), run `ohpm install` from the project root first. Without it, `hvigorw test` hangs indefinitely in `GenerateUnitTestResult` — the offline Previewer child cannot load `@ohos/hypium` and never emits the `OHOS_REPORT_STATUS: taskconsuming` marker hvigor waits on. See `.cursor/dev-commands.md` section 2 for the detailed symptom/fix.
3. Read [`.cursor/dev-commands.md`](.cursor/dev-commands.md) section **Unit test (no device)**.
4. Apply **`safe-command-policy`**.

## On failure

- Classify with **`test-failure-classifier`** (expect **unit**).
- If logs suggest **device required**, the manifest is wrong: move that case to the post-emulator / **`harmony-ui-test`** path and update the manifest; do not fake “local” for Instrument tests.

## On success

Proceed to **`harmony-emulator-manage`** in the default autofix order.
