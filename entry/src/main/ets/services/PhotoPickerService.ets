import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';

/**
 * PhotoPickerService — V0.6.x.
 *
 * Shared gallery picker plumbing extracted from V0.5.8's
 * LessonImagePicker so multiple call sites (lesson import, scan-binding
 * QR-from-gallery) can reuse the same adapter while still having their
 * own AppStorage override key for the ohosTest short-circuit.
 *
 * Camera picking stays inside LessonImagePicker — only one feature
 * uses it, so the shared service stays gallery-only.
 *
 * See `docs/superpowers/specs/2026-05-02-scan-binding-gallery-qr-design.md`.
 */

/** A handle returned by the system gallery picker. Class (not interface)
 *  so ArkTS strict mode can typecheck `new PickedFileRef()` literals
 *  via `arkts-no-untyped-obj-literals`. */
export class PickedFileRef {
  uri: string = '';
}

/** Stub-friendly contract. ScanBindingPage and LessonImagePicker both
 *  consume this; production wires `RealPhotoPickerAdapter`. */
export interface IPhotoPickerAdapter {
  /** Returns null on user cancel. */
  selectGallery(): Promise<PickedFileRef | null>;
}

/** Pull `AppStorage[overrideKey]` and trim whitespace; returns '' for
 *  any non-string / empty value or empty `overrideKey`. ohosTest writes
 *  the key (see `LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY` and
 *  `SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY`); production never does.
 *  Exported so unit tests can pin the parsing semantics without needing
 *  a UIAbilityContext. */
export function readPickerOverrideUri(overrideKey: string): string {
  if (overrideKey.length === 0) {
    return '';
  }
  const raw: string | undefined = AppStorage.get<string>(overrideKey);
  if (typeof raw !== 'string') {
    return '';
  }
  return raw.trim();
}

/** Production gallery-only adapter. The `overrideKey` constructor arg
 *  selects which AppStorage key short-circuits the system picker (lesson
 *  flow uses `LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY`; scan-binding flow
 *  uses `SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY`). Empty string
 *  disables the override (production-only behaviour). */
export class RealPhotoPickerAdapter implements IPhotoPickerAdapter {
  private ctx: common.UIAbilityContext;
  private overrideKey: string;

  constructor(ctx: common.UIAbilityContext, overrideKey: string) {
    this.ctx = ctx;
    this.overrideKey = overrideKey;
  }

  async selectGallery(): Promise<PickedFileRef | null> {
    const override: string = readPickerOverrideUri(this.overrideKey);
    if (override.length > 0) {
      const ref: PickedFileRef = new PickedFileRef();
      ref.uri = override;
      return ref;
    }
    const uri: string | null = await RealPhotoPickerAdapter.invokeGalleryPicker();
    if (uri === null) {
      return null;
    }
    const ref: PickedFileRef = new PickedFileRef();
    ref.uri = uri;
    return ref;
  }

  // Each underlying SDK call is wrapped in its own try/catch + re-throw
  // helper so ArkTS strict mode's "function may throw" diagnostic is
  // satisfied at every call site. The outer `invokeGalleryPicker` then
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
      console.error(`PhotoPickerService.invokeGalleryPicker failed: ${JSON.stringify(be)}`);
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
}
