import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@ohos.base';

/**
 * BarcodeImageDecoder — V0.6.x.
 *
 * Static-image QR decoder seam. Production wraps `@kit.ScanKit`'s
 * `detectBarcode.decode` API (one-shot static-image decode that takes
 * a URI + options and returns the decoded payload, no native UI).
 * Tests inject either a stub implementing `BarcodeImageDecoderLike`
 * directly, or write the AppStorage override key below to short-
 * circuit the production decoder without changing the call site.
 *
 * Why an override seam: `detectBarcode.decode` against arbitrary
 * on-device URIs (especially app-sandbox tempDir paths) is unstable
 * on the OpenHarmony emulator. The same selinux story that pushed
 * V0.5.8 toward the picker override (see `LessonImagePicker.ets`)
 * applies here. ohosTest writes
 * `AppStorage[SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY]` to
 * pin the decoded payload; production never writes that key.
 *
 * See `docs/superpowers/specs/2026-05-02-scan-binding-gallery-qr-design.md`.
 */

/** AppStorage key the ohosTest harness writes to override the picker
 *  short-circuit URI for ScanBindingPage's gallery-QR path. Lives
 *  alongside the decoder key so a single import grabs both into
 *  ParentBindingFlow.ui.test.ets. */
export const SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY: string =
  'scanBindingPhotoPickerOverrideUri';

/** AppStorage key for `RealBarcodeImageDecoder.decodeFromUri` short-
 *  circuit. Production never writes this key; ohosTest writes it to
 *  the expected QR payload string before clicking the gallery button. */
export const SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY: string =
  'scanBindingBarcodeDecoderOverridePayload';

/** Stub-friendly contract. */
export interface BarcodeImageDecoderLike {
  /** Returns the decoded string. Throws `NoBarcodeFoundError` if the
   *  image contains no barcode or the SDK fails for any reason. */
  decodeFromUri(uri: string): Promise<string>;
}

/** Sentinel: image had no detectable barcode (or the SDK couldn't
 *  decode). DeviceBindingService maps this to `TOKEN_INVALID`. */
export class NoBarcodeFoundError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NoBarcodeFoundError';
  }
}

export class RealBarcodeImageDecoder implements BarcodeImageDecoderLike {
  async decodeFromUri(uri: string): Promise<string> {
    const override: string = readDecoderOverridePayload();
    if (override.length > 0) {
      return override;
    }
    return await RealBarcodeImageDecoder.invokeScanKitDecode(uri);
  }

  // The production decode is wrapped in its own try/catch + re-throw
  // helper so ArkTS strict mode's "function may throw" diagnostic is
  // satisfied at every call site. All non-NoBarcodeFoundError failures
  // are also normalised to NoBarcodeFoundError so the
  // DeviceBindingService gallery-image path surfaces a single failure
  // shape (TOKEN_INVALID) regardless of whether the image had no QR
  // or the SDK couldn't read the URI.
  private static async invokeScanKitDecode(uri: string): Promise<string> {
    try {
      const opts: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: false,
      };
      const inputImage: detectBarcode.InputImage = { uri };
      const results: Array<scanBarcode.ScanResult> =
        await detectBarcode.decode(inputImage, opts);
      if (results.length === 0 || results[0].originalValue.length === 0) {
        throw new NoBarcodeFoundError('decode returned no results');
      }
      return results[0].originalValue;
    } catch (err) {
      if (err instanceof NoBarcodeFoundError) {
        throw err;
      }
      const be: BusinessError = err as BusinessError;
      throw new NoBarcodeFoundError(
        `detectBarcode.decode failed: code=${be.code} msg=${be.message}`,
      );
    }
  }
}

function readDecoderOverridePayload(): string {
  const raw: string | undefined =
    AppStorage.get<string>(SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY);
  if (typeof raw !== 'string') {
    return '';
  }
  return raw.trim();
}
