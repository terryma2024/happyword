import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { clickByIdShared } from './RoutingFlow.ui.test';

/**
 * V0.5 client follow-up (VC0.5.B) acceptance for the manual word-
 * pack sync entry on ConfigPage.
 *
 * The four cases here drive the real production
 * `https://happyword.vercel.app/api/v1/packs/latest.json` endpoint
 * (the build is wired to PROD by default — see
 * RemoteWordPackConfig.ets) so they double as a smoke test for the
 * server side. They REQUIRE a valid pack to be published —
 * server-side `seed_from_rawfile.py` + `publish_pack.py` need to
 * have run at least once with ≥ MIN_WORDS_PER_PACK words. If
 * production is missing or holds a sub-3-word pack the cases here
 * will fail loudly with the post-sync assertion (status text must
 * start with the success prefix).
 *
 * Coverage:
 *   1. syncRowIsRendered — surface present, status non-empty.
 *   2. tapSyncCachesPackAndShowsSuccessToast — strict: toast must
 *      report 已同步至 / 已是最新; status must start with
 *      "已缓存 schema v"; cached schemaVersion ≥ 1.
 *   3. cachedStatusPersistsAcrossPageReentry — leaving and re-
 *      entering ConfigPage still shows the cached schema info
 *      (proves the cache write survives `aboutToAppear` reload).
 *   4. secondConsecutiveSyncIsIdempotent — back-to-back taps both
 *      succeed; the second toast still reports success (production
 *      currently does not advertise an ETag, so the wire result is
 *      Updated each time, which the assertion accepts).
 */

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

/** Status-text shape after any successful sync (Updated or UpToDate). */
const CACHED_STATUS_PREFIX: string = '已缓存 schema v';
/** Status-text shape before any sync ever ran on this install. */
const UNSYNCED_STATUS_PREFIX: string = '尚未同步';

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

/**
 * Open ConfigPage and scroll the sync/admin row pair into view. The
 * narrow landscape emulator viewport is shorter than the form once
 * we appended ConfigSync* + ConfigParentAdminButton, so a single
 * swipe-up is required before any of the new V0.5 ids resolve.
 */
async function openConfigAndScrollToSync(driver: Driver): Promise<void> {
  await clickByIdShared(driver, 'HomeConfigButton');
  await driver.delayMs(1500);
  await driver.assertComponentExist(ON.id('ConfigTitle'));
  await driver.swipe(1400, 1100, 1400, 300, 600);
  await driver.delayMs(400);
}

/**
 * Wait up to `maxMs` for ConfigSyncToast to appear, polling at
 * 250 ms. The sync round-trip against the production server
 * typically lands within 1.5–4 s on a warm emulator + CDN, but a
 * cold Vercel function can extend that to 8 s; pick a 20 s ceiling
 * so we don't flake on CDN cold-start. Returns the toast text (or
 * empty string when the toast never appeared, which the caller
 * must treat as a failure).
 */
async function waitForSyncToast(driver: Driver, maxMs: number): Promise<string> {
  const stepMs: number = 250;
  let waited: number = 0;
  while (waited < maxMs) {
    const toast: Component | null =
      await driver.findComponent(ON.id('ConfigSyncToast'));
    if (toast !== null) {
      return await toast.getText();
    }
    await driver.delayMs(stepMs);
    waited += stepMs;
  }
  return '';
}

/**
 * Wait up to `maxMs` for `ConfigSyncStatus` to flip to the
 * "已缓存 schema v…" prefix, polling at 250 ms. Useful in the
 * persistence test where we re-enter the page and want to skip past
 * the brief unsynced flash that `aboutToAppear` may show before the
 * `WordPackCache.init` Promise resolves.
 */
async function waitForCachedStatus(driver: Driver, maxMs: number): Promise<string> {
  const stepMs: number = 250;
  let waited: number = 0;
  while (waited < maxMs) {
    const comp: Component | null =
      await driver.findComponent(ON.id('ConfigSyncStatus'));
    if (comp !== null) {
      const text: string = await comp.getText();
      if (text.indexOf(CACHED_STATUS_PREFIX) >= 0) {
        return text;
      }
    }
    await driver.delayMs(stepMs);
    waited += stepMs;
  }
  return '';
}

/**
 * Tap the sync button and assert the resulting toast reports a
 * successful pull (Updated or UpToDate). Throws via expect() on
 * any failure-shape toast so callers get a loud signal that
 * production state regressed (e.g. fewer than MIN_WORDS_PER_PACK
 * words in the pack).
 *
 * Retry: the very first sync of an app session triggers a Vercel
 * function cold start. If the cold-start latency exceeds
 * REMOTE_FETCH_TIMEOUT_MS (8 s in production builds) the client
 * returns status=0 → toast "同步失败 (网络错误)". A single retry
 * after a 5 s breather is enough to land on the now-warm function
 * without masking real production regressions (the second attempt
 * still hits the strict success assertion below).
 */
async function tapSyncAndAssertSuccess(driver: Driver): Promise<string> {
  const maxAttempts: number = 2;
  let lastToast: string = '';
  for (let attempt: number = 0; attempt < maxAttempts; attempt++) {
    await clickByIdShared(driver, 'ConfigSyncButton');
    const toast: string = await waitForSyncToast(driver, 20000);
    expect(toast.length > 0).assertTrue();
    const isSuccess: boolean =
      toast.indexOf('已同步至') >= 0 || toast.indexOf('已是最新') >= 0;
    if (isSuccess) {
      return toast;
    }
    lastToast = toast;
    // Wait out the in-page 2.4 s toast TTL plus a 2.6 s breather so
    // (a) the failure toast disappears before we tap again, and
    // (b) Vercel has time to finish warming the cold instance.
    await driver.delayMs(5000);
  }
  // Both attempts failed — assert against the last toast so the
  // diagnostic stream points at the real production regression
  // (e.g. RejectedTooSmall, HttpError) rather than a silent timeout.
  const isSuccess: boolean =
    lastToast.indexOf('已同步至') >= 0 || lastToast.indexOf('已是最新') >= 0;
  expect(isSuccess).assertTrue();
  return lastToast;
}

export default function configSyncFlowUiTest(): void {
  describe('ConfigSyncFlowV050B', () => {
    /**
     * The sync row is rendered under ConfigPage with both the button
     * (`ConfigSyncButton`) and the status text (`ConfigSyncStatus`).
     * The status text is non-empty even before any sync — it shows
     * either the unsynced or cached prefix on render, so we accept
     * either shape here.
     */
    it('syncRowIsRendered', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfigAndScrollToSync(driver);

      await driver.assertComponentExist(ON.id('ConfigSyncButton'));
      await driver.assertComponentExist(ON.id('ConfigSyncStatus'));

      const statusComp = await driver.findComponent(ON.id('ConfigSyncStatus'));
      const status: string = await statusComp.getText();
      expect(status.length > 0).assertTrue();
      const looksValid: boolean =
        status.indexOf(UNSYNCED_STATUS_PREFIX) >= 0 ||
        status.indexOf(CACHED_STATUS_PREFIX) >= 0;
      expect(looksValid).assertTrue();

      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    /**
     * Real round-trip against the production endpoint MUST succeed:
     *  - Toast contains 已同步至 (Updated) or 已是最新 (UpToDate).
     *  - Status flips to "已缓存 schema vN · 同步时间 …".
     *  - Parsed schemaVersion is ≥ 1.
     *
     * Failure modes that intentionally fail the test (rather than
     * being silently tolerated):
     *  - 同步失败 (HTTP …) — server unreachable / 4xx / 5xx.
     *  - 同步失败 (服务端词包过小) — pack has < MIN_WORDS_PER_PACK
     *    words. Run server-side `publish_pack.py` to refresh prod.
     *  - 同步失败 (网络错误) — emulator's host loopback is broken.
     */
    it('tapSyncCachesPackAndShowsSuccessToast', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfigAndScrollToSync(driver);

      await tapSyncAndAssertSuccess(driver);

      // Status text must reflect the cached pack now. The exact
      // schema version depends on what server-side publishing wrote,
      // but the prefix is stable.
      const statusComp = await driver.findComponent(ON.id('ConfigSyncStatus'));
      const status: string = await statusComp.getText();
      expect(status.indexOf(CACHED_STATUS_PREFIX) >= 0).assertTrue();

      // Parse the schema version digit out of the status line and
      // assert it is ≥ 1 (no negative / zero schemas can be
      // round-tripped through this surface).
      const match: RegExpMatchArray | null = status.match(/v(\d+)/);
      expect(match !== null).assertTrue();
      if (match !== null) {
        const schemaVersion: number = parseInt(match[1], 10);
        expect(schemaVersion >= 1).assertTrue();
      }

      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    /**
     * Cache survives leaving ConfigPage and re-entering it. The
     * assertion proves that the JSON envelope written by
     * WordPackSyncService.writeRecord() is read back by
     * WordPackCache.init() on the next `aboutToAppear`, NOT just
     * held in component @State.
     *
     * Sequence:
     *   1. Land on ConfigPage with sync row in view.
     *   2. Sync once, expect success.
     *   3. Cancel back to Home.
     *   4. Re-enter ConfigPage, scroll back to the sync row.
     *   5. Wait up to 5 s for the status text to flip to the
     *      cached-prefix (the cache read is async).
     */
    it('cachedStatusPersistsAcrossPageReentry', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);

      await openConfigAndScrollToSync(driver);
      await tapSyncAndAssertSuccess(driver);

      // Leave and re-enter — the cancel button on the bottom row
      // remains in view because the Scroll position from the swipe
      // above is preserved.
      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      await openConfigAndScrollToSync(driver);
      // The cache read is async; status may briefly show the
      // unsynced prefix on the very first paint before
      // WordPackCache.init resolves. Poll up to 5 s.
      const cached: string = await waitForCachedStatus(driver, 5000);
      expect(cached.length > 0).assertTrue();
      expect(cached.indexOf(CACHED_STATUS_PREFIX) >= 0).assertTrue();

      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });

    /**
     * Two consecutive syncs both succeed. Production currently does
     * NOT emit an `etag` response header (verified via curl -I on
     * `/api/v1/packs/latest.json`), so WordPackSyncService skips the
     * `If-None-Match` short-circuit and re-writes the cache on each
     * tap — the Updated branch fires both times. The assertion only
     * pins on the success-shape so that if production starts honouring
     * etags later (returning 304 → toast 已是最新), the case still
     * passes.
     *
     * Both calls re-use the same syncToast slot; the helper waits
     * for the toast to appear, then before the second tap we wait
     * out the toast TTL (~2.4 s in ConfigPage) so the first toast
     * is gone and the second one's appearance is unambiguous.
     */
    it('secondConsecutiveSyncIsIdempotent', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openConfigAndScrollToSync(driver);

      const firstToast: string = await tapSyncAndAssertSuccess(driver);
      expect(firstToast.length > 0).assertTrue();

      // Wait out the in-page 2.4 s toast TTL so the second toast we
      // observe is genuinely the result of the second tap. Add a
      // small margin.
      await driver.delayMs(3000);

      const secondToast: string = await tapSyncAndAssertSuccess(driver);
      expect(secondToast.length > 0).assertTrue();

      // After two successful syncs the status row must still be in
      // the cached shape (the cache record must not be wiped by an
      // idempotent re-sync).
      const statusComp = await driver.findComponent(ON.id('ConfigSyncStatus'));
      const status: string = await statusComp.getText();
      expect(status.indexOf(CACHED_STATUS_PREFIX) >= 0).assertTrue();

      await clickByIdShared(driver, 'ConfigCancelButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      done();
    });
  });
}
