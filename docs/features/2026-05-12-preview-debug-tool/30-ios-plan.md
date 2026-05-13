# iOS Plan

## Scope

- Add `BackendRouting` types for environment selection, Preview targets, header generation, manifest parsing, and debug network request summaries.
- Add a debug-only DevMenu reachable from settings in Debug builds.
- Use `os.Logger` category `HW_NET_DEBUG` for request/response summaries when a debug session is active.
- Keep release UI free of debug controls.

## Verification

- If `ios/project.yml` changes, run XcodeGen before Xcode tests.
- `xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameTests -derivedDataPath /private/tmp/wordmagic-dd`
- Manual debug simulator check: save Preview URL and debug session id, issue one backend request, verify `HW_NET_DEBUG`.
