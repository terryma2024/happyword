# V0.9.2 — Boss Dialogue and Built-in Pack Expansion — Cross-Platform Design

> Feature ID: `2026-05-25-boss-dialogue-v0-9-2`
> Status: `draft`
> Owner: Terry Ma
> Last updated: 2026-05-25

This document is the platform-neutral source of truth for V0.9.2 Boss personality dialogue, built-in pack expansion, and initial battle defaults. HarmonyOS implements first; iOS and Android replicate only after the Harmony soft gate and human signature in [`20-replication-trigger.md`](20-replication-trigger.md).

## 1. Motivation

V0.9.1 added sentence cloze questions, moving the learning loop from word recognition toward context understanding. The battle loop still treats most monsters as visual targets rather than characters. V0.9.2 gives every current monster a short personality beat at entry and defeat, while also increasing built-in pack word counts so longer initial battles can show more monster variety without repeating the same small word pool too quickly.

## 2. Goals

- Add short bilingual Boss dialogue for all 100 current `MonsterCatalog` entries.
- Show lightweight intro bubbles for Level 1 / 2 / 3 monsters.
- Show a more ornate, short, auto-dismissing intro banner for SuperBoss monsters.
- Show a short defeat bubble for every defeated monster.
- Use English as the primary line and Chinese as smaller supporting text.
- Keep the tone playful and challenging, with slightly more fairy-tale drama for SuperBoss entries.
- Expand each of the five built-in packs from 10 words to 15 words.
- Change first-install battle defaults to `monstersTotal=10`, `monsterMaxHp=5`, and `playerMaxHp=10`.
- Preserve existing saved `GameConfig` values instead of forcibly overwriting returning users.

## 3. Non-Goals

- No server endpoint, OpenAPI, or shared client runtime changes.
- No admin or parent editing UI for dialogue copy.
- No LLM generation flow; content production and review remain a V0.9.6 concern.
- No region story card, chapter intro, or chapter completion celebration; those remain V0.9.3.
- No battle BGM, audio mixing, or voice acting; those remain V0.10.
- No click-to-start interaction for SuperBoss intro banners.
- No result-page redesign for defeat dialogue.

## 4. User Flows

### 4.1 Ordinary Monster Intro

```mermaid
flowchart TD
  start["Battle spawns Level 1 / 2 / 3 monster"] --> lookup["Resolve monster dialogue"]
  lookup --> bubble["Show intro bubble near monster"]
  bubble --> question["Question remains playable"]
  question --> fade["Bubble auto fades after about 1.0s"]
```

### 4.2 SuperBoss Intro

```mermaid
flowchart TD
  start["Battle spawns SuperBoss"] --> lookup["Resolve SuperBoss dialogue"]
  lookup --> banner["Show ornate intro banner"]
  banner --> block["Briefly block answer input / question reveal"]
  block --> dismiss["Auto dismiss after about 1.2s"]
  dismiss --> question["Normal question UI becomes playable"]
```

### 4.3 Defeat Dialogue

```mermaid
flowchart TD
  defeat["Monster HP reaches 0"] --> lookup["Resolve defeat dialogue"]
  lookup --> bubble["Show short defeat bubble"]
  bubble --> next{"More monsters?"}
  next -->|yes| spawn["Transition to next monster"]
  next -->|no| result["Existing result page"]
```

## 5. Stable Test IDs (parity contract)

Every ID listed here must be implemented verbatim on all three platforms. Agents may not rename them per platform.

| ID | Where it lives | Purpose |
| --- | --- | --- |
| `BattleBossIntroBubble` | Ordinary monster intro overlay | Asserts Level 1 / 2 / 3 intro is lightweight bubble UI. |
| `BattleBossIntroName` | Ordinary monster intro overlay | Shows the monster display name. |
| `BattleBossIntroLineEn` | Ordinary monster intro overlay | Shows the English intro line. |
| `BattleBossIntroLineZh` | Ordinary monster intro overlay | Shows the Chinese support line. |
| `BattleSuperBossIntroBanner` | SuperBoss intro overlay | Asserts SuperBoss uses the ornate banner path. |
| `BattleSuperBossIntroTitle` | SuperBoss intro overlay | Shows SuperBoss title / monster display name. |
| `BattleSuperBossIntroLineEn` | SuperBoss intro overlay | Shows the English SuperBoss intro line. |
| `BattleSuperBossIntroLineZh` | SuperBoss intro overlay | Shows the Chinese support line. |
| `BattleBossDefeatBubble` | Defeat overlay | Asserts every defeated monster can show a defeat line. |
| `BattleBossDefeatName` | Defeat overlay | Shows the defeated monster display name. |
| `BattleBossDefeatLineEn` | Defeat overlay | Shows the English defeat line. |
| `BattleBossDefeatLineZh` | Defeat overlay | Shows the Chinese support line. |

Platform mapping reminder:

- HarmonyOS: ArkUI `.id('<ID>')` and the `findComponent` lookup used by ohosTest.
- iOS: SwiftUI `.accessibilityIdentifier("<ID>")`.
- Android: Compose `Modifier.testTag("<ID>")`; use `contentDescription` only when the same string also doubles as accessibility text.

## 6. Domain Rules

### 6.1 Dialogue Data

Each current `MonsterCatalog` entry must have complete global default dialogue:

```text
MonsterDialogue {
  introLine.en
  introLine.zh
  defeatLine.en
  defeatLine.zh
}
```

The source copy for all 100 entries is [`boss-dialogue-catalog.md`](boss-dialogue-catalog.md). Implementations may store it in platform-native code or JSON, but the shipped content must match that catalog unless the design document is updated first.

Future pack / scene overrides are allowed by the model, but V0.9.2 does not ship remote editing or server publication for them. Dialogue resolution uses this priority:

```text
pack / scene override for selected monster
→ global monster dialogue
→ safe fallback generated from monster name
```

The fallback is defensive only. Tests must assert every current catalog index has complete bilingual dialogue.

### 6.2 Presentation by Level

```text
function introPresentation(level):
  if level == Super:
    return ornate_auto_banner
  return small_nonblocking_bubble
```

Ordinary Level 1 / 2 / 3 intro bubbles:

- Appear near the monster.
- Do not pause the battle.
- Do not require a tap.
- Fade after about 1.0 second.
- Must not block answer options, HP, or the main prompt.

SuperBoss intro banners:

- Use a more ornate visual treatment: gold edge, star accents, and a SuperBoss label.
- Briefly block answer input or question reveal for about 1.2 seconds.
- Auto dismiss without requiring a tap.
- Must keep the battle page readable on phone and tablet viewports.

Defeat bubbles:

- Appear for every defeated monster, regardless of level.
- Use the same short bubble style as ordinary intro, with defeat copy.
- May overlap the existing damage / defeat animation window.
- Auto fade before the next monster or result page.
- Do not move `defeatLine` into ResultPage.

### 6.3 Copy Rules

- English is primary; Chinese is supporting text below it.
- English should be short and child-readable, preferably no more than 32 characters.
- Chinese should be natural, not stiff literal translation, preferably no more than 18 Chinese characters.
- Intro copy should sound like a playful challenge.
- Defeat copy should sound surprised, impressed, or gently yielding.
- SuperBoss copy may be slightly more fairy-tale dramatic.
- Copy must not frighten, shame, belittle, or use adult themes.
- Copy should avoid broad repeated formulas across the 100-entry catalog.

### 6.4 Built-in Pack Expansion

The five built-in packs must expand from 10 words to 15 words each:

- `fruit-forest`
- `school-castle`
- `home-cottage`
- `animal-safari`
- `ocean-realm`

Required additions:

| Pack | New word ids / words | Chinese meanings |
| --- | --- | --- |
| `fruit-forest` | `fruit-strawberry` / `strawberry`, `fruit-pineapple` / `pineapple`, `fruit-watermelon` / `watermelon`, `fruit-kiwi` / `kiwi`, `fruit-blueberry` / `blueberry` | 草莓、菠萝、西瓜、猕猴桃、蓝莓 |
| `school-castle` | `place-restaurant` / `restaurant`, `place-cinema` / `cinema`, `place-airport` / `airport`, `place-playground` / `playground`, `place-bookstore` / `bookstore` | 餐厅、电影院、机场、操场、书店 |
| `home-cottage` | `home-kitchen` / `kitchen`, `home-bathroom` / `bathroom`, `home-clock` / `clock`, `home-phone` / `phone`, `home-fridge` / `fridge` | 厨房、浴室、时钟、电话、冰箱 |
| `animal-safari` | `animal-bird` / `bird`, `animal-elephant` / `elephant`, `animal-monkey` / `monkey`, `animal-rabbit` / `rabbit`, `animal-panda` / `panda` | 鸟、大象、猴子、兔子、熊猫 |
| `ocean-realm` | `ocean-shell` / `shell`, `ocean-coral` / `coral`, `ocean-beach` / `beach`, `ocean-wave` / `wave`, `ocean-seaweed` / `seaweed` | 贝壳、珊瑚、海滩、海浪、海草 |

New built-in words must include:

```text
id
word
meaningZh
distractors
example.en
example.zh
```

`example.en` and `example.zh` are required because V0.9.1 sentence cloze is default-enabled. New words must support sentence cloze under the V0.9.1 matching rules.

### 6.5 Initial Battle Defaults

First-install battle defaults change to:

```text
monstersTotal = 10
monsterMaxHp = 5
playerMaxHp = 10
```

These defaults apply only when no saved `GameConfig` exists. Existing user-saved config snapshots are not forcibly overwritten.

## 7. Persistence and Migration

| Key | Type | Default | Migration from older snapshot |
| --- | --- | --- | --- |
| Existing `GameConfig.monstersTotal` | integer | `10` | Only new / missing config uses this default. Preserve saved value. |
| Existing `GameConfig.monsterMaxHp` | integer | `5` | Only new / missing config uses this default. Preserve saved value. |
| Existing `GameConfig.playerMaxHp` | integer | `10` | Already the current default; preserve saved value. |
| New platform-local monster dialogue table | static data | complete 100-entry catalog | No user persistence; shipped with app. |
| Future pack / scene dialogue overrides | optional structured data | absent | V0.9.2 parser may ignore or safely carry unknown fields; no server source in this version. |

No snapshot-version bump is required unless a platform's existing config persistence cannot distinguish missing config from a saved older default. If such a platform-specific issue exists, the platform plan must spell out the migration rule and tests.

## 8. Cross-Platform Contracts

No server or OpenAPI changes.

- New / changed endpoints: None.
- Schema additions: None for server contracts.
- Fixture diffs under [`shared/fixtures/`](../../../shared/fixtures/): None required.
- Regenerate OpenAPI: Not required.
- Server test requirement: Not applicable unless implementation unexpectedly touches `server/`.

The cross-platform content contract is local to this feature folder:

- [`boss-dialogue-catalog.md`](boss-dialogue-catalog.md) is the copy source of truth.
- Each platform's `MonsterCatalog` / equivalent dialogue table must cover catalog indices 1 through 100.
- Built-in pack word additions must remain semantically aligned across HarmonyOS JSON, iOS JSON, and Android built-in constants.

## 9. Edge Cases and Error Paths

- Missing dialogue for a monster: use safe fallback generated from monster name and log a local warning; tests should prevent this in shipped data.
- Missing only one language: use fallback for the missing line; tests should prevent this in shipped data.
- Long line: allow wrapping to two lines, shrink within existing platform conventions, and avoid covering answer controls.
- SuperBoss transition interrupted by battle end: cancel the intro banner and show normal result / defeat flow.
- User changes saved config: preserve their chosen `monstersTotal`, `monsterMaxHp`, and `playerMaxHp`.
- Sparse remote or family packs: built-in pack expansion does not impose a 15-word minimum on remote/family packs.

## 10. Telemetry / Logs

No analytics events are required. Optional local debug logs may be platform-specific and must not become parity requirements.

If a platform logs missing dialogue, use this stable prefix:

| Event | Trigger | Fields |
| --- | --- | --- |
| `boss_dialogue_missing` | Missing local dialogue for a catalog index | `catalogIndex`, `monsterName`, `lineKind` |

## 11. Accessibility / Localization

- Screen readers should expose the same text as visible UI: monster name, English line, then Chinese line.
- Ordinary intro and defeat bubbles are informational overlays and should not steal focus from answer controls.
- SuperBoss intro banner may be announced as a temporary status message, but it must not require a separate dismiss action.
- Chinese support text is always visible in V0.9.2, not hidden behind a setting.
- Keep visible English and Chinese copy identical across HarmonyOS, iOS, and Android.

## 12. Open Questions

None for V0.9.2. Future V0.9.3 region story copy may reuse the dialogue override shape or introduce a separate scene-story block, but that decision is outside this feature.

## 13. References

- [`docs/WordMagicGame_roadmap.md`](../../WordMagicGame_roadmap.md) V0.9.2 row.
- [`docs/features/2026-05-24-sentence-cloze-v0-9-1/00-design.md`](../2026-05-24-sentence-cloze-v0-9-1/00-design.md) for sentence cloze example requirements.
- HarmonyOS baseline: `harmonyos/entry/src/main/ets/data/MonsterCatalog.ets`, `harmonyos/entry/src/main/ets/pages/BattlePage.ets`, `harmonyos/entry/src/main/resources/rawfile/data/builtin/*.json`.
- iOS baseline: `ios/WordMagicGame/Core/MonsterCodex.swift`, `ios/WordMagicGame/Features/CoreLoop/BattleView.swift`, `ios/WordMagicGame/Resources/BuiltinPacks/*.json`.
- Android baseline: `android/app/src/main/java/cool/happyword/wordmagic/core/GrowthModels.kt`, `android/app/src/main/java/cool/happyword/wordmagic/ui/battle/BattleUi.kt`, `android/app/src/main/java/cool/happyword/wordmagic/core/PackModels.kt`.
