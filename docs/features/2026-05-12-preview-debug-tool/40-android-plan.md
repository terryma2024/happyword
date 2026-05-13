# Android Plan

## Scope

- Add `INTERNET` permission.
- Fetch the real Preview manifest and prefer `branch_url`.
- Persist Preview selection, bypass secret, and debug session id in the debug routing repository.
- Attach bypass/debug headers only for Preview through one helper.
- Expose debug session input in DevMenu.
- Log request/response summaries with `HW_NET_DEBUG`.

## Verification

- `cd android && ./gradlew testDebugUnitTest`
- `cd android && ./gradlew assembleDebug`
- Manual debug build check: select Preview, save session id, reproduce once, and confirm Android logcat and server trace share the session id.
- Release gate: release path does not expose DevMenu controls and non-Preview requests have no bypass/debug headers.
