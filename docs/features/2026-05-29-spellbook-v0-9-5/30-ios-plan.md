# V0.9.5 Spellbook Codex — iOS Replication Plan

> Inputs: [`00-design.md`](00-design.md), signed [`20-replication-trigger.md`](20-replication-trigger.md)

iOS replication starts after `20-replication-trigger.md` has `replication_approved: true`.

## Tasks

1. Core model and persistence
   - Add `scene.spellbookCoverUrl` decoding while keeping existing pack JSON compatible.
   - Add pure spellbook progress/state rules and unit tests for locked, seen, mastered, completion, zero-word packs, and one-time 50-coin reward eligibility.
   - Add local claimed-pack persistence under `UserDefaults`; keep reward accounting client-only for V0.9.5.

2. Assets
   - Copy the six Harmony cover PNGs into `Assets.xcassets` as transparent 128x128 image sets.
   - Use bundled covers for the five built-in packs plus the default fallback; tolerate remote cover URLs for future server-created packs.

3. UI
   - Add `AppRoute.spellbook`, `openSpellbook()`, and a home entry button with `HomeSpellbookButton`.
   - Render the selected pack cover on home with `HomePackSpellbookCover`.
   - Add `SpellbookView` with stable accessibility identifiers from `00-design.md`, card states, word detail sheet, locked tip, pack progress, and reward claim button/claimed state.

4. Release metadata and verification
   - Bump iOS marketing/build version to `0.9.5 / 1009005`.
   - Run targeted iOS unit tests, regenerate the Xcode project if needed, and run a simulator build/test command.

## Verification

- `xcodegen` was unavailable on this machine, so `ios/WordMagicGame.xcodeproj/project.pbxproj` was narrowly synced for the new Swift/test files and version metadata.
- `xcodebuild test -project WordMagicGame.xcodeproj -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameTests/SpellbookTests -derivedDataPath /private/tmp/wordmagic-spellbook-ios-dd` — 4 tests passed.
- `xcodebuild test -project WordMagicGame.xcodeproj -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameTests -derivedDataPath /private/tmp/wordmagic-spellbook-ios-full-dd` — 179 tests passed.
