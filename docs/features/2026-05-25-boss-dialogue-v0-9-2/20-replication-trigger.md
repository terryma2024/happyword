# V0.9.2 Boss Dialogue and Built-in Pack Expansion — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document is the single gate that controls when iOS / Android replication may begin. iOS and Android agents must verify the signature block at the bottom is filled in before starting any work in `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

- [x] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: 2026-05-25, final line `BUILD SUCCESSFUL in 2 s 952 ms`.
- [x] **ohosTest UI tests green** — `scripts/run_ui_tests.sh --suite BattleFlow --rebuild`
  - Evidence: 2026-05-25, `Tests run: 4, Failure: 0, Error: 0, Pass: 4, Ignore: 0`; `TestFinished-ResultCode: 0`.
- [x] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: 2026-05-25, final line `BUILD SUCCESSFUL in 3 s 854 ms`; output contained no `ArkTS:WARN` lines. A toolchain `sun.misc.Unsafe` warning was present and is not an ArkTS warning.
- [x] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: 2026-05-25, final line `No defects found in your code.`
- [x] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: already `versionName=0.9.2` `versionCode=1009002` in this branch.
  - To: `versionName=0.9.2` `versionCode=1009002`.
- [ ] **Feature merged to main**
  - Commit: pending owner integration.
- [ ] **Screenshots refreshed** — for every screen this feature visibly changed
  - Files updated under `assets/screenshots/harmonyos/`: pending screenshot pass.
- [x] **Server contracts up to date** — no server/shared contract change.
  - Regenerated: N/A.
  - Tests: N/A.
  - Fixture diffs: N/A.

## 2. Delta Letter

### 2.1 New / changed code

| Layer | HarmonyOS files |
| --- | --- |
| Data | `harmonyos/entry/src/main/ets/data/MonsterCatalog.ets` |
| Models | `harmonyos/entry/src/main/ets/models/AdventureRegion.ets`, `harmonyos/entry/src/main/ets/models/GameConfig.ets` |
| Services | `harmonyos/entry/src/main/ets/services/BattleEngine.ets`, `harmonyos/entry/src/main/ets/services/TodayAdventureBuilder.ets` |
| Pages | `harmonyos/entry/src/main/ets/pages/BattlePage.ets` |
| Built-in rawfiles | `harmonyos/entry/src/main/resources/rawfile/data/builtin/*.json` |
| Tests | `harmonyos/entry/src/test/MonsterDialogue.test.ets`, `BuiltinPackLoader.test.ets`, `LocalUnit.test.ets`, `TodayAdventureBuilder.test.ets`, `BattleFlow.ui.test.ets`, `RoutingFlow.ui.test.ets`, `MagicAttack.ui.test.ets` |

### 2.2 Persistence keys (cross-platform; replicas must match semantics)

| Key | Type | Default | Migration notes |
| --- | --- | --- | --- |
| `gameConfig.playerMaxHp` | number | `10` | Existing saved values are preserved by clone/copy paths. |
| `gameConfig.monsterMaxHp` | number | `5` | Existing saved values are preserved by clone/copy paths. |
| `gameConfig.monstersTotal` | number | `10` | Existing saved values are preserved by clone/copy paths. |

### 2.3 Stable IDs introduced or changed

| ID | Where | Notes |
| --- | --- | --- |
| `BattleBossIntroBubble` | Battle ordinary intro overlay | Level 1 / 2 / 3 intro container. |
| `BattleBossIntroName` | Battle ordinary intro overlay | Monster display name. |
| `BattleBossIntroLineEn` | Battle ordinary intro overlay | English primary line. |
| `BattleBossIntroLineZh` | Battle ordinary intro overlay | Chinese support line. |
| `BattleSuperBossIntroBanner` | Battle SuperBoss intro overlay | Ornate banner, auto-dismissed, blocks input while visible. |
| `BattleSuperBossIntroTitle` | Battle SuperBoss intro overlay | Banner title. |
| `BattleSuperBossIntroLineEn` | Battle SuperBoss intro overlay | English primary line. |
| `BattleSuperBossIntroLineZh` | Battle SuperBoss intro overlay | Chinese support line. |
| `BattleBossDefeatBubble` | Battle defeat overlay | Short defeat container. |
| `BattleBossDefeatName` | Battle defeat overlay | Monster display name. |
| `BattleBossDefeatLineEn` | Battle defeat overlay | English primary line. |
| `BattleBossDefeatLineZh` | Battle defeat overlay | Chinese support line. |

### 2.4 Edge cases discovered during stabilization

- `TodayAdventureBuilder` must expand legacy 5-slot monster templates to 10 output slots by cycling the template; simply changing `MONSTER_PLAN_SLOT_COUNT` is not enough.
- With 15-word built-in packs and a 20-slot `wordPlan`, the plan builder must allow deterministic word reuse after exhausting unique candidates.
- UI automation answer maps must include all newly added built-in words; otherwise helper-driven correct/wrong taps fail on new prompts.
- SuperBoss intro blocks input while visible; ordinary intro and defeat bubbles do not intercept taps.

### 2.5 Tests requiring parity counterparts

| HarmonyOS test | iOS counterpart (XCTest / XCUITest) | Android counterpart (JUnit / Compose UI / UIA) |
| --- | --- | --- |
| `MonsterDialogue.test.ets` | Validate 100 dialogue rows and resolver fallback. | Validate 100 dialogue rows and resolver fallback. |
| `LocalUnit.test.ets` default assertions | Validate first-install defaults 10 / 5 / 10 and saved-config preservation. | Validate first-install defaults 10 / 5 / 10 and saved-config preservation. |
| `TodayAdventureBuilder.test.ets` | Validate 10 monster slots and word-plan cycling semantics. | Validate 10 monster slots and word-plan cycling semantics. |
| `BuiltinPackLoader.test.ets` | Validate five built-in packs each expose 15 sentence-ready words. | Validate five built-in packs each expose 15 sentence-ready words. |
| `BattleFlow.ui.test.ets` | UI test ordinary intro, SuperBoss banner auto-dismiss, defeat bubble. | UI test ordinary intro, SuperBoss banner auto-dismiss, defeat bubble. |

### 2.6 Pitfalls / "do not repeat my mistakes"

- Do not wrap Hypium async UI tests in `try { ... } catch (err) { done(err) }`; this runner can report false success. Let assertion errors throw directly.
- Do not rely on process exit code alone for Hvigor unit tests; inspect console output for `ERROR: Error in ...`.
- Do not make SuperBoss intro require an extra tap; it must auto-dismiss.
- Do not mark `replication_approved: true`; only the human owner signs below.

## 3. Open Questions for the Replicas

- [x] None.

## 4. Human-Confirm Signature Block

> **iOS / Android agents:** if `replication_approved` is missing, blank, or `false`, refuse to start Stage 4 and ask the human owner. Do not proceed.

```yaml
approved_by:
approved_at:
replication_approved: false
notes:
```
