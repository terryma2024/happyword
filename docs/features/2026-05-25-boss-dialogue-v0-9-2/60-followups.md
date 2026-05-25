# V0.9.2 Follow-ups

## 2026-05-25 HarmonyOS bugfix delta

- Re-battle launch now re-resolves a real `Pack` from `PackLibrary` when HomePage is still holding a synthetic first-frame fallback pack. This keeps the next battle's `TodaySessionPlan` scoped to the selected pack instead of falling back to the all-pack repository.
- Question-type-derived monster plans now rotate catalog indices within each `MonsterLevel` pool. Advanced and Super slots keep their difficulty level but no longer reuse the same representative monster throughout the battle.
- Regression coverage:
  - `PackHomeIntegration.resolveTodayAdventurePack` recovers the persisted selected pack when current HomePage state is synthetic.
  - `TodayAdventureBuilder` selected advanced question type plans produce multiple advanced catalog indices.

Replication note: iOS and Android should copy these semantics when V0.9.2 replication is approved; they should not implement pack retry from the global/all-pack word pool.
