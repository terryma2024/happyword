---
name: harmony-build
description: Runs OHPM and Hvigor build steps for this HarmonyOS repo using the project manifest. Use when compiling the app, after dependency changes, or as the first step of an autofix loop.
---

# harmony-build

## Before running

1. Read [`.cursor/dev-commands.md`](.cursor/dev-commands.md) section **Build**.
2. Apply **`safe-command-policy`**: run the exact or manifest-approved `ohpm` / `hvigorw` lines.

## Steps

1. `ohpm install` from **project root** (unless manifest says already satisfied).
2. `hvigorw assembleHap` (assumes `hvigorw` is installed and available on `PATH`; or use the manifest’s module-scoped `assembleHap`).

## On success

Proceed to **`harmony-unit-test`** in a full loop, or as orchestrated.

## On failure

- Capture** stderr/stdout** tail.
- Hand to **`harmony-log-analyzer`** then **`test-failure-classifier`** (expect **compile** or **env-infra** if SDK).

**Do not** start the emulator in this phase.
