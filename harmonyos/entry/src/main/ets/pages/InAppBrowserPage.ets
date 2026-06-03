import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { InAppBrowserRouteParams } from '../services/SystemBrowser';
import { PageTopChrome } from '../components/PageTopChrome';
import { requestPageOrientation } from '../utils/orientation';

const FALLBACK_URL: string = 'https://happyword.com.cn';

@Entry
@Component
struct InAppBrowserPage {
  @State private targetUrl: string = FALLBACK_URL;
  private controller: webview.WebviewController = new webview.WebviewController();

  private applyOrientationPolicy(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'InAppBrowserPage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  aboutToAppear(): void {
    this.applyOrientationPolicy();
    const raw: object | undefined = this.getUIContext().getRouter().getParams() as object | undefined;
    if (raw === undefined) {
      return;
    }
    const params: InAppBrowserRouteParams = raw as InAppBrowserRouteParams;
    if (typeof params.targetUrl === 'string' && params.targetUrl.length > 0) {
      this.targetUrl = params.targetUrl;
    }
  }

  onPageShow(): void {
    this.applyOrientationPolicy();
  }

  build(): void {
    Column() {
      PageTopChrome({
        backButtonId: 'InAppBrowserBackButton',
        title: '网页',
        titleId: 'InAppBrowserTitle',
        onBack: (): void => {
          this.getUIContext().getRouter().back();
        },
      });

      Web({
        src: this.targetUrl,
        controller: this.controller,
      })
        .id('InAppBrowserWeb')
        .layoutWeight(1)
        .width('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF');
  }
}
