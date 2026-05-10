# iOS Replica Phase 4 — Debug, Preview Routing, And Developer Tools Design

> Status: design-for-implementation
> Date: 2026-05-10
> Scope: debug-only backend environment switching, preview bypass secret, and developer routing tools.

## 1. Background

HarmonyOS has a debug-only DevMenu for switching backend environments and a BypassSecret page for Vercel preview protection. AGENTS.md states release builds must not expose Settings -> Developer -> Backend environment. iOS must keep the same rule.

Phase 4 starts after the user-facing child and parent flows exist.

## 2. Goals

- Add debug-only backend environment switching.
- Add preview manifest loading and preview URL selection.
- Add preview bypass secret storage for protected Vercel previews.
- Preserve release-build hiding of developer tools.
- Make XCUITest able to inject local/mock server URLs without relying on hidden UI.

## 3. Non-Goals

- Do not expose DevMenu in release builds.
- Do not add production user settings for backend URL.
- Do not make preview bypass token part of cloud credentials.
- Do not change server deployment policy.

## 4. Source Evidence

HarmonyOS code:

- `pages/DevMenuPage.ets`
- `pages/BypassSecretPage.ets`
- `services/BackendEnv.ets`
- `services/BackendHeaders.ets`
- `services/PreviewManifestService.ets`
- `services/VersionTripleTap.ets`

Screenshots:

- `assets/screenshots/harmonyos/dev-menu.png`
- `assets/screenshots/harmonyos/bypass-secret.png`

Shared fixtures:

- `shared/fixtures/public/preview-urls.sample.json`
- `shared/contracts/domains/public.md`

Repository rules:

- Debug builds can open DevMenu from Settings/Developer.
- Release builds must not expose the entry.
- ohosTest excludes DevMenu and version-label triple-tap paths; developers exercise them manually.

## 5. iOS Architecture

Swift services:

| Service | Responsibility |
| --- | --- |
| `BackendEnvironmentStore` | Selected environment and override URL. |
| `BackendURLProvider` | Effective base URL for API clients. |
| `BackendHeaderProvider` | Preview bypass headers. |
| `PreviewManifestClient` | Fetch and decode preview manifest. |
| `BypassSecretStore` | Local debug-only bypass token. |
| `DeveloperMenuViewModel` | Debug page state, health probe, preview selection. |

Build gating:

- Developer UI is compiled or routed only under Debug/internal configuration.
- Release UI has no visible path to DevMenu.
- API clients may still accept launch-environment URL overrides for automated tests.

## 6. DevMenu UI

Portrait or landscape can be chosen by implementation, but it must be simple and functional.

Required sections:

- Current backend environment.
- Local/staging/production/preview choices.
- Preview manifest refresh.
- Preview URL list.
- Health probe result.
- Bypass secret entry.
- Routing debug summary.

Identifiers:

- `DevMenuRefreshManifestButton`
- `DevMenuBypassSecretButton`
- `DevMenuLastProbeStatus`
- `DevMenuRoutingDebug`

## 7. BypassSecret UI

Rules:

- Token is local to the app.
- Empty token clears bypass header.
- Token is applied only to preview URLs that require bypass.
- Validation is minimal: trim whitespace, reject empty save only when the user expects a non-empty token.

Identifiers:

- `BypassSecretPageTitle`
- `BypassSecretPageInput`
- `BypassSecretPageError`
- `BypassSecretPageCancelButton`
- `BypassSecretPageSaveButton`

## 8. Test And Automation Policy

XCTest:

- `BackendURLProvider` precedence: launch override > selected preview > selected fixed environment > production default.
- `PreviewManifestClient` decodes `shared/fixtures/public/preview-urls.sample.json`.
- `BackendHeaderProvider` attaches bypass header only for preview routes.

XCUITest:

- Prefer launch arguments/environment variables for mock server URL.
- Do not require user-visible DevMenu automation in the main UI suite.
- A debug-only UI test can verify DevMenu exists in debug builds.

Release check:

- Release scheme snapshot or UI traversal must prove no DevMenu entry exists.
- BypassSecret route must not be reachable from release navigation.

## 9. Error Handling

- Preview manifest fetch failure keeps the previous manifest.
- Health probe failure is displayed as a debug result, not a blocking app error.
- Invalid preview URL is ignored and logged in debug output.
- Missing bypass token on protected preview should show the HTTP failure and link to BypassSecret in debug builds only.

## 10. Acceptance Criteria

- Debug build can route to local/staging/production/preview.
- API clients consume one `BackendURLProvider`.
- Release build does not expose DevMenu or BypassSecret.
- XCUITest can use launch environment overrides without opening DevMenu.
