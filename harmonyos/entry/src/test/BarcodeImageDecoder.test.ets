import { describe, it, expect } from '@ohos/hypium';
import {
  NoBarcodeFoundError,
  RealBarcodeImageDecoder,
  SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY,
  SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY,
} from '../main/ets/services/BarcodeImageDecoder';

export default function barcodeImageDecoderTest(): void {
  describe('BarcodeImageDecoder', () => {
    /**
     * The override-key constants are read by the ohosTest harness in
     * `entry/src/ohosTest/ets/test/ParentBindingFlow.ui.test.ets`.
     * Renaming either key requires a coordinated change across that
     * harness, so we pin the literal string values here.
     */
    it('SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY constant pinned', 0, () => {
      expect(SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY)
        .assertEqual('scanBindingBarcodeDecoderOverridePayload');
    });

    it('SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY constant pinned', 0, () => {
      expect(SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY)
        .assertEqual('scanBindingPhotoPickerOverrideUri');
    });

    it('decodeFromUri returns override payload when key is set', 0, async () => {
      AppStorage.setOrCreate<string>(
        SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY,
        'https://happyword.cool/p/uitestqr01',
      );
      try {
        const dec: RealBarcodeImageDecoder = new RealBarcodeImageDecoder();
        const out: string = await dec.decodeFromUri('file:///does/not/exist.png');
        expect(out).assertEqual('https://happyword.cool/p/uitestqr01');
      } finally {
        AppStorage.delete(SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY);
      }
    });

    it('decodeFromUri trims override payload whitespace', 0, async () => {
      AppStorage.setOrCreate<string>(
        SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY,
        '  https://x/p/abc \n',
      );
      try {
        const dec: RealBarcodeImageDecoder = new RealBarcodeImageDecoder();
        expect(await dec.decodeFromUri('any')).assertEqual('https://x/p/abc');
      } finally {
        AppStorage.delete(SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY);
      }
    });

    it('NoBarcodeFoundError name is preserved', 0, () => {
      const e: NoBarcodeFoundError = new NoBarcodeFoundError('no barcode');
      expect(e.name).assertEqual('NoBarcodeFoundError');
      expect(e.message).assertEqual('no barcode');
    });
  });
}
