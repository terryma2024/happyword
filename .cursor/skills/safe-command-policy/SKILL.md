---
name: safe-command-policy
description: Constrains shell operations during HarmonyOS local CI and autofix runs—no destructive broad deletes, no unreviewed download-pipe, prefer manifest-defined commands. Use when executing hvigor, hdc, ohpm, or automation loops that run shell in the project.
---

# safe-command-policy

**Role:** Prevents runaway or unsafe shell, **without** duplicating the command manifest.

## Rules

1. **Prefer manifest copy:** For this repo, concrete commands must match [`.cursor/dev-commands.md`](.cursor/dev-commands.md) (or a path the user points to). If the agent is about to run a **new** flag or a different `hvigorw` invocation, stop and **update the manifest** or get explicit user approval in chat.
2. **Deny (unless user explicitly orders in this session):**
   - `rm -rf /` or `rm -rf` on `$HOME`, `/System`, or repo root in one go without listing targets
   - `curl|sh`, `wget|sh`, or piping unknown URLs into `bash`
   - `chmod -R` on system dirs; `chown` of `/` or other users’ trees
   - Dropping or truncating production DBs / remote resources (not applicable in typical Harmony app repos, but keep the rule)
3. **Caution (confirm intent):** `git reset --hard`, `git clean -fdx`, deleting signing keys or `local.properties` contents.
4. **Secrets:** Never paste signing passwords, `local.properties` secrets, or tokens into the chat; use env/CI as project rules require.

## Check before running

- Is this command the **same** as in the manifest (or an approved subset such as a path argument)? If **mutated**, pause and align.

## Integration

- Apply whenever **`harmony-build`**, **`harmony-unit-test`**, **`harmony-emulator-manage`**, or **`harmony-ui-test`** is about to execute a shell line.
