import bundleManager from '@ohos.bundle.bundleManager';
import { BusinessError } from '@ohos.base';

export interface VersionInfo {
  versionName: string;
  /** YYMMDDHHmm, local time, minute precision. */
  timestamp: string;
}

const FALLBACK_VERSION_NAME: string = '?.?.?';

/**
 * Format an epoch millis value as YYMMDDHHmm in the device's local
 * time. Pure function — deterministic given an input ms. Seconds are
 * intentionally dropped: minute precision is enough to identify which
 * install corresponds to which build, and avoids visual churn from
 * re-installs within the same minute.
 */
export function formatBuildTimestamp(epochMs: number): string {
  const d: Date = new Date(epochMs);
  const yy: string = String(d.getFullYear() % 100).padStart(2, '0');
  const mm: string = String(d.getMonth() + 1).padStart(2, '0');
  const dd: string = String(d.getDate()).padStart(2, '0');
  const hh: string = String(d.getHours()).padStart(2, '0');
  const mn: string = String(d.getMinutes()).padStart(2, '0');
  return `${yy}${mm}${dd}${hh}${mn}`;
}

/**
 * Read versionName + bundle update time from the OHOS bundle manager
 * and return a {versionName, timestamp} pair. On any failure returns
 * the fallback `?.?.?` versionName and `formatBuildTimestamp(now)`.
 *
 * `updateTime` corresponds to when the HAP was last installed/updated
 * on this device — close enough to "build identity" for dev/QA loops
 * without requiring a custom hvigor plugin (see spec §6).
 */
export async function readVersionInfo(): Promise<VersionInfo> {
  try {
    const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
    );
    const name: string = (info.versionName !== undefined && info.versionName.length > 0)
      ? info.versionName
      : FALLBACK_VERSION_NAME;
    const ms: number = (info.updateTime !== undefined && info.updateTime > 0)
      ? info.updateTime
      : Date.now();
    return { versionName: name, timestamp: formatBuildTimestamp(ms) };
  } catch (err) {
    console.error(`BuildInfo.readVersionInfo failed: ${JSON.stringify(err as BusinessError)}`);
    return { versionName: FALLBACK_VERSION_NAME, timestamp: formatBuildTimestamp(Date.now()) };
  }
}

/** Convenience composer: `v{name}({timestamp})`. */
export function formatVersionLabel(info: VersionInfo): string {
  return `v${info.versionName}(${info.timestamp})`;
}
