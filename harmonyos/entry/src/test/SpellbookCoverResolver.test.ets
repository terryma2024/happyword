import { describe, it, expect } from '@ohos/hypium';
import { Pack } from '../main/ets/models/Pack';
import {
  DEFAULT_SPELLBOOK_COVER_ASSET,
  SpellbookCoverSource,
  SpellbookCoverSourceKind,
  spellbookCoverSourceForPack,
} from '../main/ets/services/SpellbookCoverResolver';

function pack(id: string, source: 'builtin' | 'global' | 'family'): Pack {
  const p: Pack = new Pack();
  p.id = id;
  p.source = source;
  return p;
}

export default function spellbookCoverResolverTest(): void {
  describe('SpellbookCoverResolver', () => {
    it('uses bundled cover for known builtin pack id', 0, () => {
      const source: SpellbookCoverSource = spellbookCoverSourceForPack(pack('fruit-forest', 'builtin'));
      expect(source.kind).assertEqual(SpellbookCoverSourceKind.Rawfile);
      expect(source.value).assertEqual('spellbook_covers/fruit-forest.png');
    });

    it('uses remote cover url for non-builtin pack when present', 0, () => {
      const p: Pack = pack('family-pack', 'family');
      p.scene.spellbookCoverUrl = 'https://blob.example/covers/family.png';
      const source: SpellbookCoverSource = spellbookCoverSourceForPack(p);
      expect(source.kind).assertEqual(SpellbookCoverSourceKind.RemoteUrl);
      expect(source.value).assertEqual('https://blob.example/covers/family.png');
    });

    it('falls back to default cover for unknown pack without remote url', 0, () => {
      const source: SpellbookCoverSource = spellbookCoverSourceForPack(pack('custom-pack', 'family'));
      expect(source.kind).assertEqual(SpellbookCoverSourceKind.Rawfile);
      expect(source.value).assertEqual(DEFAULT_SPELLBOOK_COVER_ASSET);
    });
  });
}
