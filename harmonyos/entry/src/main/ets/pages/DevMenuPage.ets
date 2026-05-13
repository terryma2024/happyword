import http from '@ohos.net.http';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  BackendEnv,
  appendAuditLog,
  AuditRow,
  initBackendEnvPrefs,
  loadBackendEnv,
  loadBypassSecret,
  loadDebugSessionId,
  loadPreviewUrl,
  metaFor,
  saveBackendEnv,
  saveBypassSecret,
  saveDebugSessionId,
  savePreviewUrl,
} from '../services/BackendEnv';
import {
  buildVercelBypassHeader,
} from '../services/BackendHeaders';
import {
  fetchManifest,
  getCached,
  ManifestRow,
  PreviewManifest,
} from '../services/PreviewManifestService';
import { resetForEnvSwitch } from '../services/SessionResetService';
import { effectiveServerBaseUrl } from '../services/RemoteWordPackConfig';
import BuildProfile from 'BuildProfile';
import { BypassSecretDialog } from '../components/BypassSecretDialog';

/**
 * Route params bag for `pages/DevMenuPage`. Mirrors the class
 * declaration in HomePage.ets — ArkTS strict mode rejects inline
 * object literals (arkts-no-untyped-obj-literals), so callers and
 * consumers each declare the same shape and pass / cast a typed
 * instance. Same pattern as LessonReviewRouteParams elsewhere.
 */
class DevMenuRouteParams {
  presetEnv: string = '';
}

/**
 * V0.6.1 unified card model. One card per pickable backend
 * environment (Local, Staging, plus one per manifest preview). The
 * @Builder reads from a flat list of CardProps so the same builder
 * renders every card type — title is bold up to 3 lines (preview
 * titles can be long; "Local" / "Staging" are 1 line), and footer is
 * a single centred line (preview short-sha or env URL).
 *
 * `previewUrl` is empty for Local / Staging cards. Card taps route
 * through DevMenuPage.onCardTap which derives the actual url from
 * `metaFor(env).defaultUrl` for Local / Staging and from this field
 * for Preview cards. Carrying `previewUrl` on the props lets the
 * highlight ring be a pure function of (env, previewUrl, currentEnv,
 * currentPreviewUrl) without re-reading the manifest from inside the
 * builder.
 */
class CardProps {
  id: string = '';
  title: string = '';
  footer: string = '';
  env: BackendEnv = BackendEnv.STAGING;
  previewUrl: string = '';
  highlighted: boolean = false;
}

/**
 * Outcome bag for `probeHealth`. The boolean drives the apply-or-block
 * gate; the message is a human-readable line that the dev menu pins
 * at the bottom of the page so the user can see the exact URL hit
 * and the HTTP code (or transport error) that came back. Helps
 * disambiguate "URL is wrong" from "deployment is auth-gated"
 * (Vercel preview protection returns 401, which we surface verbatim).
 */
class ProbeResult {
  ok: boolean = false;
  message: string = '';
}

@Entry
@Component
struct DevMenuPage {
  @State private currentEnv: BackendEnv = BackendEnv.STAGING;
  @State private currentPreviewUrl: string = '';
  @State private manifest: PreviewManifest | null = null;
  @State private manifestBusy: boolean = false;
  @State private applying: boolean = false;
  // Last probe attempt — pinned at the bottom of the page so failed
  // probes show the exact URL + status code instead of just the
  // generic "Cannot reach" toast. Empty string = no probe attempted
  // this session, hide the line.
  @State private lastProbeStatus: string = '';
  // Cached Vercel "Protection Bypass for Automation" secret. Hydrated
  // from prefs in `aboutToAppear`; updated via `BypassSecretPage` or
  // first-time Preview flow (`BypassSecretDialog`). AppStorage is the
  // source of truth for outgoing HTTP calls (see BackendHeaders.ets).
  @State private bypassSecret: string = '';
  @State private debugSessionId: string = '';
  // Local handle to the current dialog — held so the closure-driven
  // close path (mirrors AddCustomWishDialog) works regardless of
  // whether the auto-bound controller field on the dialog struct
  // wires up correctly under customStyle: true.
  private bypassDialog: CustomDialogController | null = null;
  /** Debug-only footer on Developer Options — env / preview / bypass / API base. */
  @State private routingDebugText: string = '';

  private showToast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (err) {
      console.error(`DevMenuPage.showToast failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  aboutToAppear(): void {
    // V0.6 PREVIEW preset (from HomePage's triple-tap) is now a
    // no-op for the layout — the card grid already shows every env
    // including Preview entries — so we drop the old `presetEnv`
    // wiring. The route param itself is kept on the call site for
    // forward compatibility (writing-skills' graceful-removal
    // discipline) but no consumer reads it.
    this.hydrate().catch((err: BusinessError): void => {
      console.error(`DevMenuPage.hydrate failed: ${JSON.stringify(err)}`);
    });
  }

  onPageShow(): void {
    this.refreshRoutingDebugPanel();
  }

  /**
   * Developer Options bottom strip (debug builds): single line showing the
   * effective API base URL — the value every outgoing HTTP call resolves to.
   */
  private refreshRoutingDebugPanel(): void {
    if (BuildProfile.BUILD_MODE_NAME !== 'debug') {
      this.routingDebugText = '';
      return;
    }
    const dbg: string = this.debugSessionId.length > 0 ? ` debug=${this.debugSessionId}` : ' debug=off';
    this.routingDebugText = `API base: ${effectiveServerBaseUrl()}${dbg}`;
  }

  /**
   * Manifest rows and prefs sometimes differ by a trailing slash only.
   * Normalise so the active preview card highlights correctly.
   */
  private normalizeDeploymentUrl(url: string): string {
    let u: string = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  private async hydrate(): Promise<void> {
    try {
      const ctx: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      await initBackendEnvPrefs(ctx);
    } catch (err) {
      console.error(`DevMenuPage.initBackendEnvPrefs: ${JSON.stringify(err as BusinessError)}`);
    }
    this.manifest = getCached();
    this.currentEnv = await loadBackendEnv();
    this.currentPreviewUrl = await loadPreviewUrl();
    this.bypassSecret = await loadBypassSecret();
    this.debugSessionId = await loadDebugSessionId();
    this.refreshRoutingDebugPanel();
    this.refreshManifest(false).catch((err: BusinessError): void => {
      console.error(`DevMenuPage.refreshManifest: ${JSON.stringify(err)}`);
    });
  }

  private async refreshManifest(force: boolean): Promise<void> {
    this.manifestBusy = true;
    this.manifest = await fetchManifest(force);
    this.manifestBusy = false;
  }

  /**
   * Probe `<url>/api/v1/health` and return both the gating boolean
   * (HTTP 200) and a verbose status string for the on-screen debug
   * line. Timeout is 10s — first-hit TLS handshake to *.vercel.app from
   * the OpenHarmony emulator (cold DNS / cold TCP / cold edge) often
   * exceeds 5s; once the host has warmed the path, subsequent requests
   * complete in well under a second.
   *
   * The optional `bypassSecret` is folded into an
   * `x-vercel-protection-bypass` header when non-empty (mirrors the
   * server-side e2e driver in `server/tests/e2e/_utils/vercel.py`).
   * Without it, Vercel preview deployments return HTTP 401 + an HTML
   * SSO page; with it, the platform layer waves the request through
   * to the FastAPI function which returns 200.
   *
   * Note we pass the secret in directly rather than reading the
   * AppStorage mirror — the user's just-entered secret has not yet
   * been persisted at the moment this method is called from
   * `onCardTap`, so we can't rely on `vercelBypassHeader()`.
   */
  private async probeHealth(url: string, bypassSecret: string): Promise<ProbeResult> {
    const fullUrl: string = `${url}/api/v1/health`;
    const req: http.HttpRequest = http.createHttp();
    const out: ProbeResult = new ProbeResult();
    try {
      // Direct call to buildVercelBypassHeader (the pure helper) —
      // bypasses the AppStorage read because the secret may not yet
      // be persisted at this point in the flow.
      const headers: Record<string, string> = buildVercelBypassHeader(
        BackendEnv.PREVIEW,
        bypassSecret,
      );
      const resp: http.HttpResponse = await req.request(fullUrl, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 10000,
      });
      out.ok = resp.responseCode === 200;
      out.message = `${fullUrl} → HTTP ${resp.responseCode}`;
    } catch (err) {
      out.ok = false;
      const be: BusinessError = err as BusinessError;
      const reason: string = be.message !== undefined && be.message.length > 0
        ? be.message
        : JSON.stringify(err);
      out.message = `${fullUrl} → unreachable (${reason})`;
    } finally {
      req.destroy();
    }
    return out;
  }

  /**
   * V0.6.2 unified tap handler. Routes Preview cards through the
   * bypass-secret prompt (when no secret is yet stored) before
   * running the safety pipeline; Local / Staging / Prod skip the
   * prompt and the probe.
   *
   * Safety pipeline (Preview only): bypass-secret prompt (if needed)
   * → probeHealth with secret → resetForEnvSwitch → saveBackendEnv
   * → savePreviewUrl → saveBypassSecret → audit row → toast →
   * replaceUrl back to HomePage. Re-entrancy is guarded by
   * `applying`; while a tap is in flight every card is rendered
   * with `enabled(false)` so a second-finger double-tap can't fire
   * a parallel pipeline.
   */
  private onCardTap(env: BackendEnv, previewUrl: string): void {
    if (this.applying) {
      return;
    }
    if (env === BackendEnv.PREVIEW && this.bypassSecret.length === 0) {
      // Defer apply until the user enters the secret. Dialog's
      // onSubmit closure resumes the pipeline.
      this.openBypassDialog(previewUrl);
      return;
    }
    this.applyEnv(env, previewUrl, this.bypassSecret).catch((err: BusinessError): void => {
      console.error(`onCardTap.applyEnv failed: ${JSON.stringify(err)}`);
    });
  }

  /**
   * Open the bypass-secret prompt for the given preview URL. On
   * submit, persist the secret and resume the apply pipeline; on
   * cancel, leave state untouched (no env switch).
   */
  private openBypassDialog(previewUrl: string): void {
    let ctrl: CustomDialogController | null = null;
    ctrl = new CustomDialogController({
      builder: BypassSecretDialog({
        initialSecret: this.bypassSecret,
        onSubmit: (secret: string): void => {
          if (ctrl !== null) {
            ctrl.close();
          }
          this.bypassSecret = secret;
          this.applyEnv(BackendEnv.PREVIEW, previewUrl, secret).catch((err: BusinessError): void => {
            console.error(`openBypassDialog.applyEnv failed: ${JSON.stringify(err)}`);
          });
        },
        onCancel: (): void => {
          if (ctrl !== null) {
            ctrl.close();
          }
        },
      }),
      autoCancel: true,
      customStyle: true,
    });
    this.bypassDialog = ctrl;
    ctrl.open();
  }

  /**
   * Run the actual env-switch pipeline. Extracted from `onCardTap`
   * so the post-prompt resume path (after `BypassSecretDialog`
   * confirms) and the no-prompt path (Local / Staging / cached
   * Preview secret) share one code path.
   */
  private async applyEnv(
    env: BackendEnv,
    previewUrl: string,
    bypassSecret: string,
  ): Promise<void> {
    this.applying = true;
    try {
      let urlForAudit: string = previewUrl;
      if (env === BackendEnv.PREVIEW) {
        // Surface the URL we're about to probe BEFORE the request so
        // the user sees something even if the call hangs to timeout.
        this.lastProbeStatus = `Probing ${previewUrl}/api/v1/health…`;
        const result: ProbeResult = await this.probeHealth(previewUrl, bypassSecret);
        this.lastProbeStatus = result.message;
        if (!result.ok) {
          this.showToast('Cannot reach /api/v1/health — see status at bottom');
          return;
        }
      }
      const ctx: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      await resetForEnvSwitch(ctx);
      await saveBackendEnv(env);
      if (env === BackendEnv.PREVIEW) {
        await savePreviewUrl(previewUrl);
        // Persist the secret only after a successful 200 probe so a
        // mistyped secret never gets cached.
        await saveBypassSecret(bypassSecret);
      } else {
        await savePreviewUrl('');
        urlForAudit = '';
      }
      const row: AuditRow = {
        ts: Date.now(),
        from: this.currentEnv,
        to: env,
        preview_url: urlForAudit,
      };
      await appendAuditLog(row);
      this.currentEnv = env;
      this.currentPreviewUrl = env === BackendEnv.PREVIEW ? previewUrl : '';
      this.showToast('Environment updated. Re-bind parent account if needed.');
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/HomePage' }).catch((err: BusinessError): void => {
        console.error(`DevMenuPage.replaceUrl HomePage failed: ${JSON.stringify(err)}`);
      });
    } finally {
      this.applying = false;
    }
  }

  /**
   * Build the flat card list in display order: Local, Staging,
   * then one card per manifest preview. Recomputed every build()
   * pass — cheap enough (<10 cards typically) and keeps the
   * highlight ring reactive to `currentEnv` / `currentPreviewUrl`
   * without manual invalidation.
   */
  private cardList(): CardProps[] {
    const out: CardProps[] = [];

    const local: CardProps = new CardProps();
    local.id = 'DevMenuLocalCard';
    local.title = 'Local';
    local.footer = metaFor(BackendEnv.LOCAL).defaultUrl;
    local.env = BackendEnv.LOCAL;
    local.previewUrl = '';
    local.highlighted = this.currentEnv === BackendEnv.LOCAL;
    out.push(local);

    const staging: CardProps = new CardProps();
    staging.id = 'DevMenuStagingCard';
    staging.title = 'Staging';
    staging.footer = metaFor(BackendEnv.STAGING).defaultUrl;
    staging.env = BackendEnv.STAGING;
    staging.previewUrl = '';
    staging.highlighted = this.currentEnv === BackendEnv.STAGING;
    out.push(staging);

    if (this.manifest !== null) {
      // Hoist @State reads out of the loop body — codelinter
      // flags repeated `this.<state>` accesses inside a for/of as
      // a performance smell because every read ticks the ArkUI
      // observation counter even when the value is unchanged.
      const isPreviewActive: boolean = this.currentEnv === BackendEnv.PREVIEW;
      const activeNorm: string = this.normalizeDeploymentUrl(this.currentPreviewUrl);
      for (const row of this.manifest.previews) {
        const c: CardProps = new CardProps();
        c.id = `DevMenuPreviewCard_${row.pr}`;
        c.title = row.title;
        const sha: string = row.head_sha.length > 7
          ? row.head_sha.substring(0, 7)
          : row.head_sha;
        c.footer = `#${row.pr}(${sha})`;
        c.env = BackendEnv.PREVIEW;
        c.previewUrl = row.url;
        c.highlighted =
          isPreviewActive && activeNorm === this.normalizeDeploymentUrl(row.url);
        out.push(c);
      }
    }
    return out;
  }

  /**
   * Chunk the flat card list into pairs for the 2-column grid.
   * Trailing odd card pads with an empty CardProps marker (`id`
   * empty) so the row keeps symmetric `layoutWeight(1)` widths.
   * Builder recognises the empty marker and renders an empty
   * Column placeholder instead of a full card.
   */
  private cardPairs(): CardProps[][] {
    const flat: CardProps[] = this.cardList();
    const pairs: CardProps[][] = [];
    for (let i = 0; i < flat.length; i += 2) {
      const pair: CardProps[] = [flat[i]];
      if (i + 1 < flat.length) {
        pair.push(flat[i + 1]);
      } else {
        pair.push(new CardProps()); // empty placeholder
      }
      pairs.push(pair);
    }
    return pairs;
  }

  /**
   * Single card builder used for every entry in the grid. Empty
   * placeholders (`props.id === ''`) render a transparent
   * layoutWeight(1) Column so the trailing odd card keeps the row
   * symmetric without floating to the centre.
   */
  @Builder
  private card(props: CardProps): void {
    if (props.id.length === 0) {
      // Empty placeholder for an odd trailing card.
      Column()
        .layoutWeight(1)
        .height(96);
    } else {
      // Fixed-height card so 1-line and 2-line titles render the same row
      // size; title pinned to top, footer pinned to bottom via SpaceBetween.
      Column() {
        Text(props.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#222222')
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Row() {
          Text(props.footer)
            .fontSize(13)
            .fontColor('#555555')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%')
        .justifyContent(FlexAlign.Center);
      }
      .id(props.id)
      .layoutWeight(1)
      .height(96)
      .padding(12)
      .justifyContent(FlexAlign.SpaceBetween)
      .borderRadius(12)
      .backgroundColor(props.highlighted ? '#CDE8FF' : '#F5F5F5')
      .border({
        width: 1,
        color: props.highlighted ? '#457B9D' : '#E0E0E0',
      })
      .enabled(!this.applying)
      .opacity(this.applying ? 0.6 : 1.0)
      .onClick((): void => {
        this.onCardTap(props.env, props.previewUrl);
      });
    }
  }

  build(): void {
    Scroll() {
      Column() {
        // Header row: Back (left) — title — Refresh (right). The
        // Refresh button used to live below the manifest list with
        // a "X previews" sibling label; pinning it top-right keeps
        // the action a finger-tap away regardless of how far the
        // user scrolled the card grid.
        Row() {
          Button('Back')
            .fontSize(14)
            .height(36)
            .onClick((): void => {
              this.getUIContext().getRouter().back();
            });
          Text('Developer Options')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .margin({ left: 16 });
          Blank();
          Button('Bypass Secret')
            .id('DevMenuBypassSecretButton')
            .fontSize(13)
            .height(36)
            .margin({ right: 10 })
            .enabled(!this.applying)
            .onClick((): void => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/BypassSecretPage' }).catch((err: BusinessError): void => {
                console.error(`DevMenuPage.pushUrl BypassSecretPage failed: ${JSON.stringify(err)}`);
              });
            });
          Button(this.manifestBusy ? 'Refreshing...' : 'Refresh Manifest')
            .id('DevMenuRefreshManifestButton')
            .fontSize(13)
            .height(36)
            .enabled(!this.manifestBusy && !this.applying)
            .onClick((): void => {
              this.refreshManifest(true).catch((err: BusinessError): void => {
                console.error(`refreshManifest: ${JSON.stringify(err)}`);
              });
            });
        }
        .width('100%')
        .margin({ bottom: 16 });

        Text('Backend environment (debug builds only)')
          .fontSize(14)
          .fontColor('#666666')
          .margin({ bottom: 12 });

        Text('Debug session')
          .fontSize(12)
          .fontColor('#666666')
          .margin({ bottom: 6 });
        Row({ space: 8 }) {
          TextInput({ placeholder: 'dbg_...', text: this.debugSessionId })
            .id('DevMenuDebugSessionInput')
            .fontSize(12)
            .layoutWeight(1)
            .onChange((value: string): void => {
              this.debugSessionId = value.trim();
            });
          Button('Save')
            .id('DevMenuDebugSessionSaveButton')
            .fontSize(12)
            .height(34)
            .enabled(!this.applying)
            .onClick((): void => {
              saveDebugSessionId(this.debugSessionId).then((): void => {
                this.showToast(this.debugSessionId.length > 0 ? 'Debug session enabled' : 'Debug session cleared');
                this.refreshRoutingDebugPanel();
              }).catch((err: BusinessError): void => {
                console.error(`DevMenuPage.saveDebugSessionId failed: ${JSON.stringify(err)}`);
              });
            });
          Button('Clear')
            .id('DevMenuDebugSessionClearButton')
            .fontSize(12)
            .height(34)
            .enabled(!this.applying)
            .onClick((): void => {
              this.debugSessionId = '';
              saveDebugSessionId('').then((): void => {
                this.showToast('Debug session cleared');
                this.refreshRoutingDebugPanel();
              }).catch((err: BusinessError): void => {
                console.error(`DevMenuPage.clearDebugSessionId failed: ${JSON.stringify(err)}`);
              });
            });
        }
        .width('100%')
        .margin({ bottom: 14 });

        // 2-column card grid. Each row is two cards side-by-side
        // with `layoutWeight(1)` so they share the available width
        // evenly. The `space: 12` on the outer Column gives breathing
        // room between rows; per-card padding(12) handles inset.
        Column({ space: 12 }) {
          ForEach(this.cardPairs(), (pair: CardProps[]) => {
            Row({ space: 12 }) {
              this.card(pair[0]);
              this.card(pair[1]);
            }
            .width('100%')
            .alignItems(VerticalAlign.Top);
          }, (pair: CardProps[], idx: number) => {
            // Include `highlighted` in the key: when the active env / preview
            // URL flips, the keys change and ArkUI tears down + recreates
            // the affected card nodes so the new background colour and ring
            // are applied (otherwise ForEach reuses the existing node and
            // leaves stale paint).
            const a: CardProps = pair[0];
            const b: CardProps = pair[1];
            return `pair-${idx}-${a.id}-${a.highlighted ? '1' : '0'}-${b.id}-${b.highlighted ? '1' : '0'}`;
          });
        }
        .width('100%')
        .margin({ bottom: 16 });

        if (this.manifest === null) {
          Text(this.manifestBusy ? 'Loading manifest...' : 'No manifest available')
            .fontSize(12)
            .fontColor('#888888')
            .margin({ bottom: 16 });
        } else if (this.manifest.previews.length === 0) {
          Text('No preview deployments in manifest')
            .fontSize(12)
            .fontColor('#888888')
            .margin({ bottom: 16 });
        }

        if (this.lastProbeStatus.length > 0) {
          // Pinned debug line — shows the most recent /api/v1/health
          // probe URL + outcome. Stays visible even after a failed
          // tap so the user can verify which URL was hit (Vercel
          // preview deployments often return 401, which the toast
          // alone does not disambiguate from a typo'd URL).
          Text('Last health probe')
            .fontSize(12)
            .fontColor('#666666')
            .margin({ top: 16, bottom: 4 });
          Text(this.lastProbeStatus)
            .id('DevMenuLastProbeStatus')
            .fontSize(11)
            .fontColor('#444444')
            .width('100%');
        }

        if (BuildProfile.BUILD_MODE_NAME === 'debug' && this.routingDebugText.length > 0) {
          Text(this.routingDebugText)
            .id('DevMenuRoutingDebug')
            .fontSize(11)
            .fontColor('#888888')
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 16 });
        }
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .backgroundColor('#FFFFFF')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
  }
}
