# iOS Replica Phase 1 — Core Loop And ParentAdmin Design

> Status: design-for-implementation
> Date: 2026-05-10
> Scope: Home -> Battle -> Result plus Config -> PIN -> ParentAdmin -> LessonDraftReview.
> Related plan: `docs/ios-replica/03-phase1-core-and-parent-admin.md`

## 1. Background

Phase 1 must prove that iOS can carry both the child learning loop and the parent lesson-import loop. The child flow targets iPhone landscape. ParentAdmin and LessonDraftReview remain portrait because HarmonyOS intentionally locks those parent workflows to portrait for form-heavy interaction.

The phase copies behavior from HarmonyOS, not ArkTS structure. SwiftUI views render state; pure Swift engines and stores own behavior.

## 2. Goals

- Build the first iOS implementation slice around Home, Battle, Result, Config, Parent PIN, ParentAdmin, and LessonDraftReview.
- Preserve HarmonyOS battle defaults, timer choices, combo rules, today rewards, parent PIN gating, and ParentAdmin API boundaries.
- Keep ParentAdmin in Phase 1 with mockable adapters first and real network shape preserved.
- Make all pure rules XCTest-testable before UI integration.
- Use stable XCUITest identifiers from the first implementation.

## 3. Non-Goals

- Do not implement full three-layer PackManager UI in Phase 1.
- Do not implement device binding or cloud stats sync.
- Do not require real camera/gallery permissions for Phase 1 acceptance; preserve `LessonImagePicker` interface.
- Do not implement real OpenAI recognition on-device; recognition remains server-side.
- Do not add Cocos2D battle rendering in this phase.

## 4. Source Evidence

Screenshots:

- `assets/screenshots/harmonyos/home.png`
- `assets/screenshots/harmonyos/battle.png`
- `assets/screenshots/harmonyos/result.png`
- `assets/screenshots/harmonyos/config-part1.png` through `config-part4.png`
- `assets/screenshots/harmonyos/parent-pin-setup.png`
- `assets/screenshots/harmonyos/parent-admin-part1.png` through `parent-admin-part4.png`

HarmonyOS code:

- `pages/HomePage.ets`
- `pages/BattlePage.ets`
- `pages/ResultPage.ets`
- `pages/ConfigPage.ets`
- `pages/ParentPinSetupPage.ets`
- `pages/ParentAdminPage.ets`
- `pages/LessonDraftReviewPage.ets`
- `components/ParentPinDialog.ets`
- `components/CustomTimerDialog.ets`
- `services/BattleEngine.ets`
- `services/QuestionGenerator.ets`
- `services/TodayAdventureBuilder.ets`
- `services/ParentApiClient.ets`
- `utils/orientation.ets`

Historical specs:

- V0.5.8 ParentAdmin revamp design.
- V0.3 fun-learning core design.
- V0.4.1 spelling question design.
- V0.6.5 three-layer pack model design for future pack compatibility.

## 5. User Experience Design

### Home

iPhone landscape layout:

- Top compact strip: child badge, coin badge, toolbar actions.
- Center title: `Small Magician Word Adventure`.
- Main AdventureCard: selected pack title, active pack chips, badge row, story/summary, primary red start button.
- Pack chip labels are English, matching the HarmonyOS all-English decision.
- Review, Codex, Plan, Wishlist, Config affordances may route to placeholders until Phase 2, except Config must be functional.

Required identifiers:

- `HomeTitle`
- `HomeCoinBalance`
- `HomeConfigButton`
- `HomeStartButton`
- `AdventureCard`
- `AdventureCardTitle`
- `RegionChip_<packId>`

### Battle

iPhone landscape layout:

- Left: player card and HP.
- Center: question prompt, speaker button, feedback text.
- Right: monster card and HP.
- Bottom: three answer buttons.
- Top status: combo, title, timer.

Phase 1 must support Choice questions. The Swift types must already model FillLetter, FillLetterMedium, and Spell so enabling them later does not rewrite the engine boundary.

Audio rule:

- Auto pronunciation plays once when a new question appears.
- For `FillLetterMedium`, filling the first missing letter advances to the second missing-letter step inside the same question. That in-place step advance must not trigger auto pronunciation again.
- The speaker button remains available and manually replays the full English answer regardless of the current missing-letter step.

Required identifiers:

- `BattleComboLabel`
- `BattleTitle`
- `BattleTimerLabel`
- `PlayerArea`
- `MonsterArea`
- `BattlePrompt`
- `BattleSpeakerButton`
- `BattleOptionA`
- `BattleOptionB`
- `BattleOptionC`
- `BattleFeedback`

### Result

Layout:

- Win/loss headline.
- Stars.
- Defeated monsters, correct rate, learned word count.
- Today reward row: coins earned and total.
- Primary Home action.

Required identifiers:

- `ResultTitle`
- `ResultStars`
- `ResultAccuracy`
- `ResultCoinsEarned`
- `ResultCoinsTotal`
- `ResultHomeButton`

### Config And PIN

Phase 1 Config rows:

- Player HP stepper.
- Monster HP stepper.
- Monster count stepper.
- Timer chips: 30s, 3m, 5m, 10m.
- Custom timer entry, valid range 1...3600.
- Auto pronunciation toggle.
- Parent PIN setup/edit.
- ParentAdmin entry.
- PackManager entry placeholder for Phase 2.

PIN behavior:

- Six digits.
- Setup is two-step confirmation.
- Empty PIN means parent-only actions show setup guidance.
- Config -> ParentAdmin requires PIN when configured.

### ParentAdmin

Portrait layout:

- Back button.
- Title `家长管理后台`.
- Server label.
- Overview card with refresh state.
- Lesson import card with camera/gallery actions.
- Pending draft list.
- Failed draft area where applicable.
- Publish new pack card with notes and publish button.

ParentAdmin must be implemented against a protocol-backed `ParentApiClient` so mock and real implementations share one surface.

Required identifiers:

- `ParentAdminBack`
- `ParentAdminTitle`
- `ParentAdminServerLabel`
- `ParentAdminRefresh`
- `ParentAdminPickCameraButton`
- `ParentAdminPickGalleryButton`
- `ParentAdminImportProgress`
- `ParentAdminImportError`
- `ParentAdminImportSuccess`
- `ParentAdminPendingTitle`
- `LessonDraftReviewLink_<draftId>`
- `ParentAdminPublishNotes`
- `ParentAdminPublishButton`
- `ParentAdminPublishSummary`

### LessonDraftReview

Portrait layout:

- Back.
- Title.
- Source image thumbnail.
- Category/theme input.
- Candidate word rows.
- Keep/drop toggle.
- Edit dialog for English and Chinese text.
- Save draft, approve, reject actions.

Required identifiers:

- `LessonReviewBack`
- `LessonReviewTitle`
- `LessonReviewThumbnail`
- `LessonReviewCategoryInput`
- `LessonReviewRow_<index>`
- `LessonReviewRowToggle_<index>`
- `LessonReviewRowEdit_<index>`
- `LessonReviewEditDialog`
- `LessonReviewEditEnglish`
- `LessonReviewEditChinese`
- `LessonReviewApproveButton`
- `LessonReviewRejectButton`

## 6. Swift Architecture

Recommended modules inside the future iOS project:

```text
WordMagicGame/Core
  GameConfig.swift
  WordEntry.swift
  Question.swift
  BattleState.swift
  SessionResult.swift
  BattleEngine.swift
  QuestionGenerator.swift
  TodayAdventureBuilder.swift

WordMagicGame/Services
  GameConfigStore.swift
  ParentPinStore.swift
  CoinAccount.swift
  ParentApiClient.swift
  LessonImagePicker.swift
  OrientationController.swift

WordMagicGame/Features/CoreLoop
  HomeView.swift
  BattleView.swift
  ResultView.swift

WordMagicGame/Features/Settings
  ConfigView.swift
  ParentPinSetupView.swift

WordMagicGame/Features/ParentAdmin
  ParentAdminView.swift
  LessonDraftReviewView.swift
```

State ownership:

- `BattleEngine` owns battle transitions.
- `HomeViewModel` owns selected pack and start-battle orchestration.
- `ConfigViewModel` owns a draft `GameConfig`.
- `ParentAdminViewModel` owns stats, draft list, import state, and publish state.
- `LessonDraftReviewViewModel` owns draft editing and approve/reject commands.

## 7. Data Flow

Home start:

```text
HomeView tap start
  -> HomeViewModel builds TodaySessionPlan from selected Pack
  -> AppCoordinator routes to Battle with plan + active pack
  -> BattleViewModel creates BattleEngine
```

Battle answer:

```text
BattleView tap answer
  -> BattleEngine.submitAnswer
  -> BattleViewModel renders feedback
  -> after feedback window, next question or route to Result
```

Today reward:

```text
Battle end
  -> SessionResult
  -> CoinAccount earns stars for today mode
  -> ResultView displays stars and coin delta
  -> Home reads updated local coin state on return
```

ParentAdmin:

```text
Config tap ParentAdmin
  -> ParentPinDialog verifies PIN
  -> OrientationController enters portrait
  -> ParentAdminView loads stats + drafts through ParentApiClient
  -> Import success creates/returns draft id
  -> LessonDraftReview loads draft detail, patches edits, approves or rejects
  -> Back restores landscape after parent flow exits
```

## 8. Error Handling

Core loop:

- Missing or invalid active pack falls back to builtin first pack.
- Too-small word pool blocks Battle start and shows a friendly local error.
- Invalid answer submissions are programmer errors in XCTest, not recoverable UI states.
- Timer reaching zero routes to Result as loss.

Config:

- Invalid custom timer keeps dialog open and shows validation text.
- PIN mismatch keeps setup on confirmation step and shows mismatch hint.

ParentAdmin:

- Network failures render non-destructive retry states.
- Import failure keeps user on ParentAdmin and shows a human-readable error.
- `ALREADY_REVIEWED` on draft approval/rejection shows a toast/message and returns to ParentAdmin.
- Mock adapter states must mirror real network success/error shapes.

## 9. Test Plan

XCTest:

- `BattleEngineTests`: start, correct, wrong, combo burst, monster defeat, win, loss by HP, loss by timer, star computation.
- `GameConfigTests`: defaults, stepper bounds, timer presets, custom timer validation.
- `QuestionGeneratorTests`: answer inclusion, no duplicate options, fallback distractors.
- `ParentApiClientDTOTests`: decode stats, draft list, draft detail, import response, publish response, error envelope.
- `LessonDraftReviewStoreTests`: toggle keep/drop, edit row, approve payload, reject behavior.

XCUITest:

- Home -> Battle -> Result deterministic fixture path.
- Config -> Parent PIN setup -> ParentAdmin.
- ParentAdmin mock refresh.
- ParentAdmin mock import -> LessonDraftReview -> edit -> approve.
- ParentAdmin back restores landscape.

Screenshot tests:

- iPhone landscape Home/Battle/Result/Config/PIN.
- iPhone portrait ParentAdmin/LessonDraftReview.

## 10. Acceptance Criteria

- Phase 1 can be implemented without changing server or HarmonyOS code.
- Child flow is playable offline with builtin fixture words.
- ParentAdmin is reachable in Phase 1 and preserves real API boundaries.
- ParentAdmin remains portrait and child flow remains landscape.
- The implementation has stable XCUITest identifiers matching this spec.
- All Phase 1 pure logic is testable without SwiftUI.
