# UI suite interactive triage (worktree only)

**Branch:** `fix/ui-suite-triage`  
**Worktree path:** `happyword/.worktrees/ui-suite-triage` (sibling to main clone root — adjust if your layout differs)

All edits for this effort happen **only in this worktree**. Do not commit triage notes to `main` until reviewed.

---

## SOP (per suite)

1. **Run the suite once** (from worktree root):
   ```bash
   export JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-21.jdk/Contents/Home
   export PATH="$JAVA_HOME/bin:$PATH"
   cd /path/to/happyword/.worktrees/ui-suite-triage
   ./scripts/run_ui_tests.sh --suite <HypiumClassName>
   ```
   Log tip: `tee build-tmp/suite_<name>.log`

2. **If green** → mark task done, **stop and ask the human** before starting the next suite.

3. **If red** → triage loop:
   - Use **hdc** (shell / uitest) to drive the app to the same screens as the test (document exact taps/route).
   - At **key steps**, capture **screenshots** (`hdc shell snapshot_display` or device screenshot flow your team uses).
   - Note what differs from expected (missing id, wrong text, wrong route, timing).
   - **Read code** (app + test) for that path; write a short **cause summary** (hypothesis + evidence).
   - **Discuss** fix options with the human; **decision points** go to the human.
   - Implement fix **only after agreement**; keep scope to **this suite** unless obviously shared.

4. **Before starting the next suite** → explicit **confirmation** from the human (no batch-fix across suites).

---

## Hypium `--suite` class names

| Register order (List.test) | `--suite` value |
|---------------------------|-----------------|
| HomeToolbarLocked | `HomeToolbarLocked` |
| MonsterCodexFlow | `MonsterCodexFlow` |
| RoutingFlow | `RoutingFlowUiTest` |
| CritSpectacle | `CritSpectacleUiTest` |
| SpeakerButton | `SpeakerButtonUiTest` |
| ReviewMode | `ReviewModeUiTest` |
| MagicAttack | `MagicAttackUiTest` |
| FillLetterFlow | `FillLetterFlow` |
| SpellQuestionFlow | `SpellQuestionFlow` |
| AdventureFlow | `AdventureFlow` |
| TodayPlanFlow | `TodayPlanFlow` |
| LearningReportFlow | `LearningReportFlow` |
| RegionPickerFlow | `RegionPickerFlow` |
| WishlistFlow | `WishlistFlow` |
| CustomWishlistFlow | `CustomWishlistFlow` |
| ConfigFlow | `ConfigFlow` |
| PackManagerFlow | `PackManagerFlow` |
| ParentAdminFlow | `ParentAdminFlow` |
| LessonDraftReviewFlow | `LessonDraftReviewFlow` |
| ParentBindingFlow | `ParentBindingFlow` |
| BoundDeviceInfoFlow | `BoundDeviceInfoFlow` |

---

## Tasks (failing suites — baseline from last per-suite run)

Use this list as the **default order** for “攻克”. Green suites from that run are omitted here; re-run full list if regressions appear.

### Task 1 — HomeToolbarLocked
- **Failed cases (baseline):** `lockedReviewShowsToastAndStays` (Error)

### Task 2 — FillLetterFlow
- **Failed cases:** `singleLetterFillAcceptsCorrectLetter`, `mediumLetterFillCompletesBothSteps`

### Task 3 — SpellQuestionFlow
- **Failed cases:** `fillsSpellSlotsByTappingCorrectPoolLetters`, `rejectsTapsThatDoNotMatchTheNextSlot`

### Task 4 — WishlistFlow
- **Failed cases:** `correctPinShowsGiftBoxAndConfirmsRedemption`

### Task 5 — CustomWishlistFlow
- **Failed cases:** `addCustomDialogOpensAfterCorrectPin`, `submitEmptyFormShowsInlineNameError`, `submitOutOfRangeCostShowsInlineCostError`, `validInputAddsWishCardToList`

### Task 6 — ConfigFlow
- **Failed cases:** `configParentPinButtonNavigatesToSetupPage`, `twoStepMatchPersistsPinAndUpdatesButtonLabel`, `customTimerDialogAcceptsThreeSecondsAndUpdatesChip`, `customTimerDialogRejectsZeroAndKeepsDialogOpen`, `mismatchSurfacesHintAndResetsBuffer`

### Task 7 — PackManagerFlow
- **Failed cases:** `syncedGlobalPackAppearsInListAndActivatingItGrowsHomeChipRow`

### Task 8 — ParentAdminFlow
- **Failed cases:** `configHasAdminEntryButton`, `correctPinNavigatesToParentAdmin`, `adminButtonOpensPinDialogAndWrongPinStays`, `parentAdminInteractionsStayStable`, `refreshShowsMockedStats`, `pendingListShowsMockedDraft`, `tapPickGalleryUploadsAndShowsImported`, `tapReviewLinkOpensReviewPageWithMockedDraft`, `tapPublishShowsSuccessSummary`

### Task 9 — ParentBindingFlow
- **Failed cases:** `unboundConfigPageRendersBindEntryOnly`, `tapBindOpensScanBindingPage`, `shortCodeRedeemFlipsConfigToBound`, `pickQrFromGalleryRedeemsAndFlipsToBound`, `unbindFromBoundDeviceInfoPageFlipsBackToUnbound`

---

## Environment cleanup (before a clean run)

- Free host port **8123**, remove stale `hdc fport` for `tcp:8123` if needed.
- `scripts/run_ui_tests.sh` starts mock + `rport`; do not run a second mock on the same port.

---

## Push remote (optional)

When ready to collaborate without touching `main`:

```bash
cd .worktrees/ui-suite-triage
git push -u origin fix/ui-suite-triage
```
