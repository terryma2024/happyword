import { router } from '@kit.ArkUI';
import http from '@ohos.net.http';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  BackendEnv,
  appendAuditLog,
  AuditRow,
  loadAuditLog,
  loadBackendEnv,
  loadPreviewUrl,
  metaFor,
  saveBackendEnv,
  savePreviewUrl,
} from '../services/BackendEnv';
import {
  fetchManifest,
  getCached,
  ManifestRow,
  PreviewManifest,
} from '../services/PreviewManifestService';
import { resetForEnvSwitch } from '../services/SessionResetService';
import { STAGING_BASE_URL } from '../services/RemoteWordPackConfig';

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

@Entry
@Component
struct DevMenuPage {
  @State private currentEnv: BackendEnv = BackendEnv.STAGING;
  @State private currentPreviewUrl: string = '';
  @State private manifest: PreviewManifest | null = null;
  @State private manifestBusy: boolean = false;
  @State private applying: boolean = false;
  @State private auditLines: string[] = [];

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

  private async hydrate(): Promise<void> {
    this.manifest = getCached();
    this.currentEnv = await loadBackendEnv();
    this.currentPreviewUrl = await loadPreviewUrl();
    const audits: AuditRow[] = await loadAuditLog();
    const lines: string[] = [];
    const max: number = Math.min(audits.length, 10);
    for (let i = audits.length - max; i < audits.length; i++) {
      const r: AuditRow = audits[i];
      lines.push(`${r.ts}: ${r.from} -> ${r.to} ${r.preview_url}`);
    }
    this.auditLines = lines;
    this.refreshManifest(false).catch((err: BusinessError): void => {
      console.error(`DevMenuPage.refreshManifest: ${JSON.stringify(err)}`);
    });
  }

  private async refreshManifest(force: boolean): Promise<void> {
    this.manifestBusy = true;
    this.manifest = await fetchManifest(force);
    this.manifestBusy = false;
  }

  private async probeHealth(url: string): Promise<boolean> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await req.request(`${url}/api/v1/health`, {
        method: http.RequestMethod.GET,
        connectTimeout: 2000,
        readTimeout: 2000,
      });
      return resp.responseCode === 200;
    } catch (_err) {
      return false;
    } finally {
      req.destroy();
    }
  }

  /**
   * V0.6.1 unified tap handler. Replaces the old `onApply` button
   * path. Re-entrancy is guarded by `applying`; while a tap is in
   * flight every card is rendered with `enabled(false)` so a
   * second-finger double-tap can't fire a parallel pipeline.
   *
   * Safety pipeline preserved from V0.5: probeHealth (Preview only)
   * → resetForEnvSwitch → saveBackendEnv → savePreviewUrl → audit
   * row → toast → replaceUrl back to HomePage. Local / Staging skip
   * the probe (their URL is fixed by `metaFor(env).defaultUrl` and
   * health is not the dev menu's concern for those modes).
   */
  private async onCardTap(env: BackendEnv, previewUrl: string): Promise<void> {
    if (this.applying) {
      return;
    }
    this.applying = true;
    try {
      let urlForAudit: string = previewUrl;
      if (env === BackendEnv.PREVIEW) {
        const ok: boolean = await this.probeHealth(previewUrl);
        if (!ok) {
          this.showToast('Cannot reach /api/v1/health on that URL');
          return;
        }
      }
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      await resetForEnvSwitch(ctx);
      await saveBackendEnv(env);
      if (env === BackendEnv.PREVIEW) {
        await savePreviewUrl(previewUrl);
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
      router.replaceUrl({ url: 'pages/HomePage' });
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
      const activePreviewUrl: string = this.currentPreviewUrl;
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
        c.highlighted = isPreviewActive && activePreviewUrl === row.url;
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
      Column({ space: 8 }) {
        Text(props.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#222222')
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Row() {
          Text(props.footer)
            .fontSize(13)
            .fontColor('#555555')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%')
        .justifyContent(FlexAlign.Center);
      }
      .id(props.id)
      .layoutWeight(1)
      .padding(12)
      .borderRadius(12)
      .backgroundColor(props.highlighted ? '#CDE8FF' : '#F5F5F5')
      .border({
        width: 1,
        color: props.highlighted ? '#457B9D' : '#E0E0E0',
      })
      .enabled(!this.applying)
      .opacity(this.applying ? 0.6 : 1.0)
      .onClick((): void => {
        this.onCardTap(props.env, props.previewUrl).catch((err: BusinessError): void => {
          console.error(`onCardTap: ${JSON.stringify(err)}`);
        });
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
              router.back();
            });
          Text('Developer options')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .margin({ left: 16 });
          Blank();
          Button(this.manifestBusy ? 'Refreshing...' : 'Refresh manifest')
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
            // Stable key per pair: combine the two card ids so a
            // changing manifest forces a re-key only on actually
            // shifted rows.
            return `pair-${idx}-${pair[0].id}-${pair[1].id}`;
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

        Text(`Release builds always use staging: ${STAGING_BASE_URL}`)
          .fontSize(11)
          .fontColor('#999999')
          .margin({ top: 8 });

        if (this.auditLines.length > 0) {
          Text('Recent switches')
            .fontSize(14)
            .margin({ top: 16, bottom: 8 });
          ForEach(this.auditLines, (line: string, idx: number) => {
            Text(line)
              .fontSize(10)
              .fontColor('#777777')
              .margin({ bottom: 4 });
          }, (line: string, idx: number) => `${idx}`);
        }
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto);
  }
}
