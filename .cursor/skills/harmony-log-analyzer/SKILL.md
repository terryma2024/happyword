---
name: harmony-log-analyzer
description: Gathers and summarizes failure evidence from Hvigor output, test reports, and hdc hilog in the order defined by the project manifest. Use after any failed build, unit, or UI test step in a HarmonyOS autofix flow.
---

# harmony-log-analyzer

## Source of order

Read **section 5 (Failure artifacts)** in [`.cursor/dev-commands.md`](.cursor/dev-commands.md). Follow that **read order** literally.

## General sequence (if manifest is brief)

1. **Terminal:** last 200–400 lines of the failing command.
2. **Disk:** search `entry/build/**` for `*report*`, `*test*`, or `test-results` style outputs (paths vary; note what you find for this run).
3. **UI/device:** `hdc hilog` (or team-standard filter) after reproducing, if the failure is on-device.

## Output (for `test-failure-classifier` only)

- `excerpt` (key errors, a few short blocks, not the whole build).
- `paths_found`: list of report or log file paths you actually read.
- `failed_phase`: build | codelinter | unit | emulator | ui (which step produced the primary error).

**Do not** assign edit instructions; **`test-failure-classifier`** and **`harmony-fix-strategy`** do that.
