---
name: harmony-autofix-orchestrator
description: Schedules a HarmonyOS autofix loop (build, no-device unit, emulator, UI test) with guards and failure classification. Use when the user wants to fix until green, run a local CI-style loop, hvigor until tests pass, or asks for an orchestrated HarmonyOS build-and-test cycle with human escalation on infra failures.
---

# harmony-autofix-orchestrator

**Role:** **Scheduler only.** It does **not** embed long `hvigorw` or `hdc` command tables—read [`.cursor/dev-commands.md`](.cursor/dev-commands.md) in the repo root for copy-pastable lines.

## Default pipeline order (one full pass)

1. **`harmony-build`**
2. **`harmony-unit-test`** (no device / Local only; see manifest)
3. **`harmony-emulator-manage`**
4. **`harmony-ui-test`**

Rationale: fail compile early; run **no-device** unit tests **before** starting the simulator to save time; then device; then on-device/Instrument and UI.

## After any failure in a pass

1. **`harmony-log-analyzer`**
2. **`test-failure-classifier`** (type + **tier** only)
3. If `human_required` → **stop** with a user checklist; **no** file edits in that turn
4. Else → **`harmony-fix-strategy`** (what may change, how) within tier rules
5. **`autoloop-guard`:** count rounds; exit if over **max rounds** or **same error** repeats
6. **`safe-command-policy`** before every new shell run

## Guards

- Load **`autoloop-guard`**, **`safe-command-policy`**, **`test-failure-classifier`** at appropriate points; do not merge their policies into this file—delegate.

## Rerun rule

- After a fix, re-run from the **failed phase** (or from build if the change can affect compile—use judgment: large API changes → from **build**).

## Stop conditions (must end in one of these)

- All phases pass
- `human_required` (signing, device, SDK, OOM, etc.)
- `autoloop-guard` triggers (max rounds / repeated signature)
- User interrupt or `harmony-fix-strategy` says `none — escalate`

## Sub-skills to invoke (project `.cursor/skills/**/SKILL.md` names)

`harmony-build` · `harmony-unit-test` · `harmony-emulator-manage` · `harmony-ui-test` · `harmony-log-analyzer` · `harmony-fix-strategy` · `autoloop-guard` · `safe-command-policy` · `test-failure-classifier`
