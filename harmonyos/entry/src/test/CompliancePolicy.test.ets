import { describe, it, expect } from '@ohos/hypium';
import {
  PRIVACY_POLICY_URL,
  REPORT_CHANNEL_URL,
  TERMS_OF_SERVICE_URL,
  PRIVACY_CONSENT_PREF_KEY,
  PRIVACY_CONSENT_PREF_NAME,
} from '../main/ets/services/CompliancePolicy';

export default function compliancePolicyTest(): void {
  describe('CompliancePolicy', () => {
    it('uses public happyword policy and report channels', 0, () => {
      expect(PRIVACY_POLICY_URL).assertEqual('https://happyword.cool/privacy');
      expect(TERMS_OF_SERVICE_URL).assertEqual('https://happyword.cool/terms');
      expect(REPORT_CHANNEL_URL).assertEqual('https://happyword.cool/report_and_appeal');
    });

    it('uses stable privacy consent preference keys', 0, () => {
      expect(PRIVACY_CONSENT_PREF_NAME).assertEqual('wordmagic_compliance');
      expect(PRIVACY_CONSENT_PREF_KEY).assertEqual('privacy_consent_v1');
    });
  });
}
