import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { Pack } from '../models/Pack';
import {
  SpellbookCoverSource,
  SpellbookCoverSourceKind,
  spellbookCoverSourceForPack,
} from './SpellbookCoverResolver';
import { AssetKind, RemoteAssetCache } from './RemoteAssetCache';

export class CachedSpellbookCover {
  packId: string = '';
  path: string = '';
}

export function coverImageSourceForCachedPath(path: string): string {
  if (path.length === 0) return '';
  if (path.startsWith('file://')) return path;
  return `file://${path}`;
}

export async function cachedSpellbookCoverPathForPack(
  cache: RemoteAssetCache,
  pack: Pack,
): Promise<string | undefined> {
  const source: SpellbookCoverSource = spellbookCoverSourceForPack(pack);
  if (source.kind !== SpellbookCoverSourceKind.RemoteUrl) {
    return undefined;
  }
  return cache.cachedPath(source.value, AssetKind.Cover);
}

export async function cachedSpellbookCoverPathsForPacks(
  ctx: common.UIAbilityContext,
  packs: Pack[],
): Promise<CachedSpellbookCover[]> {
  const cache: RemoteAssetCache = RemoteAssetCache.forContext(ctx);
  const out: CachedSpellbookCover[] = [];
  for (let i = 0; i < packs.length; i++) {
    const path: string | undefined = await cachedSpellbookCoverPathForPack(cache, packs[i]);
    if (path !== undefined) {
      const item: CachedSpellbookCover = new CachedSpellbookCover();
      item.packId = packs[i].id;
      item.path = coverImageSourceForCachedPath(path);
      out.push(item);
    }
  }
  return out;
}

export async function refreshSpellbookCoverCacheForPacks(
  ctx: common.UIAbilityContext,
  packs: Pack[],
): Promise<void> {
  const cache: RemoteAssetCache = RemoteAssetCache.forContext(ctx);
  const seenUrls: string[] = [];
  for (let i = 0; i < packs.length; i++) {
    const source: SpellbookCoverSource = spellbookCoverSourceForPack(packs[i]);
    if (source.kind !== SpellbookCoverSourceKind.RemoteUrl || source.value.length === 0) {
      continue;
    }
    if (seenUrls.indexOf(source.value) >= 0) {
      continue;
    }
    seenUrls.push(source.value);
    try {
      await cache.resolve(source.value, AssetKind.Cover);
    } catch (err) {
      console.error(`refreshSpellbookCoverCacheForPacks failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
}
