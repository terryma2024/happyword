import { describe, it, expect } from '@ohos/hypium';
import {
  COMPRESS_TARGET_BYTES,
  IImageCompressor,
  ImageCompressionError,
  RealImageCompressor,
} from '../main/ets/services/ImageCompressor';
import { PickedImage } from '../main/ets/services/ParentApiClient';

/**
 * Unit-level coverage for the parts of `RealImageCompressor` that
 * don't need the live `@kit.ImageKit` decoder: the early-return short
 * circuit, the public constants, and the typed error contract used by
 * `ParentAdminPage.humanizeImportError`. The actual decode → re-encode
 * loop touches native ImageKit code that isn't available in this
 * off-device unit-test harness; that path is exercised on-device via
 * ohosTest when a real photo is uploaded through ParentAdminFlow.
 */
// Use a concrete `ImageCompressionError | null` instead of the
// nominal-broader `Error | null`: ArkTS's strict-typing rule
// `arkts-no-structural-typing` rejects the assignment of a subclass
// instance to a field declared as `Error`. Narrowing here keeps the
// stub honest (only the production error class can be thrown) and
// avoids the compile failure at the assignment site.
class CapturingCompressor implements IImageCompressor {
  lastInput: PickedImage | null = null;
  lastMaxBytes: number = -1;
  toReturn: PickedImage = new PickedImage();
  toThrow: ImageCompressionError | null = null;

  async compress(picked: PickedImage, maxBytes: number): Promise<PickedImage> {
    this.lastInput = picked;
    this.lastMaxBytes = maxBytes;
    if (this.toThrow !== null) {
      throw this.toThrow;
    }
    return this.toReturn;
  }
}

export default function imageCompressorTest(): void {
  describe('RealImageCompressor', () => {
    it('returns the original PickedImage instance when size already fits', 0, async () => {
      // Behaviour pin: the short-circuit path must NOT decode (which
      // would touch ImageKit and either no-op or fail in the off-device
      // harness), and it must return the exact same instance so the
      // caller's `mime` / `filename` survive untouched.
      const c: RealImageCompressor = new RealImageCompressor();
      const img: PickedImage = new PickedImage();
      img.bytes = new ArrayBuffer(100);
      img.mime = 'image/png';
      img.filename = 'fits.png';
      img.sizeBytes = 100;

      const out: PickedImage = await c.compress(img, 1000);
      expect(out === img).assertTrue();
      expect(out.mime).assertEqual('image/png');
      expect(out.filename).assertEqual('fits.png');
    });

    it('returns the original PickedImage when size equals the cap exactly', 0, async () => {
      // Off-by-one regression guard: the condition is `sizeBytes <=
      // maxBytes`, not `<`. A 4 MB photo on a 4 MB cap should NOT
      // re-decode through ImageKit.
      const c: RealImageCompressor = new RealImageCompressor();
      const img: PickedImage = new PickedImage();
      img.bytes = new ArrayBuffer(4096);
      img.mime = 'image/jpeg';
      img.filename = 'edge.jpg';
      img.sizeBytes = 4096;

      const out: PickedImage = await c.compress(img, 4096);
      expect(out === img).assertTrue();
    });
  });

  describe('ImageCompressionError', () => {
    it('carries the code and name discriminator used by humanizeImportError', 0, () => {
      // ParentAdminPage.humanizeImportError branches on
      // `instanceof ImageCompressionError` AND on `code` — both must
      // round-trip through the constructor unchanged.
      const e: ImageCompressionError =
        new ImageCompressionError('DECODE_FAILED', 'corrupt jpeg');
      expect(e.code).assertEqual('DECODE_FAILED');
      expect(e.name).assertEqual('ImageCompressionError');
      expect(e.message).assertEqual('corrupt jpeg');
      expect(e instanceof ImageCompressionError).assertTrue();
      expect(e instanceof Error).assertTrue();
    });

    it('supports each documented error code', 0, () => {
      // Pin the four codes the production path can emit so a future
      // rename surfaces here instead of as a stale humanizer branch.
      const codes: string[] = ['DECODE_FAILED', 'ENCODE_FAILED', 'SCALE_FAILED', 'NOT_ACHIEVABLE'];
      for (let i: number = 0; i < codes.length; i++) {
        const e: ImageCompressionError = new ImageCompressionError(codes[i], 'msg');
        expect(e.code).assertEqual(codes[i]);
      }
    });
  });

  describe('COMPRESS_TARGET_BYTES', () => {
    it('targets 4 MB (well under Vercel\'s 4.5 MB edge cap)', 0, () => {
      // Pin: the constant is the contract between the picker flow
      // (which calls `compress(file, COMPRESS_TARGET_BYTES)`) and the
      // upload (which guards on IMPORT_MAX_BYTES = 4.5 MB). Lifting
      // this above 4.5 MB without also lifting Vercel's plan would
      // re-introduce the silent edge-drop that produced `网络异常`.
      expect(COMPRESS_TARGET_BYTES).assertEqual(4 * 1024 * 1024);
    });
  });

  describe('IImageCompressor (stub contract)', () => {
    it('lets ParentAdminPage swap in a deterministic compressor for tests', 0, async () => {
      // This pins the seam: any future refactor that drops the
      // interface (e.g. inlines the call into ParentAdminPage) breaks
      // this test loudly so the testability story doesn't silently
      // regress.
      const stub: CapturingCompressor = new CapturingCompressor();
      const original: PickedImage = new PickedImage();
      original.sizeBytes = 9_000_000;
      original.mime = 'image/jpeg';
      original.filename = 'big.jpg';
      const replacement: PickedImage = new PickedImage();
      replacement.sizeBytes = 1024;
      replacement.bytes = new ArrayBuffer(1024);
      replacement.mime = 'image/jpeg';
      replacement.filename = 'big.jpg';
      stub.toReturn = replacement;

      const out: PickedImage = await stub.compress(original, 4_000_000);
      expect(out === replacement).assertTrue();
      expect(stub.lastInput === original).assertTrue();
      expect(stub.lastMaxBytes).assertEqual(4_000_000);
    });

    it('propagates ImageCompressionError to the caller', 0, async () => {
      const stub: CapturingCompressor = new CapturingCompressor();
      stub.toThrow = new ImageCompressionError('NOT_ACHIEVABLE', 'too noisy');
      const img: PickedImage = new PickedImage();
      img.sizeBytes = 9_000_000;
      let caught: ImageCompressionError | null = null;
      try {
        await stub.compress(img, 4_000_000);
      } catch (e) {
        if (e instanceof ImageCompressionError) {
          caught = e;
        }
      }
      expect(caught !== null).assertTrue();
      if (caught !== null) {
        expect(caught.code).assertEqual('NOT_ACHIEVABLE');
      }
    });
  });
}
