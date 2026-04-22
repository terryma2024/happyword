---
name: harmony-unit-test
description: Runs no-device local unit tests for the HarmonyOS entry module using manifest commands. Use after a successful build and before starting the simulator in an autofix loop, or when fixing Local test failures under entry/src/test.
---

# harmony-unit-test

**Scope:** **No device.** `entry/src/test/**` and Local/ unit targets only. No `hdc`, no `ohosTest` / full UI automation in this step.

## Before running

1. **Build must have succeeded** (or user explicitly re-runs tests only).
2. Read [`.cursor/dev-commands.md`](.cursor/dev-commands.md) section **Unit test (no device)**.
3. Apply **`safe-command-policy`**.

## On failure

- Classify with **`test-failure-classifier`** (expect **unit**).
- If logs suggest **device required**, the manifest is wrong: move that case to the post-emulator / **`harmony-ui-test`** path and update the manifest; do not fake “local” for Instrument tests.

## On success

Proceed to **`harmony-emulator-manage`** in the default autofix order.
