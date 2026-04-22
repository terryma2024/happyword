---
name: harmony-emulator-manage
description: Verifies or starts a HarmonyOS simulator or USB device via hdc, without running UI tests. Use after no-device unit tests in an autofix loop, or when hdc list targets is empty before on-device steps.
---

# harmony-emulator-manage

**Scope:** Connectivity only—**no** `hvigorw` test execution and **no** full UI test suite.

## Before running

1. Read [`.cursor/dev-commands.md`](.cursor/dev-commands.md) section **Emulator / device**.
2. Apply **`safe-command-policy`**.

## Flow

1. `hdc list targets`.
2. If a valid target exists, apply the manifest **skip** rule: verify stability (optionally a trivial `hdc shell` ping if the team uses it).
3. If empty: follow manifest **(fill)** for starting the emulator, then wait and re-check `hdc list targets` up to a reasonable timeout.

## On failure

- **`test-failure-classifier`:** usually **env-infra**, tier **human_required** if the simulator cannot be started non-interactively.
- Do **not** “fix” code; stop and list device/emulator checklist for the user.

## On success

Proceed to **`harmony-ui-test`**.
