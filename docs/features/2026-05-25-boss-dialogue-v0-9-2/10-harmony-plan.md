# V0.9.2 Boss Dialogue and Built-in Pack Expansion — HarmonyOS Implementation Plan

> Inputs: [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md), [`50-parity-checklist.md`](50-parity-checklist.md)
>
> Status: **Done**. This file records the completed HarmonyOS implementation scope and verification evidence. The original task-by-task draft was superseded during tuning: SuperBoss now uses the same non-blocking `MessageBubble` intro as ordinary monsters, and defeat bubbles are disabled for V0.9.2.

## Scope

- [x] Added the 100-entry bilingual Boss dialogue catalog from [`boss-dialogue-catalog.md`](boss-dialogue-catalog.md).
- [x] Extracted the monster catalog to `harmonyos/entry/src/main/ets/data/monster_catalog.json` and load it during initialization.
- [x] Added reusable `MessageBubble` / `MessageBubbleGeometry` / `MessageBubbleLabState` components.
- [x] Added the `MessageBubbleLabPage` debug surface under the backend service developer tab.
- [x] Swapped battle boss intro messages to the shared `MessageBubble` component.
- [x] Used the same non-blocking intro presentation for Level 1 / 2 / 3 and Super monsters.
- [x] Disabled boss defeat bubbles for V0.9.2 to avoid overlap with the next monster intro.
- [x] Suppressed repeated intro lines when the same catalog monster appears again in the same battle.
- [x] Expanded the five built-in packs from 10 to 15 sentence-cloze-ready words each.
- [x] Set first-install battle defaults to `monstersTotal = 10`, monster HP `5`, and player HP `10`, while preserving existing saved configs.
- [x] Fixed selected-pack retry so re-battle stays scoped to the chosen pack.
- [x] Fixed monster variety so advanced / Super pools rotate catalog entries rather than repeating one representative monster.
- [x] Implemented the strict battle-stage scheduler: enabled question types progress easy to hard; a monster can survive across stage advancement; the next spawned monster uses the active stage level.
- [x] Added compact `L1` / `L2` / `L3` / `L4` monster level labels.
- [x] Updated HarmonyOS version metadata to `0.9.2 / 1009002`.

## Verification

- [x] Harmony no-device unit tests passed for monster dialogue, built-in packs, battle scheduler, message-bubble geometry, config defaults, pack retry, and plan generation.
- [x] `hvigorw assembleHap` passed with zero `ArkTS:WARN` lines.
- [x] CodeLinter passed with no defects.
- [x] BattleFlow ohosTest coverage passed for boss intro bubble and level label.
- [x] Latest debug HAP was rebuilt and installed to device `3QDBB24806202044` on 2026-05-26 after switching to a Development signing certificate.
- [x] Harmony parity rows in [`50-parity-checklist.md`](50-parity-checklist.md) are all green.

## Follow-up

Boss defeat / exit presentation is intentionally outside V0.9.2. Reopen it as a separate future design so exit copy can be shown without overlapping the next boss intro. Tracking notes live in [`60-followups.md`](60-followups.md).
