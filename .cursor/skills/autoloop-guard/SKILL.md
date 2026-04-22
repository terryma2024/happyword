---
name: autoloop-guard
description: Enforces max retry rounds, same-error-signature early exit, and optional time budget for autonomous build/test fix loops. Use when running a HarmonyOS autofix loop, iterative hvigor test retries, or any agent loop that could spin on repeated failure.
---

# autoloop-guard

**Role:** Policy only. Does **not** run build, `hvigorw`, or `hdc`.

## Defaults (override via user or `harmony-autofix-orchestrator` if documented)

- **max_rounds:** 3–5 full loop iterations (build → unit → device → UI or the pipeline in play) unless the user sets another cap.
- **max_same_error:** If the **normalized** failure signature (first meaningful error line + exit code) repeats **2–3** times in a row, **stop** and report; do not keep editing blindly.
- **time_budget (optional):** If the user sets a wall-clock cap, stop when exceeded with a short summary.

## On stop

- Output: rounds used, last error signature, recommendation (human, env, or new hypothesis).
- Do **not** add new file edits in the same turn as the hard stop; escalate only.

## Integration

- Invoked from **`harmony-autofix-orchestrator`** at loop boundaries and when deciding whether to start another **fix** round.
