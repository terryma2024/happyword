# iOS Release Readiness Checklist

> Status: implementation checklist
> Scope: Phase 5 release hardening for the native iOS replica.

## Build Gates

- Debug builds may expose `ConfigDeveloperBackendButton`, `DevMenuRefreshManifestButton`, `DevMenuBypassSecretButton`, `DevMenuRoutingDebug`, and `BypassSecretPageInput`.
- Release builds must not expose developer routing or bypass-secret controls. Validate with:

```sh
cd ios
xcodebuild build -scheme WordMagicGame -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/wordmagic-release
```

- Unit tests must decode every shared fixture used by the iOS cloud clients:
  - `shared/fixtures/pairing/pair-redeem.sample.json`
  - `shared/fixtures/packs/global-packs-latest.sample.json`
  - `shared/fixtures/packs/family-packs-latest.sample.json`
  - `shared/fixtures/child/word-stats-sync.sample.json`
  - `shared/fixtures/public/preview-urls.sample.json`

## Debug Routing Gates

- `HAPPYWORD_API_BASE_URL` launch environment has the highest priority for simulator automation.
- Debug-only backend environment selection supports local, staging, production, and preview.
- Preview routing attaches `x-vercel-protection-bypass` only when a non-empty secret is saved and the selected environment is preview.
- Preview manifest decoding accepts both the current `previews` shape and older `pulls` samples.

## Accessibility Gates

- Core child flow identifiers remain stable: `HomeStartButton`, `BattleCorrectOption`, `ResultHomeButton`.
- Parent/cloud identifiers remain stable: `HomeChildProfileButton`, `CloudBindingStatus`, `账号信息`, `解除设备绑定`, `孩子名字`.
- Debug identifiers remain stable in Debug only: `ConfigDeveloperBackendButton`, `DevMenuRoutingDebug`, `DevMenuLastProbeStatus`, `BypassSecretPageInput`.

## Manual Smoke Pass

- Launch the app in Debug, open settings, and confirm `Backend environment` appears.
- Switch to Local and Preview, then confirm the routing summary updates.
- Open Bypass Secret, save a test value, and confirm returning to DevMenu succeeds.
- Build Release and confirm there is no visible developer entry from settings.
- Run the primary iPhone landscape XCUITest smoke flow before TestFlight packaging.
