# Android Replica Phase 3 - Parent Cloud, Binding, And Sync Design

> Status: design-for-implementation
> Date: 2026-05-11
> Scope: child-device binding, cloud credentials, global/family pack sync, word-stats sync, BoundDeviceInfo, and unbind flow.

## 1. Background

Phase 2 gives Android local pack management and local learning/growth state. Phase 3 connects that offline-first client to the existing parent cloud contracts used by HarmonyOS. Android must preserve server contract semantics while using native Android storage, camera/gallery capabilities, and network APIs.

Cloud integration must not make the child learning flow fragile. The app remains playable from bundled packs when offline, unbound, or temporarily unable to reach the server.

## 2. Goals

- Add child-device binding using QR token and manual short code.
- Store stable device identity and device token securely.
- Sync anonymous global packs and authenticated family packs.
- Sync word stats without blocking battle completion or result display.
- Add BoundDeviceInfo UI and parent-PIN-gated unbind flow.
- Preserve server-side tenant isolation: `family_id` is display/context only, not local authorization.
- Decode shared fixtures and map API DTOs to shared contracts.

## 3. Non-Goals

- Do not build the parent web dashboard in Android.
- Do not add multi-parent management in the child app.
- Do not cloud-sync active pack selection or pin state in this phase.
- Do not block battle, result, local coins, or local report on network success.
- Do not implement push notifications.
- Do not add release-visible debug backend switching; that is Phase 4.

## 4. Source Evidence

HarmonyOS code:

- `harmonyos/entry/src/main/ets/pages/ScanBindingPage.ets`
- `harmonyos/entry/src/main/ets/pages/BoundDeviceInfoPage.ets`
- `harmonyos/entry/src/main/ets/services/DeviceIdProvider.ets`
- `harmonyos/entry/src/main/ets/services/DeviceBindingService.ets`
- `harmonyos/entry/src/main/ets/services/BindingApiClient.ets`
- `harmonyos/entry/src/main/ets/services/CloudCredentials.ets`
- `harmonyos/entry/src/main/ets/services/CloudSyncService.ets`
- `harmonyos/entry/src/main/ets/services/FamilyPackService.ets`
- `harmonyos/entry/src/main/ets/services/GlobalPackService.ets`
- `harmonyos/entry/src/main/ets/services/DeviceUnbindClient.ets`

Shared contracts and fixtures:

- `shared/contracts/protocols/device-binding.md`
- `shared/contracts/protocols/pack-sync.md`
- `shared/contracts/protocols/word-stats-sync.md`
- `shared/contracts/protocols/wishlist-redemption.md`
- `shared/contracts/openapi/happyword-api.openapi.json`
- `shared/fixtures/pairing/pair-redeem.sample.json`
- `shared/fixtures/packs/global-packs-latest.sample.json`
- `shared/fixtures/packs/family-packs-latest.sample.json`
- `shared/fixtures/child/word-stats-sync.sample.json`

Screenshots:

- `assets/screenshots/harmonyos/bound-device-info.png`

## 5. Android Architecture

Kotlin services:

| Service | Responsibility |
| --- | --- |
| `DeviceIdProvider` | Stable app-private UUID, generated once and retained across app restarts. |
| `DeviceBindingClient` | Redeem QR token or short code using shared contract DTOs. |
| `CloudCredentialsStore` | Store device token, binding id, child profile, and family metadata. |
| `GlobalPackClient` | Anonymous ETag global pack sync. |
| `FamilyPackClient` | Bearer-token ETag family pack sync. |
| `WordStatsSyncClient` | Encode and post local word stats snapshot. |
| `CloudSyncCoordinator` | Non-blocking orchestration for pack and stats sync. |
| `DeviceUnbindClient` | Server unbind request. |
| `BoundDeviceInfoViewModel` | Bound child profile display, nickname refresh/edit if supported, unbind state. |

Recommended Android storage:

- Device id: app-private storage; Android Keystore-backed encrypted storage if available in project dependencies.
- Device token: encrypted storage or Android Keystore-backed wrapper. Do not store plain token in normal SharedPreferences.
- Non-secret labels: app-private JSON/SharedPreferences/DataStore.
- Pack caches: app-private JSON with ETag metadata.
- Word stats: local learning recorder remains offline source of truth.

Network stack:

- Implementation may use OkHttp, Retrofit, Ktor client, or platform HTTP.
- Whichever stack is chosen, DTO tests must decode shared fixtures and encode request payloads that match `shared/contracts`.
- API clients must read the effective base URL from one provider so Phase 4 debug routing can reuse it.

## 6. Binding Flow

Flow:

```text
Config -> ScanBinding
  -> QR camera scan, gallery QR decode, or manual short-code input
  -> DeviceBindingClient.redeem(tokenOrCode, deviceId)
  -> CloudCredentialsStore.save(deviceToken, child/family context)
  -> Config shows bound state
  -> optional immediate pack sync
```

Implementation order:

1. Manual short-code redeem path first because it is easiest to test.
2. Gallery QR decode using a fixture-driven test path.
3. Camera QR scan after permissions and emulator limitations are understood.

Android permission rules:

- Camera permission is requested only for camera QR scan.
- Gallery decode uses Android picker APIs when implementation reaches that path.
- Manual short-code path requires no runtime permission.

Error handling:

- Expired code: show retry message and stay on ScanBinding.
- Invalid code: show validation message and stay on ScanBinding.
- Network failure: keep unbound state and allow local play.
- Successful binding replaces stale credentials atomically.
- Partial credential save is not allowed; either all binding fields are saved or none are.

Suggested test tags:

- `ScanBindingScreen`
- `ScanBindingManualCodeInput`
- `ScanBindingRedeemButton`
- `ScanBindingGalleryButton`
- `ScanBindingCameraButton`
- `ScanBindingError`

## 7. Pack Sync

Global endpoint:

```text
GET /api/v1/public/global-packs/latest.json
```

Family endpoint:

```text
GET /api/v1/family/{family_id}/family-packs/latest.json
Authorization: Bearer <deviceToken>
```

Rules:

- Cold start loads builtin packs and cached pack layers first.
- Manual sync lives in PackManager.
- Background sync can happen after binding, app start, and battle result, but cannot block UI.
- ETag values are stored per layer.
- 200 replaces the corresponding cached layer after DTO validation.
- 204/304 keeps cached data.
- Network failure keeps cached data.
- 401/403 marks credentials as rejected and surfaces rebind guidance.
- 410 indicates binding gone; guide the user to BoundDeviceInfo or rebind flow.
- Merge remains family > global > builtin.

Pack cache validation:

- Reject packs without id or name.
- Reject packs with no words.
- Preserve previous cache on invalid response.
- Log validation failures in debug logs.

## 8. Word Stats Sync

Flow:

```text
Battle result / app foreground / explicit sync
  -> read local LearningRecorder snapshot
  -> WordStatsSyncClient.post(snapshot, syncedThroughMs)
  -> update sync checkpoint only after server success
  -> never block Result
```

Rules:

- Local stats remain source of offline truth.
- Sync failures are queued or retried later.
- Server derives family and child from device token.
- Payload shape must match `shared/contracts/protocols/word-stats-sync.md`.
- Do not send parent-only data from the child app.

## 9. BoundDeviceInfo

UI requirements:

- Show bound/unbound state.
- Show child nickname/avatar if present.
- Show family/account label if contract provides it.
- Show device display id or shortened local device id.
- Show last pack sync and word-stats sync status.
- Provide manual sync button.
- Provide unbind action behind parent PIN.

Unbind flow:

```text
BoundDeviceInfo tap unbind
  -> ParentPinDialog
  -> DeviceUnbindClient.post
  -> clear CloudCredentialsStore
  -> detach CloudSyncCoordinator from token-authenticated work
  -> keep local packs/stats/coins unless server contract later requires pruning
  -> return to Config unbound state
```

Error handling:

- PIN failure keeps dialog open.
- Network failure keeps credentials and shows retry message.
- 401/410 can clear credentials after showing an explanation.
- Clearing credentials must not erase local learning progress.

Suggested test tags:

- `BoundDeviceInfoScreen`
- `BoundDeviceInfoNickname`
- `BoundDeviceInfoSyncStatus`
- `BoundDeviceInfoManualSync`
- `BoundDeviceInfoUnbind`
- `BoundDeviceInfoUnbindConfirm`

## 10. Test Plan

JVM tests:

- Decode `pair-redeem.sample.json`.
- `DeviceIdProvider` returns stable id across store reloads.
- `CloudCredentialsStore` saves and clears token with fake secure storage.
- `GlobalPackClient` handles 200/204/304/network failure using fake HTTP.
- `FamilyPackClient` handles 200/304/401/403/410 using fake HTTP.
- `PackLibrary` merges family/global/builtin fixtures.
- `WordStatsSyncClient` encodes fixture-compatible payload.
- `CloudSyncCoordinator` does not throw when one sync step fails.
- `DeviceUnbindClient` clears local credentials only through the coordinator path.

Compose UI tests:

- Config unbound row opens ScanBinding.
- Manual short-code redeem with fake client flips Config/BoundDeviceInfo to bound.
- PackManager sync pulls a fake global fixture and updates pack list.
- BoundDeviceInfo manual sync shows success status.
- Unbind with valid PIN flips Config to unbound.

Manual verification:

- Use `adb logcat` to verify sync failures are logged without app crash.
- Use airplane mode or disabled network to verify Home and Battle still work.

## 11. Acceptance Criteria

- Bound Android devices can pull global and family pack fixtures through contract-compatible clients.
- Offline launch remains playable after sync failure.
- Device token is not stored in plain normal SharedPreferences.
- `family_id` is never trusted as a local authorization decision.
- Unbind clears cloud credentials while retaining local offline progress.
- Tests cover DTO decoding, ETag branches, credential save/clear, and UI bound/unbound transitions.
