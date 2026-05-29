# V0.8.3 — Battle Polish — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> iOS / Android agents must verify the signature block at the bottom before starting replication. Refreshed on 2026-05-29 after the product owner confirmed V0.8.3 is complete.

## 1. Soft Gate (machine-checkable)

- [x] **Harmony implementation present in current worktree**
  - Evidence: `MAX_ACTIVE_PACKS = 10`, `appendOrRotate`, `MonsterLevel`, `bonusKillCount`, `BattleResultBonusCoinRow`, `DamageFloaterLabel`, `BattleDamageFloaterLabel_*`, and `MonsterBonusStar_*` are present under `harmonyos/entry/src/main/ets`.
- [x] **Harmony V0.8.4 built on top of V0.8.3**
  - Evidence: [`../2026-05-18-battle-balance-v0-8-4/00-design.md`](../2026-05-18-battle-balance-v0-8-4/00-design.md) names V0.8.3 as a prerequisite and preserves bonus / heavy-attack / floater rules.
- [x] **No server contract changed**
  - Evidence: V0.8.3 remains client-only; `shared/contracts/` and service routes are not part of the design.
- [x] **Replication approved**
  - Evidence: product owner request on 2026-05-23 explicitly asked to fill the V0.8.3 iOS / Android parity gaps after rebasing roadmap hygiene onto latest `main`.

## 2. Delta Letter

### 2.1 HarmonyOS delta already present

| Area | Evidence in HarmonyOS |
| --- | --- |
| Pack cap / auto-rotate | `PackSelectionService.MAX_ACTIVE_PACKS = 10`, `appendOrRotate`, `PackManagerAutoRotateToast`, `PackManagerCapRefuseToast` |
| Monster level metadata | `MonsterLevel`, `monsterLevelForCatalogIndex`, `levelBadgeZhForMonsterLevel`, `MonsterCodexLevelBadge_*` |
| Bonus / heavy attack | `rollMonsterBonus`, `computePlayerDamage`, `bonusKillCount`, `BattleResultBonusCoinRow` |
| Damage floaters | `DamageFloaterLabel`, `BattleDamageFloaterLabel_player`, `BattleDamageFloaterLabel_monster` |

### 2.2 Replica gaps to close before marking Done

| Gap | iOS current state | Android current state |
| --- | --- | --- |
| Active pack cap 10 + 11th-pack auto-rotate | Implemented: `PackSelectionStore.maxActivePacks = 10`, `appendOrRotate` | Implemented: `PackSelectionStore.MAX_ACTIVE = 10`, overflow activates by closing earliest unpinned |
| PackManager auto-rotate / all-pinned refusal stable IDs | Implemented: `PackManagerAutoRotateToast`, `PackManagerCapRefuseToast` | Implemented: `PackManagerAutoRotateToast`, `PackManagerCapRefuseToast` |
| `MonsterLevel` catalog parity + codex badges | Implemented: `MonsterLevel`, `levelBadgeZh`, `MonsterCodexLevelBadge_*` | Implemented: `MonsterLevel`, `levelLabelZh`, `MonsterCodexLevelBadge_*` |
| Bonus monster star + bonus coin row | Implemented: `MonsterBonusStar_*`, `BattleResultBonusCoinRow`, `bonusKillCount` | Implemented: `MonsterBonusStar_*`, `BattleResultBonusCoinRow`, `bonusKillCount` |
| HP-2 heavy attack by advanced/super monsters | Implemented in `BattleEngine` with injectable random roll | Implemented in `BattleEngine` with injectable random roll |
| Damage floater labels | Present | Present |

## 3. Human-Confirm Signature Block

```yaml
approved_by: matianyi
approved_at: 2026-05-23
replication_approved: true
notes: V0.8.3 is complete by product-owner confirmation; it is no longer a verification blocker.
```
