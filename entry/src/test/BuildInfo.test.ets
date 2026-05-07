import { describe, it, expect } from '@ohos/hypium';
import { formatBuildTimestamp, formatVersionLabel, VersionInfo } from '../main/ets/services/BuildInfo';

export default function buildInfoTest(): void {
  describe('formatBuildTimestamp', () => {
    it('produces10CharDigitString', 0, () => {
      const out: string = formatBuildTimestamp(0);
      expect(out.length).assertEqual(10);
      // Every char is a digit.
      for (let i: number = 0; i < out.length; i++) {
        const code: number = out.charCodeAt(i);
        expect(code >= 48 && code <= 57).assertTrue();
      }
    });

    it('roundtripsViaDateConstructor', 0, () => {
      // Use a Date built locally so the assertion is timezone-stable.
      // 2026-05-07 20:52:34 local time — seconds intentionally non-zero
      // so the assertion proves they're dropped, not coincidentally :00.
      const d: Date = new Date(2026, 4, 7, 20, 52, 34);
      const out: string = formatBuildTimestamp(d.getTime());
      // YY=26, MM=05, DD=07, HH=20, mm=52 → '2605072052'.
      // Seconds (34) are intentionally absent.
      expect(out).assertEqual('2605072052');
    });
  });

  describe('formatVersionLabel', () => {
    it('composesLabel', 0, () => {
      const info: VersionInfo = { versionName: '0.6.0', timestamp: '2605072052' };
      expect(formatVersionLabel(info)).assertEqual('v0.6.0(2605072052)');
    });

    it('preservesFallbackVersionName', 0, () => {
      const info: VersionInfo = { versionName: '?.?.?', timestamp: '2605072052' };
      expect(formatVersionLabel(info)).assertEqual('v?.?.?(2605072052)');
    });
  });
}
