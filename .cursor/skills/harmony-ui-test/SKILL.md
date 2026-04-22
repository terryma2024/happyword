---
name: harmony-ui-test
description: Installs HAP and runs on-device or Instrument UI tests (ohosTest, UiTest) per the project manifest. Use when hdc is up and the autofix loop reaches device-dependent tests, or when debugging failed ohosTest cases.
---

# harmony-ui-test

**Scope:** `entry/src/ohosTest/**` and on-device/Instrument tasks. Includes **device-dependent** cases not run in the no-device unit step.

## Before running

1. **Emulator or device** must be available (`harmony-emulator-manage` succeeded or skipped with a target).
2. Read [`.cursor/dev-commands.md`](.cursor/dev-commands.md) section **UI / on-device (Instrument)**.
3. Build artifacts: install the **debug `.hap`** path your build produced (manifest may add exact path pattern).
4. Apply **`safe-command-policy`**.

## Run

- `hdc install` then the manifest’s **on-device** / `ohosTest` / UiTest `hvigorw` task, as recorded for the team’s **DevEco** version.

## On failure

- **`harmony-log-analyzer`**, then **`test-failure-classifier`:** expect **ui** or **env-infra** (or **unit**-like if a non-UI instrument test failed—still use classifier consistently).

## Notes

- Exact Hvigor task names change between SDKs—**the manifest** owns the string; this skill enforces *when* to run, not a hard-coded flag table.
