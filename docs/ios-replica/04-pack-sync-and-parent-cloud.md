# Later Phases: Pack Sync, Growth, And Parent Cloud

## Phase 2: Pack Management And Local Growth

### PackManager

Source behavior:

- `PackManagerPage` owns manual sync, active count, source tags, pin buttons, and switches.
- `PackSelectionService` caps active packs at five.
- Home reloads pack selection on page show.

iOS design:

- Build `PackLibrary` and `PackSelectionStore` before rendering PackManager.
- Use builtin packs first; global/family caches can be empty.
- List rows show source tag, English name, pin button, and toggle.
- Sync button calls `GlobalPackClient` and `FamilyPackClient` when credentials exist.
- After save/sync, Home must reflect changed active chips on return.

Tests:

- Active set defaults to five builtin packs.
- Toggling an active pack removes its Home chip.
- Pin button appears only for active packs.
- Active cap prevents sixth selection.

### Wishlist And Redemption History

Source behavior:

- Local magic wishes.
- Add/delete/apply all gated by parent PIN.
- GiftBox modal after confirmed redemption.
- History is capped at 50 records.

iOS design:

- `WishlistStore`, `CoinAccount`, and `RedemptionHistoryStore` are local stores in Phase 2.
- The `添加愿望` button opens an explicit custom-wish form instead of creating a hard-coded sample wish.
- Cloud wishlist and web approval are deferred to later cloud work.
- Result coin rewards must already exist from Phase 1.

Tests:

- Applying a wish requires PIN and sufficient coins.
- Confirmed redemption deducts coins and records history.
- GiftBox can be screenshot-tested separately from store logic.

### MonsterCodex

Source behavior:

- Carousel/card viewer over current monster catalog.

iOS design:

- Use migrated character assets after an explicit asset task.
- Preserve monster names, kind tags, descriptions, and index count.

### TodayPlan

Source behavior:

- Read-only daily plan with review/learning/new buckets.

iOS design:

- Use the same `TodayAdventureBuilder` and `LearningRecorder` data.
- Do not let TodayPlan mutate battle state.

### LearningReport

Source behavior:

- V0.6.7.8 switched report rows from category to pack.

iOS design:

- `LearningReportBuilder.build(library, activeIds, recorder, now)` produces pack rows.
- Active packs sort first in selection order.
- Inactive packs with seen words sort by low accuracy first.
- Inactive packs with zero stats are hidden.

Tests:

- Shared word in two packs counts toward both pack rows.
- Top-level totals dedupe shared words.
- Pack row order matches active selection order.

## Phase 3: Device Binding And Cloud Sync

### Binding

Contracts:

- `shared/contracts/protocols/device-binding.md`
- `shared/fixtures/pairing/pair-redeem.sample.json`

iOS design:

- Stable `device_id` comes from Keychain-backed UUID.
- QR camera/gallery scanning can use iOS camera APIs later; short-code entry and pasted QR landing links share the current testable path.
- Device token belongs in Keychain.
- Client displays family/child context but server remains authority for `family_id`.
- Child profile rename persists locally first, then calls `PUT /api/v1/child/profile` with the device token.

Tests:

- Pair redeem DTO decoding.
- Short-code success stores token and child profile.
- 410/unbind clears credentials only through explicit flow.

### Pack Sync

Contracts:

- `shared/contracts/protocols/pack-sync.md`
- `shared/fixtures/packs/global-packs-latest.sample.json`
- `shared/fixtures/packs/family-packs-latest.sample.json`

iOS design:

- `HTTPPackLayerClient.fetchGlobal` supports ETag and 200/204/304/network failure handling.
- `HTTPPackLayerClient.fetchFamily` adds bearer device token and handles 401/403/410.
- Cache layers separately, then merge family > global > builtin.
- File-backed remote layer caches load on cold start before any network call.
- Never block Home or Battle on sync failure.

Tests:

- 304 preserves cache.
- 204 clears the relevant remote layer.
- Network failure keeps cached layer and builtin fallback.
- Same `pack_id` merges with family > global > builtin.

### Word Stats Sync

Contracts:

- `shared/contracts/protocols/word-stats-sync.md`
- `shared/fixtures/child/word-stats-sync.sample.json`

iOS design:

- Local `LearningRecorder` remains source of offline playability.
- Sync is fire-and-forget on battle result, app background, and explicit parent/account action.
- Failed sync schedules retry and never blocks Result.
- `WordStatsSyncStateStore` tracks `synced_through_ms` and retry state in local defaults.

## Phase 4: Debug And Preview Operations

Debug surfaces:

- `DevMenuPage`
- `BypassSecretPage`
- version-label triple tap

iOS design:

- Compile or runtime gate all debug entries out of release builds.
- Backend environment switcher mirrors HarmonyOS DevMenu semantics.
- Preview bypass token is stored locally and only applied to preview URLs.

Tests:

- Debug build can switch local/staging/preview base URL.
- Release build has no visible DevMenu entry.

## Phase 5: Release Hardening

Deliverables:

- Screenshot parity matrix for iPhone landscape child screens and iPhone portrait parent screens.
- Stable accessibility identifiers for every XCUITest surface.
- TestFlight smoke checklist.
- Server contract fixture decoding suite.
- Asset migration audit that preserves source assets under `assets/`.
