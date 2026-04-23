---
name: harmony-codelinter
description: Runs HarmonyOS CodeLinter (codelinter) on the project after a successful HAP build, using code-linter.json5, and fixes reported issues. Use in autofix loops immediately after harmony-build, or when addressing static analysis / code style findings.
---

# harmony-codelinter

**Role:** **Static analysis gate** after compile. It does not replace **`hvigorw`**; it runs **only after** a successful `assembleHap` (or the manifest’s equivalent), unless the user explicitly runs lint-only.

## Before running

1. Read [`.cursor/dev-commands.md`](.cursor/dev-commands.md) section **1) Build** — subsection **CodeLinter (after successful build)** — for the exact command and working directory.
2. Apply **`safe-command-policy`**: use the manifest line; do not invent new `codelinter` flags without updating the manifest.
3. Optional context: in-repo reference [codelinter.md](../../docs/arkts-references/codelinter.md) (command-line options, `--fix`, `--exit-on`).

## When `codelinter` is not on PATH

- Treat as **env-infra**: do not change application code to “skip” lint; report that **DevEco Command Line Tools** (or the environment where `codelinter` is installed) is required, and point to the reference above.
- If the user’s machine has `codelinter` configured, re-run the manifest command after the environment is fixed.

## On success

Proceed to **`harmony-unit-test`** in a full loop (see **`harmony-autofix-orchestrator`**), or continue the pipeline as orchestrated.

## On failure

1. **`harmony-log-analyzer`** (console output of `codelinter` / report file if `-o` was used).
2. **`test-failure-classifier`**: expect **lint**-style or **compile**-adjacent static issues; tier usually **agent_safe** for code fixes, **env-infra** if the tool is missing.
3. If **`harmony-fix-strategy`** allows edits: fix the listed files (prefer `codelinter -c ./code-linter.json5 . --fix` when safe, then hand-fix remaining issues).
4. Re-run from **`codelinter`** (or from **`harmony-build`** if a change may affect compile).

**Do not** start the emulator solely because codelinter failed.

## Project references (ArkTS / tooling)

For deeper context on Hvigor, CodeLinter, state management, and UI patterns, use the copies under [docs/arkts-references/](../../docs/arkts-references/) (see **`harmony-build`** and this skill for entry points).
