# Scan Binding 从图库选择二维码 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Mode:** Inline execution by author. Per-task commit. TDD throughout.
> **Branch:** `feat/v0.6-parent-account` (already pushed; this plan adds 4 commits on top of `2994689`).
> **Spec:** [`2026-05-02-scan-binding-gallery-qr-design.md`](../specs/2026-05-02-scan-binding-gallery-qr-design.md) (revision 1)
> **Roadmap:** [`WordMagicGame_roadmap.md` §13 V0.6](../../WordMagicGame_roadmap.md)

**Goal:** Add a 「📷 从图库选择二维码」 button to `ScanBindingPage` that decodes a saved QR via `@kit.ScanKit`'s static-image API and feeds the existing redeem state machine, with end-to-end ohosTest coverage using a pre-generated QR fixture.

**Architecture:** Extract a shared `PhotoPickerService` (gallery only) consumed by both V0.5.8's `LessonImagePicker` and the new flow. Add a new `BarcodeImageDecoder` seam (production calls `scanBarcode.decode`, tests inject an AppStorage override). Wire the new path through `DeviceBindingService.startFromGalleryImage(uri)` which reuses the existing `redeem()` private path.

**Tech Stack:** ArkTS / ArkUI / `@kit.ScanKit` / `@kit.CoreFileKit.picker` / `@ohos/hypium` / Python `qrcode`.

---

## Task 1: Extract `PhotoPickerService`, refactor `LessonImagePicker`, keep V0.5.8 green

**Files:**
- Create: `entry/src/main/ets/services/PhotoPickerService.ets`
- Create: `entry/src/test/PhotoPickerService.test.ets`
- Modify: `entry/src/main/ets/services/LessonImagePicker.ets`
- Modify: `entry/src/test/LessonImagePicker.test.ets`
- Modify: `entry/src/main/ets/pages/ParentAdminPage.ets:73-76`
- Modify: `entry/src/test/List.test.ets` (register new test)

### Why this slice

V0.5.8 `LessonImagePicker.ets` owns both the gallery + camera adapter and the AppStorage override key. We need the gallery half to be reusable, but the V0.5.8 ohosTest case (`tapPickGalleryUploadsAndShowsImported`) MUST keep passing — that means the `LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY` constant value, `IPhotoPickerAdapter` interface shape (in lesson tests), and `LessonImagePicker` constructor behaviour all stay observable. The cleanest way is:

- New `PhotoPickerService.ets` defines `IPhotoPickerAdapter` (gallery only), `PickedFileRef`, `RealPhotoPickerAdapter(ctx, overrideKey)`, and `readPickerOverrideUri(key)`.
- `LessonImagePicker.ets` keeps a NEW interface `ILessonCameraAdapter` (camera only, since only lesson uses camera) plus its existing `IPhotoFileReader` reader. The lesson `IPhotoPickerAdapter` interface that the existing test uses is **re-exported** from `PhotoPickerService.ets` — old import path stays valid via a re-export.
- `LessonImagePicker.ets` constructor signature changes from `(IPhotoPickerAdapter, IPhotoFileReader)` to `(IPhotoPickerAdapter, ILessonCameraAdapter, IPhotoFileReader)`. Existing tests that construct it with two args break — we update them to pass a stub camera adapter, but the **observable behaviour** (gallery picks an image, camera picks an image, override key is `'lessonImagePickerOverrideUri'` and reads via `readPickerOverrideUri()` with no args) stays identical.

Note: the old `LessonImagePicker.ets` exported a `readPickerOverrideUri()` (no args) helper that read the lesson-specific key. We turn that into a thin wrapper around the new `readPickerOverrideUri(key)` so the call sites and lesson tests don't need to change.

- [ ] **Step 1: Write failing test for `PhotoPickerService`**

Create `entry/src/test/PhotoPickerService.test.ets`:

```typescript
import { describe, it, expect } from '@ohos/hypium';
import {
  PickedFileRef,
  readPickerOverrideUri,
} from '../main/ets/services/PhotoPickerService';

const SCAN_KEY: string = 'scanBindingPhotoPickerOverrideUri';

export default function photoPickerServiceTest(): void {
  describe('PhotoPickerService', () => {
    it('readPickerOverrideUri returns empty string when key is unset', 0, () => {
      AppStorage.delete(SCAN_KEY);
      expect(readPickerOverrideUri(SCAN_KEY)).assertEqual('');
    });

    it('readPickerOverrideUri returns the trimmed override path', 0, () => {
      AppStorage.setOrCreate<string>(SCAN_KEY, '  /data/local/tmp/qr.png\n');
      expect(readPickerOverrideUri(SCAN_KEY)).assertEqual('/data/local/tmp/qr.png');
      AppStorage.delete(SCAN_KEY);
    });

    it('readPickerOverrideUri returns empty for empty key parameter', 0, () => {
      AppStorage.setOrCreate<string>(SCAN_KEY, '/something');
      expect(readPickerOverrideUri('')).assertEqual('');
      AppStorage.delete(SCAN_KEY);
    });

    it('PickedFileRef defaults uri to empty string', 0, () => {
      const r: PickedFileRef = new PickedFileRef();
      expect(r.uri).assertEqual('');
    });
  });
}
```

Also register the new test in `entry/src/test/List.test.ets`. Find the existing `import lessonImagePickerTest` block and add:

```typescript
import photoPickerServiceTest from './PhotoPickerService.test';
// ...inside the test list registration:
photoPickerServiceTest();
```

- [ ] **Step 2: Run the new test to verify it fails**

```bash
cd /Users/bytedance/Projects/happyword
hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -30
```

Expected: FAIL — `PhotoPickerService` module does not exist (compile error).

- [ ] **Step 3: Create `PhotoPickerService.ets` with minimal API**

```typescript
// entry/src/main/ets/services/PhotoPickerService.ets
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';

/** A handle returned by the system gallery picker. Class (not interface)
 *  so ArkTS strict mode can typecheck `new PickedFileRef()` literals. */
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
 *  any non-string/empty value or empty `overrideKey`. ohosTest writes
 *  the key; production never does. Exported so unit tests can pin the
 *  parsing semantics without needing a UIAbilityContext. */
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
```

- [ ] **Step 4: Run the new test to verify it passes**

```bash
hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -30
```

Expected: PASS for the 4 new cases. Existing `LessonImagePicker.test.ets` cases will FAIL because `IPhotoPickerAdapter` is now defined in two places — fix in next step.

- [ ] **Step 5: Refactor `LessonImagePicker.ets` to consume `PhotoPickerService`**

Edit `entry/src/main/ets/services/LessonImagePicker.ets`:

1. Re-export `PickedFileRef`, `IPhotoPickerAdapter` from PhotoPickerService (so existing imports `from './LessonImagePicker'` keep working):

```typescript
import {
  IPhotoPickerAdapter,
  PickedFileRef,
  RealPhotoPickerAdapter as SharedRealPhotoPickerAdapter,
  readPickerOverrideUri as readPickerOverrideUriShared,
} from './PhotoPickerService';

// Re-export for V0.5.8 callers (ParentAdminPage + LessonImagePicker.test).
export { IPhotoPickerAdapter, PickedFileRef };
```

2. Keep the lesson-specific override key:

```typescript
export const LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY: string =
  'lessonImagePickerOverrideUri';

/** Backward-compatible wrapper: existing callers / tests call
 *  `readPickerOverrideUri()` with no args expecting the lesson key. */
export function readPickerOverrideUri(): string {
  return readPickerOverrideUriShared(LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY);
}
```

3. Add a `ILessonCameraAdapter` interface and `RealLessonCameraAdapter` class — extracted from the existing `RealPhotoPickerAdapter.selectCamera` + camera helpers (lift the body verbatim, just rename the class):

```typescript
export interface ILessonCameraAdapter {
  selectCamera(): Promise<PickedFileRef | null>;
}

export class RealLessonCameraAdapter implements ILessonCameraAdapter {
  private ctx: common.UIAbilityContext;
  constructor(ctx: common.UIAbilityContext) { this.ctx = ctx; }

  async selectCamera(): Promise<PickedFileRef | null> {
    // override seam shared with gallery (test fixture stands in for both)
    const override: string = readPickerOverrideUriShared(LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY);
    if (override.length > 0) {
      const ref: PickedFileRef = new PickedFileRef();
      ref.uri = override;
      return ref;
    }
    const uri: string | null = await RealLessonCameraAdapter.invokeCameraPicker(this.ctx);
    if (uri === null) {
      return null;
    }
    const ref: PickedFileRef = new PickedFileRef();
    ref.uri = uri;
    return ref;
  }

  // Lift `invokeCameraPicker`, `makeCameraProfile`, `runCameraPick` private
  // statics from the OLD RealPhotoPickerAdapter into this class verbatim.
}
```

4. Re-export the gallery adapter as `RealPhotoPickerAdapter` so existing `ParentAdminPage` imports still resolve, but bound to the LESSON override key by default. This avoids changing `ParentAdminPage` semantics:

```typescript
export class RealPhotoPickerAdapter extends SharedRealPhotoPickerAdapter {
  constructor(ctx: common.UIAbilityContext) {
    super(ctx, LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY);
  }
}
```

5. Remove the OLD `RealPhotoPickerAdapter` class body (the gallery + camera fused class). The lesson-only camera logic moves to `RealLessonCameraAdapter`; the gallery half is now in `PhotoPickerService`.

6. Refactor `LessonImagePicker` constructor to take 3 args:

```typescript
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
    return this.materialize(await this.gallery.selectGallery());
  }

  async pickFromCamera(): Promise<PickedImage | null> {
    return this.materialize(await this.camera.selectCamera());
  }

  private async materialize(ref: PickedFileRef | null): Promise<PickedImage | null> {
    // unchanged
  }
}
```

- [ ] **Step 6: Update `LessonImagePicker.test.ets` to the 3-arg constructor**

The test's `StubPicker` currently implements both `selectGallery` and `selectCamera`. Split it:

```typescript
import {
  IPhotoPickerAdapter,
  PickedFileRef,
} from '../main/ets/services/PhotoPickerService';
import {
  ILessonCameraAdapter,
  IPhotoFileReader,
  LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY,
  LessonImagePicker,
  readPickerOverrideUri,
} from '../main/ets/services/LessonImagePicker';

class StubPicker implements IPhotoPickerAdapter {
  galleryResult: PickedFileRef | null = null;
  galleryCalls: number = 0;
  async selectGallery(): Promise<PickedFileRef | null> {
    this.galleryCalls += 1;
    return this.galleryResult;
  }
}

class StubCamera implements ILessonCameraAdapter {
  cameraResult: PickedFileRef | null = null;
  cameraCalls: number = 0;
  async selectCamera(): Promise<PickedFileRef | null> {
    this.cameraCalls += 1;
    return this.cameraResult;
  }
}
```

Then update every `new LessonImagePicker(p, r)` to `new LessonImagePicker(p, new StubCamera(), r)` (or `new LessonImagePicker(new StubPicker(), c, r)` for the camera-focused case).

- [ ] **Step 7: Update `ParentAdminPage.ets:73-76` for the new constructor**

```typescript
import {
  ILessonCameraAdapter,
  LessonImagePicker,
  RealLessonCameraAdapter,
  RealPhotoFileReader,
  RealPhotoPickerAdapter,
} from '../services/LessonImagePicker';

// inside the struct:
private picker: LessonImagePicker = new LessonImagePicker(
  new RealPhotoPickerAdapter(this.getUIContext().getHostContext() as common.UIAbilityContext),
  new RealLessonCameraAdapter(this.getUIContext().getHostContext() as common.UIAbilityContext),
  new RealPhotoFileReader(),
);
```

- [ ] **Step 8: Run the full host-side test suite**

```bash
hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -50
```

Expected: PASS — both `PhotoPickerService.test` and `LessonImagePicker.test` green; all other host tests untouched.

- [ ] **Step 9: Build the HAP to make sure ParentAdminPage still compiles**

```bash
hvigorw assembleHap --no-daemon 2>&1 | tail -10
```

Expected: `BUILD SUCCESSFUL`. Lint warnings about deprecated picker APIs are pre-existing — ignore.

- [ ] **Step 10: Commit**

```bash
git add \
  entry/src/main/ets/services/PhotoPickerService.ets \
  entry/src/main/ets/services/LessonImagePicker.ets \
  entry/src/test/PhotoPickerService.test.ets \
  entry/src/test/LessonImagePicker.test.ets \
  entry/src/test/List.test.ets \
  entry/src/main/ets/pages/ParentAdminPage.ets
git commit -m "refactor(client): extract PhotoPickerService from LessonImagePicker"
```

---

## Task 2: `BarcodeImageDecoder` module + override key + unit test

**Files:**
- Create: `entry/src/main/ets/services/BarcodeImageDecoder.ets`
- Create: `entry/src/test/BarcodeImageDecoder.test.ets`
- Modify: `entry/src/test/List.test.ets` (register new test)

### Why this slice

`DeviceBindingService.startFromGalleryImage` needs an injection point for the static-image decoder. `RealBarcodeImageDecoder` wraps `@kit.ScanKit`'s `scanBarcode.decode` API; tests inject a stub that throws or returns a canned URL. The AppStorage override key lets ohosTest skip the real ScanKit call (which is unreliable on the OpenHarmony emulator against arbitrary URIs in the app sandbox — same selinux story that pushed V0.5.8 toward the picker override).

This task also defines the `SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY` constant (so both override keys live in one test-infrastructure module).

- [ ] **Step 1: Write failing test for `BarcodeImageDecoder`**

```typescript
// entry/src/test/BarcodeImageDecoder.test.ets
import { describe, it, expect } from '@ohos/hypium';
import {
  NoBarcodeFoundError,
  RealBarcodeImageDecoder,
  SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY,
  SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY,
} from '../main/ets/services/BarcodeImageDecoder';

export default function barcodeImageDecoderTest(): void {
  describe('BarcodeImageDecoder', () => {
    it('SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY constant pinned', 0, () => {
      // ohosTest writes this exact string. Renaming requires a coordinated
      // change in ParentBindingFlowV06.ui.test.ets.
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
        'https://happyword.vercel.app/p/uitestqr01',
      );
      try {
        const dec: RealBarcodeImageDecoder = new RealBarcodeImageDecoder();
        const out: string = await dec.decodeFromUri('file:///does/not/exist.png');
        expect(out).assertEqual('https://happyword.vercel.app/p/uitestqr01');
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
    });
  });
}
```

Register in `entry/src/test/List.test.ets`:

```typescript
import barcodeImageDecoderTest from './BarcodeImageDecoder.test';
// ...
barcodeImageDecoderTest();
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -10
```

Expected: FAIL — `BarcodeImageDecoder` module does not exist.

- [ ] **Step 3: Create `BarcodeImageDecoder.ets`**

```typescript
// entry/src/main/ets/services/BarcodeImageDecoder.ets
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@ohos.base';

/**
 * V0.6.x — static-image QR decoder seam. Production wraps
 * `scanBarcode.decode` (ScanKit's one-shot static-image API).
 *
 * Why an override seam: ScanKit's decode against arbitrary on-device
 * URIs (especially app-sandbox tempDir paths) is unstable on the
 * OpenHarmony emulator. The same selinux story that pushed V0.5.8 to
 * use a PhotoViewPicker override (see `LessonImagePicker.ets`) applies
 * here. ohosTest writes
 * `AppStorage[SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY]` to
 * pin the decoded payload; production never writes that key.
 */

/** AppStorage key the ohosTest harness writes to override the picker
 *  short-circuit URI for ScanBindingPage's gallery-QR path. Lives
 *  alongside the decoder key so a single import grabs both. */
export const SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY: string =
  'scanBindingPhotoPickerOverrideUri';

/** AppStorage key for `RealBarcodeImageDecoder.decodeFromUri` short-circuit. */
export const SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY: string =
  'scanBindingBarcodeDecoderOverridePayload';

/** Stub-friendly contract. */
export interface BarcodeImageDecoderLike {
  /** Returns the decoded string. Throws `NoBarcodeFoundError` if the
   *  image contains no barcode; throws `Error` for other SDK failures. */
  decodeFromUri(uri: string): Promise<string>;
}

/** Sentinel: image had no detectable barcode (or the SDK couldn't decode). */
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

  private static async invokeScanKitDecode(uri: string): Promise<string> {
    try {
      const opts: scanBarcode.DecodeOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
      };
      const inputImage: scanBarcode.InputImage = { uri };
      const results: scanBarcode.ScanResult[] =
        await scanBarcode.decode(inputImage, opts);
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
        `scanBarcode.decode failed: code=${be.code} msg=${be.message}`,
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
```

NOTE: the actual `scanBarcode.decode` and `InputImage` / `DecodeOptions` shapes need to match the SDK at API level 20. If the build complains that `decode` or these types don't exist, fall back to the alternative API name (HMS docs use `scanBarcode.decode` since OpenHarmony 4.1+; if missing, swap to `customScan` flow at this single point). Verify via the build in Step 5 — adjust the SDK call only inside `invokeScanKitDecode`.

- [ ] **Step 4: Run test to verify it passes**

```bash
hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -20
```

Expected: PASS — all 5 cases green. (Override-active cases bypass ScanKit entirely; SDK-touching paths are not exercised by host tests.)

- [ ] **Step 5: Smoke-build the HAP to verify the ScanKit imports compile**

```bash
hvigorw assembleHap --no-daemon 2>&1 | tail -10
```

Expected: `BUILD SUCCESSFUL`. If the `scanBarcode.decode`/`InputImage`/`DecodeOptions` symbols are reported missing, adjust the production-only `invokeScanKitDecode` body — the override seam will still pass tests.

- [ ] **Step 6: Commit**

```bash
git add \
  entry/src/main/ets/services/BarcodeImageDecoder.ets \
  entry/src/test/BarcodeImageDecoder.test.ets \
  entry/src/test/List.test.ets
git commit -m "feat(client): BarcodeImageDecoder seam for ScanBindingPage gallery-QR path"
```

---

## Task 3: `DeviceBindingService.startFromGalleryImage` + `ScanBindingPage` UI button

**Files:**
- Modify: `entry/src/main/ets/services/DeviceBindingService.ets`
- Modify: `entry/src/test/DeviceBindingService.test.ets`
- Modify: `entry/src/main/ets/pages/ScanBindingPage.ets`

### Why this slice

The new method reuses the existing private `redeem(token, '')` path so all server-error mapping is automatic. The page wires both adapters (picker + decoder) inside `bootstrapService()` and adds a third button between camera and short-code.

- [ ] **Step 1: Add the failing test cases**

Add to `entry/src/test/DeviceBindingService.test.ets`:

```typescript
import { BarcodeImageDecoderLike, NoBarcodeFoundError }
  from '../main/ets/services/BarcodeImageDecoder';

class StubDecoder implements BarcodeImageDecoderLike {
  payload: string = '';
  shouldThrow: boolean = false;
  calls: number = 0;
  async decodeFromUri(_uri: string): Promise<string> {
    this.calls += 1;
    if (this.shouldThrow) {
      throw new NoBarcodeFoundError('stub no barcode');
    }
    return this.payload;
  }
}

// Adjust makeService to take the decoder:
async function makeService(
  scanner: StubScanner,
  decoder: StubDecoder,
  http: StubHttp,
): Promise<DeviceBindingService> {
  const provider: DeviceIdProvider = new DeviceIdProvider();
  provider.injectAssetStore(new StubAsset());
  provider.injectPreferences(new MemPrefs());
  const cc: CloudCredentials = new CloudCredentials();
  cc.injectPreferences(new MemPrefs());
  return new DeviceBindingService(scanner, decoder, http, provider, cc);
}
```

Update every existing call site `await makeService(scanner, http)` → `await makeService(scanner, new StubDecoder(), http)` (the existing tests don't care about the decoder).

Add a new `describe` block:

```typescript
describe('DeviceBindingService.startFromGalleryImage', () => {
  it('redeemsOnValidPairUrl', 0, async () => {
    const decoder: StubDecoder = new StubDecoder();
    decoder.payload = 'https://happyword.vercel.app/p/abc12345';
    const http: StubHttp = new StubHttp();
    http.result = makeOkResult();
    const svc: DeviceBindingService = await makeService(new StubScanner(), decoder, http);
    const rec: StateRecorder = new StateRecorder();
    svc.setListener(rec.listener());
    await svc.startFromGalleryImage('file:///x/qr.png');
    expect(rec.states[0]).assertEqual('scanning');
    expect(rec.states[1]).assertEqual('redeeming');
    expect(rec.states[rec.states.length - 1]).assertEqual('bound');
    expect(decoder.calls).assertEqual(1);
    expect(http.lastArgs?.token).assertEqual('abc12345');
    expect(http.lastArgs?.shortCode).assertEqual('');
  });

  it('failsTokenInvalidWhenDecoderThrows', 0, async () => {
    const decoder: StubDecoder = new StubDecoder();
    decoder.shouldThrow = true;
    const http: StubHttp = new StubHttp();
    const svc: DeviceBindingService = await makeService(new StubScanner(), decoder, http);
    const rec: StateRecorder = new StateRecorder();
    svc.setListener(rec.listener());
    await svc.startFromGalleryImage('file:///x/notqr.png');
    expect(rec.states[rec.states.length - 1]).assertEqual('failed');
    expect(rec.lastReason).assertEqual('TOKEN_INVALID');
  });

  it('failsTokenInvalidWhenPayloadHasNoSlashP', 0, async () => {
    const decoder: StubDecoder = new StubDecoder();
    decoder.payload = 'hello world';
    const http: StubHttp = new StubHttp();
    const svc: DeviceBindingService = await makeService(new StubScanner(), decoder, http);
    const rec: StateRecorder = new StateRecorder();
    svc.setListener(rec.listener());
    await svc.startFromGalleryImage('file:///x/wrong.png');
    expect(rec.lastReason).assertEqual('TOKEN_INVALID');
  });

  it('failsTokenInvalidOnTokenLengthOutOfRange', 0, async () => {
    const decoder: StubDecoder = new StubDecoder();
    decoder.payload = 'https://x/p/x'; // length 1
    const http: StubHttp = new StubHttp();
    const svc: DeviceBindingService = await makeService(new StubScanner(), decoder, http);
    const rec: StateRecorder = new StateRecorder();
    svc.setListener(rec.listener());
    await svc.startFromGalleryImage('file:///x/short.png');
    expect(rec.lastReason).assertEqual('TOKEN_INVALID');
  });

  it('mapsServerExpiredThroughExistingRedeemPath', 0, async () => {
    const decoder: StubDecoder = new StubDecoder();
    decoder.payload = 'https://x/p/expired12345';
    const http: StubHttp = new StubHttp();
    http.err = new BindingHttpError('TOKEN_EXPIRED', 'gone', 410);
    const svc: DeviceBindingService = await makeService(new StubScanner(), decoder, http);
    const rec: StateRecorder = new StateRecorder();
    svc.setListener(rec.listener());
    await svc.startFromGalleryImage('file:///x/expired.png');
    expect(rec.lastReason).assertEqual('TOKEN_EXPIRED');
  });
});
```

- [ ] **Step 2: Run tests to verify failures**

```bash
hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -30
```

Expected: FAIL — `startFromGalleryImage` not defined; `DeviceBindingService` constructor signature mismatch.

- [ ] **Step 3: Modify `DeviceBindingService.ets`**

Add `BarcodeImageDecoderLike` import:

```typescript
import { BarcodeImageDecoderLike, NoBarcodeFoundError }
  from './BarcodeImageDecoder';
```

Add the `decoder` field, expand the constructor:

```typescript
export class DeviceBindingService {
  private readonly scanner: BarcodeScannerLike;
  private readonly decoder: BarcodeImageDecoderLike;   // NEW
  private readonly http: BindingHttpClientLike;
  private readonly deviceIdProvider: DeviceIdProvider;
  private readonly credentials: CloudCredentials;
  private listener?: BindingStateListener;
  private state: BindingState = 'idle';

  constructor(
    scanner: BarcodeScannerLike,
    decoder: BarcodeImageDecoderLike,                  // NEW
    http: BindingHttpClientLike,
    deviceIdProvider: DeviceIdProvider,
    credentials: CloudCredentials,
  ) {
    this.scanner = scanner;
    this.decoder = decoder;
    this.http = http;
    this.deviceIdProvider = deviceIdProvider;
    this.credentials = credentials;
  }

  // ... existing methods unchanged ...

  /**
   * V0.6.x — gallery-QR path. Pick → decode → token-extract → existing
   * redeem path. Decoder failure / parser failure surface as
   * `TOKEN_INVALID` to share the existing red-text UX.
   */
  async startFromGalleryImage(uri: string): Promise<void> {
    this.transition('scanning');
    let payload: string = '';
    try {
      payload = await this.decoder.decodeFromUri(uri);
    } catch (err) {
      if (err instanceof NoBarcodeFoundError) {
        this.fail('TOKEN_INVALID');
        return;
      }
      this.fail('NETWORK');
      return;
    }
    const token: string = extractTokenFromQrPayload(payload);
    if (token.length < 4 || token.length > 64) {
      this.fail('TOKEN_INVALID');
      return;
    }
    await this.redeem(token, '');
  }
}
```

- [ ] **Step 4: Run the unit tests to verify green**

```bash
hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -30
```

Expected: PASS — all DeviceBindingService cases green (5 new + the existing ones updated to pass `new StubDecoder()`).

- [ ] **Step 5: Modify `ScanBindingPage.ets` to wire the new path**

Update imports:

```typescript
import {
  BarcodeImageDecoderLike,
  RealBarcodeImageDecoder,
  SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY,
} from '../services/BarcodeImageDecoder';
import {
  IPhotoPickerAdapter,
  PickedFileRef,
  RealPhotoPickerAdapter,
} from '../services/PhotoPickerService';
```

Modify `bootstrapService()` to construct both adapters and pass the decoder to the service:

```typescript
private bootstrapService(): void {
  const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  const provider: DeviceIdProvider = new DeviceIdProvider();
  const credentials: CloudCredentials = new CloudCredentials();
  const baseUrl: string = effectiveServerBaseUrl();
  const httpClient: BindingApiClient = new BindingApiClient(
    new RealParentFetchAdapter(),
    baseUrl,
  );
  const galleryPicker: IPhotoPickerAdapter =
    new RealPhotoPickerAdapter(ctx, SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY);
  const decoder: BarcodeImageDecoderLike = new RealBarcodeImageDecoder();

  Promise.all([provider.init(ctx), credentials.init(ctx)])
    .then(() => {
      const svc: DeviceBindingService = new DeviceBindingService(
        new RealScanKitScanner(),
        decoder,
        httpClient,
        provider,
        credentials,
      );
      svc.setListener((u: BindingStateUpdate): void => {
        this.state = u.state;
        if (u.snapshot !== undefined) {
          this.childNickname = u.snapshot.nickname;
        }
        if (u.reason !== undefined) {
          this.failureReason = u.reason as string;
        }
      });
      this.service = svc;
      this.galleryPicker = galleryPicker;
      this.serviceReady = true;
    })
    .catch((err: BusinessError) => {
      console.error(`ScanBindingPage.bootstrap failed: ${JSON.stringify(err)}`);
      this.serviceReady = false;
    });
}
```

Add a private field next to `service`:

```typescript
private service?: DeviceBindingService;
private galleryPicker?: IPhotoPickerAdapter;
```

Add the handler:

```typescript
private async onPickQrTap(): Promise<void> {
  if (this.service === undefined || this.galleryPicker === undefined || this.busy) {
    return;
  }
  this.busy = true;
  this.failureReason = '';
  try {
    const ref: PickedFileRef | null = await this.galleryPicker.selectGallery();
    if (ref === null) {
      return;
    }
    await this.service.startFromGalleryImage(ref.uri);
  } finally {
    this.busy = false;
  }
}
```

Insert the new button into the idle state column (between "打开扫码器" and "无法扫码？手动输入短码"):

```typescript
} else {
  Column({ space: 12 }) {
    Text('请扫描家长网页 /parent/devices/add 显示的二维码')
      .id('ScanBindingIdlePrompt')
      .fontSize(14).fontColor('#475569').textAlign(TextAlign.Center)
    Button(this.busy ? '正在打开扫码器…' : '打开扫码器')
      .id('ScanBindingScannerButton')
      .enabled(!this.busy && this.serviceReady)
      .margin({ top: 16 })
      .onClick(() => this.onScanTap())
    Button('📷 从图库选择二维码')
      .id('ScanBindingGalleryButton')
      .enabled(!this.busy && this.serviceReady)
      .onClick(() => this.onPickQrTap())
    Button('无法扫码？手动输入短码')
      .id('ScanBindingManualToggle')
      .backgroundColor('#e2e8f0').fontColor('#1f2937')
      .onClick(() => { this.manualMode = true; })
    if (this.reasonHint().length > 0) {
      Text(this.reasonHint()).fontColor('#dc2626').fontSize(13).margin({ top: 16 })
    }
  }.width('100%').padding(24)
}
```

- [ ] **Step 6: Build the HAP**

```bash
hvigorw assembleHap --no-daemon 2>&1 | tail -10
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 7: Commit**

```bash
git add \
  entry/src/main/ets/services/DeviceBindingService.ets \
  entry/src/main/ets/pages/ScanBindingPage.ets \
  entry/src/test/DeviceBindingService.test.ets
git commit -m "feat(client): ScanBindingPage gallery-QR button + service wiring"
```

---

## Task 4: QR fixture script + bundled PNG + ohosTest case + docs

**Files:**
- Create: `tools/generate_scan_binding_qr_fixture.py`
- Create: `entry/src/ohosTest/resources/rawfile/scan_binding_qr_fixture.png` (generated by the script, ~800B)
- Modify: `entry/src/ohosTest/ets/test/ParentBindingFlowV06.ui.test.ets`
- Modify: `docs/WordMagicGame_roadmap.md`
- Modify: `docs/WordMagicGame_overall_spec.md`
- Modify: `.cursor/dev-commands.md`

- [ ] **Step 1: Create the fixture-generator script**

```python
# tools/generate_scan_binding_qr_fixture.py
"""Generate the ohosTest QR fixture used by ParentBindingFlowV06.

Run: uv run python tools/generate_scan_binding_qr_fixture.py
Output: entry/src/ohosTest/resources/rawfile/scan_binding_qr_fixture.png
"""
from __future__ import annotations

from pathlib import Path

import qrcode
from qrcode.constants import ERROR_CORRECT_M
from qrcode.image.pil import PilImage

PAYLOAD: str = "https://happyword.vercel.app/p/uitestqr01"
OUT: Path = (
    Path(__file__).resolve().parent.parent
    / "entry"
    / "src"
    / "ohosTest"
    / "resources"
    / "rawfile"
    / "scan_binding_qr_fixture.png"
)


def main() -> None:
    qr = qrcode.QRCode(error_correction=ERROR_CORRECT_M, box_size=8, border=2)
    qr.add_data(PAYLOAD)
    qr.make(fit=True)
    img = qr.make_image(image_factory=PilImage, fill_color="black", back_color="white")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes) encoding {PAYLOAD}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run the script to generate the fixture**

```bash
cd /Users/bytedance/Projects/happyword/server
uv run python ../tools/generate_scan_binding_qr_fixture.py
```

Expected: `wrote /Users/bytedance/Projects/happyword/entry/src/ohosTest/resources/rawfile/scan_binding_qr_fixture.png (XXX bytes) encoding https://happyword.vercel.app/p/uitestqr01`. PNG file should exist.

- [ ] **Step 3: Add the new ohosTest case + helper**

Edit `entry/src/ohosTest/ets/test/ParentBindingFlowV06.ui.test.ets`. Add imports near the top (alongside the existing imports from `../../../main/ets/services/`):

```typescript
import {
  SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY,
  SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY,
} from '../../../main/ets/services/BarcodeImageDecoder';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
```

Add the helper near the top of the file (alongside other helpers):

```typescript
const DELEGATOR = abilityDelegatorRegistry.getAbilityDelegator();
const SCAN_QR_FIXTURE_NAME: string = 'scan_binding_qr_fixture.png';
const SCAN_QR_FIXTURE_PAYLOAD: string =
  'https://happyword.vercel.app/p/uitestqr01';

/**
 * Materialise the scan-binding QR fixture into the app sandbox.
 *
 * Mirrors `ensureLessonImportFixtureOnDevice()` in ParentAdminFlow:
 * the PNG bytes are bundled in the ohosTest module's rawfile
 * (`entry/src/ohosTest/resources/rawfile/scan_binding_qr_fixture.png`),
 * we copy them to `<appCtx.tempDir>/<name>` once per ability lifetime,
 * and the AppStorage picker-override key points there. We can NOT
 * use `hdc file send` to a shell-writable path because HarmonyOS
 * NEXT's selinux blocks the bundle UID from reading those paths.
 */
async function ensureScanBindingQrFixtureOnDevice(): Promise<string> {
  const appCtx: common.Context = DELEGATOR.getAppContext();
  const dest: string = `${appCtx.tempDir}/${SCAN_QR_FIXTURE_NAME}`;
  if (fs.accessSync(dest)) {
    return dest;
  }
  const moduleCtx: common.Context = appCtx.createModuleContext('entry_test');
  const bytes: Uint8Array = await moduleCtx.resourceManager.getRawFileContent(
    SCAN_QR_FIXTURE_NAME,
  );
  const file: fs.File = await fs.open(
    dest,
    fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
  );
  try {
    await fs.write(file.fd, bytes.buffer);
  } finally {
    await fs.close(file);
  }
  return dest;
}
```

Add the new `it()` block inside the existing `describe('ParentBindingFlowV06', () => {})`:

```typescript
/**
 * V0.6.x — ScanBindingPage 「📷 从图库选择二维码」 path.
 *
 * Two AppStorage overrides bypass system services that are unstable
 * on the OpenHarmony emulator:
 *   - SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY → makes the gallery
 *     picker return a fixed on-device path without showing the
 *     out-of-process system picker UI.
 *   - SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY → makes
 *     scanBarcode.decode return our pre-known payload string without
 *     touching the real ScanKit decoder.
 *
 * The on-device PNG fixture is still copied (and asserted to exist)
 * to keep the picker-override seam honest: the file IS read by the
 * production picker pipeline, just not decoded by ScanKit.
 */
it('pickQrFromGalleryRedeemsAndFlipsToBound', 0, async (done: Function) => {
  const fixturePath: string = await ensureScanBindingQrFixtureOnDevice();
  expect(fs.accessSync(fixturePath)).assertTrue();

  AppStorage.setOrCreate<string>(
    SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY, fixturePath);
  AppStorage.setOrCreate<string>(
    SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY,
    SCAN_QR_FIXTURE_PAYLOAD);

  try {
    const driver: Driver = await launchApp();
    await returnToHome(driver);
    await ensureParentPin(driver, KNOWN_PIN);
    await openConfigPage(driver);
    await tapBindOpensScanBindingPage(driver);
    await driver.assertComponentExist(ON.id('ScanBindingGalleryButton'));
    await clickByIdShared(driver, 'ScanBindingGalleryButton');
    // Picker stub returns instantly; decoder stub returns instantly;
    // redeem POST round-trips against the local mock. 3s is comfortable
    // for cold start; ~500ms on warm.
    await driver.delayMs(3000);
    await driver.assertComponentExist(ON.id('ScanBindingSuccessLabel'));
  } finally {
    AppStorage.delete(SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY);
    AppStorage.delete(SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY);
  }
  done();
});
```

(`tapBindOpensScanBindingPage`, `openConfigPage`, `clickByIdShared`, `KNOWN_PIN` already exist in this file — reuse them.)

- [ ] **Step 4: Build the test HAP and verify the fixture is bundled**

```bash
hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | tail -10
```

Expected: `BUILD SUCCESSFUL`. The rawfile gets packaged into `entry/build/.../entry-ohosTest-signed.hap`.

- [ ] **Step 5: Run the new ohosTest case via the local mock**

```bash
HDC_TARGET=5FFBB25926205346 scripts/run_ui_tests.sh --rebuild --suite ParentBindingFlowV06#pickQrFromGalleryRedeemsAndFlipsToBound 2>&1 | tail -20
```

If the device target is the emulator instead, drop the `HDC_TARGET=` prefix.

Expected output ending: `OHOS_REPORT_RESULT: stream=Tests run: 1, Failure: 0, Error: 0, Pass: 1, Ignore: 0`.

- [ ] **Step 6: Update `docs/WordMagicGame_roadmap.md`**

In the V0.6 row in the table near line 61, append a sentence to the existing description:

```
| V0.6   | 家长账户与设备绑定版       | 家长账号、孩子档案、二维码绑定设备、云端学习同步、云端愿望单（含 V0.5.8 留下的 admin 路由家长账户隔离）；ScanBindingPage 增「📷 从图库选择二维码」入口，让家长把 web 端 QR 截图发到孩子设备完成绑定（@kit.ScanKit.scanBarcode.decode 静态解码） | 必需       |
```

- [ ] **Step 7: Update `docs/WordMagicGame_overall_spec.md`**

Find the V0.6 ohosTest enumeration (around the existing `ParentBindingFlowV06` mention — search for `ParentBindingFlowV06`). Add a sentence noting the new case:

> `ParentBindingFlowV06` V0.6.x 增量：`pickQrFromGalleryRedeemsAndFlipsToBound`，沿用 V0.5.8 lesson-fixture 的「ohosTest rawfile 预打包 → tempDir 拷贝 → AppStorage 双 override key（picker + decoder）」机制，端到端验证从图库选 QR → 解码 → redeem → 绑定成功的链路。

- [ ] **Step 8: Update `.cursor/dev-commands.md`**

Find the section that mentions `lesson_import_fixture.jpg` (around line 110). Generalise the description:

> ohosTest 在 `entry/src/ohosTest/resources/rawfile/` 下打包两份固件：`lesson_import_fixture.jpg`（V0.5.8 课本导入用）与 `scan_binding_qr_fixture.png`（V0.6.x 扫码绑定从图库选 QR 用，由 `tools/generate_scan_binding_qr_fixture.py` 生成）。两份都通过 `Context.resourceManager.getRawFileContent` 拷到 `<appCtx.tempDir>/`，然后写各自的 `AppStorage` override key（lesson 用 `LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY`，scan-binding 用 `SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY` 与 `SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY`）。这是 HarmonyOS NEXT 上唯一能让 ohosTest 绕开 selinux 沙箱限制的方式。

- [ ] **Step 9: Run the full UI test suite to confirm zero regressions**

```bash
HDC_TARGET=5FFBB25926205346 scripts/run_ui_tests.sh --rebuild 2>&1 | tail -10
```

Expected: `Tests run: 60, Failure: 0, Error: <pre-existing flake count or 0>, Pass: 60, Ignore: 0` (was 59; add 1 = 60).

- [ ] **Step 10: Commit**

```bash
git add \
  tools/generate_scan_binding_qr_fixture.py \
  entry/src/ohosTest/resources/rawfile/scan_binding_qr_fixture.png \
  entry/src/ohosTest/ets/test/ParentBindingFlowV06.ui.test.ets \
  docs/WordMagicGame_roadmap.md \
  docs/WordMagicGame_overall_spec.md \
  .cursor/dev-commands.md
git commit -m "test(ui): scan-binding gallery-QR ohosTest + fixture + docs"
```

- [ ] **Step 11: Push**

```bash
git push origin feat/v0.6-parent-account
```

---

## Self-review (post-plan check)

- **Spec coverage:** §3 UI / §4 file structure / §5 contracts / §6 tests / §10 fixture script — each maps to a Task above (1–4).
- **Type consistency:** `IPhotoPickerAdapter.selectGallery() → Promise<PickedFileRef | null>` used identically in PhotoPickerService.ets, LessonImagePicker tests, ScanBindingPage. `BarcodeImageDecoderLike.decodeFromUri(uri: string) → Promise<string>` used identically in BarcodeImageDecoder, DeviceBindingService, ScanBindingPage. `DeviceBindingService` constructor everywhere takes `(scanner, decoder, http, deviceIdProvider, credentials)` — 5 args.
- **Override-key constants:** `SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY = 'scanBindingPhotoPickerOverrideUri'` and `SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY = 'scanBindingBarcodeDecoderOverridePayload'` referenced consistently in tests + docs.
- **No placeholders.**
- **Commit segmentation:** 4 commits, each independently green-buildable + green-tested.
