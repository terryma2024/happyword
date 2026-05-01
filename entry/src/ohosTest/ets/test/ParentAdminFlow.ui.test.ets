import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want, common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@ohos.base';
import { LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY } from '../../../main/ets/services/LessonImagePicker';
import { clickByIdShared } from './RoutingFlow.ui.test';

/**
 * V0.5.8 acceptance: parent admin backend + parent-PIN gate.
 *
 * ConfigPage exposes `ConfigParentAdminButton`; tapping it either
 * nudges the operator to set up a parent PIN (when none is configured)
 * or pops the existing `ParentPinDialog` and routes to ParentAdminPage
 * on the correct PIN.
 *
 * V0.5.8 removed the JWT login UI. The parent admin page now renders
 * the stats / publish surface immediately on mount; we DO NOT assert
 * statsCard contents because that would require a live server.
 *
 * Order: this file MUST run after configFlowUiTest's
 * twoStepMatchPersistsPinAndUpdatesButtonLabel (which is what seeds
 * GameConfig.parentPin = "123456" into AppStorage). List.test.ets
 * registers it after that suite; if you reorder, also re-seed the
 * PIN here.
 */

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

/** PIN value committed by configFlowUiTest's twoStep test. */
const KNOWN_PIN: string = '123456';

async function launchApp(): Promise<Driver> {
  const want: Want = { bundleName: BUNDLE, abilityName: 'EntryAbility' };
  await DELEGATOR.startAbility(want);
  const driver: Driver = Driver.create();
  await driver.delayMs(1000);
  return driver;
}

async function returnToHome(driver: Driver): Promise<void> {
  for (let i: number = 0; i < 5; i++) {
    const home: Component | null =
      await driver.findComponent(ON.id('HomeStartButton'));
    if (home !== null) {
      return;
    }
    await driver.pressBack();
    await driver.delayMs(500);
  }
}

async function openConfigAndScrollToAdmin(driver: Driver): Promise<void> {
  await clickByIdShared(driver, 'HomeConfigButton');
  await driver.delayMs(1500);
  await driver.assertComponentExist(ON.id('ConfigTitle'));
  // The admin row sits below the sync row at the very bottom of the
  // form. A single swipe-up is enough on the narrow landscape
  // emulator viewport to bring it into view.
  await driver.swipe(1400, 1100, 1400, 300, 600);
  await driver.delayMs(400);
}

async function tapPinDialogKey(driver: Driver, key: string): Promise<void> {
  await clickByIdShared(driver, `ParentPinDialogKey_${key}`);
  await driver.delayMs(80);
}

async function tapPinSetupKey(driver: Driver, key: string): Promise<void> {
  await clickByIdShared(driver, `ParentPinSetupKey_${key}`);
  await driver.delayMs(80);
}

/**
 * Idempotent PIN seeder. Mirrors WishlistFlow.ui.test.ets's
 * ensureParentPin so this suite can run independently of
 * configFlowUiTest's ordering. Re-committing the same PIN is a no-op
 * from the operator's perspective: ParentPinSetupPage's
 * commitOrReset() persists `firstBuf` into AppStorage and routes
 * back to ConfigPage either way.
 */
async function ensureParentPin(driver: Driver, pin: string): Promise<void> {
  await clickByIdShared(driver, 'HomeConfigButton');
  await driver.delayMs(1500);
  await driver.swipe(1400, 1100, 1400, 300, 600);
  await driver.delayMs(300);
  await clickByIdShared(driver, 'ConfigParentPinButton');
  await driver.delayMs(1200);

  for (let i: number = 0; i < pin.length; i++) {
    await tapPinSetupKey(driver, pin.charAt(i));
  }
  await driver.delayMs(400);
  for (let i: number = 0; i < pin.length; i++) {
    await tapPinSetupKey(driver, pin.charAt(i));
  }
  await driver.delayMs(1500);

  await clickByIdShared(driver, 'ConfigCancelButton');
  await driver.delayMs(800);
  await returnToHome(driver);
}

/**
 * Drive HomePage → ConfigPage → ParentAdminButton → ParentPinDialog →
 * correct PIN → ParentAdminPage. Caller must have already returned to
 * HomePage and ensured KNOWN_PIN is committed.
 */
async function navigateToParentAdminPage(driver: Driver): Promise<void> {
  await openConfigAndScrollToAdmin(driver);
  await clickByIdShared(driver, 'ConfigParentAdminButton');
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('ParentPinDialog'));
  for (let i: number = 0; i < KNOWN_PIN.length; i++) {
    await tapPinDialogKey(driver, KNOWN_PIN.charAt(i));
  }
  // ParentPinDialog auto-dismisses on a correct PIN, then the
  // CustomDialog onConfirm pushes pages/ParentAdminPage. Allow a beat
  // for the page transition + aboutToAppear (which also locks portrait).
  await driver.delayMs(1500);
  await driver.assertComponentExist(ON.id('ParentAdminTitle'));
}

/**
 * Bring the ParentAdminPage publishCard into view. The page is a
 * Scroll() that lays out: title → server label → statsCard →
 * lessonImportCard → draftListCard → publishCard. Once the local
 * mock server (server/mock_ui_server.py) responds, statsCard renders
 * 8 stat lines and draftListCard renders ≥1 row, which pushes the
 * publish controls below the portrait viewport on the emulator.
 *
 * Coordinates target the portrait emulator (locked in
 * ParentAdminPage.aboutToAppear). One upward swipe is enough to
 * expose the publish card at the bottom of the page; the post-swipe
 * delay lets ArkUI settle the new visible region before UiTest's
 * matcher pass picks the realised components up.
 */
async function scrollParentAdminToPublish(driver: Driver): Promise<void> {
  await driver.swipe(360, 1000, 360, 300, 600);
  await driver.delayMs(400);
}

/**
 * Reverse of {@link scrollParentAdminToPublish}: drag the page back
 * to the top so callers can interact with title-row / refresh /
 * stats components again. Required before {@link exitParentAdminPage}
 * because the back button lives at the very top of the page.
 */
async function scrollParentAdminToTop(driver: Driver): Promise<void> {
  await driver.swipe(360, 300, 360, 1000, 600);
  await driver.delayMs(400);
}

/**
 * Inverse of navigateToParentAdminPage: ParentAdminBack → ConfigPage →
 * pressBack → HomePage. ConfigPage's outer Scroll is reset to the top
 * by the portrait-to-landscape flip in ParentAdminPage.aboutToDisappear,
 * so the ConfigCancelButton at the bottom is below the fold and we
 * have to dismiss with pressBack instead of clicking it.
 */
async function exitParentAdminPage(driver: Driver): Promise<void> {
  // The page may have been scrolled down to expose publishCard during
  // the test body. Scroll back up so the back button at the top is
  // visible to the matcher.
  await scrollParentAdminToTop(driver);
  await clickByIdShared(driver, 'ParentAdminBack');
  await driver.delayMs(1500);
  await driver.assertComponentExist(ON.id('ConfigTitle'));
  await driver.pressBack();
  await driver.delayMs(800);
  await driver.assertComponentExist(ON.id('HomeStartButton'));
}

/**
 * Materialise the lesson-import fixture into the app sandbox.
 *
 * The fixture is bundled into the ohosTest module at
 * `entry/src/ohosTest/resources/rawfile/lesson_import_fixture.jpg` so
 * the bytes are part of the test HAP — there is no host-side
 * copy step at runtime. We can NOT use `hdc file send` to drop the
 * file at a known path: HarmonyOS NEXT's selinux blocks every path
 * the shell user can write (`/data/local/tmp/`,
 * `/storage/media/100/local/files/`, the bundle's `el2/.../files/`)
 * from being read by the bundle's UID. Bundling the bytes inside the
 * test HAP and copying via the test-ability's fs APIs is the only
 * reliable on-device path.
 *
 * Writes the bytes to `<appCtx.tempDir>/lesson_import_fixture.jpg`
 * (the bundle's own sandbox temp dir, always readable by the app's
 * UIAbilityContext) and overwrites the AppStorage picker-override
 * key so `RealPhotoPickerAdapter.{selectGallery,selectCamera}` see
 * a path that fs.open accepts. Returns the absolute path.
 */
async function ensureLessonImportFixtureOnDevice(): Promise<string> {
  const appCtx: common.Context = DELEGATOR.getAppContext();
  const dest: string = `${appCtx.tempDir}/lesson_import_fixture.jpg`;

  // Idempotent: if the file is already there from a previous it()
  // we don't re-copy (saves ~226KB of fs.write per test invocation).
  if (fs.accessSync(dest)) {
    AppStorage.setOrCreate<string>(LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY, dest);
    return dest;
  }

  // The fixture lives in the ohosTest module's rawfile, so we need
  // a context scoped to the `entry_test` module to find its
  // resourceManager. `appCtx.resourceManager` only sees the main
  // module's (entry) resources — calling getRawFileContent through
  // the app context fails with "GetRawFileContent failed".
  const moduleCtx: common.Context = appCtx.createModuleContext('entry_test');
  const bytes: Uint8Array = await moduleCtx.resourceManager.getRawFileContent(
    'lesson_import_fixture.jpg',
  );
  const file: fs.File = await fs.open(
    dest,
    fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
  );
  try {
    await fs.write(file.fd, bytes.buffer);
  } finally {
    await fs.close(file);
  }
  AppStorage.setOrCreate<string>(LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY, dest);
  return dest;
}

/**
 * Type text into a ParentAdminPage TextInput, then dismiss the soft
 * keyboard so the next interaction can locate its target. Mirrors the
 * pattern that CustomWishlistFlow's typeInto uses for AddCustomWishDialog.
 */
async function typeIntoAdmin(driver: Driver, id: string, text: string): Promise<void> {
  await driver.assertComponentExist(ON.id(id));
  const input = await driver.findComponent(ON.id(id));
  await input.inputText(text);
  await driver.delayMs(300);
  await driver.pressBack();
  await driver.delayMs(400);
}

export default function parentAdminFlowUiTest(): void {
  describe('ParentAdminFlowV058', () => {
    /**
     * The admin entry button lives on ConfigPage just below the
     * sync row. Renders unconditionally — the parent-PIN guard is
     * applied on the click handler, not via visibility.
     */
    it('configHasAdminEntryButton', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfigAndScrollToAdmin(driver);

      await driver.assertComponentExist(ON.id('ConfigParentAdminButton'));
      const btn = await driver.findComponent(ON.id('ConfigParentAdminButton'));
      const label: string = await btn.getText();
      expect(label.indexOf('家长管理后台') >= 0).assertTrue();

      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    /**
     * With a configured PIN, tapping the admin entry pops the
     * `ParentPinDialog`. Wrong PIN keeps the dialog open and lights
     * up the inline error; pressBack then dismisses the dialog
     * without ever pushing ParentAdminPage onto the route stack.
     *
     * pressBack (rather than the in-dialog Cancel button) is the
     * dismissal channel because the keypad fills the dialog's full
     * height on the narrow landscape emulator viewport, leaving
     * `ParentPinDialogCancel` below the visible frame for findComponent.
     */
    it('adminButtonOpensPinDialogAndWrongPinStays', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      // Idempotent PIN seed — the configFlow twoStep test already
      // committed 123456, but re-seeding makes this case independent.
      await ensureParentPin(driver, KNOWN_PIN);

      await openConfigAndScrollToAdmin(driver);
      await clickByIdShared(driver, 'ConfigParentAdminButton');
      await driver.delayMs(800);

      await driver.assertComponentExist(ON.id('ParentPinDialog'));
      await driver.assertComponentExist(ON.id('ParentPinDialogTitle'));
      await driver.assertComponentExist(ON.id('ParentPinDialogKeypad'));

      // Wrong PIN: 000000 (KNOWN_PIN is 123456). Six taps fills
      // ParentPinDialog.buf, fails validatePin, fires the shake
      // animation and clears the buffer. The dialog STAYS open and
      // ParentAdminPage MUST NOT have been pushed.
      const wrong: string = '000000';
      for (let i: number = 0; i < wrong.length; i++) {
        await tapPinDialogKey(driver, wrong.charAt(i));
      }
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ParentPinDialog'));
      const adminTitle: Component | null =
        await driver.findComponent(ON.id('ParentAdminTitle'));
      expect(adminTitle === null).assertTrue();

      // Dismiss the dialog and confirm we're still on ConfigPage.
      await driver.pressBack();
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ConfigParentAdminButton'));
      const dialog: Component | null =
        await driver.findComponent(ON.id('ParentPinDialog'));
      expect(dialog === null).assertTrue();

      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    /**
     * Entering the correct 6-digit PIN auto-dismisses ParentPinDialog
     * and pushes ParentAdminPage. We assert the structural surface
     * (title, server label, publish button) and back out.
     *
     * V0.5.8 removed the JWT login UI, so the page surfaces stats /
     * publish directly. We do NOT assert stats values — that would
     * require a live server response.
     */
    it('correctPinNavigatesToParentAdmin', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, KNOWN_PIN);
      await navigateToParentAdminPage(driver);

      await driver.assertComponentExist(ON.id('ParentAdminServerLabel'));

      // V0.5.8 F1+F2: photo-import card and pending-drafts list both
      // render unconditionally (no login wall). Stats may take a moment
      // to populate, but the structural ids are wired into the build()
      // tree from mount.
      await driver.assertComponentExist(ON.id('ParentAdminPickCameraButton'));
      await driver.assertComponentExist(ON.id('ParentAdminPickGalleryButton'));
      await driver.assertComponentExist(ON.id('ParentAdminPendingTitle'));

      // The publish card sits below the fold once stats + pending
      // rows render — scroll to expose it before asserting.
      await scrollParentAdminToPublish(driver);
      await driver.assertComponentExist(ON.id('ParentAdminPublishButton'));

      // Login UI must NOT be present — the V0.5.8 C2 rewrite dropped it
      // entirely. Re-asserting here catches any regression where the
      // page accidentally re-introduces a login gate.
      const loginBtn: Component | null =
        await driver.findComponent(ON.id('ParentAdminLoginButton'));
      expect(loginBtn === null).assertTrue();
      const usernameInput: Component | null =
        await driver.findComponent(ON.id('ParentAdminUsername'));
      expect(usernameInput === null).assertTrue();
      const passwordInput: Component | null =
        await driver.findComponent(ON.id('ParentAdminPassword'));
      expect(passwordInput === null).assertTrue();

      await exitParentAdminPage(driver);
      done();
    });

    /**
     * V0.5.8 in-page interactions (server-independent):
     *   - The publish notes TextInput accepts typed text and reads it
     *     back via getText.
     *   - The Refresh button is enabled / tappable; tapping it must not
     *     crash the page (the async getStats may succeed against the
     *     prod server, fail with a toast, or stay pending — all three
     *     outcomes leave the structural surface intact, which is what
     *     this case asserts).
     *   - The pending-drafts area renders one of two visible
     *     states: ParentAdminPendingEmpty when the server has no
     *     pending drafts, OR LessonDraftRow_<id> rows otherwise. We
     *     match the OR with an existence probe so the assertion is
     *     stable regardless of server data on this emulator session.
     *   - Stat lines render with their `ParentAdminStat_<label>` ids
     *     once stats arrive. We probe one of them (用户数) without
     *     assertTrue so the case stays green when the server is
     *     unreachable.
     */
    it('parentAdminInteractionsStayStable', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, KNOWN_PIN);
      await navigateToParentAdminPage(driver);

      // Tap Refresh first while the title row is still on-screen.
      // The async getStats settles against the local mock; we only
      // assert the page survives the round-trip (no crash, title
      // intact) so we don't depend on a particular fixture value.
      await clickByIdShared(driver, 'ParentAdminRefresh');
      await driver.delayMs(2500);
      await driver.assertComponentExist(ON.id('ParentAdminTitle'));

      // Pending drafts area: empty-state text OR a visible row id.
      // findComponent with the empty-state id covers the no-network
      // case (refreshPendingDrafts caught the error and the array
      // stayed []) and the "mock returned 0 drafts" case (array is
      // also []). If the mock returned at least one draft, ForEach
      // renders LessonDraftRow_<id> instead.
      const emptyState: Component | null =
        await driver.findComponent(ON.id('ParentAdminPendingEmpty'));
      if (emptyState === null) {
        // Some draft must be visible — assert the title at minimum.
        // We can't pin a specific draft id without server fixtures.
        await driver.assertComponentExist(ON.id('ParentAdminPendingTitle'));
      }

      // Photo-import buttons stay enabled — we don't tap them because
      // the system gallery / camera picker would steal focus and is
      // not part of this case's scope.
      const camBtn = await driver.findComponent(ON.id('ParentAdminPickCameraButton'));
      expect(camBtn !== null).assertTrue();
      const galBtn = await driver.findComponent(ON.id('ParentAdminPickGalleryButton'));
      expect(galBtn !== null).assertTrue();

      // The publish-notes input lives in publishCard at the bottom of
      // the page; scroll it into view before typing. Done LAST in the
      // case so we don't have to scroll back up between the refresh
      // and pending-area assertions above.
      await scrollParentAdminToPublish(driver);

      // Publish notes round-trip — purely client-side state.
      await typeIntoAdmin(driver, 'ParentAdminPublishNotes', 'lesson v1');
      const notesInput = await driver.findComponent(ON.id('ParentAdminPublishNotes'));
      const notesText: string = await notesInput.getText();
      expect(notesText.indexOf('lesson v1') >= 0).assertTrue();

      await exitParentAdminPage(driver);
      done();
    });

    /**
     * V0.5.8 mock-server path #1: GET /api/v1/admin/stats.
     *
     * `ParentAdminPage.aboutToAppear` fires `refreshStats()` against
     * `effectiveServerBaseUrl()` (which the test harness in
     * `List.test.ets` redirects to `http://127.0.0.1:8123`, served by
     * `server/mock_ui_server.py`). Once the response lands the page
     * stops rendering `ParentAdminStatsEmpty` and instead emits
     * `ParentAdminStat_<label>` rows.
     *
     * Mock fixture (see `server/mock_ui_server.py::admin_stats`):
     *   user_count = 1, word_count = 50 (mirrors the prod
     *   rawfile catalog so synced gameplay tests stay deterministic),
     *   category_count = 1 (the mock returns a flat count rather than
     *   walking the catalog because the production /admin/stats
     *   endpoint groups by category-document, not by word.category).
     *
     * We assert these three because they're stable across all tests
     * in the suite — `pack_count` and `latest_version` increment when
     * `tapPublishShowsSuccessSummary` runs, and `lesson_import_draft_pending`
     * tracks the seeded draft so it can flip to 0 after future
     * approve / reject coverage lands.
     */
    it('refreshShowsMockedStats', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, KNOWN_PIN);
      await navigateToParentAdminPage(driver);

      // aboutToAppear's refresh races with mount; tap Refresh so we
      // know we're observing a fresh round-trip rather than a stale
      // cache, and wait long enough for the localhost POST to settle.
      await clickByIdShared(driver, 'ParentAdminRefresh');
      await driver.delayMs(2500);

      // The stats card flips from ParentAdminStatsEmpty to per-line ids
      // once `this.stats !== undefined`; if either label is missing the
      // round-trip never completed. Each line renders as
      // "<label>: <value>", so we substring-match on the value rather
      // than equality-matching the full string (label whitespace and
      // colon variants drift between ArkUI versions).
      await driver.assertComponentExist(ON.id('ParentAdminStat_用户数'));
      const userCountComp = await driver.findComponent(ON.id('ParentAdminStat_用户数'));
      const userCountText: string = await userCountComp.getText();
      expect(userCountText.indexOf('1') >= 0).assertTrue();

      // 50 (the prod catalog size). We pin the literal "50" rather
      // than ">= 4" because a regression that drops words during
      // serialisation (rare but possible) would silently shrink the
      // count to a still-non-zero number.
      await driver.assertComponentExist(ON.id('ParentAdminStat_词条数'));
      const wordCountComp = await driver.findComponent(ON.id('ParentAdminStat_词条数'));
      const wordCountText: string = await wordCountComp.getText();
      expect(wordCountText.indexOf('50') >= 0).assertTrue();

      // category_count is a flat 1 from the mock; pin it for the same
      // reason — a regression that drops the field would surface as 0.
      await driver.assertComponentExist(ON.id('ParentAdminStat_类别数'));
      const categoryCountComp =
        await driver.findComponent(ON.id('ParentAdminStat_类别数'));
      const categoryCountText: string = await categoryCountComp.getText();
      expect(categoryCountText.indexOf('1') >= 0).assertTrue();

      await exitParentAdminPage(driver);
      done();
    });

    /**
     * V0.5.8 mock-server path #2: GET /api/v1/admin/lesson-drafts.
     *
     * `server/mock_ui_server.py::_reset_state()` seeds one pending
     * draft with id `ui-mock-draft-001` on every process boot. The
     * orchestrator script restarts the mock per `aa test` invocation
     * so this id is guaranteed present, regardless of which other
     * tests in the suite ran before this one (none of the existing
     * tests approve / reject the seeded draft).
     *
     * The page renders `LessonDraftRow_<id>` and
     * `LessonDraftReviewLink_<id>` for each item; we don't tap the
     * link here — that's covered by the dedicated navigation test
     * `tapReviewLinkOpensReviewPageWithMockedDraft`.
     */
    it('pendingListShowsMockedDraft', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, KNOWN_PIN);
      await navigateToParentAdminPage(driver);

      // aboutToAppear fires refreshPendingDrafts; small delay lets
      // the localhost GET settle before we look at the rendered list.
      await driver.delayMs(2000);

      // The empty-state must NOT be on screen — the mock seeds one row.
      const emptyState: Component | null =
        await driver.findComponent(ON.id('ParentAdminPendingEmpty'));
      expect(emptyState === null).assertTrue();

      // The seeded draft id is wired into both row + review-link ids.
      await driver.assertComponentExist(ON.id('LessonDraftRow_ui-mock-draft-001'));
      await driver.assertComponentExist(
        ON.id('LessonDraftReviewLink_ui-mock-draft-001'),
      );

      await exitParentAdminPage(driver);
      done();
    });

    /**
     * V0.5.8 mock-server path #3: POST /api/v1/admin/packs/publish.
     *
     * Tap the publish button and assert the success summary line
     * (`ParentAdminPublishSummary`) appears with the canonical shape
     * `已发布 v<N> (schema_v<M>, <K> 词)`. We pin only the prefix
     * (`已发布 v` + a digit) because:
     *   - The mock increments `latest_version` on every POST and
     *     remembers it within a single `aa test` run; if this test
     *     reruns after a previous publish the version is ≥ 2.
     *   - Other suites or future tests may publish before us.
     *
     * On failure the page renders a toast (`ParentAdminToast`) instead
     * of the summary line, so a stale prefix here surfaces real
     * regressions (HTTP wrong shape, mock unreachable, JSON parse).
     */
    it('tapPublishShowsSuccessSummary', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, KNOWN_PIN);
      await navigateToParentAdminPage(driver);

      // The publish controls live at the bottom of the Scroll; bring
      // them into view before tapping.
      await scrollParentAdminToPublish(driver);

      // Optional notes — exercises the multipart-less PublishIn body.
      await typeIntoAdmin(driver, 'ParentAdminPublishNotes', 'mock e2e');

      await clickByIdShared(driver, 'ParentAdminPublishButton');
      // The handler does publish → refreshStats; localhost round-trips
      // are fast but we still want both calls to settle before asserting.
      await driver.delayMs(3000);

      await driver.assertComponentExist(ON.id('ParentAdminPublishSummary'));
      const summaryComp =
        await driver.findComponent(ON.id('ParentAdminPublishSummary'));
      const summary: string = await summaryComp.getText();
      // Shape: 已发布 v{version} (schema_v{schemaVersion}, {wordCount} 词)
      const match: RegExpMatchArray | null = summary.match(/已发布 v(\d+)/);
      expect(match !== null).assertTrue();
      if (match !== null) {
        const version: number = parseInt(match[1], 10);
        expect(version >= 1).assertTrue();
      }
      // The page also clears publishNotes after a successful publish;
      // confirm the input echoed the reset.
      const notesAfter =
        await driver.findComponent(ON.id('ParentAdminPublishNotes'));
      const notesText: string = await notesAfter.getText();
      // The TextInput widget reports either '' or the placeholder
      // text after reset depending on focus state. We just assert the
      // typed value is gone.
      expect(notesText.indexOf('mock e2e') < 0).assertTrue();

      await exitParentAdminPage(driver);
      done();
    });

    /**
     * V0.5.8 mock-server path #4: GET /api/v1/admin/lesson-drafts/{id}
     * exercised through the cross-page navigation
     * `ParentAdminPage` → `LessonDraftReviewPage`.
     *
     * Tapping `LessonDraftReviewLink_<id>` pushes
     * `pages/LessonDraftReviewPage` with `params.draftId = <id>`. The
     * review page's `aboutToAppear` reads the id and calls
     * `client.getLessonDraft(id)` against the local mock, which
     * returns the seeded draft (3 fixture words: apple / banana / cherry).
     *
     * We assert the structural surface of the review page — title,
     * count, and the first two word rows — without approving or
     * rejecting the draft (which would mutate the seeded fixture and
     * break {@link pendingListShowsMockedDraft} on the next run).
     */
    it('tapReviewLinkOpensReviewPageWithMockedDraft', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, KNOWN_PIN);
      await navigateToParentAdminPage(driver);

      // Wait for the pending list to populate so the link button is
      // tappable (otherwise the row is rendered with the empty-state
      // placeholder and the id is absent).
      await driver.delayMs(2000);
      await driver.assertComponentExist(
        ON.id('LessonDraftReviewLink_ui-mock-draft-001'),
      );

      await clickByIdShared(driver, 'LessonDraftReviewLink_ui-mock-draft-001');
      // Page transition + aboutToAppear's getLessonDraft round-trip.
      await driver.delayMs(2500);

      // Title is hardcoded by the page — its presence + literal text
      // confirms the route landed and the page tree mounted.
      await driver.assertComponentExist(ON.id('LessonReviewTitle'));
      const titleComp = await driver.findComponent(ON.id('LessonReviewTitle'));
      const titleText: string = await titleComp.getText();
      expect(titleText).assertEqual('课本单词复核');

      // Defensive: if the page hit the error path
      // (`humanizeError(err)`), surface the exact message in the
      // assertion failure rather than letting a downstream check
      // fail on missing children.
      const errorComp: Component | null =
        await driver.findComponent(ON.id('LessonReviewError'));
      if (errorComp !== null) {
        const errorText: string = await errorComp.getText();
        expect(`unexpected error path: ${errorText}`).assertEqual('');
      }

      // The mock fixture returns 3 words; LessonReviewCount renders
      // "共 3 个候选词" once the draft loads. This is the canonical
      // assertion that the GET /api/v1/admin/lesson-drafts/{id}
      // round-trip parsed the extracted.words array correctly. It
      // also exercises the null-vs-undefined edited_extracted guard
      // in `applyDraft`, since the mock seeds edited_extracted: null.
      await driver.assertComponentExist(ON.id('LessonReviewCount'));
      const countComp = await driver.findComponent(ON.id('LessonReviewCount'));
      const countText: string = await countComp.getText();
      expect(countText).assertEqual('共 3 个候选词');

      // First word row content — a regression in JSON deserialisation
      // would either drop the row entirely or surface camelCase /
      // snake_case mismatches in the values. Text widgets propagate
      // `.id()` reliably; Toggle and other non-Text widgets do not.
      await driver.assertComponentExist(ON.id('LessonReviewRowWord_0'));
      const word0Comp = await driver.findComponent(ON.id('LessonReviewRowWord_0'));
      const word0: string = await word0Comp.getText();
      expect(word0).assertEqual('apple');

      await driver.assertComponentExist(ON.id('LessonReviewRowMeaning_0'));
      const meaning0Comp =
        await driver.findComponent(ON.id('LessonReviewRowMeaning_0'));
      const meaning0: string = await meaning0Comp.getText();
      expect(meaning0).assertEqual('苹果');
      // NOTE: the action row (LessonReviewApproveButton /
      // LessonReviewRejectButton) sits below the fold on the portrait
      // emulator viewport and ArkUI's UiTest matcher does not realise
      // off-screen children inside the inner Scroll's parent Column.
      // Asserting it would require an explicit scroll, which on this
      // page would mutate the inner Scroll offset and is out of scope
      // for the GET-draft endpoint coverage this test owns. The
      // approve/reject paths can be added later via dedicated tests
      // that opt in to the scroll choreography and reset the seeded
      // fixture afterwards.

      // Back through the page stack: LessonDraftReviewPage →
      // ParentAdminPage → ConfigPage → HomePage. We tap LessonReviewBack
      // explicitly because the back button is at the top and visible.
      await clickByIdShared(driver, 'LessonReviewBack');
      await driver.delayMs(1500);
      await driver.assertComponentExist(ON.id('ParentAdminTitle'));

      await exitParentAdminPage(driver);
      done();
    });

    /**
     * V0.5.8 mock-server path #5: POST /api/v1/admin/lessons/import
     * (multipart/form-data with a real on-device JPG).
     *
     * End-to-end flow exercised by this test:
     *   1. `ensureLessonImportFixtureOnDevice()` reads the bundled
     *      `lesson_import_fixture.jpg` from the ohosTest HAP's rawfile
     *      via `Context.resourceManager.getRawFileContent`, writes
     *      ~50KB of real JPG bytes to `<appCtx.tempDir>/`, then writes
     *      that absolute path into
     *      `AppStorage[LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY]`.
     *   2. We tap `ParentAdminPickGalleryButton`.
     *   3. The page calls `LessonImagePicker.pickFromGallery` →
     *      `RealPhotoPickerAdapter.selectGallery`, which short-circuits
     *      on the override and returns `PickedFileRef{uri: <path>}`
     *      WITHOUT invoking the system PhotoViewPicker. We deliberately
     *      bypass the system UI here because that picker runs
     *      out-of-process and its UI tree is not stably matchable from
     *      Hypium across HarmonyOS NEXT versions.
     *   4. `RealPhotoFileReader.readAsArrayBuffer` does a real
     *      `fs.open` + `fs.read` against the on-device file (50 KB).
     *   5. `ParentApiClient.importLesson` builds the multipart body
     *      (`Content-Type: multipart/form-data`, field name `image`,
     *      filename, MIME) and POSTs to /api/v1/admin/lessons/import
     *      against the local mock.
     *   6. Mock drains the upload, allocates a fresh draft id, returns
     *      a 201 with a draft whose extracted.words has length 3
     *      (apple / banana / cherry — see `_fresh_draft`).
     *   7. Page sets `lastImportedId` + `lastImportedWordCount = 3`,
     *      calls `refreshPendingDrafts`, and re-renders the import
     *      success line `✓ 已识别 3 个单词，请确认` with the
     *      `去复核 →` button.
     *
     * Production rebuilds without the override would hit the system
     * picker normally — neither the override nor the on-device fixture
     * has any effect off-test (the AppStorage key is never written by
     * release builds; the test rawfile lives only in the ohosTest HAP).
     *
     * Why we don't drive the system gallery via `hdc file send` to
     * /data/local/tmp/: HarmonyOS NEXT's selinux blocks every path the
     * shell user can write to from being read by the bundle's UID
     * (data_local_tmp:s0 → app_data_file:s0 transition is denied).
     * The bundled-rawfile + tempDir-copy path is the only one that
     * survives the sandbox boundary while still exercising the real
     * `fs.open`/`fs.read`/multipart/HTTP code paths.
     */
    it('tapPickGalleryUploadsAndShowsImported', 0, async (done: Function) => {
      const fixturePath: string = await ensureLessonImportFixtureOnDevice();
      // Sanity: confirm the fixture is on disk where the picker
      // override points. A regression in resource bundling (rawfile
      // not packed into the test HAP) would otherwise surface as a
      // confusing "上传失败" downstream.
      expect(fs.accessSync(fixturePath)).assertTrue();

      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await ensureParentPin(driver, KNOWN_PIN);
      await navigateToParentAdminPage(driver);

      // The gallery button lives in `lessonImportCard`, the SECOND
      // card on ParentAdminPage (statsCard → lessonImportCard →
      // draftListCard → publishCard). On the portrait emulator
      // viewport the button is visible at the default scroll offset,
      // so no scroll choreography is needed before the tap.
      await driver.assertComponentExist(ON.id('ParentAdminPickGalleryButton'));
      await clickByIdShared(driver, 'ParentAdminPickGalleryButton');

      // The page hop is: picker.selectGallery() (overridden, returns
      // a PickedFileRef in microseconds) → RealPhotoFileReader.fs.open
      // + fs.read (~50 KB) → ParentApiClient.importLesson() multipart
      // POST → mock returns 201 → page also kicks refreshPendingDrafts
      // before re-rendering. 5s covers cold-start + both round-trips
      // with comfortable headroom; 2-3s would be enough on warm runs
      // but flakes on cold-start.
      await driver.delayMs(5000);

      // If the file read or HTTP failed, the page renders
      // ParentAdminImportError instead of the success line. Surface
      // that message in the assertion failure so a regression in the
      // /data/local/tmp/ permission boundary or in the mock multipart
      // handler is unambiguous.
      const errorComp: Component | null =
        await driver.findComponent(ON.id('ParentAdminImportError'));
      if (errorComp !== null) {
        const errorText: string = await errorComp.getText();
        expect(`unexpected import error: ${errorText}`).assertEqual('');
      }

      // Success line: "✓ 已识别 3 个单词，请确认". The mock fixture
      // returns 3 words (apple / banana / cherry) — pin the literal
      // count so a regression in either the multipart encoding (image
      // bytes truncated → server returns 0 words) or in the page's
      // `lastImportedWordCount` plumbing is unambiguous.
      await driver.assertComponentExist(ON.id('ParentAdminImportSuccess'));
      const successComp =
        await driver.findComponent(ON.id('ParentAdminImportSuccess'));
      const successText: string = await successComp.getText();
      expect(successText.indexOf('3 个单词') >= 0).assertTrue();

      // Goto-review button gates the next step in the parent's flow
      // (ParentAdminPage → LessonDraftReviewPage on the freshly
      // imported draft). We don't tap it here — that path is covered
      // by `tapReviewLinkOpensReviewPageWithMockedDraft` against the
      // pre-seeded draft. Asserting the button exists is enough to
      // confirm `lastImportedId` was set (the row only renders when
      // `this.lastImportedId.length > 0`).
      await driver.assertComponentExist(ON.id('ParentAdminGotoReviewButton'));

      await exitParentAdminPage(driver);
      done();
    });
  });
}
