# V0.9.5 Spellbook Codex — HarmonyOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the HarmonyOS-first Spellbook Codex slice: Home entry, pack/word collection page, local reward claim, and cover URL plumbing.

**Architecture:** Keep collection rules in pure services so local unit tests cover card states, pack completion, reward idempotency, and cover fallback. UI pages only load PackLibrary, LearningRecorder stats, SpellbookRewardStore, and CoinAccount, then render stable IDs from `00-design.md`. Server-side image generation is represented in contracts/spec only for this Harmony stage; implementation waits for the backend plan.

**Tech Stack:** ArkTS / ArkUI, Hypium local unit tests, Harmony rawfile PNG assets, existing PackLibrary, WrongAnswerStore, CoinAccount, RemoteAssetCache.

---

### Task 1: Spellbook Pure Rules

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/SpellbookService.ets`
- Create: `harmonyos/entry/src/test/SpellbookService.test.ets`
- Modify: `harmonyos/entry/src/test/List.test.ets`

- [ ] **Step 1: Write failing tests**

Add tests for:
- missing stat -> `locked`
- seen stat with `seenCount > 0` and non-mastered memory -> `seen`
- `memoryState === 'mastered'` -> `mastered`
- pack completion requires every pack word to be mastered and zero-word packs are not complete
- progress counts total/seen/mastered

Run: `cd harmonyos && hvigorw -p module=entry@default test`
Expected: FAIL because `SpellbookService.ets` does not exist.

- [ ] **Step 2: Implement pure helpers**

Implement `SpellbookCardState`, `SpellbookCard`, `SpellbookPackProgress`, `spellbookStateForWord`, `buildSpellbookCards`, `spellbookProgressForPack`, `isSpellbookPackComplete`, `spellbookRewardTxnId`, and `SPELLBOOK_REWARD_COINS = 50`.

- [ ] **Step 3: Verify green**

Run: `cd harmonyos && hvigorw -p module=entry@default test`
Expected: PASS for the new SpellbookService tests.

### Task 2: Reward Store

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/SpellbookRewardStore.ets`
- Create: `harmonyos/entry/src/test/SpellbookRewardStore.test.ets`
- Modify: `harmonyos/entry/src/test/List.test.ets`

- [ ] **Step 1: Write failing tests**

Add tests for:
- malformed JSON parses to version 1 with no claimed packs
- valid JSON removes empty/duplicate pack ids
- `claimPackId()` persists one pack id and is idempotent

Run: `cd harmonyos && hvigorw -p module=entry@default test`
Expected: FAIL because `SpellbookRewardStore.ets` does not exist.

- [ ] **Step 2: Implement store**

Use preferences name `wordmagic_spellbook_rewards`, key `snapshot_v1`, plus an injectable `StringPreferencesLike` test seam matching `WrongAnswerStore`. Expose `init(ctx)`, `load()`, `hasClaimed(packId)`, `claimPackId(packId)`, `parseSpellbookRewardSnapshot`, and `serializeSpellbookRewardSnapshot`.

- [ ] **Step 3: Verify green**

Run: `cd harmonyos && hvigorw -p module=entry@default test`
Expected: PASS for reward store tests.

### Task 3: Cover Metadata and Cache Plumbing

**Files:**
- Modify: `harmonyos/entry/src/main/ets/models/Pack.ets`
- Modify: `harmonyos/entry/src/main/ets/services/BuiltinPackLoader.ets`
- Modify: `harmonyos/entry/src/main/ets/services/GlobalPackService.ets`
- Modify: `harmonyos/entry/src/main/ets/services/RemoteAssetCache.ets`
- Modify tests: `Pack.test.ets`, `BuiltinPackLoader.test.ets`, `GlobalPackService.test.ets`, `RemoteAssetCache.test.ets`

- [ ] **Step 1: Write failing tests**

Add assertions that `SceneMetadata.spellbookCoverUrl` defaults to `undefined`, built-in/global parsers preserve `scene.spellbookCoverUrl`, global parser also accepts `scene.spellbook_cover_url`, and RemoteAssetCache stores `AssetKind.Cover` under a separate `covers` bucket.

Run: `cd harmonyos && hvigorw -p module=entry@default test`
Expected: FAIL on missing field/kind.

- [ ] **Step 2: Implement metadata/cache**

Add optional `spellbookCoverUrl?: string` to `SceneMetadata`, parse it in built-in/global loaders, and extend `RemoteAssetCache` with `AssetKind.Cover`, `ASSET_DIR_COVERS`, and `COVER_LRU_CAP`.

- [ ] **Step 3: Verify green**

Run: `cd harmonyos && hvigorw -p module=entry@default test`
Expected: PASS for changed unit tests.

### Task 4: Spellbook Page and Home Entry

**Files:**
- Create: `harmonyos/entry/src/main/ets/pages/SpellbookPage.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/HomePage.ets`
- Modify: `harmonyos/entry/src/main/resources/base/profile/main_pages.json`

- [ ] **Step 1: Add page and route**

Create `SpellbookPage` with stable IDs from `00-design.md`: `SpellbookPage`, `SpellbookBackButton`, `SpellbookTitle`, `SpellbookPackCover_<packId>`, `SpellbookPackProgress_<packId>`, `SpellbookPackRewardButton_<packId>`, `SpellbookPackRewardClaimed_<packId>`, `SpellbookCard_<packId>_<wordId>`, state-specific card IDs, `SpellbookLockedTip`, and word detail sheet IDs.

- [ ] **Step 2: Wire data loading**

On page load, call `loadHomeIntegration(ctx)`, initialize `LearningRecorder`, `SpellbookRewardStore`, and `CoinAccount`, then render all packs from `PackLibrary.allPacks()`. Use `icons/spellbook.png` as the default/built-in fallback cover for this Harmony slice.

- [ ] **Step 3: Wire reward claim**

When a pack is complete and not claimed, apply coin txn `spellbook-pack-complete:<packId>` with reason `spellbook_pack_complete`, flush CoinAccount, then persist the claimed pack id. Refresh the page state after success.

- [ ] **Step 4: Wire Home**

Add `HomeSpellbookButton` to the top toolbar using `icons/spellbook.png` and route to `pages/SpellbookPage`. Add `HomePackSpellbookCover` to the current adventure card with the current pack's cover/default image.

- [ ] **Step 5: Verify compile**

Run: `cd harmonyos && hvigorw assembleHap`
Expected: exit 0 and no `ArkTS:WARN` lines.

### Task 5: Version and Final Verification

**Files:**
- Modify: `harmonyos/AppScope/app.json5` if it is not already `0.9.5 / 1009005`
- Modify: `docs/features/2026-05-29-spellbook-v0-9-5/50-parity-checklist.md`

- [ ] **Step 1: Bump Harmony metadata**

Set Harmony version name/code to `0.9.5 / 1009005`.

- [ ] **Step 2: Run required checks**

Run:
- `cd harmonyos && hvigorw assembleHap`
- `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
- `cd harmonyos && hvigorw -p module=entry@default test`

Expected: build exit 0 with zero `ArkTS:WARN`; codelinter exit 0; unit tests exit 0.

- [ ] **Step 3: Update checklist**

Mark only the completed Harmony rows in `50-parity-checklist.md`. Leave iOS/Android unchecked until replication is approved.
