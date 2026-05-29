# V0.9.5 Spellbook Codex — Parity Checklist

> Inputs (frozen): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)

The feature is Done only when every applicable row below is green on HarmonyOS, iOS, and Android.

## 1. User flows

| Flow | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Open Spellbook from Home | [x] | [x] | [x] | `HomeSpellbookButton` to `SpellbookPage`. |
| View pack covers and word-card states | [x] | [x] | [x] | Locked / seen / mastered cards. |
| Open seen/mastered word detail | [x] | [x] | [x] | Grey cards are viewable; locked cards show guidance. |
| Claim completed pack reward once | [x] | [x] | [x] | +50 coins, idempotent by `packId`. |

## 2. Stable IDs

IDs are listed in [`00-design.md`](00-design.md) §5 and must be implemented verbatim.

## 3. Pure-rule tests

| Rule | Harmony | iOS | Android |
| --- | --- | --- | --- |
| Card state derives from missing/seen/mastered stats | [x] | [x] | [x] |
| Pack complete only when all pack words are mastered | [x] | [x] | [x] |
| Reward can be claimed once per `packId` | [x] | [x] | [x] |
| Cover fallback order is built-in asset, remote cached URL, default asset | [x] | [x] | [ ] |

## 4. Contract usage

| Contract / fixture | Harmony | iOS | Android |
| --- | --- | --- | --- |
| `scene.spellbookCoverUrl` in pack scene metadata | [x] | [x] | [x] |

## 5. Server / Admin Acceptance

| Requirement | Status | Notes |
| --- | --- | --- |
| App parent import can run cover generation inside the existing asynchronous import job | [ ] | Import UI remains usable while provider runs. |
| Web admin create saves the pack record before any image generation starts | [ ] | Cover generation is manual from edit/detail page. |
| Pack publish remains allowed without a confirmed cover | [ ] | Clients use the default cover fallback. |

## 6. Screenshots

| Screen | `assets/screenshots/harmonyos/...` | `assets/screenshots/ios/...` | `assets/screenshots/android/...` |
| --- | --- | --- | --- |
| Home with spellbook cover/button | [ ] | [ ] | [ ] |
| Spellbook page | [ ] | [ ] | [ ] |
| Spellbook word detail | [ ] | [ ] | [ ] |

## 7. Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `harmonyos/AppScope/app.json5` `versionName` / `versionCode` | `0.9.5` / `1009005` |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | `0.9.5` / `1009005` |
| Android | `android/app/build.gradle.kts` `versionName` / `versionCode` | `0.9.5` / `1009005` |

## 8. Sign-off

```yaml
done_by:
done_at:
notes: "Client replication implemented and verified on iOS/Android; screenshots and server/admin acceptance remain open."
```
