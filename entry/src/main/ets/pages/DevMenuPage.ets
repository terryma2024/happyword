import { router } from '@kit.ArkUI';
import http from '@ohos.net.http';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import BuildProfile from 'BuildProfile';
import {
  BackendEnv,
  appendAuditLog,
  AuditRow,
  enabledEnvsForBuildMode,
  loadAuditLog,
  loadBackendEnv,
  loadHistory,
  loadPreviewUrl,
  metaFor,
  pushHistory,
  saveBackendEnv,
  saveHistory,
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

@Entry
@Component
struct DevMenuPage {
  @State private pendingEnv: BackendEnv = BackendEnv.STAGING;
  @State private currentEnv: BackendEnv = BackendEnv.STAGING;
  @State private pasteUrl: string = '';
  @State private manifest: PreviewManifest | null = null;
  @State private manifestBusy: boolean = false;
  @State private selectedManifestUrl: string = '';
  @State private history: string[] = [];
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
    this.hydrate().catch((err: BusinessError): void => {
      console.error(`DevMenuPage.hydrate failed: ${JSON.stringify(err)}`);
    });
  }

  private async hydrate(): Promise<void> {
    this.manifest = getCached();
    this.pendingEnv = await loadBackendEnv();
    this.currentEnv = this.pendingEnv;
    this.pasteUrl = '';
    const pv: string = await loadPreviewUrl();
    this.selectedManifestUrl = pv;
    this.history = await loadHistory();
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

  private previewChosenUrl(): string {
    if (this.pasteUrl.trim().length > 0) {
      return this.pasteUrl.trim();
    }
    return this.selectedManifestUrl;
  }

  private async onApply(): Promise<void> {
    if (this.applying) {
      return;
    }
    this.applying = true;
    try {
      let chosenUrl: string = '';
      if (this.pendingEnv === BackendEnv.PREVIEW) {
        chosenUrl = this.previewChosenUrl();
        if (!chosenUrl.startsWith('https://') || !chosenUrl.endsWith('.vercel.app')) {
          this.showToast('Preview URL must be https and end with .vercel.app');
          return;
        }
        const ok: boolean = await this.probeHealth(chosenUrl);
        if (!ok) {
          this.showToast('Cannot reach /api/v1/health on that URL');
          return;
        }
      }
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      await resetForEnvSwitch(ctx);
      await saveBackendEnv(this.pendingEnv);
      if (this.pendingEnv === BackendEnv.PREVIEW) {
        await savePreviewUrl(chosenUrl);
        const nh: string[] = pushHistory(this.history, chosenUrl);
        this.history = nh;
        await saveHistory(nh);
      } else {
        await savePreviewUrl('');
      }
      const row: AuditRow = {
        ts: Date.now(),
        from: this.currentEnv,
        to: this.pendingEnv,
        preview_url: chosenUrl,
      };
      await appendAuditLog(row);
      this.currentEnv = this.pendingEnv;
      this.showToast('Environment updated. Re-bind parent account if needed.');
      router.replaceUrl({ url: 'pages/HomePage' });
    } finally {
      this.applying = false;
    }
  }

  build(): void {
    Column() {
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
      }
      .width('100%')
      .margin({ bottom: 16 });

      Text('Backend environment (debug builds only)')
        .fontSize(14)
        .fontColor('#666666')
        .margin({ bottom: 8 });

      Row({ space: 8 }) {
        ForEach(enabledEnvsForBuildMode(BuildProfile.BUILD_MODE_NAME), (env: BackendEnv) => {
          Button(metaFor(env).label)
            .fontSize(14)
            .height(36)
            .backgroundColor(this.pendingEnv === env ? '#457B9D' : '#E0E0E0')
            .fontColor(this.pendingEnv === env ? '#FFFFFF' : '#333333')
            .onClick((): void => {
              this.pendingEnv = env;
            });
        }, (env: BackendEnv) => `${env}`);
      }
      .margin({ bottom: 16 });

      if (this.pendingEnv === BackendEnv.PREVIEW) {
        Text('Manifest previews')
          .fontSize(14)
          .margin({ bottom: 8 });
        if (this.manifestBusy) {
          Text('Loading manifest...').fontSize(12).fontColor('#888888');
        }
        if (this.manifest !== null && this.manifest.previews.length > 0) {
          Scroll() {
            Column({ space: 6 }) {
              ForEach(this.manifest.previews, (row: ManifestRow) => {
                Button(`#${row.pr} ${row.title}`)
                  .fontSize(12)
                  .height(32)
                  .width('100%')
                  .backgroundColor(this.selectedManifestUrl === row.url ? '#CDE8FF' : '#F5F5F5')
                  .onClick((): void => {
                    this.selectedManifestUrl = row.url;
                    this.pasteUrl = '';
                  });
              }, (row: ManifestRow) => `${row.pr}-${row.url}`);
            };
          }
          .height(140)
          .margin({ bottom: 8 });
        }

        Text('Or paste preview URL')
          .fontSize(14)
          .margin({ top: 8, bottom: 4 });
        TextInput({ text: this.pasteUrl, placeholder: 'https://….vercel.app' })
          .onChange((v: string) => {
            this.pasteUrl = v;
          })
          .width('100%')
          .margin({ bottom: 12 });

        if (this.history.length > 0) {
          Text('Recent URLs')
            .fontSize(12)
            .fontColor('#888888')
            .margin({ bottom: 4 });
          ForEach(this.history, (u: string) => {
            Text(u)
              .fontSize(11)
              .fontColor('#555555')
              .margin({ bottom: 4 })
              .onClick((): void => {
                this.pasteUrl = u;
              });
          }, (u: string, idx: number) => `${idx}-${u}`);
        }
      }

      Row({ space: 12 }) {
        Button(this.manifestBusy ? 'Refreshing...' : 'Refresh manifest')
          .fontSize(13)
          .height(36)
          .enabled(!this.manifestBusy)
          .onClick((): void => {
            this.refreshManifest(true).catch((err: BusinessError): void => {
              console.error(`refreshManifest: ${JSON.stringify(err)}`);
            });
          });
        Text(this.manifest !== null ? `${this.manifest.previews.length} previews` : 'No manifest')
          .fontSize(12)
          .fontColor('#888888');
      }
      .margin({ bottom: 16 });

      Button(this.applying ? 'Applying...' : 'Apply')
        .width('80%')
        .height(44)
        .enabled(!this.applying)
        .onClick((): void => {
          this.onApply().catch((err: BusinessError): void => {
            console.error(`onApply: ${JSON.stringify(err)}`);
          });
        });

      Text(`Release builds always use staging: ${STAGING_BASE_URL}`)
        .fontSize(11)
        .fontColor('#999999')
        .margin({ top: 16 });

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
    .height('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start);
  }
}
