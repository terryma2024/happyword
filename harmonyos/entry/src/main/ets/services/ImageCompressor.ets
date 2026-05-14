import { image } from '@kit.ImageKit';
import { BusinessError } from '@ohos.base';
import { PickedImage } from './ParentApiClient';

/**
 * ImageCompressor — V0.7 client-side textbook photo downsizing.
 *
 * Why we need this
 * ----------------
 * The lesson-import upload (`POST /api/v1/family/{family_id}/lessons/import`) is
 * deployed as a Vercel Function. Vercel's edge enforces a hard
 * **4.5 MB request body limit** independent of the FastAPI handler's
 * own check. Modern phone gallery photos are routinely 5–10 MB, so a
 * fresh-from-album JPEG is silently dropped at the Vercel edge before
 * the function is ever invoked. The HarmonyOS http stack surfaces that
 * dropped connection as a transport failure → `LessonImportError(code
 * = 'NETWORK')` → the user-facing toast `网络异常，请检查重试`.
 *
 * Compressing on the client to a comfortable margin under the cap
 * (`COMPRESS_TARGET_BYTES`, currently 4 MB) keeps the multipart body
 * + envelope under the edge limit and lets uploads succeed.
 *
 * Strategy
 * --------
 * 1. Early-return the original `PickedImage` if it already fits — no
 *    decode / re-encode cost.
 * 2. Decode once into a `PixelMap` via `@kit.ImageKit`.
 * 3. Sweep `COMPRESSION_QUALITIES` (descending). The first JPEG output
 *    that fits wins; we stop early.
 * 4. If even the lowest quality (25) still exceeds the target, scale
 *    the pixel map down by `SCALE_FACTOR` and repeat the quality
 *    sweep. Up to `MAX_SCALE_ATTEMPTS` extra rounds.
 * 5. Always re-encode to JPEG — small, universally supported, and
 *    `_ACCEPTED_MIME` on the server already includes it.
 * 6. Release `ImageSource` / `PixelMap` / `ImagePacker` in `finally`
 *    even on the early-return path. PixelMap holds a native bitmap;
 *    forgetting `release()` is a real memory leak on long sessions.
 *
 * The interface seam (`IImageCompressor`) lets `ParentAdminPage` swap
 * a deterministic stub in unit tests (the real `@kit.ImageKit` calls
 * touch native code that's not available off-device).
 */

/** Re-encoded JPEG quality levels tried on each scale attempt, high
 *  to low. Higher quality is preferred but we stop at the first one
 *  that fits the target. 25 is roughly the lowest that keeps text in
 *  a textbook photo OCR-readable; below that the OCR LLM will start
 *  to miss low-contrast words. */
const COMPRESSION_QUALITIES: number[] = [85, 70, 55, 40, 25];
/** Multiplicative downscale factor between attempts. 0.7 ≈ 0.5×
 *  pixel area per round; combined with the quality sweep this
 *  converges to ~4 MB within 1–2 attempts even from a 12 MP source. */
const SCALE_FACTOR: number = 0.7;
/** Cap on scale-down rounds to prevent unbounded recursion on
 *  pathological inputs (e.g. a noisy photo that doesn't compress).
 *  After this many rounds we throw NOT_ACHIEVABLE so the user sees a
 *  clear error rather than a hang. */
const MAX_SCALE_ATTEMPTS: number = 4;

/** Target byte budget for the compressed body. Picked to leave ~500
 *  KB headroom under Vercel's 4.5 MB request-body limit so the
 *  multipart envelope (+~200 bytes) and any TLS framing fit. Also
 *  exported so `ParentAdminPage` can pass the same constant to
 *  `compress(...)` without redeclaring it. */
export const COMPRESS_TARGET_BYTES: number = 4 * 1024 * 1024;

/** Failure modes:
 *  - DECODE_FAILED: `@kit.ImageKit` rejected the input bytes (corrupt
 *    file, unsupported format that slipped past the picker's MIME
 *    sniff, etc.). The original `PickedImage` is unrecoverable.
 *  - NOT_ACHIEVABLE: the sweep exhausted all qualities × scales and
 *    the smallest output still exceeded the target. Realistically
 *    only happens on huge solid-noise inputs; phone photos converge.
 */
export class ImageCompressionError extends Error {
  code: string = '';
  constructor(code: string, message: string) {
    super(message);
    this.name = 'ImageCompressionError';
    this.code = code;
  }
}

export interface IImageCompressor {
  /** Return a `PickedImage` whose `sizeBytes` is `<= maxBytes`. If the
   *  input already fits, return it unchanged (no decode). On failure
   *  throw `ImageCompressionError`. */
  compress(picked: PickedImage, maxBytes: number): Promise<PickedImage>;
}

export class RealImageCompressor implements IImageCompressor {
  async compress(picked: PickedImage, maxBytes: number): Promise<PickedImage> {
    if (picked.sizeBytes <= maxBytes) {
      return picked;
    }

    let source: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      source = RealImageCompressor.createSource(picked.bytes);
      pixelMap = await RealImageCompressor.decodePixelMap(source);
      packer = image.createImagePacker();

      for (let attempt: number = 0; attempt <= MAX_SCALE_ATTEMPTS; attempt++) {
        for (let i: number = 0; i < COMPRESSION_QUALITIES.length; i++) {
          const quality: number = COMPRESSION_QUALITIES[i];
          const out: ArrayBuffer =
            await RealImageCompressor.packJpeg(packer, pixelMap, quality);
          if (out.byteLength <= maxBytes) {
            return RealImageCompressor.toPicked(picked, out);
          }
        }
        if (attempt < MAX_SCALE_ATTEMPTS) {
          await RealImageCompressor.scaleDown(pixelMap, SCALE_FACTOR);
        }
      }

      throw new ImageCompressionError(
        'NOT_ACHIEVABLE',
        `compress: image still > ${maxBytes} bytes after ` +
          `${COMPRESSION_QUALITIES.length} qualities × ` +
          `${MAX_SCALE_ATTEMPTS + 1} scale attempts`,
      );
    } finally {
      // Order matters: packer holds no references to source/pixelMap,
      // but releasing pixelMap before source mirrors the system docs'
      // examples and avoids any chance of a use-after-free if a future
      // SDK rev links them.
      await RealImageCompressor.releaseQuietly(packer, pixelMap, source);
    }
  }

  /** Wrap the synchronous `image.createImageSource` call so a
   *  malformed buffer surfaces as our typed `ImageCompressionError`
   *  instead of a generic `BusinessError` that would punt the user to
   *  the catch-all "上传失败" path. */
  private static createSource(bytes: ArrayBuffer): image.ImageSource {
    try {
      return image.createImageSource(bytes);
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      throw new ImageCompressionError(
        'DECODE_FAILED',
        `createImageSource failed: ${JSON.stringify(be)}`,
      );
    }
  }

  private static async decodePixelMap(src: image.ImageSource): Promise<image.PixelMap> {
    try {
      return await src.createPixelMap();
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      throw new ImageCompressionError(
        'DECODE_FAILED',
        `createPixelMap failed: ${JSON.stringify(be)}`,
      );
    }
  }

  private static async packJpeg(
    packer: image.ImagePacker,
    pm: image.PixelMap,
    quality: number,
  ): Promise<ArrayBuffer> {
    const opts: image.PackingOption = { format: 'image/jpeg', quality };
    try {
      return await packer.packToData(pm, opts);
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      throw new ImageCompressionError(
        'ENCODE_FAILED',
        `packing(quality=${quality}) failed: ${JSON.stringify(be)}`,
      );
    }
  }

  private static async scaleDown(pm: image.PixelMap, factor: number): Promise<void> {
    try {
      await pm.scale(factor, factor);
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      throw new ImageCompressionError(
        'SCALE_FAILED',
        `pixelMap.scale(${factor}) failed: ${JSON.stringify(be)}`,
      );
    }
  }

  private static toPicked(original: PickedImage, bytes: ArrayBuffer): PickedImage {
    const out: PickedImage = new PickedImage();
    out.bytes = bytes;
    out.mime = 'image/jpeg';
    out.filename = RealImageCompressor.toJpegFilename(original.filename);
    out.sizeBytes = bytes.byteLength;
    return out;
  }

  /** Replace the original extension with `.jpg` (case-insensitive).
   *  Server-side validation only checks the multipart `Content-Type`
   *  header (which we set to `image/jpeg`), but a matching extension
   *  keeps audit logs / blob URLs readable. */
  private static toJpegFilename(name: string): string {
    if (name.length === 0) {
      return 'lesson.jpg';
    }
    const dot: number = name.lastIndexOf('.');
    if (dot <= 0) {
      return `${name}.jpg`;
    }
    return `${name.substring(0, dot)}.jpg`;
  }

  /** Best-effort native-resource release. Never throws — a release
   *  failure is logged so the next leak is debuggable but never masks
   *  the real (or successful) compression result. */
  private static async releaseQuietly(
    packer: image.ImagePacker | null,
    pixelMap: image.PixelMap | null,
    source: image.ImageSource | null,
  ): Promise<void> {
    if (packer !== null) {
      try {
        await packer.release();
      } catch (e) {
        const be: BusinessError = e as BusinessError;
        console.error(`ImageCompressor.packer.release failed: ${JSON.stringify(be)}`);
      }
    }
    if (pixelMap !== null) {
      try {
        await pixelMap.release();
      } catch (e) {
        const be: BusinessError = e as BusinessError;
        console.error(`ImageCompressor.pixelMap.release failed: ${JSON.stringify(be)}`);
      }
    }
    if (source !== null) {
      try {
        await source.release();
      } catch (e) {
        const be: BusinessError = e as BusinessError;
        console.error(`ImageCompressor.source.release failed: ${JSON.stringify(be)}`);
      }
    }
  }
}
