# V0.9.5 Spellbook Codex — Android Replication Plan

> Inputs: [`00-design.md`](00-design.md), signed [`20-replication-trigger.md`](20-replication-trigger.md)

Android replication starts after `20-replication-trigger.md` has `replication_approved: true`.

## Tasks

1. Core model and persistence
   - Add `scene.spellbookCoverUrl` to cached and built-in pack parsing while keeping older JSON compatible.
   - Add pure spellbook progress/state rules and unit tests for locked, seen, mastered, completion, zero-word packs, and one-time 50-coin reward eligibility.
   - Add local claimed-pack persistence in the Android local progress repository; keep reward accounting client-only for V0.9.5.

2. Assets
   - Copy the six Harmony cover PNGs into Android drawable resources.
   - Use bundled covers for the five built-in packs plus the default fallback; fall back to default for future remote/custom packs if no local cover exists.

3. UI
   - Add `AppRoute.Spellbook`, home entry button `HomeSpellbookButton`, and selected pack cover `HomePackSpellbookCover`.
   - Add `SpellbookScreen` with stable test tags from `00-design.md`, card states, word detail dialog, locked tip, pack progress, and reward claim button/claimed state.

4. Release metadata and verification
   - Bump Android version to `0.9.5 / 1009005`.
   - Run targeted Android unit tests and a debug build/test command.

## Verification

- `GRADLE_USER_HOME=/private/tmp/happyword-gradle ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.SpellbookServiceTest` — passed.
- `GRADLE_USER_HOME=/private/tmp/happyword-gradle ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.data.AndroidLocalProgressRepositoriesTest` — passed.
- `GRADLE_USER_HOME=/private/tmp/happyword-gradle ./gradlew testDebugUnitTest` — passed.
