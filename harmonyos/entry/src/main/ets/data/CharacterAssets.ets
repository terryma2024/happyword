import { MonsterEntry, MonsterKind } from './MonsterCatalog';

export const PLAYER_CHARACTER_ASSET: string = 'character/magican.svg';

export function characterAssetForKind(kind: MonsterKind): string {
  if (kind === MonsterKind.Normal) {
    return 'character/slime.svg';
  }
  if (kind === MonsterKind.Spelling || kind === MonsterKind.Review) {
    return 'character/zombie.svg';
  }
  return 'character/dragon.svg';
}

/**
 * V0.3.8 resolver: prefers the entry's own assetPath when set, falling
 * back to the kind-based bucket. The three archetype entries keep an empty assetPath and reach the fallback path; expanded boss entries carry per-entry SVG paths so every region can rotate distinct artwork without expanding MonsterKind.
 */
export function assetPathForEntry(entry: MonsterEntry): string {
  if (entry.assetPath !== '') {
    return entry.assetPath;
  }
  return characterAssetForKind(entry.kind);
}

