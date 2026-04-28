import { MonsterKind } from './MonsterCatalog';

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

