# V0.9.2 Boss Dialogue and Built-in Pack Expansion — iOS Replication Plan

> Inputs: [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md), [`50-parity-checklist.md`](50-parity-checklist.md)
>
> Status: **Done**. This plan records the completed iOS parity work rather than future implementation tasks.

## Scope

- [x] Verified `replication_approved: true` before starting iOS replication.
- [x] Added the 100-entry bilingual monster dialogue catalog and resolver fallback coverage.
- [x] Expanded the five built-in packs to 15 sentence-cloze-ready words each.
- [x] Implemented first-install battle defaults: `monstersTotal = 10`, monster HP `5`, player HP `10`.
- [x] Ported the battle-stage scheduler semantics: enabled question types progress easy to hard; current monster can survive stage advancement; the next monster uses the active stage level when spawned.
- [x] Kept retry / re-battle scoped to the selected pack.
- [x] Added the reusable `MessageBubble` component and message-bubble lab.
- [x] Replaced boss intro presentation with the shared non-blocking `BattleBossIntro*` bubble for all monster levels, including Super.
- [x] Kept defeat bubbles disabled for V0.9.2.
- [x] Added compact `L1` / `L2` / `L3` / `L4` monster level labels.
- [x] Tuned the iOS boss intro bubble placement leftward after simulator review.

## Verification

- [x] Focused `BattleEngineTests` passed for boss intro bubble placement.
- [x] Focused `WordMagicGameUITests` passed for catalog dialogue and level label.
- [x] Version metadata is `0.9.2 / 1009002`.
- [x] iOS parity rows in [`50-parity-checklist.md`](50-parity-checklist.md) are all green.

## Follow-up

Boss defeat / exit presentation is intentionally outside V0.9.2. Reopen it as a separate future design so exit copy can be shown without overlapping the next boss intro. Tracking notes live in [`60-followups.md`](60-followups.md).
