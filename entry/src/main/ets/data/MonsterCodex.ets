/**
 * MonsterCodex: editorial monster archetype lore for the codex page.
 * Decoupled from MonsterCatalog (battle catalog) so editing description
 * copy or adding archetypes never touches battle invariants.
 *
 * Spec: docs/superpowers/specs/2026-04-28-v0.3.7-monster-codex-design.md
 *
 * Invariants (pinned in MonsterCodex.test.ets):
 *   - MONSTER_CODEX.length === 3 and entries are in Slime / Zombie / Dragon order.
 *   - All five fields per entry are non-empty.
 *   - keys are unique and exactly {'slime', 'zombie', 'dragon'}.
 *   - nameEn values are unique.
 *   - descriptionZh length ∈ [40, 200] characters.
 *   - assetPath aligns with characterAssetForKind(Normal/Spelling/Elite).
 */
export class CodexEntry {
  key: string = '';
  nameEn: string = '';
  kindLabelZh: string = '';
  descriptionZh: string = '';
  assetPath: string = '';
}

function makeCodexEntry(
  key: string,
  nameEn: string,
  kindLabelZh: string,
  descriptionZh: string,
  assetPath: string
): CodexEntry {
  const e: CodexEntry = new CodexEntry();
  e.key = key;
  e.nameEn = nameEn;
  e.kindLabelZh = kindLabelZh;
  e.descriptionZh = descriptionZh;
  e.assetPath = assetPath;
  return e;
}

export const MONSTER_CODEX: CodexEntry[] = [
  makeCodexEntry(
    'slime',
    'Slime',
    '普通怪物',
    'Slime 是一只软软的小精灵，整天住在森林深处的青草丛里。它最喜欢的事情就是在月光下打滚，把身体滚得圆圆的。它见到谁都会咧开大嘴笑一笑，从来不会真的生气。',
    'character/slime.svg'
  ),
  makeCodexEntry(
    'zombie',
    'Zombie',
    '拼写专家',
    'Zombie 来自一座很老很老的图书馆，他喜欢把翻烂的书页披在身上当披风。他口袋里装满了散落一地的字母，每天都要把它们重新摆一摆。他看起来有点呆呆的，其实只是太爱发呆。',
    'character/zombie.svg'
  ),
  makeCodexEntry(
    'dragon',
    'Dragon',
    '精英挑战者',
    'Dragon 是住在云朵后面的一只老巨龙，鳞片闪着金色的光。他大部分时间都在睡觉，一觉就是一百年。打喷嚏的时候会喷出小小的火苗，把天上的云染成漂亮的橘红色。',
    'character/dragon.svg'
  ),
];
