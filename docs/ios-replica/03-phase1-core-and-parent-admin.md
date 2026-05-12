# Phase 1: Core Learning Loop And ParentAdmin

## Goal

Ship the first native iOS slice as a design-complete plan for:

```text
Home -> Battle -> Result
Config -> Parent PIN -> ParentAdmin -> Lesson image import entry -> LessonDraftReview
```

Child-facing pages target iPhone landscape. ParentAdmin and LessonDraftReview target iPhone portrait.

## Phase 1 Components

### App Shell And Orientation

Responsibilities:

- Start in child landscape flow.
- Route Home, Battle, Result, Config, ParentPinSetup, ParentAdmin, LessonDraftReview.
- Switch to portrait when entering ParentAdmin or LessonDraftReview.
- Restore landscape when leaving parent admin flow.

Implementation guidance for later SwiftUI work:

- Use a central `AppRoute` enum and an app-level coordinator rather than view-local ad hoc navigation.
- Keep orientation policy isolated in `OrientationController`.
- Treat orientation changes as part of route transition tests.

Acceptance:

- Config opens ParentAdmin only after PIN verification.
- ParentAdmin appears in portrait.
- Back from ParentAdmin restores child landscape route.

### Home

Data inputs:

- `GameConfig`
- current child display name if available
- coin balance
- active pack list, initially five builtin pack names
- today completion state

Phase 1 behavior:

- Show compact top identity/coin/tool row.
- Show `Small Magician Word Adventure`.
- Show active pack chips in English.
- Show AdventureCard for selected pack.
- Tapping a chip changes selected pack only locally.
- Primary button builds a today plan and routes to Battle.
- Review/Codex/Wishlist/LearningReport toolbar entries may be disabled, hidden, or routed to Phase 2 placeholders, but their eventual role must be documented.

Acceptance:

- First loaded Home can start a battle offline.
- Active pack title and selected chip match.
- iPhone landscape view does not require scrolling for primary action.

### Battle

Data inputs:

- `GameConfig`
- `TodaySessionPlan`
- active `Pack.words`
- local `LearningRecorder`

Phase 1 behavior:

- Start with player HP, monster HP, monster count, timer defaults matching HarmonyOS.
- Render player card, question prompt, speaker action, monster card, and three choice buttons.
- Support `Choice` questions in the first playable implementation.
- Keep type boundaries for `FillLetter`, `FillLetterMedium`, and `Spell`; these can be enabled later without replacing the engine.
- Correct answer damages monster; wrong answer damages player.
- Three consecutive correct answers trigger double damage and combo feedback.
- Battle ends on all monsters defeated, player HP 0, or timer 0.
- Result route receives `SessionResult`.

Acceptance:

- XCTest covers core `BattleEngine` transitions before UI acceptance.
- XCUITest can tap through a deterministic mock battle.
- HP bars, timer, prompt, and answers remain visible in iPhone landscape.

### Result

Data inputs:

- `SessionResult`
- coin account snapshot

Phase 1 behavior:

- Show win/loss, stars, defeated monsters, correct rate, learned word count.
- Today mode grants coins equal to stars, matching current HarmonyOS rule.
- Provide primary route to Home.
- Wishlist shortcut can be hidden or disabled until Phase 2, but the result model must keep coin fields.

Acceptance:

- A won deterministic battle shows stars and coin delta.
- Returning Home updates today completion/coin display in the local app state.

### Config And Parent PIN

Phase 1 Config includes:

- Player HP stepper.
- Monster HP stepper.
- Monster count stepper.
- Timer chips: 30s, 3m, 5m, 10m.
- Custom timer entry with 1...3600 seconds.
- Auto pronunciation toggle.
- Parent PIN setup/edit entry.
- ParentAdmin entry gated by PIN.
- PackManager row visible as Phase 2 target, with clear disabled or placeholder behavior.

PIN rules:

- Six digits.
- Empty PIN means ParentAdmin entry shows setup guidance.
- Two-step confirmation in setup/edit.
- PIN is local in Phase 1.

Acceptance:

- Config can save and reload `GameConfig`.
- Custom timer `3` remains valid for future UI timeout tests.
- ParentAdmin cannot open without PIN when a PIN is configured.

### ParentAdmin

ParentAdmin is Phase 1, portrait.

Data inputs:

- selected backend environment
- parent PIN gate already satisfied
- `ParentApiClient`, initially mockable

Phase 1 behavior:

- Show server label.
- Show overview card and refresh state.
- Show lesson import card with camera and gallery buttons.
- Show pending draft list.
- Show publish new pack card.
- Preserve all real API boundaries even if the first running app uses mock adapters.

Network boundary:

- `ParentApiClient.fetchStats()`
- `ParentApiClient.fetchLessonDrafts()`
- `ParentApiClient.importLessonImage(_:)`
- `ParentApiClient.publishPack(notes:)`

Acceptance:

- XCUITest can route Config -> PIN -> ParentAdmin.
- Mock refresh displays overview values.
- Mock import displays a success state and route to LessonDraftReview.
- Publish action can be tested against a mock success summary.

### LessonDraftReview

Portrait, Phase 1.

Data inputs:

- draft detail from `ParentApiClient`
- local edit state in `LessonDraftReviewStore`

Phase 1 behavior:

- Show original image thumbnail.
- Show editable category/theme label.
- Render candidate word rows.
- Allow keep/drop toggles.
- Allow editing English and Chinese text.
- Approve path patches edited draft, then calls approve.
- Reject path calls reject.
- Already-reviewed response shows a message and returns to ParentAdmin.

Acceptance:

- XCTest covers DTO decoding and local row edit state.
- XCUITest can open review from ParentAdmin mock draft and approve via mock client.

## First Implementation Task Breakdown

This docs pass does not create Swift files. When implementation starts, use these slices:

1. Create iOS project shell and test targets.
2. Add pure Swift core models and `BattleEngine` with failing XCTest first.
3. Add deterministic fixture word repository and question generation.
4. Build Home/Battle/Result SwiftUI screens around fake data.
5. Add Config and local `GameConfigStore`.
6. Add PIN setup/gate.
7. Add ParentAdmin portrait route with mock `ParentApiClient`.
8. Add LessonDraftReview portrait route with mock draft detail.
9. Add screenshot/XCUITest identifiers for Phase 1 screens.

## Explicit Deferrals

- Real camera/gallery permission behavior can be deferred, but `LessonImagePicker` must exist as an interface.
- Real OpenAI recognition is server-side and not implemented in iOS.
- PackManager full activation/sync/pin behavior is Phase 2.
- Device binding and family pack sync are Phase 3.
- DevMenu and preview bypass are Phase 4.
