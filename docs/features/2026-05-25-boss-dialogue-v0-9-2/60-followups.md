# V0.9.2 Follow-ups

## 2026-05-25 HarmonyOS bugfix delta

- Re-battle launch now re-resolves a real `Pack` from `PackLibrary` when HomePage is still holding a synthetic first-frame fallback pack. This keeps the next battle's `TodaySessionPlan` scoped to the selected pack instead of falling back to the all-pack repository.
- Question-type-derived monster plans now rotate catalog indices within each `MonsterLevel` pool. Advanced and Super slots keep their difficulty level but no longer reuse the same representative monster throughout the battle.
- Regression coverage:
  - `PackHomeIntegration.resolveTodayAdventurePack` recovers the persisted selected pack when current HomePage state is synthetic.
  - `TodayAdventureBuilder` selected advanced question type plans produce multiple advanced catalog indices.

Replication note: iOS and Android should copy these semantics when V0.9.2 replication is approved; they should not implement pack retry from the global/all-pack word pool.

## 2026-05-25 Battle stage scheduling rule

Question types are stage-ordered by difficulty:

1. `choice` — 中文选词
2. `fill-letter` — 单字母填空
3. `fill-letter-medium` — 双字母填空
4. `spell` — 多字母选择
5. `sentence-cloze` — 句子填词

Within the user's enabled question-type set, battle stages run strictly from easy to hard. For a stage `QTn`, all words in the selected pack that support `QTn` must be served at least once before the scheduler may advance to `QTn+1`.

Question-stage coverage and monster lifetime are decoupled:

- If a monster dies before the current stage's word coverage is complete, spawn another monster from the same stage difficulty pool and continue with the next uncovered word.
- When the current stage's words are all covered, advance immediately to the next enabled stage with supported words, even if the current monster is still alive.
- The current monster keeps its original catalog identity and difficulty level until defeated, even if it survives across one or more question-stage advances.
- When that monster is defeated, spawn the next monster from the difficulty pool of the question stage that is active at that moment. For example, if `M1L1` survives through `QT1` and `QT2` and dies during `QT3`, the next monster is `M?L3`.
- If all enabled stages are complete but `monstersTotal` is not yet reached, stay on the last enabled supported stage and keep spawning monsters from that stage's difficulty pool until `monstersTotal` ends the battle.

Current platform difficulty mapping uses existing catalog levels:

| Question type | Stage label | Catalog pool |
| --- | --- | --- |
| `choice` | L1 | `MonsterLevel.Beginner` |
| `fill-letter` | L2 | `MonsterLevel.Intermediate` |
| `fill-letter-medium` | L3 | `MonsterLevel.Advanced` |
| `spell` | L4 | `MonsterLevel.Super` |
| `sentence-cloze` | L5 semantic stage | `MonsterLevel.Super` until a fifth art/catalog level exists |

This mapping is strict: a lower stage must not spawn a higher-level monster, and a higher stage must not fall back to a lower-level monster. If no word supports a question type, skip that stage and do not spawn its monster level.

Dialogue presentation follows catalog identity per battle:

- Super monsters use the same non-blocking bubble presentation as ordinary monsters.
- The first appearance of a catalog monster in a battle may show intro and defeat lines.
- If the same catalog monster appears again in the same battle, suppress both intro and defeat lines.

Battle monster cards show the current monster's level badge beside its name:

- Beginner: `L1`
- Intermediate: `L2`
- Advanced: `L3`
- Super: `L4`

Replication note: iOS and Android must implement the same state machine; do not reuse the older intro/challenge random scheduler.
