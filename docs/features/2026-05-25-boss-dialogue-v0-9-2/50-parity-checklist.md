# V0.9.2 Boss Dialogue and Built-in Pack Expansion — Parity Checklist

> Inputs (frozen): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
>
> The feature is **Done** only when every row below is `[x]` in all three platform columns. iOS and Android remain blocked until the Harmony replication trigger is human-approved.

| Parity item | HarmonyOS | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| 100-entry bilingual Boss dialogue catalog exists. | [x] | [ ] | [ ] | Harmony `MonsterCatalog.ets`; source copy `boss-dialogue-catalog.md` |
| Ordinary Level 1 / 2 / 3 intro uses `BattleBossIntro*` bubble. | [x] | [ ] | [ ] | `BattleFlow.bossDialogueIntroAndDefeatOverlaysRender` |
| SuperBoss intro uses `BattleSuperBossIntro*` ornate auto banner. | [x] | [ ] | [ ] | `BattleFlow.superBossIntroUsesBannerAndAutoDismisses` |
| Defeat line uses `BattleBossDefeat*` bubble for every monster. | [x] | [ ] | [ ] | `BattleFlow.bossDialogueIntroAndDefeatOverlaysRender` |
| Built-in packs contain 15 sentence-cloze-ready words each. | [x] | [ ] | [ ] | `BuiltinPackLoader.test.ets`; rawfile count check |
| First-install defaults are 10 monsters / 5 monster HP / 10 player HP. | [x] | [ ] | [ ] | `LocalUnit.test.ets`; `TodayAdventureBuilder.test.ets` |

## Stable IDs

| Stable ID | HarmonyOS | iOS | Android |
| --- | --- | --- | --- |
| `BattleBossIntroBubble` | [x] | [ ] | [ ] |
| `BattleBossIntroName` | [x] | [ ] | [ ] |
| `BattleBossIntroLineEn` | [x] | [ ] | [ ] |
| `BattleBossIntroLineZh` | [x] | [ ] | [ ] |
| `BattleSuperBossIntroBanner` | [x] | [ ] | [ ] |
| `BattleSuperBossIntroTitle` | [x] | [ ] | [ ] |
| `BattleSuperBossIntroLineEn` | [x] | [ ] | [ ] |
| `BattleSuperBossIntroLineZh` | [x] | [ ] | [ ] |
| `BattleBossDefeatBubble` | [x] | [ ] | [ ] |
| `BattleBossDefeatName` | [x] | [ ] | [ ] |
| `BattleBossDefeatLineEn` | [x] | [ ] | [ ] |
| `BattleBossDefeatLineZh` | [x] | [ ] | [ ] |

## Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `harmonyos/AppScope/app.json5` `versionName` / `versionCode` | `0.9.2` / `1009002` |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | pending replication |
| Android | `versionName` / `versionCode` | pending replication |

## Sign-off

- [ ] Owner verified all rows above are green.
- [ ] Owner ran a smoke pass on at least one device per platform.
- [ ] Feature linked from [`docs/features/README.md`](../../features/README.md) is marked `Done`.

```yaml
done_by:
done_at:
notes:
```
