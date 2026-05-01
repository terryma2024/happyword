import { picker } from '@kit.CoreFileKit';
import { cameraPicker as camPicker } from '@kit.CameraKit';
import camera from '@ohos.multimedia.camera';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { PickedImage } from './ParentApiClient';

/**
 * LessonImagePicker — V0.5.8.
 *
 * Photo source for the parent admin lesson-import flow. The class is
 * split into two seams so unit tests can stub both:
 *   - `IPhotoPickerAdapter`: opens the system gallery / camera picker
 *     and returns a `PickedFileRef` (or null on user cancel).
 *   - `IPhotoFileReader`: reads bytes off the picker's URI.
 *
 * MIME is sniffed from the URI extension because the system pickers
 * don't return a separate MIME field on this SDK (API 20). The server
 * validates again on `POST /api/v1/admin/lessons/import`, so this is
 * a fast-fail check rather than a security boundary.
 *
 * Real adapters wrap @kit.CoreFileKit `picker.PhotoViewPicker` (gallery)
 * and @kit.CameraKit `cameraPicker.pick` (camera). Real reader wraps
 * @kit.CoreFileKit `fileIo` `openSync` + `readSync`.
 *
 * See `docs/superpowers/specs/2026-05-01-v0.5.8-parent-admin-revamp-design.md`.
 */

/** A handle returned by the system picker. We keep this as a class
 *  (rather than an interface) so ArkTS strict mode can typecheck the
 *  test stubs' object literals via `new PickedFileRef()` without
 *  tripping `arkts-no-untyped-obj-literals`. */
export class PickedFileRef {
  uri: string = '';
}

export interface IPhotoPickerAdapter {
  selectGallery(): Promise<PickedFileRef | null>;
  selectCamera(): Promise<PickedFileRef | null>;
}

export interface IPhotoFileReader {
  readAsArrayBuffer(uri: string): Promise<ArrayBuffer>;
  sizeOf(uri: string): Promise<number>;
}

/** Production gallery + camera adapter. Constructed with the current
 *  UIAbility context because @kit.CameraKit's `pick` requires it. */
export class RealPhotoPickerAdapter implements IPhotoPickerAdapter {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  async selectGallery(): Promise<PickedFileRef | null> {
    const uri: string | null = await RealPhotoPickerAdapter.invokeGalleryPicker();
    if (uri === null) {
      return null;
    }
    const ref: PickedFileRef = new PickedFileRef();
    ref.uri = uri;
    return ref;
  }

  async selectCamera(): Promise<PickedFileRef | null> {
    const uri: string | null = await RealPhotoPickerAdapter.invokeCameraPicker(this.ctx);
    if (uri === null) {
      return null;
    }
    const ref: PickedFileRef = new PickedFileRef();
    ref.uri = uri;
    return ref;
  }

  // Each underlying SDK call is wrapped in its own try/catch + re-throw
  // helper so ArkTS strict mode's "function may throw" diagnostic is
  // satisfied at every call site. The outer `invoke*Picker` then
  // swallows errors and returns `null` (treated identically to user-
  // cancel by the caller).
  private static async invokeGalleryPicker(): Promise<string | null> {
    try {
      const opts: picker.PhotoSelectOptions =
        RealPhotoPickerAdapter.makeGalleryOpts();
      const photoPicker: picker.PhotoViewPicker =
        RealPhotoPickerAdapter.newPhotoViewPicker();
      const res: picker.PhotoSelectResult =
        await RealPhotoPickerAdapter.runPhotoSelect(photoPicker, opts);
      const uris: Array<string> | undefined = res.photoUris;
      if (uris === undefined || uris.length === 0) {
        return null;
      }
      return uris[0];
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      console.error(`RealPhotoPickerAdapter.invokeGalleryPicker failed: ${JSON.stringify(be)}`);
      return null;
    }
  }

  private static async invokeCameraPicker(ctx: common.UIAbilityContext): Promise<string | null> {
    try {
      const profile: camPicker.PickerProfile =
        RealPhotoPickerAdapter.makeCameraProfile();
      const mediaTypes: camPicker.PickerMediaType[] = [camPicker.PickerMediaType.PHOTO];
      const res: camPicker.PickerResult =
        await RealPhotoPickerAdapter.runCameraPick(ctx, mediaTypes, profile);
      if (res.resultCode !== 0 || res.resultUri.length === 0) {
        return null;
      }
      return res.resultUri;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      console.error(`RealPhotoPickerAdapter.invokeCameraPicker failed: ${JSON.stringify(be)}`);
      return null;
    }
  }

  private static makeGalleryOpts(): picker.PhotoSelectOptions {
    try {
      const opts: picker.PhotoSelectOptions = new picker.PhotoSelectOptions();
      opts.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 1;
      return opts;
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      throw new Error(`makeGalleryOpts failed: ${JSON.stringify(be)}`);
    }
  }

  private static newPhotoViewPicker(): picker.PhotoViewPicker {
    try {
      return new picker.PhotoViewPicker();
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      throw new Error(`newPhotoViewPicker failed: ${JSON.stringify(be)}`);
    }
  }

  private static async runPhotoSelect(
    p: picker.PhotoViewPicker,
    opts: picker.PhotoSelectOptions,
  ): Promise<picker.PhotoSelectResult> {
    try {
      return await p.select(opts);
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      throw new Error(`photoPicker.select failed: ${JSON.stringify(be)}`);
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
  private picker: IPhotoPickerAdapter;
  private reader: IPhotoFileReader;

  constructor(p: IPhotoPickerAdapter, r: IPhotoFileReader) {
    this.picker = p;
    this.reader = r;
  }

  async pickFromGallery(): Promise<PickedImage | null> {
    const ref: PickedFileRef | null = await this.picker.selectGallery();
    return this.materialize(ref);
  }

  async pickFromCamera(): Promise<PickedImage | null> {
    const ref: PickedFileRef | null = await this.picker.selectCamera();
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
