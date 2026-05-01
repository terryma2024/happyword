import routingFlowUiTest from './RoutingFlow.ui.test';
import critSpectacleUiTest from './CritSpectacle.ui.test';
import speakerButtonUiTest from './SpeakerButton.ui.test';
import reviewModeUiTest from './ReviewMode.ui.test';
import magicAttackUiTest from './MagicAttack.ui.test';
import v03AdventureUiTest from './V03Adventure.ui.test';
import homeToolbarLockedUiTest from './HomeToolbarLocked.ui.test';
import fillLetterFlowUiTest from './FillLetterFlow.ui.test';
import spellQuestionFlowUiTest from './SpellQuestionFlow.ui.test';
import monsterCodexFlowUiTest from './MonsterCodexFlow.ui.test';
import todayPlanFlowUiTest from './TodayPlanFlow.ui.test';
import learningReportFlowUiTest from './LearningReportFlow.ui.test';
import regionPickerFlowUiTest from './RegionPickerFlow.ui.test';
import wishlistFlowUiTest from './WishlistFlow.ui.test';
import customWishlistFlowUiTest from './CustomWishlistFlow.ui.test';
import configFlowUiTest from './ConfigFlow.ui.test';
import configSyncFlowUiTest from './ConfigSyncFlow.ui.test';
import parentAdminFlowUiTest from './ParentAdminFlow.ui.test';
import lessonDraftReviewFlowUiTest from './LessonDraftReviewFlow.ui.test';

export default function testsuite() {
  // HomeToolbarLocked must run before any suite that seeds wrong
  // answers into LearningRecorder (ReviewMode / MagicAttack / V03 etc.)
  // — its lockedReviewShowsToastAndStays case asserts the toast is
  // surfaced when recentWrongCount < 3, which would silently flip to
  // navigation once the recorder has accrued ≥3 wrongs.
  homeToolbarLockedUiTest();
  // MonsterCodexFlow is order-independent: the codex page reads only
  // a frozen static array (MONSTER_CODEX) and does not touch the
  // recorder. Runs second to surface failures fast — codex regressions
  // shouldn't be hidden behind 6+ minutes of unrelated suites.
  monsterCodexFlowUiTest();
  routingFlowUiTest();
  critSpectacleUiTest();
  speakerButtonUiTest();
  reviewModeUiTest();
  magicAttackUiTest();
  v03AdventureUiTest();
  // FillLetterFlow taps correct answers driven by a static catalog
  // map (see the file's header comment) so it stays deterministic
  // even after earlier suites populated the LearningRecorder. Runs
  // last so any monster-defeated stat seeded here does not pollute
  // the assumptions the other suites bake in.
  fillLetterFlowUiTest();
  // V0.4.1: drives a Boss Spell question end-to-end on the same
  // fruit-forest plan as FillLetterFlow. Reuses the static zh→en
  // catalog so the suite stays deterministic.
  spellQuestionFlowUiTest();
  // V0.4.4: read-only daily plan page. Navigation-only test —
  // verifies HomePlanButton → TodayPlanPage → back works and the
  // page renders its essential ids. Order-independent vs the
  // recorder-seeded suites because TodayPlanService tolerates any
  // recorder state.
  todayPlanFlowUiTest();
  // V0.4.5: navigation-only — opens HomePage → TodayPlanPage →
  // LearningReportPage; surface and back nav. Tolerates any
  // recorder state because LearningReportBuilder treats every
  // word the same way regardless of prior taps.
  learningReportFlowUiTest();
  // V0.4.6: navigation-only — verifies all 5 region chips exist
  // in the new horizontal Scroll container, and tapping one swaps
  // the AdventureCard title. Resets to fruit-forest before
  // returning so downstream suites still start on the default.
  regionPickerFlowUiTest();
  // V0.3.9: wishlist redesign + parent PIN setup. Both suites are
  // navigation-only (they do not seed coins, do not redeem); the
  // full PIN → GiftBox → history flow is unit-tested.
  wishlistFlowUiTest();
  // V0.4.7: parent-created custom wishlist entries. Runs after the
  // built-in wishlistFlowUiTest because the second test in this
  // suite re-commits the parent PIN — we don't want PIN setup
  // bleed-over interfering with WishlistFlow's
  // applyWithoutPinPromptsParentPinSetupHint case (which assumes
  // the cheapest wish either has WishApply or WishGap, not a
  // mid-PIN-entry side-effect).
  customWishlistFlowUiTest();
  configFlowUiTest();
  // V0.5 client follow-up (VC0.5.B): manual word-pack sync entry on
  // ConfigPage. Order-independent; relies only on the cache slot
  // schema and the production /packs/latest.json endpoint.
  configSyncFlowUiTest();
  // V0.5.8: parent admin backend behind parent PIN (auth removed,
  // photo lesson import added). Re-seeds the PIN to KNOWN_PIN inside
  // each case so we don't depend on configFlowUiTest's twoStep
  // ordering, but it is still scheduled after configFlowUiTest
  // because the latter's mismatchSurfacesHintAndResetsBuffer leaves
  // AppStorage in a mismatch state that this suite then heals.
  parentAdminFlowUiTest();
  // V0.5.8 H2: smoke-test that pages/LessonDraftReviewPage was added
  // to main_pages.json without breaking app boot. Real edit / approve
  // / reject coverage lives in ParentApiClient unit tests.
  lessonDraftReviewFlowUiTest();
}
