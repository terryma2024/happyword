---
name: parity-scout
description: Drives a per-feature visual + spec-anchored gap scout across HarmonyOS / iOS / Android using tools/parity_scout/. Use when asked to "find iOS / Android gaps vs HarmonyOS main", "check parity for <feature>", or "screenshot the three platforms and tell me what's different".
---

Keep in sync with [`.cursor/skills/parity-scout/SKILL.md`](../../../.cursor/skills/parity-scout/SKILL.md) when editing the flow.

# parity-scout

**Role:** **Scheduler only.** It does **not** embed CLI flag tables — read [`tools/parity_scout/README.md`](../../../tools/parity_scout/README.md) for copy-pastable lines and [`docs/superpowers/specs/2026-05-13-parity-scout-design.md`](../../../docs/superpowers/specs/2026-05-13-parity-scout-design.md) for the full design.

## Inputs

A user task that names a scope: a feature folder, a spec doc, an explicit page list, "overall", or a free-form description.

## Flow

1. **Inputs.** Identify a scope from the task:
   - feature folder name → `--feature <id>` (pass the folder path, e.g. `docs/features/<id>`)
   - spec doc path → `--spec <path>`
   - "scout everything" / "overall" → `--scope overall`
   - free prose → `--describe "<verbatim user prose>"`
   - explicit pages → `--pages a,b,c`
   - Harmony suite name → `--suite Foo,Bar`

   Otherwise: **ask the user once in chat**.
2. **Doctor.** Run `python3 tools/parity_scout/scout.py doctor` and surface its output. It is non-gating — even with red rows you may proceed if the user accepts the risk, but call them out.
3. **Plan.** Run `python3 tools/parity_scout/scout.py plan ...`. If `--scope overall`, **stop and confirm with the user** — this is the expensive global mode. Otherwise present the tree in chat and ask which branches to pick (checkbox list). Blocked / all-feature-absent branches are shown but greyed.
4. **Pick.** Run `scout.py pick --run <id> --branches <user-selection>`. If the user picked any `blocked` leaf, **refuse to start `run`** and tell them to add the capture route first; offer to flip into an "add the route" subtask before resuming.
5. **Per-leaf loop.** Run `scout.py run --run <id>` foreground, watched. For each `LEAF READY page=<id> dir=<path>` line emitted by the process:
   1. Read the staged `<path>/spec-excerpts.md`. If absent (e.g. `--scope overall` runs that bypass spec extraction), fall back to spec anchors from the registry entry and proceed without excerpts.
   2. Read each `*.png` under `<path>/{harmony,ios,android}/` (agent vision over images).
   3. Compare PNGs across platforms and against the spec excerpts. The spec excerpts narrow what counts as a gap; visual-only differences not anchored by the spec are downranked, not promoted.
   4. Append findings to `.parity_scout/<run-id>/findings.md` under a `## <page>` heading, with bullet lines tagged `[harmony|ios|android]` + a severity hint (`critical`, `notable`, `nit`).
   5. `touch <dir>/next.flag` to release `scout.py run` to the next leaf.

   On `LEAF SKIPPED page=<id> reason=feature_absent`: do not look for PNGs; instead record a one-line entry in `findings.md` noting "Feature missing on platform(s): ..." and continue.
6. **Curate.** After `RUN DONE`:
   1. Read `findings.md`. Drop noise. Write `findings.curated.md`.
   2. Group items by feature folder (each item's page id usually maps to one feature; if ambiguous, ask the user). Write `findings.curated.<feature-id>.md` for every feature touched. Items that can't be assigned go to `findings.curated.unassigned.md`.
   3. Show the user a one-screen summary listing every feature slice and ask: "promote which slices? (all / none / pick)".
7. **Promote.** For each picked slice, run `scout.py promote --run <id> --feature <feature-id>` and show the resulting diff hunk in chat. **Do not commit.** The user runs git themselves.

## Guards to invoke

- **`safe-command-policy`** (under `.cursor/skills/safe-command-policy/`) before every `scout.py` invocation.
- **`autoloop-guard`** on the per-leaf loop. If `LEAF READY` repeats without `findings.md` growth, abort.
- **`harmony-emulator-manage`** (and the iOS / Android device preflight in their respective command manifests) when any selected leaf needs that platform's adapter.

## HarmonyOS baseline discipline

`parity_scout` treats HarmonyOS `main` as the source of truth. Before `run`:

- Confirm the worktree is on `main` and clean. If not, surface `doctor`'s baseline row and either (a) ask the user to stash/commit before continuing, or (b) accept `--allow-dirty-baseline` and warn loudly in chat.
- Never silently scout against a feature branch — gaps reported under those conditions cannot be trusted as "HarmonyOS-relative".

## Stop conditions (must end in one of these)

- `RUN DONE` + user resolved every curated feature slice (promote or skip) + (if promoted) diff hunks shown.
- Precondition refused — missing capture route on a selected leaf, dirty HarmonyOS baseline without `--allow-dirty-baseline`, or a required device unreachable preflight → user told what to add; no files touched.
- `autoloop-guard` tripped → run dir preserved for inspection.

## Sub-skills to invoke

`safe-command-policy` · `autoloop-guard` · `harmony-emulator-manage` (paths under `.cursor/skills/` in this repo)

iOS and Android device preflight pull from their respective command manifests (`.cursor/ios-dev-commands.md`, `.cursor/android-dev-commands.md`), not dedicated sub-skills.

## What this skill does NOT do

- It does not write CLI flag tables — read `tools/parity_scout/README.md`.
- It does not run `git commit`. The user owns the commit step after `promote`.
- It does not create `docs/features/<id>/` folders. `promote` refuses if the folder is missing.
- It does not invent capture routes. If a leaf is `blocked` (feature exists but no automation entry), the SKILL refuses to capture and asks the user to add the route to `tools/parity_scout/page_suite_map.yml` first.
