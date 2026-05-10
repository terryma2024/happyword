import { SERVER_BASE_URL_OVERRIDE_KEY } from '../../../main/ets/services/RemoteWordPackConfig';
import routingFlowUiTest from './RoutingFlow.ui.test';
import critSpectacleUiTest from './CritSpectacle.ui.test';
import speakerButtonUiTest from './SpeakerButton.ui.test';
import reviewModeUiTest from './ReviewMode.ui.test';
import magicAttackUiTest from './MagicAttack.ui.test';
import adventureFlowUiTest from './AdventureFlow.ui.test';
import homeToolbarLockedUiTest from './HomeToolbarLocked.ui.test';
import homeVersionTapUiTest from './HomeVersionTap.ui.test';
import devMenuCardListUiTest from './DevMenuCardList.ui.test';
import fillLetterFlowUiTest from './FillLetterFlow.ui.test';
import spellQuestionFlowUiTest from './SpellQuestionFlow.ui.test';
import monsterCodexFlowUiTest from './MonsterCodexFlow.ui.test';
import todayPlanFlowUiTest from './TodayPlanFlow.ui.test';
import learningReportFlowUiTest from './LearningReportFlow.ui.test';
import regionPickerFlowUiTest from './RegionPickerFlow.ui.test';
import wishlistFlowUiTest from './WishlistFlow.ui.test';
import customWishlistFlowUiTest from './CustomWishlistFlow.ui.test';
import configFlowUiTest from './ConfigFlow.ui.test';
import parentAdminFlowUiTest from './ParentAdminFlow.ui.test';
import lessonDraftReviewFlowUiTest from './LessonDraftReviewFlow.ui.test';
import parentBindingFlowUiTest from './ParentBindingFlow.ui.test';
import boundDeviceInfoFlowUiTest from './BoundDeviceInfoFlow.ui.test';
import packManagerFlowUiTest from './PackManagerFlow.ui.test';

/**
 * V0.5.8: route every HTTP call from the test ability through the
 * locally-hosted FastAPI mock at 127.0.0.1:8123 (see
 * server/mock_ui_server.py + scripts/run_ui_tests.sh).
 *
 * The override URL is read by `effectiveServerBaseUrl()` in
 * RemoteWordPackConfig.ets every time a page (or sync service)
 * builds its API client. Pages are only constructed AFTER the test
 * delegator launches the main ability, so writing the key here in
 * `testsuite()` guarantees the first page never sees the prod URL.
 *
 * Production / release builds NEVER write this key. They land on
 * STAGING_BASE_URL through the same `effectiveServerBaseUrl()` call,
 * which falls back to `pickServerBaseUrl(BuildProfile.BUILD_MODE_NAME)`
 * when the override is absent or empty.
 *
 * The orchestrator script `scripts/run_ui_tests.sh` is responsible
 * for booting the mock server on the host and forwarding the
 * device's loopback (`hdc rport tcp:8123 tcp:8123`); this file is
 * only the in-process injection of the override URL.
 */
const UI_TEST_SERVER_BASE_URL: string = 'http://127.0.0.1:8123';

function injectMockServerOverride(): void {
  AppStorage.setOrCreate<string>(
    SERVER_BASE_URL_OVERRIDE_KEY,
    UI_TEST_SERVER_BASE_URL,
  );
}

export default function testsuite() {
  injectMockServerOverride();
  // The lesson-import picker override is written by individual UI
  // tests in ParentAdminFlow because materialising the bundled
  // fixture into the app sandbox is async (`fs.open` + `fs.write`)
  // and `testsuite()` runs synchronously. See
  // `ParentAdminFlow.ui.test.ets::ensureLessonImportFixtureOnDevice`.
  // HomeToolbarLocked must run before any suite that seeds wrong
  // answers into LearningRecorder (ReviewMode / MagicAttack / AdventureFlow etc.)
  // — its lockedReviewShowsToastAndStays case asserts the toast is
  // surfaced when recentWrongCount < 3, which would silently flip to
  // navigation once the recorder has accrued ≥3 wrongs.
  homeToolbarLockedUiTest();
  // V0.6: debug-only version label + triple-tap → DevMenu navigation.
  // Order-independent: these tests press Back at the tail so HomePage
  // is reachable for the next suite. Placed right after
  // homeToolbarLockedUiTest because both are "home toolbar / top
  // chrome" smoke tests and grouping them surfaces top-screen
  // regressions early.
  homeVersionTapUiTest();
  // V0.6: DevMenuPage unified card grid (Local / Staging / previews).
  // Tap-to-apply; manifest GET uses PREVIEW_MANIFEST_JSON_URL only (not the mock base URL).
  devMenuCardListUiTest();
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
  adventureFlowUiTest();
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
  // V0.6.7: the manual `词库同步` row was removed from ConfigPage —
  // pack synchronisation is now handled by `pages/PackManagerPage`
  // (📦 我的词包 → 🔄 同步词包), which drives the three-layer
  // GlobalPackService + FamilyPackService stack. The legacy
  // `configSyncFlowUiTest` (CACHED_STATUS_PREFIX / ConfigSyncButton)
  // was deleted with that surface.
  // V0.6.7.3: PackManagerPage routing + 固定 button conditional-render
  // contract. Each test restores PackSelection to default (5/5
  // active, none pinned) before returning to HomePage so this suite
  // is order-independent vs everything below it.
  packManagerFlowUiTest();
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
  // V0.6 — parent-account binding lifecycle on ConfigPage.
  // Drives unbound → ScanBindingPage → manual short-code redeem →
  // bound state → unbind via parent PIN → unbound again, all through
  // the local mock at 127.0.0.1:8123. Runs LAST because it leaves
  // AppStorage in a parent-PIN-set state that downstream suites
  // would have to clean up; placing it at the tail keeps every other
  // suite's assumptions intact.
  parentBindingFlowUiTest();
  // V0.6.8 — device-side child-nickname edit on `BoundDeviceInfoPage`.
  // Self-contained: drives a short-code redeem on the mock, opens the
  // bound-device info page, taps ✏️ 编辑, replaces the input, saves,
  // and asserts that the row + the ConfigPage button label both
  // refresh to the new nickname. Runs after ParentBindingFlow (which
  // leaves the device unbound) so we start clean.
  boundDeviceInfoFlowUiTest();
}
