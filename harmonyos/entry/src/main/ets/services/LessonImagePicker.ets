import { cameraPicker as camPicker } from '@kit.CameraKit';
import camera from '@ohos.multimedia.camera';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { PickedImage } from './ParentApiClient';
import {
  IPhotoPickerAdapter,
  PickedFileRef,
  RealPhotoPickerAdapter as SharedRealPhotoPickerAdapter,
  readPickerOverrideUri as readPickerOverrideUriShared,
} from './PhotoPickerService';

/**
 * LessonImagePicker — V0.5.8 (refactored V0.6.x).
 *
 * Photo source for the parent admin lesson-import flow. The class is
 * split into three seams so unit tests can stub each independently:
 *   - `IPhotoPickerAdapter` (gallery, shared with scan-binding flow —
 *     defined in PhotoPickerService.ets and re-exported below).
 *   - `ILessonCameraAdapter` (camera, only used by lesson import).
 *   - `IPhotoFileReader` (reads bytes off the picker's URI).
 *
 * MIME is sniffed from the URI extension because the system pickers
 * don't return a separate MIME field on this SDK (API 20). The server
 * validates again on `POST /api/v1/admin/lessons/import`, so this is
 * a fast-fail check rather than a security boundary.
 *
 * Real adapters wrap @kit.CoreFileKit `picker.PhotoViewPicker` (gallery,
 * via PhotoPickerService) and @kit.CameraKit `cameraPicker.pick`
 * (camera, in this file). Real reader wraps @kit.CoreFileKit `fileIo`
 * `openSync` + `readSync`.
 *
 * See `docs/superpowers/specs/2026-05-01-v0.5.8-parent-admin-revamp-design.md`
 * and `docs/superpowers/specs/2026-05-02-scan-binding-gallery-qr-design.md`
 * for the V0.6.x extraction.
 */

// Re-export so existing imports `from './LessonImagePicker'` keep
// working (V0.5.8 callers + tests). New scan-binding callers import
// directly from PhotoPickerService.
export { IPhotoPickerAdapter, PickedFileRef };

/**
 * AppStorage key the ohosTest harness writes to redirect the system
 * gallery / camera picker at a deterministic on-device file path.
 * When the value is a non-empty string `RealPhotoPickerAdapter` skips
 * the system UI entirely and returns a `PickedFileRef` whose `uri`
 * is the override path; the downstream `RealPhotoFileReader.readAsArrayBuffer`
 * still reads real bytes off disk, exercising the production multipart
 * upload + mock reception code paths.
 *
 * Production / release builds never write this key, so the override
 * is a strict zero-impact addition: the existing
 * `picker.PhotoViewPicker` / `cameraPicker.pick` code paths stay
 * unchanged and untested-modulo this short-circuit.
 *
 * Why a runtime override instead of driving the system gallery UI:
 * the HarmonyOS system PhotoViewPicker runs out-of-process and its
 * UI tree is version-specific and not stably matchable from Hypium.
 * The override lets us test the upload pipeline (file read → multipart
 * encode → POST → server reception) without owning the system UI's
 * brittleness.
 */
export const LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY: string =
  'lessonImagePickerOverrideUri';

/** Backward-compatible wrapper: existing V0.5.8 callers / tests call
 *  `readPickerOverrideUri()` with no args expecting the lesson key. */
export function readPickerOverrideUri(): string {
  return readPickerOverrideUriShared(LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY);
}

/** Stub-friendly camera contract. Lesson is the only consumer, so the
 *  camera adapter stays in this module (unlike the gallery adapter,
 *  which moved to PhotoPickerService for scan-binding to share). */
export interface ILessonCameraAdapter {
  selectCamera(): Promise<PickedFileRef | null>;
}

export interface IPhotoFileReader {
  readAsArrayBuffer(uri: string): Promise<ArrayBuffer>;
  sizeOf(uri: string): Promise<number>;
}

/** Production gallery adapter for the lesson flow. Subclasses the
 *  shared adapter with the lesson override key pre-bound so existing
 *  call sites `new RealPhotoPickerAdapter(ctx)` keep working without
 *  knowing about the second constructor parameter. Scan-binding
 *  constructs the shared adapter directly with its own override key. */
export class RealPhotoPickerAdapter extends SharedRealPhotoPickerAdapter {
  constructor(ctx: common.UIAbilityContext) {
    super(ctx, LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY);
  }
}

/** Production camera adapter. Lifted verbatim from the V0.5.8
 *  `RealPhotoPickerAdapter.selectCamera` + camera helper statics; the
 *  gallery half lives in PhotoPickerService now. */
export class RealLessonCameraAdapter implements ILessonCameraAdapter {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  async selectCamera(): Promise<PickedFileRef | null> {
    // ohosTest short-circuit — same override key as gallery so a
    // single AppStorage write covers both pick-from-gallery and
    // pick-from-camera buttons. The fixture image stands in for both
    // a saved photo and a freshly-captured frame.
    const override: string = readPickerOverrideUri();
    if (override.length > 0) {
      const ref: PickedFileRef = new PickedFileRef();
      ref.uri = override;
      return ref;
    }
    const uri: string | null =
      await RealLessonCameraAdapter.invokeCameraPicker(this.ctx);
    if (uri === null) {
      return null;
    }
    const ref: PickedFileRef = new PickedFileRef();
    ref.uri = uri;
    return ref;
  }

  private static async invokeCameraPicker(ctx: common.UIAbilityContext): Promise<string | null> {
    try {
      const profile: camPicker.PickerProfile =
        RealLessonCameraAdapter.makeCameraProfile();
      const mediaTypes: camPicker.PickerMediaType[] = [camPicker.PickerMediaType.PHOTO];
      const res: camPicker.PickerResult =
        await RealLessonCameraAdapter.runCameraPick(ctx, mediaTypes, profile);
      if (res.resultCode !== 0 || res.resultUri.length === 0) {
        return null;
      }
      return res.resultUri;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      console.error(`RealLessonCameraAdapter.invokeCameraPicker failed: ${JSON.stringify(be)}`);
      return null;
    }
  }

  private static makeCameraProfile(): camPicker.PickerProfile {
    try {
      const profile: camPicker.PickerProfile = new camPicker.PickerProfile();
      profile.cameraPosition = camera.CameraPosition.CAMERA_POSITION_BACK;
      return profile;
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      throw new Error(`makeCameraProfile failed: ${JSON.stringify(be)}`);
    }
  }

  private static async runCameraPick(
    ctx: common.UIAbilityContext,
    mediaTypes: camPicker.PickerMediaType[],
    profile: camPicker.PickerProfile,
  ): Promise<camPicker.PickerResult> {
    try {
      return await camPicker.pick(ctx, mediaTypes, profile);
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      throw new Error(`camPicker.pick failed: ${JSON.stringify(be)}`);
    }
  }
}

/** Production reader. The async signatures use `fs.open` / `fs.stat` /
 *  `fs.read` / `fs.close` (Promise-based) and we wrap each in an
 *  explicit try/catch so ArkTS's "function may throw" strict-mode
 *  diagnostic is satisfied. Failures are converted to plain `Error`
 *  with a `BusinessError` JSON dump so callers (which don't depend on
 *  the BusinessError shape) can react uniformly. */
export class RealPhotoFileReader implements IPhotoFileReader {
  async readAsArrayBuffer(uri: string): Promise<ArrayBuffer> {
    const file: fs.File = await RealPhotoFileReader.openReadOnly(uri);
    try {
      const stat: fs.Stat = await RealPhotoFileReader.statFd(file.fd);
      const size: number = stat.size;
      const buf: ArrayBuffer = new ArrayBuffer(size);
      let read: number = 0;
      while (read < size) {
        const n: number = await RealPhotoFileReader.readFd(file.fd, buf, read);
        if (n <= 0) {
          break;
        }
        read += n;
      }
      return buf;
    } finally {
      await RealPhotoFileReader.closeQuietly(file);
    }
  }

  async sizeOf(uri: string): Promise<number> {
    const file: fs.File = await RealPhotoFileReader.openReadOnly(uri);
    try {
      const stat: fs.Stat = await RealPhotoFileReader.statFd(file.fd);
      return stat.size;
    } finally {
      await RealPhotoFileReader.closeQuietly(file);
    }
  }

  private static async openReadOnly(uri: string): Promise<fs.File> {
    try {
      return await fs.open(uri, fs.OpenMode.READ_ONLY);
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      throw new Error(`fs.open(${uri}) failed: ${JSON.stringify(be)}`);
    }
  }

  private static async statFd(fd: number): Promise<fs.Stat> {
    try {
      return await fs.stat(fd);
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      throw new Error(`fs.stat(${fd}) failed: ${JSON.stringify(be)}`);
    }
  }

  // ArkTS strict mode rejects re-exporting ReadOptions through the
  // `fileIo` namespace alias, so we hand the option object straight to
  // `read()` and let the SDK structurally typecheck it.
  private static async readFd(fd: number, buf: ArrayBuffer, offset: number): Promise<number> {
    try {
      return await fs.read(fd, buf, { offset });
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      throw new Error(`fs.read(${fd}) failed: ${JSON.stringify(be)}`);
    }
  }

  private static async closeQuietly(file: fs.File): Promise<void> {
    try {
      await fs.close(file);
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      console.error(`RealPhotoFileReader.closeQuietly failed: ${JSON.stringify(be)}`);
    }
  }
}

export class LessonImagePicker {
  private gallery: IPhotoPickerAdapter;
  private camera: ILessonCameraAdapter;
  private reader: IPhotoFileReader;

  constructor(g: IPhotoPickerAdapter, c: ILessonCameraAdapter, r: IPhotoFileReader) {
    this.gallery = g;
    this.camera = c;
    this.reader = r;
  }

  async pickFromGallery(): Promise<PickedImage | null> {
    const ref: PickedFileRef | null = await this.gallery.selectGallery();
    return this.materialize(ref);
  }

  async pickFromCamera(): Promise<PickedImage | null> {
    const ref: PickedFileRef | null = await this.camera.selectCamera();
    return this.materialize(ref);
  }

  private async materialize(ref: PickedFileRef | null): Promise<PickedImage | null> {
    if (ref === null) {
      return null;
    }
    const filename: string = filenameOf(ref.uri);
    const mime: string = sniffMime(filename);
    if (mime.length === 0) {
      return null;
    }
    const bytes: ArrayBuffer = await this.reader.readAsArrayBuffer(ref.uri);
    const out: PickedImage = new PickedImage();
    out.bytes = bytes;
    out.mime = mime;
    out.filename = filename;
    out.sizeBytes = bytes.byteLength;
    return out;
  }
}

function filenameOf(uri: string): string {
  const i: number = uri.lastIndexOf('/');
  return i >= 0 ? uri.substring(i + 1) : uri;
}

function sniffMime(filename: string): string {
  const lower: string = filename.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return '';
}
