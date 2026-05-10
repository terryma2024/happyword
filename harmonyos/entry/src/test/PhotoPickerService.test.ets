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
