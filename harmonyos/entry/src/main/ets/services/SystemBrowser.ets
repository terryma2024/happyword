import { BusinessError } from '@ohos.base';

export const IN_APP_BROWSER_PAGE_URL: string = 'pages/InAppBrowserPage';

export class InAppBrowserRouteParams {
  targetUrl: string = '';
}

export class InAppBrowserRoute {
  url: string = IN_APP_BROWSER_PAGE_URL;
  params: InAppBrowserRouteParams = new InAppBrowserRouteParams();
}

export function buildInAppBrowserRoute(url: string): InAppBrowserRoute {
  const params: InAppBrowserRouteParams = new InAppBrowserRouteParams();
  params.targetUrl = url;
  const route: InAppBrowserRoute = new InAppBrowserRoute();
  route.params = params;
  return route;
}

export async function openUrlInAppBrowser(
  uiContext: UIContext,
  url: string,
): Promise<void> {
  try {
    await uiContext.getRouter().pushUrl(buildInAppBrowserRoute(url));
  } catch (err) {
    const be: BusinessError = err as BusinessError;
    console.error(`openUrlInAppBrowser failed: ${JSON.stringify(be)}`);
    const msg: string =
      be.message !== undefined && be.message.length > 0 ? be.message : JSON.stringify(be);
    throw new Error(msg);
  }
}
