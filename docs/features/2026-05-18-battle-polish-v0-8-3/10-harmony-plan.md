# V0.8.3 — Battle Polish — HarmonyOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
>
> **Run loop:** [`.cursor/skills/harmony-autofix-orchestrator/SKILL.md`](../../../.cursor/skills/harmony-autofix-orchestrator/SKILL.md) drives build → codelinter → unit → emulator → ohosTest. Commands come from [`.cursor/ohos-dev-commands.md`](../../../.cursor/ohos-dev-commands.md). Do not invent flags.

**Goal:** Land V0.8.3 on HarmonyOS as three independently testable but co-released sub-tasks: pack-cap-and-auto-rotate, monster-tiering-with-bonus-and-heavy-attack, and damage floater label.

**Architecture:**

- **Sub-task A (Pack config):** `services/PackSelectionService.ets` constant 5→10 plus an `appendOrRotate(packId)` action that returns a discriminated outcome the UI can route into existing or new toasts. UI changes confined to `pages/PackManagerPage.ets`, `pages/ConfigPage.ets`, and `pages/HomePage.ets` chip row counter.
- **Sub-task B (Monster tiering):** New `MonsterLevel` enum and `level` field on `MonsterEntry` in `data/MonsterCatalog.ets`. New routing helper on `services/QuestionGenerator.ets` to pick question kind from `MonsterLevel`. `services/BattleEngine.ets` `applyMonsterAttack` becomes amount-aware. Session tracks `bonusKillCount`; `pages/ResultPage.ets` adds `BattleResultBonusCoinRow`. `pages/MonsterCodexPage.ets` adds level badge.
- **Sub-task C (Damage floater):** New `components/DamageFloaterLabel.ets` ArkUI component, hosted by `pages/BattlePage.ets` as two `@State`-driven slots (player side, monster side) with a small FIFO that handles overlap.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI, Hypium local tests under `harmonyos/entry/src/test/`, ohosTest UI automation under `harmonyos/entry/src/ohosTest/ets/test/`.

---

## Sub-task A — Pack activation cap 5→10 + auto-rotate

### Task A.1: Lift cap + design `appendOrRotate` API on `PackSelectionService`

**Files:**

- Modify: `harmonyos/entry/src/main/ets/services/PackSelectionService.ets`
- Test: `harmonyos/entry/src/test/PackSelectionService.test.ets`

- [ ] In `services/PackSelectionService.ets`, change `export const MAX_ACTIVE_PACKS: number = 5;` to `10`.
- [ ] Add `export interface AppendOutcome { result: 'activated' | 'refused-all-pinned'; addedId: string; autoClosed: string | null; }`.
- [ ] Implement `async appendOrRotate(packId: string): Promise<AppendOutcome>`:
  - If `getActiveIds()` already contains `packId` → return `{ result: 'activated', addedId: packId, autoClosed: null }` (no-op).
  - If `getActiveIds().length < MAX_ACTIVE_PACKS` → append + persist + return `{ result: 'activated', addedId: packId, autoClosed: null }`.
  - Otherwise scan `getActiveIds()` left→right, find first id NOT in `getPinnedIds()`. If none → return `{ result: 'refused-all-pinned', addedId: packId, autoClosed: null }` without mutating. If found → remove that victim, append `packId`, persist, return `{ result: 'activated', addedId: packId, autoClosed: victim }`.
- [ ] Write `harmonyos/entry/src/test/PackSelectionService.test.ets` cases that PIN the contract:
  - `appendOrRotateAtUnderCapJustAppends` — initial 9 ids, add 10th → outcome `activated` + `autoClosed === null`.
  - `appendOrRotateAtCapClosesEarliestNonPinned` — 10 ids with `ids[3]` pinned, add 11th → `autoClosed === ids[0]`, final ids contain `ids[3]` and new id but not `ids[0]`.
  - `appendOrRotateAtCapAllPinnedRefuses` — 10 ids all pinned, add 11th → `result === 'refused-all-pinned'`, ids unchanged.
  - `appendOrRotateNoOpOnAlreadyActive` — 5 ids, add an id already in list → ids unchanged, `autoClosed === null`.
- [ ] Run `cd harmonyos && hvigorw -p module=entry@default test`; expect green.

### Task A.2: Wire `PackManagerPage` to `appendOrRotate` + add the two toasts

**Files:**

- Modify: `harmonyos/entry/src/main/ets/pages/PackManagerPage.ets`
- Test: `harmonyos/entry/src/ohosTest/ets/test/PackManagerFlow.ui.test.ets`

- [ ] In `pages/PackManagerPage.ets`, replace any current "if at cap, refuse" branch in the Toggle ON handler with a call to `selection.appendOrRotate(pack.id)` and map the outcome to two new toasts:
  - `activated` with `autoClosed != null` → show `PackManagerAutoRotateToast` (new `.id('PackManagerAutoRotateToast')`) with text `'已关闭 \'' + oldName + '\' 以激活 \'' + newName + '\''`; reuse existing 2.4 s timer pattern (`PackManagerSyncToast` is the precedent).
  - `refused-all-pinned` → show `PackManagerCapRefuseToast` (new `.id('PackManagerCapRefuseToast')`) with `'请先取消固定一个词包'`.
  - `activated` with `autoClosed == null` → keep current silent activation behavior.
- [ ] Update the status row text from `已激活 X/5 (含 Y 个 📌)` to `已激活 X/10 (含 Y 个 📌)` (or equivalent strings — preserve the existing template).
- [ ] In `ohosTest/ets/test/PackManagerFlow.ui.test.ets`, add two cases:
  - `togglingEleventhPackAutoClosesEarliestUnpinnedAndToasts` — seed PackSelectionService prefs blob with 10 active ids (none pinned), drive UI to toggle ON pack `space-station` (or another mock-only id), assert `PackManagerAutoRotateToast` becomes visible with text containing `'已关闭'` and `'以激活'`, and the toggled pack lands in selection while the head id is gone.
  - `togglingEleventhPackWhenAllPinnedRefusesAndToasts` — seed prefs with 10 active ids ALL pinned, drive toggle ON, assert `PackManagerCapRefuseToast` shows with `'请先取消固定一个词包'`, selection blob unchanged.
- [ ] Run `scripts/run_ui_tests.sh` (target only the new cases via `--testName` if the harness supports it; otherwise run the full `PackManagerFlow.ui.test.ets`). Expect `TestFinished-ResultCode: 0`.

### Task A.3: Counter copy parity on ConfigPage + HomePage

**Files:**

- Modify: `harmonyos/entry/src/main/ets/pages/ConfigPage.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/HomePage.ets` (only if a `/5` literal exists in a label; chip row itself is fine)
- Test: existing `ConfigFlow.ui.test.ets` smoke (no new cases, just regenerate the assertion that the entry-row label still resolves at runtime).

- [ ] In `pages/ConfigPage.ets`, change the `ConfigPackManagerEntry` label template from `已激活 X/5 管理 ›` to `已激活 X/10 管理 ›` (look for the `MAX_ACTIVE_PACKS` reference or the literal `/5`).
- [ ] Confirm `pages/HomePage.ets` chip row continues to render 10 chips (no hard `5` literal expected).
- [ ] Run `scripts/run_ui_tests.sh`; smoke flows must remain green.

---

## Sub-task B — Monster tiering + bonus + HP-2 heavy attack

### Task B.1: Add `MonsterLevel` enum + `level` on `MonsterEntry`

**Files:**

- Modify: `harmonyos/entry/src/main/ets/data/MonsterCatalog.ets`
- Test: `harmonyos/entry/src/test/MonsterCatalog.test.ets`

- [ ] Add `export enum MonsterLevel { Beginner = 'beginner', Intermediate = 'intermediate', Advanced = 'advanced', Super = 'super' }`.
- [ ] Add `level: MonsterLevel = MonsterLevel.Beginner` field on `MonsterEntry`; add an overload of each `make*Entry()` factory that accepts a `MonsterLevel`. Keep existing factories backward compatible (default level via overload chain, not by mutating the global default).
- [ ] Set the levels per [`00-design.md` §6.2](00-design.md) on the 10 catalog entries:
  - Slime → `Beginner`
  - Zombie / Dragon / Pumpkin King / Imp King / Phoenix / Witch → `Intermediate`
  - Snow Queen / Unicorn → `Advanced`
  - Kraken → `Super`
- [ ] Create `harmonyos/entry/src/test/MonsterCatalog.test.ets` asserting:
  - `catalogLevelCountsMatchTargetRatio` — exactly 1 Beginner / 6 Intermediate / 2 Advanced / 1 Super.
  - `bossesAreNotForcedToAdvanced` — being Boss-kind is independent of being Advanced/Super.
  - `existingEntryNamesUnchanged` — Slime/Zombie/Dragon and the 7 named bosses still in catalog order.
- [ ] Run `hvigorw -p module=entry@default test`; expect green.

### Task B.2: `QuestionGenerator` accepts a per-position level and routes type

**Files:**

- Modify: `harmonyos/entry/src/main/ets/services/QuestionGenerator.ets`
- Test: `harmonyos/entry/src/test/QuestionGenerator.test.ets`

- [ ] Add a new optional parameter `level?: MonsterLevel` to the question-build entry point. Routing default:
  - `Beginner` → `QuestionKind.Choice`
  - `Intermediate` → `QuestionKind.FillLetter` beginner (1 blank)
  - `Advanced` → `QuestionKind.FillLetter` medium (2–3 blanks)
  - `Super` → `QuestionKind.Spell`
- [ ] Implement the fallback chain when the matched type cannot be generated for the chosen word (e.g., word length 3 cannot host FillLetter-medium): degrade `Spell` → `FillLetterMedium` → `FillLetterBeginner` → `Choice`. Do not abort the battle.
- [ ] Add test cases:
  - `routesChoiceForBeginnerLevel`
  - `routesFillLetterForIntermediateLevel`
  - `routesFillLetterMediumForAdvancedLevel`
  - `routesSpellForSuperLevel`
  - `degradesGracefullyForShortWordOnAdvanced` — feed a 3-letter word; expect Choice or FillLetterBeginner, not throw.
- [ ] Run local tests; expect green.

### Task B.3: `BattleEngine.applyMonsterAttack` returns damage `1 | 2`

**Files:**

- Modify: `harmonyos/entry/src/main/ets/services/BattleEngine.ets`
- Test: `harmonyos/entry/src/test/BattleEngine.test.ets` (or whichever existing file covers monster attacks)

- [ ] Refactor `applyMonsterAttack` (or the current monster-attack code path) to compute `baseDamage: number = 1`; if `monster.level == Advanced || monster.level == Super`, roll `Random.float() < 0.50` to set `baseDamage = 2`.
- [ ] Subtract `baseDamage` from player HP (clamped to 0).
- [ ] Return the damage so the UI can emit a `DamageFloaterLabel` with the correct amount. If `applyMonsterAttack` does not currently return anything, add the return type and update all call sites.
- [ ] Inject an `RNG` seam (existing `RandomSource` if present, otherwise add a narrow injection point) so tests can pin the 50% branch.
- [ ] Add test cases:
  - `beginnerMonsterAlwaysDamagesOne` — fixed RNG, 10 iterations, all damage = 1.
  - `superMonsterDamagesTwoWhenRngLow` — RNG < 0.5 → damage 2.
  - `superMonsterDamagesOneWhenRngHigh` — RNG ≥ 0.5 → damage 1.
  - `playerHpFloorIsZero` — apply heavy attack to HP=1 → final HP=0, returned damage = 2.
- [ ] Run local tests; expect green.

### Task B.4: Spawn-time `bonus` flag + session counter

**Files:**

- Modify: `harmonyos/entry/src/main/ets/services/BattleEngine.ets` (monster spawn / queue construction)
- Modify: a session model file if `BattleSession` does not yet track `bonusKillCount`
- Test: `harmonyos/entry/src/test/BattleEngine.test.ets`

- [ ] At monster-queue construction, for each monster of level `Advanced` or `Super`, roll `Random.float() < 0.30`; if true, set a runtime field `bonus = true` on the spawned monster instance.
- [ ] On monster death event, if `bonus`, increment `session.bonusKillCount`.
- [ ] Add test cases (RNG-injected):
  - `intermediateMonsterNeverBonus`
  - `advancedMonsterBonusWhenRngLow`
  - `superMonsterBonusWhenRngHigh`
  - `bonusKillCountIncrementsOnKill`
- [ ] Run local tests; expect green.

### Task B.5: ResultPage `BattleResultBonusCoinRow` + bonus-aware coin calc

**Files:**

- Modify: `harmonyos/entry/src/main/ets/pages/ResultPage.ets`
- Modify: any `CoinAccount` / reward-calc service that maps stars → coins, if it does not yet take `bonusKillCount`
- Test: `harmonyos/entry/src/test/CoinAccount.test.ets` (or wherever the star→coin rule is tested)

- [ ] In the star→coin calc, if `bonusKillCount > 0` AND the player won, set `finalCoins = Math.ceil(baseCoins * 1.3)`; otherwise `finalCoins = baseCoins`.
- [ ] In `pages/ResultPage.ets`, after the existing coin total row, add `BattleResultBonusCoinRow` (`.id('BattleResultBonusCoinRow')`) that renders only when `bonusKillCount > 0 && session.won`, showing `'Bonus 怪物 ×' + K + ' → +' + (finalCoins - baseCoins) + ' ✨'`.
- [ ] Add tests:
  - `noBonusKillsKeepsCoinsEqualToStars`
  - `oneBonusKillCeilsBaseTimes13` — 3 stars → 4 coins.
  - `lossWithBonusKillsStillGivesNoBonus`.
- [ ] Run local tests; expect green.

### Task B.6: `MonsterCodexPage` level badge

**Files:**

- Modify: `harmonyos/entry/src/main/ets/pages/MonsterCodexPage.ets`
- Test: existing `MonsterCodexFlow.ui.test.ets` (or equivalent); add a single smoke if missing.

- [ ] Render a small pill next to each monster name with id pattern `MonsterCodexLevelBadge_<monsterKey>` and text `初` / `中` / `高` / `Super` based on `entry.level`.
- [ ] Visual style: 10×18 px pill, color matches level palette from `00-design.md` §11 (zh-CN short labels).
- [ ] Add ohosTest assertion (single case): after navigating to the codex detail of Slime, `MonsterCodexLevelBadge_slime` resolves and its text is `'初'`.
- [ ] Run UI test; expect green.

### Task B.7: BattlePage spawns `MonsterBonusStar_{index}`

**Files:**

- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`

- [ ] When rendering the active monster card, if `monster.bonus`, overlay a small ✨ star at top-right of the card with `.id('MonsterBonusStar_' + monsterIndex)` (1-based index in the battle queue).
- [ ] No animation; just a static overlay. Do not add anything to non-bonus monsters.

---

## Sub-task C — HP -1 / -2 damage floater

### Task C.1: New `DamageFloaterLabel` component

**Files:**

- Create: `harmonyos/entry/src/main/ets/components/DamageFloaterLabel.ets`
- Test: `harmonyos/entry/src/test/DamageFloaterLabel.test.ets`

- [ ] Implement `@Component DamageFloaterLabel` with props `amount: 1 | 2`, `side: 'player' | 'monster'`, `onDispose: () => void`.
- [ ] Per [`00-design.md` §6.5](00-design.md): text `-1` / `-2`, color `#F87171` / `#7F1D1D`, font size 18 / 20 vp, optional 1 px white stroke (`-1`) or 2 px drop shadow (`-2`), 450 ms ease-out `opacity 0→1→0` (keyframes 0/50/100) + `translateY -28vp`.
- [ ] Component reports `onDispose` ~450 ms after start so the parent can free its slot.
- [ ] Export a small **pure** helper `pickFloaterStyle(amount)` returning the style props so unit tests can pin colors without mounting the component.
- [ ] In `harmonyos/entry/src/test/DamageFloaterLabel.test.ets` assert:
  - `pickFloaterStyleForOneIsBright`
  - `pickFloaterStyleForTwoIsDeep`
  - `pickFloaterStyleForOneHasStroke`
  - `pickFloaterStyleForTwoHasShadow`.
- [ ] Run local tests; expect green.

### Task C.2: BattlePage hosts floater slots and routes damage events

**Files:**

- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`
- Test: `harmonyos/entry/src/ohosTest/ets/test/BattleFlow.ui.test.ets`

- [ ] In BattlePage, hold two FIFO queues (max 4 each) of pending `{ amount, key }` floaters: one for `player`, one for `monster`. Stack-offset successive floaters within 450 ms by 6 vp so they don't overlap.
- [ ] Where the existing code applies damage to monster (player→monster, including combo crit), emit `pushFloater('monster', actualDamageDealt)`.
- [ ] Where `BattleEngine.applyMonsterAttack` returns the damage, emit `pushFloater('player', damage)`.
- [ ] Each floater inside the queue mounts `DamageFloaterLabel` with `.id('BattleDamageFloaterLabel_' + side)`. When the same side has multiple pending floaters, the topmost remains addressable by the same id (UI tests assert presence + text, not stack depth).
- [ ] In `BattleFlow.ui.test.ets`, add one smoke case `damageFloaterAppearsAndDisappearsOnHit`:
  - Drive a forced wrong answer (`super`-level monster path via mock-friendly RNG if available; otherwise rely on existing wrong-answer harness).
  - Within 100 ms of HP change, assert `BattleDamageFloaterLabel_player` exists with text `-1` or `-2`.
  - Wait 600 ms; assert the label is gone.
- [ ] Run `scripts/run_ui_tests.sh`; expect `TestFinished-ResultCode: 0`.

---

## Task V: Final verification (gate)

**Files:**

- Validate the changed HarmonyOS source and tests as a whole.

- [ ] `cd harmonyos && hvigorw -p module=entry@default test` green (all of: `PackSelectionService.test`, `MonsterCatalog.test`, `QuestionGenerator.test`, `BattleEngine.test`, `CoinAccount.test`, `DamageFloaterLabel.test`).
- [ ] `scripts/run_ui_tests.sh` green; new cases included.
- [ ] `cd harmonyos && hvigorw assembleHap` produces 0 `ArkTS:WARN` lines.
- [ ] `cd harmonyos && codelinter -c ./code-linter.json5 . --fix` clean.
- [ ] Bump [`harmonyos/AppScope/app.json5`](../../../harmonyos/AppScope/app.json5): `versionName` → `0.8.3`, `versionCode` → `1008003` (per [`.cursor/rules/harmony-app-version-code.mdc`](../../../.cursor/rules/harmony-app-version-code.mdc)).
- [ ] Refresh affected screens via `python3 scripts/capture_harmony_screenshots.py` (HomePage / PackManagerPage / BattlePage / ResultPage / MonsterCodexPage) and commit baseline updates under `assets/screenshots/harmonyos/`.
- [ ] No server contract changed → skip `tools/contracts/export_openapi.py` and `tests/test_shared_contracts.py`.
- [ ] Move on to [`20-replication-trigger.md`](20-replication-trigger.md) (to be created from template) and start filling in the gate evidence: ohosTest log excerpts, screenshot diff, version bump confirmation, and the human-signed `replication_approved: true` block.
