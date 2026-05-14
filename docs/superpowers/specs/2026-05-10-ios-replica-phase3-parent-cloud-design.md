# iOS Replica Phase 3 — Parent Cloud, Binding, And Sync Design

> Status: design-for-implementation
> Date: 2026-05-10
> Scope: parent account binding, child device credentials, global/family pack sync, word stats sync, and bound device info.

## 1. Background

HarmonyOS V0.6 introduced parent accounts, device binding, family-scoped child profiles, family packs, and local-to-cloud sync. iOS must preserve the same server contracts while using native iOS storage and camera/QR capabilities.

Phase 3 starts only after Phase 2 local pack and learning systems are stable.

## 2. Goals

- Implement child-device binding via QR or short code.
- Store stable device identity and device token securely on iOS.
- Sync global and family packs using the shared pack sync protocol.
- Sync word stats without blocking offline play.
- Add BoundDeviceInfo and unbind flow.
- Preserve tenant isolation: `family_id` is server-authoritative.

## 3. Non-Goals

- Do not build the parent web dashboard in iOS; it remains server HTML.
- Do not add multi-parent account management on device.
- Do not cloud-sync active pack selection or pin state.
- Do not block gameplay on network availability.
- Do not add push notifications in this phase.

## 4. Source Evidence

HarmonyOS code:

- `pages/ScanBindingPage.ets`
- `pages/BoundDeviceInfoPage.ets`
- `services/DeviceIdProvider.ets`
- `services/DeviceBindingService.ets`
- `services/BindingApiClient.ets`
- `services/CloudCredentials.ets`
- `services/CloudSyncService.ets`
- `services/FamilyPackService.ets`
- `services/GlobalPackService.ets`
- `services/DeviceUnbindClient.ets`
- `services/CloudWishlistService.ets`

Shared contracts:

- `shared/contracts/protocols/device-binding.md`
- `shared/contracts/protocols/pack-sync.md`
- `shared/contracts/protocols/word-stats-sync.md`
- `shared/contracts/protocols/wishlist-redemption.md`
- `shared/fixtures/pairing/pair-redeem.sample.json`
- `shared/fixtures/packs/global-packs-latest.sample.json`
- `shared/fixtures/packs/family-packs-latest.sample.json`
- `shared/fixtures/child/word-stats-sync.sample.json`

Screenshots:

- `assets/screenshots/harmonyos/bound-device-info.png`

Historical specs:

- V0.6 parent account design.
- Scan binding gallery QR design.
- V0.6.5 three-layer pack model.

## 5. iOS Architecture

Swift services:

| Service | Responsibility |
| --- | --- |
| `DeviceIdProvider` | Keychain-backed stable UUID. |
| `DeviceBindingClient` | Redeem QR token or short code. |
| `CloudCredentialsStore` | Device token, binding id, family id, child profile metadata. |
| `GlobalPackClient` | Anonymous global pack ETag sync. |
| `FamilyPackClient` | Device-token family pack ETag sync. |
| `WordStatsSyncClient` | `POST /api/v1/family/{family_id}/word-stats/sync`. |
| `DeviceUnbindClient` | Server unbind and local credential clearing. |
| `BoundDeviceInfoViewModel` | Profile display, nickname edit, unbind flow. |

Storage:

- Device id: Keychain.
- Device token: Keychain.
- Non-secret profile labels: app sandbox JSON/UserDefaults.
- Pack caches: file-backed JSON with ETag metadata.
- Word stats: local learning store remains source of offline truth.

## 6. Binding Flow

Flow:

```text
Config -> ScanBinding
  -> QR camera scan or gallery/manual short code
  -> DeviceBindingClient.redeem(tokenOrCode, deviceId)
  -> CloudCredentialsStore.save(deviceToken, child/family context)
  -> Config shows bound state
```

iOS implementation order:

1. Short-code redeem path first because it is easiest to test.
2. QR scan path using iOS camera APIs.
3. Gallery QR image decoding if needed for parity with HarmonyOS.

Error handling:

- Expired code: show retry message, stay on ScanBinding.
- Invalid code: show validation message, stay on page.
- Network failure: keep unbound state.
- Successful binding replaces any stale local binding credentials.

## 7. Pack Sync

Global endpoint:

- `GET /api/v1/public/global-packs/latest.json`
- Anonymous.
- Uses ETag and 200/204/304 handling.

Family endpoint:

- `GET /api/v1/family/{family_id}/family-packs/latest.json`
- Bearer device token.
- Uses ETag and 200/204/304/401/403/410 handling.

Client rules:

- Manual sync lives in PackManager.
- Cold start reads cached layers and builtin packs; it does not require network.
- Merge is family > global > builtin.
- Network failure keeps cached data.
- 410 indicates binding gone; guide user to bound-device/account surface.

## 8. Word Stats Sync

Flow:

```text
Battle result / app background / explicit sync
  -> read local WordStat snapshot
  -> POST /api/v1/family/{family_id}/word-stats/sync
  -> merge accepted remote state only if protocol requires it
  -> never block battle result
```

Rules:

- Local stats are playable offline.
- Sync failures are logged and retried later.
- `synced_through_ms` is maintained locally.
- Server derives family/child context from token.

## 9. Bound Device Info

UI:

- Show child nickname/avatar.
- Show device id or short device display name.
- Show family/account state.
- Home top-toolbar child profile badge opens the child profile / bound-device surface.
- Allow nickname edit from the child profile page. Persist locally first, then call the device-side server profile-update API.
- Unbind action requires parent PIN.
- Landscape profile and account pages place the `返回` button at the top-left edge, matching Config, PackManager, and other iOS replica pages.

Unbind flow:

```text
BoundDeviceInfo tap unbind
  -> ParentPinDialog
  -> DeviceUnbindClient.post
  -> clear CloudCredentialsStore
  -> detach CloudSync from local recorder
  -> return to Config unbound state
```

Error handling:

- PIN failure keeps dialog open.
- Network failure keeps credentials and shows retry message.
- 401/410 clears credentials only after user-facing explanation.

## 10. Test Plan

XCTest:

- Decode `pair-redeem.sample.json`.
- Keychain-backed `DeviceIdProvider` returns stable id.
- `GlobalPackClient` handles 200/204/304/network failure.
- `FamilyPackClient` handles 401/403/410.
- `PackLibrary` merges family/global/builtin fixtures.
- `WordStatsSyncClient` encodes fixture-compatible payload.
- `CloudCredentialsStore` saves/clears token correctly with fake Keychain.

XCUITest:

- Config unbound row opens ScanBinding.
- Manual short-code redeem with mock server flips Config to bound.
- PackManager sync pulls global fixture.
- BoundDeviceInfo unbind with PIN flips Config to unbound.

## 11. Acceptance Criteria

- Bound devices can pull family packs and global packs.
- Offline launch remains playable after failed sync.
- Device token is never stored in plain UserDefaults.
- `family_id` is never trusted as a local authorization decision.
- Unbind flow clears local cloud state and leaves local offline progress intact.
