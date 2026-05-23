# V0.8.4 — Battle Balance & Question Pacing — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> iOS / Android agents must verify the signature block at the bottom before starting `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

- [x] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: `BUILD SUCCESSFUL` (2026-05-18, branch `docs/shared-roadmap-reality-alignment`); includes `BattleQuestionScheduler.test.ets`, `BattleEngine` spell penalty cases, updated `PlanQuestionSource` / catalog tests.
- [x] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence: commit `1bd7a08` — 76 tests, `OHOS_REPORT_CODE: 0`; new suite `BattlePacing.ui.test.ets` (3 cases).
- [x] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: `BUILD SUCCESSFUL in 9 s 845 ms`; no `ArkTS:WARN` in build log (2026-05-18).
- [x] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: exit 0, `No defects found in your code.` (2026-05-18).
- [x] **Version bumped** — `harmonyos/AppScope/app.json5`
  - To: `versionName=0.8.4` `versionCode=1008004`
- [x] **Feature present in current mainline worktree**
  - Evidence: current history contains V0.8.4 battle parity plus iOS App Store review-fix release; app metadata is `0.8.4` / `1008004` on HarmonyOS and Android, and `0.8.4` / `1008006` on iOS.
- [x] **V0.8.3 prerequisite parity closed at code level**
  - Evidence: [`../2026-05-18-battle-polish-v0-8-3/50-parity-checklist.md`](../2026-05-18-battle-polish-v0-8-3/50-parity-checklist.md) shows iOS / Android rows filled for pack cap 10, auto-rotate, monster level, bonus, and HP-2 heavy attack. Android targeted tests pass; iOS targeted tests still need a machine with active Xcode.
- [x] **Screenshots refreshed**
  - N/A — no new screens; battle HP / pacing changes only. Optional parity screenshots in Stage 5.
- [x] **Server contracts up to date** — N/A (client-only; design §8).

## 2. Delta Letter

### 2.1 New / changed code (HarmonyOS)

| Layer | Files |
| --- | --- |
| Services | `services/BattleEngine.ets` (`DEFAULT_PLAYER_HP=10`, `applySpellLetterPenalty`); **new** `services/BattleQuestionScheduler.ets`; `services/PlanQuestionSource.ets`; `services/BattleQuestionTypePolicy.ets` (`resolveQuestionTypeWithinPool`) |
| Models | `models/GameConfig.ets` (`playerMaxHp` default 10) |
| UI | `components/SpellingArea.ets` (`onWrongLetterTap`); `pages/BattlePage.ets` (scheduler wiring, spell penalty feedback) |
| Data | `data/MonsterCodex.ets` (lore length fix for `lava-toad`) |
| Unit tests | `entry/src/test/BattleQuestionScheduler.test.ets`, `BattleEngine.test.ets`, `PlanQuestionSource.test.ets`, `LocalUnit.test.ets`, catalog/adventure test updates |
| ohosTest | **new** `ohosTest/ets/test/UiTestBattleHelpers.ets`, `BattlePacing.ui.test.ets`; refactors in `FillLetterFlow`, `SpellQuestionFlow`, `RoutingFlow`, `MagicAttack`, `ReviewMode`, `PackManagerFlow`, `ParentAdminFlow`, `List.test.ets` |
| Docs | `docs/WordMagicGame_overall_spec.md` §4.1; `docs/WordMagicGame_roadmap.md` |

### 2.2 Persistence keys

| Key | Change |
| --- | --- |
| `GameConfig.playerMaxHp` | Default **10** for new `GameConfig()`; existing saved prefs unchanged (no migration). |

### 2.3 Stable IDs

No new stable test IDs. Existing battle surfaces unchanged: `BattleSpellArea`, `LetterTemplateRow`, `BattlePrompt`, `BattleDamageFloaterLabel_player`, `CharacterCard` HP label.

### 2.4 Schedule modes (replicas must match)

| Mode | Config | Behavior |
| --- | --- | --- |
| `single_type` | Exactly one question type enabled | 100% that type |
| `intro_only` | Only intro kinds | Intro pass then sustain; never challenge kinds |
| `challenge_only` | Only challenge kinds | Challenge roll from Q1 |
| `two_phase` | Mixed intro + challenge | Intro pass per §5.3.3, then 50/50 challenge |

Per-word caps: at most one `choice` and one `fill-letter` per `wordId` during intro phase.

### 2.5 Tests requiring parity counterparts

| HarmonyOS | iOS (suggested) | Android (suggested) |
| --- | --- | --- |
| `BattleQuestionScheduler.test.ets` (mode derivation + caps) | `BattleQuestionSchedulerTests` | `BattleQuestionSchedulerTest` |
| `BattleEngine.test.ets` spell wrong-tap HP | `BattleEngineSpellPenaltyTests` | `BattleEngineSpellPenaltyTest` |
| `PlanQuestionSource.test.ets` scheduler integration | `PlanQuestionSourceSchedulerTests` | `PlanQuestionSourceSchedulerTest` |
| `SpellQuestionFlow` wrong-tap HP | `SpellQuestionUITests` | `SpellQuestionUiTest` |
| `BattlePacing.ui.test.ets` (optional) | `BattlePacingUITests` | `BattlePacingUiTest` |

### 2.6 Pitfalls / do not repeat

- Today/plan battles use **`BattleQuestionScheduler`** — do not rely on monster-slot index for question type in new tests; use Config single-type (§5.4) for component suites.
- Spell wrong tap: call penalty path only; **do not** `submitAnswer` until the word is complete.
- `playerMaxHp` saved as 5 stays 5 until the parent changes Config.
- `two_phase` short plans (~10 words) may end the battle before challenge surfaces appear — UI smokes observe intro kinds only when battle ends early.

### 2.7 Out of Harmony V0.8.4 scope (replicas note)

- Review-mode scheduler parity deferred (design §3).
- No server / `shared/` contract changes.

## 3. Open Questions for the Replicas

None.

## 4. Human-Confirm Signature Block

```yaml
approved_by: Terry Ma
approved_at: 2026-05-18
replication_approved: true
notes: Harmony soft gates green on docs/shared-roadmap-reality-alignment (4841da5, 1bd7a08). V0.8.4-specific parity is present in the current worktree; V0.8.3 prerequisite parity is now code-complete on iOS / Android and awaits developer-machine verification.
```
