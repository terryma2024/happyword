# Phase 1: Core Learning Loop And ParentAdmin

## Goal

Ship the first native Android slice:

```text
Home -> Battle -> Result
Config -> Parent PIN -> ParentAdmin -> Lesson image import entry -> LessonDraftReview
```

Child-facing pages target phone landscape. ParentAdmin and LessonDraftReview target phone portrait.

## Phase 1 Components

### App Shell And Orientation

Responsibilities:

- Start in child landscape flow.
- Route Home, Battle, Result, Config, ParentPinSetup, ParentAdmin, LessonDraftReview.
- Switch to portrait when entering ParentAdmin or LessonDraftReview.
- Restore landscape when leaving parent/admin flow.

Implementation guidance:

- Use a central `AppRoute` sealed interface.
- Keep orientation policy in one Android-specific adapter.
- Keep route state independent from Composables for testability.

Acceptance:

- Config opens ParentAdmin only after PIN verification.
- ParentAdmin appears in portrait.
- Back from ParentAdmin restores the child landscape route.

### Home

Data inputs:

- `GameConfig`
- current child display name when available
- coin balance
- active pack list, initially five builtin pack names
- today completion state

Phase 1 behavior:

- Show compact top identity/coin/tool row.
- Show `Small Magician Word Adventure`.
- Show active pack chips in English.
- Show AdventureCard for selected pack.
- Tapping a chip changes selected pack locally.
- Primary button builds a today plan and routes to Battle.
- Review/Codex/Wishlist/LearningReport toolbar entries may be hidden or disabled until Phase 2.

Acceptance:

- First loaded Home can start a battle offline.
- Active pack title and selected chip match.
- Landscape phone view does not require scrolling for the primary action.

### Battle

Data inputs:

- `GameConfig`
- `TodaySessionPlan`
- active `Pack.words`
- local `LearningRecorder`

Phase 1 behavior:

- Start with HarmonyOS defaults: player HP 5, monster HP 3, monster count 5, timer 300 seconds.
- Render player card, question prompt, speaker action, monster card, and three answer buttons.
- Support `Choice` questions in the first playable implementation.
- Keep type boundaries for `FillLetter`, `FillLetterMedium`, and `Spell`.
- Correct answer damages monster.
- Wrong answer damages player.
- Three consecutive correct answers trigger double damage and combo feedback.
- Battle ends on all monsters defeated, player HP 0, or timer 0.
- Result route receives `SessionResult`.

Acceptance:

- JVM tests cover core `BattleEngine` transitions before UI acceptance.
- Compose UI test can tap through a deterministic mock battle.
- HP bars, timer, prompt, and answers remain visible in landscape.

### Result

Data inputs:

- `SessionResult`
- coin account snapshot

Phase 1 behavior:

- Show win/loss, stars, defeated monsters, correct rate, learned word count.
- Today mode grants coins equal to stars, matching the current HarmonyOS rule.
- Provide primary route to Home.
- Wishlist shortcut can be hidden or disabled until Phase 2.

Acceptance:

- A deterministic won battle shows stars and coin delta.
- Returning Home updates today completion/coin display in local app state.

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
- PackManager row visible as a Phase 2 target.

PIN rules:

- Six digits.
- Empty PIN means ParentAdmin entry shows setup guidance.
- Setup/edit uses two-step confirmation.
- PIN is local in Phase 1.

Acceptance:

- Config can save and reload `GameConfig`.
- Custom timer `3` remains valid for fast timeout tests.
- ParentAdmin cannot open without PIN when a PIN is configured.

### ParentAdmin

ParentAdmin is portrait in Phase 1.

Data inputs:

- selected backend environment
- parent PIN gate already satisfied
- `ParentApiClient`, initially fake/mockable

Phase 1 behavior:

- Show server label.
- Show overview card and refresh state.
- Show lesson import card with camera and gallery buttons.
- Show pending draft list.
- Show publish new pack card.
- Preserve all real API boundaries even if the first running app uses fake adapters.

Network boundary:

- `ParentApiClient.fetchStats()`
- `ParentApiClient.fetchLessonDrafts()`
- `ParentApiClient.importLessonImage(...)`
- `ParentApiClient.publishPack(notes)`

Acceptance:

- Compose UI test can route Config -> PIN -> ParentAdmin.
- Fake refresh displays overview values.
- Fake import displays a success state and route to LessonDraftReview.
- Publish action can be tested against a fake success summary.

### LessonDraftReview

Portrait in Phase 1.

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

- JVM tests cover DTO decoding and local row edit state.
- Compose UI test can open review from ParentAdmin fake draft and approve via fake client.

## First Implementation Task Breakdown

1. Create Android project shell and test targets.
2. Add pure Kotlin core models and `BattleEngine` with failing JVM tests first.
3. Add deterministic fixture word repository and question generation.
4. Build Home/Battle/Result Compose screens around fake data.
5. Add Config and local `GameConfigStore`.
6. Add PIN setup/gate.
7. Add ParentAdmin portrait route with fake `ParentApiClient`.
8. Add LessonDraftReview portrait route with fake draft detail.
9. Add screenshot/test tags for Phase 1 screens.

## Explicit Deferrals

- Real camera/gallery permission behavior can be deferred, but `LessonImagePicker` must exist as an interface.
- Real OpenAI recognition is server-side and not implemented in Android.
- PackManager full activation/sync/pin behavior is Phase 2.
- Device binding and family pack sync are Phase 3.
- DevMenu and preview bypass are Phase 4.
