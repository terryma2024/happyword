import { Pack } from '../models/Pack';

export enum SpellbookCoverSourceKind {
  Rawfile = 'rawfile',
  RemoteUrl = 'remoteUrl',
}

export class SpellbookCoverSource {
  kind: SpellbookCoverSourceKind = SpellbookCoverSourceKind.Rawfile;
  value: string = DEFAULT_SPELLBOOK_COVER_ASSET;
}

export const DEFAULT_SPELLBOOK_COVER_ASSET: string = 'spellbook_covers/default.png';

export function spellbookCoverSourceForPack(pack: Pack): SpellbookCoverSource {
  const source: SpellbookCoverSource = new SpellbookCoverSource();
  const bundled: string = bundledSpellbookCoverAsset(pack);
  if (bundled.length > 0) {
    source.kind = SpellbookCoverSourceKind.Rawfile;
    source.value = bundled;
    return source;
  }
  if (pack.scene.spellbookCoverUrl !== undefined && pack.scene.spellbookCoverUrl.length > 0) {
    source.kind = SpellbookCoverSourceKind.RemoteUrl;
    source.value = pack.scene.spellbookCoverUrl;
    return source;
  }
  source.kind = SpellbookCoverSourceKind.Rawfile;
  source.value = DEFAULT_SPELLBOOK_COVER_ASSET;
  return source;
}

function bundledSpellbookCoverAsset(pack: Pack): string {
  if (pack.source !== 'builtin') {
    return '';
  }
  if (pack.id === 'fruit-forest') return 'spellbook_covers/fruit-forest.png';
  if (pack.id === 'school-castle') return 'spellbook_covers/school-castle.png';
  if (pack.id === 'home-cottage') return 'spellbook_covers/home-cottage.png';
  if (pack.id === 'animal-safari') return 'spellbook_covers/animal-safari.png';
  if (pack.id === 'ocean-realm') return 'spellbook_covers/ocean-realm.png';
  return '';
}
