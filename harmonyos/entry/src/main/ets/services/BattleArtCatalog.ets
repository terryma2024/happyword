/**
 * BattleArtCatalog — maps a 1-based monster catalog index to the Cocos
 * battle-scene character art key (V1.1.0).
 *
 * The Cocos scene loads monster textures from
 * `art/characters/<imageKey>/spriteFrame` (see cocos/assets/scripts/ui/
 * nodeFactory.ts). Those PNGs were synced from the iOS asset catalog where
 * each monster is named `Character` + PascalCase codex key (e.g. codex key
 * `snow-queen` → `CharacterSnowQueen`). MONSTER_CODEX shares its ordering
 * with MONSTER_CATALOG ("the catalog order mirrors MONSTER_CODEX"), so the
 * codex key at the same index is the authoritative source for the art key.
 */
import { MONSTER_CODEX } from '../data/MonsterCodex';

/** `snow-queen` → `CharacterSnowQueen`. */
export function cocosImageKeyForCodexKey(key: string): string {
  const parts: string[] = key.split('-');
  let out: string = 'Character';
  for (let i = 0; i < parts.length; i++) {
    const part: string = parts[i];
    if (part.length === 0) {
      continue;
    }
    out += part.charAt(0).toUpperCase() + part.substring(1);
  }
  return out;
}

/**
 * Cocos character art key for a 1-based catalog index. Indices wrap around
 * the roster exactly like MonsterCatalog.getMonsterByIndex, and out-of-range
 * input falls back to the first entry.
 */
export function cocosImageKeyForCatalogIndex(index1Based: number): string {
  if (MONSTER_CODEX.length === 0) {
    return 'CharacterSlime';
  }
  const idx0: number = index1Based <= 0 ? 0 : (index1Based - 1) % MONSTER_CODEX.length;
  return cocosImageKeyForCodexKey(MONSTER_CODEX[idx0].key);
}
