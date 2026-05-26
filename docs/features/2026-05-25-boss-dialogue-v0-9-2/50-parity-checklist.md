# V0.9.2 Boss Dialogue and Built-in Pack Expansion — Parity Checklist

> Inputs (frozen): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
>
> The feature is **Done** only when every row below is `[x]` in all three platform columns. iOS and Android remain blocked until the Harmony replication trigger is human-approved.

| Parity item | HarmonyOS | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| 100-entry bilingual Boss dialogue catalog exists. | [x] | [x] | [x] | Harmony `monster_catalog.json`; iOS / Android copied catalog rows and tests. |
| Level 1 / 2 / 3 intro uses non-blocking `BattleBossIntro*` `MessageBubble`. | [x] | [x] | [x] | Ordinary intro only; no input-blocking banner. |
| SuperBoss intro uses the same non-blocking `BattleBossIntro*` bubble. | [x] | [x] | [x] | Updated follow-up decision; ornate `BattleSuperBossIntro*` banner retired for V0.9.2. |
| Defeat line bubble is disabled for this version. | [x] | [x] | [x] | Retain dialogue data for future design; do not show `BattleBossDefeat*` UI in battle. |
| Built-in packs contain 15 sentence-cloze-ready words each. | [x] | [x] | [x] | Raw pack fixtures expanded and tested. |
| First-install defaults are 10 monsters / 5 monster HP / 10 player HP. | [x] | [x] | [x] | Saved configs remain preserved. |
| Battle stages progress strictly by enabled question difficulty. | [x] | [x] | [x] | Current monster can survive stage advancement; next monster uses active stage level. |
| Retry / re-battle stays scoped to the selected pack. | [x] | [x] | [x] | No fallback to global/all-pack pool for selected-pack battles. |
| Monster card shows compact `L1` / `L2` / `L3` / `L4` badge. | [x] | [x] | [x] | Badge follows catalog monster level. |

## Stable IDs

| Stable ID | HarmonyOS | iOS | Android |
| --- | --- | --- | --- |
| `BattleBossIntroBubble` | [x] | [x] | [x] |
| `BattleBossIntroName` | [x] | [x] | [x] |
| `BattleBossIntroLineEn` | [x] | [x] | [x] |
| `BattleBossIntroLineZh` | [x] | [x] | [x] |
| `BattleMonsterLevelLabel` | [x] | [x] | [x] |
| `BattleSuperBossIntroBanner` | retired | retired | retired |
| `BattleSuperBossIntroTitle` | retired | retired | retired |
| `BattleSuperBossIntroLineEn` | retired | retired | retired |
| `BattleSuperBossIntroLineZh` | retired | retired | retired |
| `BattleBossDefeatBubble` | disabled | disabled | disabled |
| `BattleBossDefeatName` | disabled | disabled | disabled |
| `BattleBossDefeatLineEn` | disabled | disabled | disabled |
| `BattleBossDefeatLineZh` | disabled | disabled | disabled |

## Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `harmonyos/AppScope/app.json5` `versionName` / `versionCode` | `0.9.2` / `1009002` |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | `0.9.2` / `1009002` |
| Android | `versionName` / `versionCode` | `0.9.2` / `1009002` |

## Sign-off

- [ ] Owner verified all rows above are green.
- [ ] Owner ran a smoke pass on at least one device per platform.
- [ ] Feature linked from [`docs/features/README.md`](../../features/README.md) is marked `Done`.

```yaml
done_by:
done_at:
notes:
```
