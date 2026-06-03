import { describe, it, expect } from '@ohos/hypium';
import {
  buildInAppBrowserRoute,
  IN_APP_BROWSER_PAGE_URL,
  InAppBrowserRoute,
} from '../main/ets/services/SystemBrowser';

export default function systemBrowserTest(): void {
  describe('SystemBrowser', () => {
    it('routesWebUrlsToTheInAppBrowserPage', 0, () => {
      const route: InAppBrowserRoute = buildInAppBrowserRoute('https://happyword.com.cn/family/login');

      expect(route.url).assertEqual(IN_APP_BROWSER_PAGE_URL);
      expect(route.params.targetUrl).assertEqual('https://happyword.com.cn/family/login');
    });
  });
}
