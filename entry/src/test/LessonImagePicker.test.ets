import { describe, it, expect } from '@ohos/hypium';
import {
  IPhotoFileReader,
  IPhotoPickerAdapter,
  LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY,
  LessonImagePicker,
  PickedFileRef,
  readPickerOverrideUri,
} from '../main/ets/services/LessonImagePicker';
import { PickedImage } from '../main/ets/services/ParentApiClient';

class StubPicker implements IPhotoPickerAdapter {
  galleryResult: PickedFileRef | null = null;
  cameraResult: PickedFileRef | null = null;
  galleryCalls: number = 0;
  cameraCalls: number = 0;

  async selectGallery(): Promise<PickedFileRef | null> {
    this.galleryCalls += 1;
    return this.galleryResult;
  }

  async selectCamera(): Promise<PickedFileRef | null> {
    this.cameraCalls += 1;
    return this.cameraResult;
  }
}

class StubReader implements IPhotoFileReader {
  bytes: ArrayBuffer = new ArrayBuffer(3);
  size: number = 3;

  constructor() {
    const view: Uint8Array = new Uint8Array(this.bytes);
    view[0] = 0xff;
    view[1] = 0xd8;
    view[2] = 0xff;
  }

  async readAsArrayBuffer(_uri: string): Promise<ArrayBuffer> {
    return this.bytes;
  }

  async sizeOf(_uri: string): Promise<number> {
    return this.size;
  }
}

function makeRef(uri: string): PickedFileRef {
  const r: PickedFileRef = new PickedFileRef();
  r.uri = uri;
  return r;
}

export default function lessonImagePickerTest(): void {
  describe('LessonImagePicker', () => {
    it('pickFromGallery returns null on user cancel', 0, async () => {
      const p: StubPicker = new StubPicker();
      const r: StubReader = new StubReader();
      const lp: LessonImagePicker = new LessonImagePicker(p, r);
      const out: PickedImage | null = await lp.pickFromGallery();
      expect(out === null).assertTrue();
      expect(p.galleryCalls).assertEqual(1);
    });

    it('pickFromGallery returns PickedImage on success with sniffed mime', 0, async () => {
      const p: StubPicker = new StubPicker();
      p.galleryResult = makeRef('file:///x/lesson.jpg');
      const r: StubReader = new StubReader();
      const lp: LessonImagePicker = new LessonImagePicker(p, r);
      const out: PickedImage | null = await lp.pickFromGallery();
      expect(out !== null).assertTrue();
      if (out !== null) {
        expect(out.mime).assertEqual('image/jpeg');
        expect(out.filename).assertEqual('lesson.jpg');
        expect(out.sizeBytes).assertEqual(3);
        expect(out.bytes.byteLength).assertEqual(3);
      }
    });

    it('pickFromCamera sniffs png from .png extension', 0, async () => {
      const p: StubPicker = new StubPicker();
      p.cameraResult = makeRef('file:///x/page.png');
      const r: StubReader = new StubReader();
      const lp: LessonImagePicker = new LessonImagePicker(p, r);
      const out: PickedImage | null = await lp.pickFromCamera();
      expect(out !== null).assertTrue();
      if (out !== null) {
        expect(out.mime).assertEqual('image/png');
      }
    });

    it('pickFromGallery returns null for unsupported extension', 0, async () => {
      const p: StubPicker = new StubPicker();
      p.galleryResult = makeRef('file:///x/doc.pdf');
      const r: StubReader = new StubReader();
      const lp: LessonImagePicker = new LessonImagePicker(p, r);
      const out: PickedImage | null = await lp.pickFromGallery();
      expect(out === null).assertTrue();
    });

    it('uri without slash uses raw uri as filename', 0, async () => {
      const p: StubPicker = new StubPicker();
      p.galleryResult = makeRef('lesson.webp');
      const r: StubReader = new StubReader();
      const lp: LessonImagePicker = new LessonImagePicker(p, r);
      const out: PickedImage | null = await lp.pickFromGallery();
      expect(out !== null).assertTrue();
      if (out !== null) {
        expect(out.filename).assertEqual('lesson.webp');
        expect(out.mime).assertEqual('image/webp');
      }
    });

    it('case-insensitively recognizes .JPEG', 0, async () => {
      const p: StubPicker = new StubPicker();
      p.galleryResult = makeRef('file:///x/Photo.JPEG');
      const r: StubReader = new StubReader();
      const lp: LessonImagePicker = new LessonImagePicker(p, r);
      const out: PickedImage | null = await lp.pickFromGallery();
      expect(out !== null).assertTrue();
      if (out !== null) {
        expect(out.mime).assertEqual('image/jpeg');
      }
    });

    /**
     * V0.5.8 ohosTest harness: AppStorage[LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY]
     * carries the on-device path of a fixture image pushed by
     * `scripts/run_ui_tests.sh` via `hdc file send`. The
     * `readPickerOverrideUri` helper is the ONE source of truth that
     * `RealPhotoPickerAdapter.{selectGallery,selectCamera}` consult
     * before invoking the system PhotoViewPicker / cameraPicker.
     *
     * We pin the key string and the parse semantics here because:
     *   - the key is shared with the ohosTest harness in
     *     `entry/src/ohosTest/ets/test/List.test.ets` — a typo / rename
     *     would silently fall back to the real system picker and the
     *     UI tests would freeze at the dialog;
     *   - whitespace trimming matters because hdc-driven shell scripts
     *     occasionally append trailing newlines when piping a path.
     */
    it('readPickerOverrideUri returns empty string when key is unset', 0, () => {
      AppStorage.delete(LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY);
      expect(readPickerOverrideUri()).assertEqual('');
    });

    it('readPickerOverrideUri returns the trimmed override path', 0, () => {
      AppStorage.setOrCreate<string>(
        LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY,
        '  /data/local/tmp/lesson_import_fixture.jpg\n',
      );
      expect(readPickerOverrideUri())
        .assertEqual('/data/local/tmp/lesson_import_fixture.jpg');
      AppStorage.delete(LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY);
      expect(readPickerOverrideUri()).assertEqual('');
    });

    it('LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY is the documented constant', 0, () => {
      // ohosTest harness writes this exact string. Renaming the key
      // requires a coordinated change across List.test.ets + this test.
      expect(LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY)
        .assertEqual('lessonImagePickerOverrideUri');
    });
  });
}
