# Android Replica Phase 4 - Debug, Preview Routing, And Developer Tools Design

> Status: design-for-implementation
> Date: 2026-05-11
> Scope: debug-only backend environment switching, preview manifest selection, bypass secret storage, mock/local routing, and automation hooks.

## 1. Background

HarmonyOS has debug-only developer tooling for backend environment switching, preview deployment selection, and Vercel preview bypass secrets. Android needs the same operational capability, but release builds must not expose it. AGENTS.md already requires debug builds only for developer backend routing entries.

Phase 4 starts after user-facing child, parent, local pack, and cloud binding flows exist. API clients from Phase 3 should already depend on one effective backend URL provider.

## 2. Goals

- Add debug-only backend environment switching.
- Add preview manifest fetch and preview URL selection.
- Add preview bypass secret entry and header injection.
- Add local/mock server routing support for instrumentation tests.
- Keep DevMenu and BypassSecret unreachable in release builds.
- Make Compose UI tests able to inject local/mock server URLs without relying on hidden UI gestures.

## 3. Non-Goals

- Do not expose backend URL selection to normal users.
- Do not expose DevMenu or BypassSecret in release builds.
- Do not store preview bypass token with child cloud credentials.
- Do not change server deployment policy.
- Do not make debug routing part of shared runtime code.

## 4. Source Evidence

HarmonyOS code:

- `harmonyos/entry/src/main/ets/pages/DevMenuPage.ets`
- `harmonyos/entry/src/main/ets/pages/BypassSecretPage.ets`
- `harmonyos/entry/src/main/ets/services/BackendEnv.ets`
- `harmonyos/entry/src/main/ets/services/BackendHeaders.ets`
- `harmonyos/entry/src/main/ets/services/PreviewManifestService.ets`
- `harmonyos/entry/src/main/ets/services/VersionTripleTap.ets`

Screenshots:

- `assets/screenshots/harmonyos/dev-menu.png`
- `assets/screenshots/harmonyos/bypass-secret.png`

Shared contracts and fixtures:

- `shared/contracts/domains/public.md`
- `shared/fixtures/public/preview-urls.sample.json`

Android command guidance:

- `.cursor/android-dev-commands.md`

## 5. Android Architecture

Kotlin services:

| Service | Responsibility |
| --- | --- |
| `BackendEnvironmentStore` | Persist selected debug environment and preview URL. |
| `BackendURLProvider` | Resolve effective base URL for every API client. |
| `BackendHeaderProvider` | Add preview bypass headers only when appropriate. |
| `PreviewManifestClient` | Fetch/decode preview manifest from public endpoint. |
| `BypassSecretStore` | Debug-only local bypass token. |
| `DevMenuViewModel` | Environment options, preview list, health probe, routing summary. |

Build gating:

- Debug builds can navigate to DevMenu.
- Release builds must not show a navigation path to DevMenu or BypassSecret.
- API clients may accept instrumentation launch override values in debug and test contexts.
- Release code can keep inert URL-provider abstractions, but no release UI should allow changing environments.

Recommended resolution precedence:

```text
instrumentation launch override
  -> explicit local/mock override
  -> selected preview URL
  -> selected fixed debug environment
  -> production/staging default
```

The exact production/staging labels should follow the server deployment policy active when Phase 4 is implemented.

## 6. DevMenu Entry

Entry rules:

- Main intended entry: debug-only Config/Developer row.
- Optional parity entry: version-label repeated tap, debug-only.
- Release builds must not render either entry.
- UI automation should not depend on triple-tap timing.

Suggested test tags:

- `ConfigDeveloperRow`
- `HomeVersionLabel`
- `DevMenuScreen`

## 7. DevMenu UI

Required sections:

- Current effective backend URL.
- Fixed environment choices: local, staging, production if configured.
- Preview manifest refresh.
- Preview URL list with selected state.
- Health probe result.
- Bypass secret entry.
- Routing debug summary.
- Clear override button.

Suggested test tags:

- `DevMenuRefreshManifestButton`
- `DevMenuPreviewRow_<previewId>`
- `DevMenuBypassSecretButton`
- `DevMenuHealthProbeButton`
- `DevMenuLastProbeStatus`
- `DevMenuRoutingDebug`
- `DevMenuClearOverrideButton`

Failure handling:

- Preview manifest fetch failure keeps previous manifest and shows error.
- Health probe failure displays debug status; it does not block navigation.
- Invalid preview URL is ignored with debug log.
- Missing bypass token on protected preview should show HTTP failure and a debug-only path to BypassSecret.

## 8. Preview Manifest

Manifest source:

- Runtime endpoint from server public route, matching HarmonyOS preview manifest behavior.
- Fixture: `shared/fixtures/public/preview-urls.sample.json`.

Rules:

- Decode and validate manifest before replacing cached list.
- Keep previous valid manifest on failure.
- Sort previews by recency if manifest includes timestamp; otherwise preserve server order.
- Persist selected preview id or URL.
- If selected preview disappears, clear selected preview and fall back to fixed environment.

## 9. BypassSecret UI

Rules:

- Token is stored locally and debug-only.
- Empty save clears token.
- Token is applied only to preview/protected-preview routes.
- Token is never attached to production/staging routes.
- Token is not cloud credential and is cleared independently.

Suggested test tags:

- `BypassSecretPageTitle`
- `BypassSecretPageInput`
- `BypassSecretPageError`
- `BypassSecretPageCancelButton`
- `BypassSecretPageSaveButton`
- `BypassSecretPageClearButton`

## 10. Mock And Local Server Routing

Instrumentation tests should prefer launch arguments/environment variables or debug-only dependency injection over manual DevMenu use.

Android equivalents:

- Use `adb reverse tcp:8123 tcp:8123` for local mock server access when target API supports it.
- Use a test-only base URL override consumed by `BackendURLProvider`.
- Keep the override out of release user settings.

Rules:

- Mock server routing must be deterministic in tests.
- Debug manual routing can be changed by the developer at runtime.
- Release build must not bundle a mock server URL as the default.

## 11. Test Plan

JVM tests:

- `BackendURLProviderTest`: override precedence, selected preview, fixed environment fallback.
- `BackendHeaderProviderTest`: bypass header only for preview routes.
- `PreviewManifestClientTest`: decode fixture, reject malformed URL, preserve previous manifest on failure.
- `BypassSecretStoreTest`: save, trim, clear, reload.
- `DevMenuViewModelTest`: refresh success/failure, health probe status.

Compose UI tests:

- Debug build Config shows Developer row.
- DevMenu refresh with fake manifest shows preview rows.
- Selecting a preview updates routing summary.
- BypassSecret save updates local store.
- A debug-only UI test verifies DevMenu exists.

Release verification:

- Release variant navigation traversal does not find `ConfigDeveloperRow`.
- Release variant does not expose BypassSecret route.
- Release logs do not print bypass token values.

## 12. Manual Verification

Use `.cursor/android-dev-commands.md` commands:

```sh
cd android
./gradlew assembleDebug
./gradlew connectedDebugAndroidTest
./gradlew installDebug
```

Useful adb checks:

```sh
adb -s <serial> logcat -c
adb -s <serial> logcat -d | rg -i "Backend|Preview|Bypass|WordMagic"
adb -s <serial> reverse tcp:8123 tcp:8123
```

## 13. Acceptance Criteria

- Debug build can route API clients to local, staging, production/default, or selected preview.
- Preview manifest can be fetched, cached, selected, and recovered from failure.
- Bypass secret is applied only to preview requests and can be cleared.
- Instrumentation tests can inject a local/mock base URL without opening DevMenu.
- Release builds do not expose DevMenu, BypassSecret, preview bypass token entry, or mock-routing UI.
