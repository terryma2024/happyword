import { describe, it, expect } from '@ohos/hypium';
import {
  DevMenuToolEntry,
  devMenuToolEntries,
} from '../main/ets/services/DevMenuToolEntries';

export default function devMenuToolEntriesTest(): void {
  describe('DevMenuToolEntries', () => {
    it('ordersDomainSwitchAudioLabAndMessageBubbleLabAsPeerEntries', 0, () => {
      const entries: DevMenuToolEntry[] = devMenuToolEntries();

      expect(entries.length).assertEqual(4);

      expect(entries[0].id).assertEqual('DevMenuDomainSwitchButton');
      expect(entries[0].title).assertEqual('Domain Switch');
      expect(entries[0].route).assertEqual('pages/DomainSwitchPage');

      expect(entries[1].id).assertEqual('DevMenuAudioLabButton');
      expect(entries[1].title).assertEqual('PcmAudioLab');
      expect(entries[1].route).assertEqual('pages/AudioLabPage');

      expect(entries[2].id).assertEqual('DevMenuMessageBubbleLabButton');
      expect(entries[2].title).assertEqual('MessageBubbleLab');
      expect(entries[2].route).assertEqual('pages/MessageBubbleLabPage');

      expect(entries[3].id).assertEqual('DevMenuCocosLabButton');
      expect(entries[3].title).assertEqual('CocosLab');
      expect(entries[3].route).assertEqual('pages/CocosBattlePage');
    });
  });
}
