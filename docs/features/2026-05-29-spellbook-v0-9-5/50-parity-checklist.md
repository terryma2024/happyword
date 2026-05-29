# V0.9.5 Spellbook Codex — Parity Checklist

> Inputs (frozen): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)

The feature is Done only when every applicable row below is green on HarmonyOS, iOS, and Android.

## 1. User flows

| Flow | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Open Spellbook from Home | [ ] | [ ] | [ ] | `HomeSpellbookButton` to `SpellbookPage`. |
| View pack covers and word-card states | [ ] | [ ] | [ ] | Locked / seen / mastered cards. |
| Open seen/mastered word detail | [ ] | [ ] | [ ] | Grey cards are viewable; locked cards show guidance. |
| Claim completed pack reward once | [ ] | [ ] | [ ] | +50 coins, idempotent by `packId`. |

## 2. Stable IDs

IDs are listed in [`00-design.md`](00-design.md) §5 and must be implemented verbatim.

## 3. Pure-rule tests

| Rule | Harmony | iOS | Android |
| --- | --- | --- | --- |
| Card state derives from missing/seen/mastered stats | [ ] | [ ] | [ ] |
| Pack complete only when all pack words are mastered | [ ] | [ ] | [ ] |
| Reward can be claimed once per `packId` | [ ] | [ ] | [ ] |
| Cover fallback order is built-in asset, remote cached URL, default asset | [ ] | [ ] | [ ] |

## 4. Contract usage

| Contract / fixture | Harmony | iOS | Android |
| --- | --- | --- | --- |
| `scene.spellbookCoverUrl` in pack scene metadata | [ ] | [ ] | [ ] |

## 5. Screenshots

| Screen | `assets/screenshots/harmonyos/...` | `assets/screenshots/ios/...` | `assets/screenshots/android/...` |
| --- | --- | --- | --- |
| Home with spellbook cover/button | [ ] | [ ] | [ ] |
| Spellbook page | [ ] | [ ] | [ ] |
| Spellbook word detail | [ ] | [ ] | [ ] |

## 6. Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `harmonyos/AppScope/app.json5` `versionName` / `versionCode` | `0.9.5` / `1009005` |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | `0.9.5` / `1009005` |
| Android | `android/app/build.gradle.kts` `versionName` / `versionCode` | `0.9.5` / `1009005` |

## 7. Sign-off

```yaml
done_by:
done_at:
notes:
```
