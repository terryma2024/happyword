---
name: three-platform-feature-orchestrator
description: Schedules the per-feature lifecycle for HarmonyOS / iOS / Android: intake, design, Harmony build+test, stabilization gate with human approval, parallel iOS+Android replication, parity checklist. Use when adding a new product feature, replicating an approved feature to iOS or Android, or asking "what stage is this feature in?"
---

# three-platform-feature-orchestrator

**Role:** **Scheduler only.** It does **not** embed long command tables — read [`.cursor/ohos-dev-commands.md`](.cursor/ohos-dev-commands.md), [`.cursor/ios-dev-commands.md`](.cursor/ios-dev-commands.md), and [`.cursor/android-dev-commands.md`](.cursor/android-dev-commands.md) for copy-pastable lines. It does **not** invent process — read [`docs/sop/00-three-platform-feature-sop.md`](../../docs/sop/00-three-platform-feature-sop.md) for the lifecycle.

## Inputs

- A task description that names a feature (or asks to start a new one).
- The feature folder under `docs/features/<feature-id>/` if it exists.

## Stage selection (one decision)

1. If the task asks to start a new feature → **Stage 0**.
2. Else, open the feature folder. The current stage is the lowest-numbered file that still has unchecked `- [ ]` items.
   - `00-design.md` open → **Stage 1**.
   - `10-harmony-plan.md` open → **Stage 2**.
   - `20-replication-trigger.md` open → **Stage 3**.
   - `30-ios-plan.md` open → **Stage 4a**.
   - `40-android-plan.md` open → **Stage 4b**.
   - `50-parity-checklist.md` has red rows → **Stage 5**.
   - All five files are fully checked → feature is **Done**; if the task is a parity bug, switch to `60-followups.md`.

## Stage actions

- **Stage 0 (Intake).** Allocate `<feature-id>`; copy [`docs/sop/templates/`](../../docs/sop/templates/) into `docs/features/<feature-id>/`; add a row to [`docs/features/README.md`](../../docs/features/README.md). Stop and ask the user to fill in motivation if the design template's §1 is empty.
- **Stage 1 (Design).** Drive `00-design.md` to completion. Pay special attention to §5 (stable IDs) — that is the parity contract.
- **Stage 2 (Harmony plan + impl).** Delegate execution to [`harmony-autofix-orchestrator`](../harmony-autofix-orchestrator/SKILL.md). Do not duplicate its loop here.
- **Stage 3 (Stabilize).** Drive the soft gate in `20-replication-trigger.md` §1. When green, fill the delta letter (§2). **Refuse to mark the feature ready for Stage 4 without the human-confirm signature block in §4.** This refusal is the entire point of Stage 3.
- **Stage 4a (iOS) and Stage 4b (Android).** Run in **parallel** (separate worktrees). Before either starts:
  1. Open `20-replication-trigger.md` §4.
  2. Verify `replication_approved: true` with non-empty `approved_by` and `approved_at`.
  3. If missing or `false`, **stop** and tell the user the trigger is unsigned. Do **not** edit any iOS or Android source until the human signs.
- **Stage 5 (Parity).** Drive `50-parity-checklist.md` to all-green. Any newly red row reopens the feature via `60-followups.md`.

## After any failure

1. Read the per-platform manifest for the right run command. Do not paraphrase from memory.
2. Use [`harmony-autofix-orchestrator`](../harmony-autofix-orchestrator/SKILL.md) for HarmonyOS failures inside Stage 2 / 3.
3. Use [`autoloop-guard`](../autoloop-guard/SKILL.md) and [`safe-command-policy`](../safe-command-policy/SKILL.md) on retries; same rules as Harmony work.
4. Keep `docs/features/<feature-id>/` and `docs/features/README.md` honest at every step — checked boxes mean what they say.

## Stop conditions (must end in one of these)

- Stage 5 is all green and the feature row in `docs/features/README.md` is marked `Done`.
- Stage 3 needs human approval and the signature block is absent → stop and ask the user.
- An ambiguity is found that requires updating `00-design.md` → stop, surface the question in `20-replication-trigger.md` §3, and ask the user.
- The orchestrator is asked to run Stage 4 work without a signed trigger → refuse and ask.

## Sub-skills to invoke (project `.cursor/skills/**/SKILL.md` names)

`harmony-autofix-orchestrator` · `harmony-build` · `harmony-codelinter` · `harmony-unit-test` · `harmony-emulator-manage` · `harmony-ui-test` · `harmony-log-analyzer` · `harmony-fix-strategy` · `autoloop-guard` · `safe-command-policy` · `test-failure-classifier`

iOS and Android phases do not yet have dedicated sub-skill files; for now, this orchestrator points at the per-platform command manifests directly.
