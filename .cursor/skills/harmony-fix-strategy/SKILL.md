---
name: harmony-fix-strategy
description: Given a classified failure tier and log excerpts, proposes minimal allowed code or test changes for HarmonyOS autofix—no duplicate taxonomy. Use only after test-failure-classifier and when agent_safe or agent_risky applies; not for unguided refactors.
---

# harmony-fix-strategy

**Prerequisite:** `test-failure-classifier` has set **category** and **tier**. **`test-failure-classifier`** does not assign file-level edits; this skill does (within tier rules).

## By tier

| Tier | Strategy |
|------|----------|
| **agent_safe** | Minimal fix: the smallest change that addresses the error (often one file or a focused test). For **lint** / **codelinter**, apply fixes in source and re-run the manifest codelinter command. Prefer **tests** for wrong expectations; prefer **app** for real bugs. |
| **agent_risky** | Prefer **test** stabilization (explicit waits, deterministic setup) or **one** scoped product fix with a short note. If the fix would change product behavior in a debatable way, **stop** and list options for the user. |
| **human_required** | **No code edits** in the loop. Produce a short checklist: signing, `hdc`, SDK path, org policy, etc. |

## Forbidden (all tiers)

- Unrelated refactors, dependency-wide upgrades, or “cleanup” not required by the error.
- Disabling tests or deleting test cases to go green.
- Patching `local.properties` or keys into the repo.
- Inventing `hvigorw` flags—if the fix is “wrong task,” update [`.cursor/dev-commands.md`](.cursor/dev-commands.md) with a verified line.

## Output

- `allowed_action`: e.g. “edit `entry/.../Foo.ets` assert X” or `none — escalate`
- `files_touched` (if any): minimal list
- Rerun order: usually **re-run from the failed phase**; full pipeline only if the orchestrator or manifest says so
