# HarmonyOS Plan

## Scope

- Reuse existing DevMenu Preview routing.
- Add a debug session input and persisted cache key.
- Attach `x-hw-debug-session` through the shared backend header path only for Preview.
- Log request/response summaries with `HW_NET_DEBUG` when the debug session header is present.
- Parse manifest `branch_url` as the active URL and preserve deployment metadata.

## Verification

- `cd harmonyos && hvigorw -p module=entry@default test`
- `cd harmonyos && hvigorw assembleHap`
- Confirm the HAP build log has `0` `ArkTS:WARN` lines.
- `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
- Manual debug build check: choose a Preview target, save a session id, reproduce once, and confirm client log and server trace share the same session id.
