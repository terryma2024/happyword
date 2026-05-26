import monsterCatalogJson from './monster_catalog.json';

/**
 * MonsterCatalog: a frozen, 1-based roster of monsters fought in BattlePage.
 * The catalog order mirrors MONSTER_CODEX so codex lore and battle art stay aligned.
 * Data lives in monster_catalog.json; this module only validates and exposes it.
 */
export enum MonsterKind {
  Normal = 'normal',
  Spelling = 'spelling',
  Review = 'review',
  Elite = 'elite',
  Boss = 'boss',
}

/** V0.8.3 difficulty tier — orthogonal to {@link MonsterKind} art grouping. */
export enum MonsterLevel {
  Beginner = 'beginner',
  Intermediate = 'intermediate',
  Advanced = 'advanced',
  Super = 'super',
}

export const MONSTER_CATALOG_SOURCE_FILE: string = 'monster_catalog.json';

export class MonsterDialogueLine {
  en: string = '';
  zh: string = '';
}

export class MonsterDialogue {
  introLine: MonsterDialogueLine = new MonsterDialogueLine();
  defeatLine: MonsterDialogueLine = new MonsterDialogueLine();
}

function line(en: string, zh: string): MonsterDialogueLine {
  const out: MonsterDialogueLine = new MonsterDialogueLine();
  out.en = en;
  out.zh = zh;
  return out;
}

function dialogue(introEn: string, introZh: string, defeatEn: string, defeatZh: string): MonsterDialogue {
  const out: MonsterDialogue = new MonsterDialogue();
  out.introLine = line(introEn, introZh);
  out.defeatLine = line(defeatEn, defeatZh);
  return out;
}

export class MonsterEntry {
  name: string = '';
  fill: string = '';
  stroke: string = '';
  kind: MonsterKind = MonsterKind.Normal;
  assetPath: string = '';
  level: MonsterLevel = MonsterLevel.Beginner;
  dialogue: MonsterDialogue = dialogue(
    'Face my word challenge!',
    '来挑战我的单词吧！',
    'Your word wins this round.',
    '这回你的单词赢啦。'
  );
}

export function makeMonsterEntryWithKind(
  name: string,
  fill: string,
  stroke: string,
  kind: MonsterKind
): MonsterEntry {
  const e: MonsterEntry = new MonsterEntry();
  e.name = name;
  e.fill = fill;
  e.stroke = stroke;
  e.kind = kind;
  return e;
}

export function makeBossEntry(
  name: string,
  fill: string,
  stroke: string,
  assetPath: string
): MonsterEntry {
  const e: MonsterEntry = new MonsterEntry();
  e.name = name;
  e.fill = fill;
  e.stroke = stroke;
  e.kind = MonsterKind.Boss;
  e.assetPath = assetPath;
  return e;
}

class RawMonsterDialogueLine {
  en: string = '';
  zh: string = '';
}

class RawMonsterDialogue {
  introLine: RawMonsterDialogueLine = new RawMonsterDialogueLine();
  defeatLine: RawMonsterDialogueLine = new RawMonsterDialogueLine();
}

class RawMonsterEntry {
  name: string = '';
  fill: string = '';
  stroke: string = '';
  kind: string = '';
  assetPath: string = '';
  level: string = '';
  dialogue: RawMonsterDialogue = new RawMonsterDialogue();
}

class RawMonsterCatalogFile {
  monsters: RawMonsterEntry[] = [];
}

function monsterKindFromRaw(value: string): MonsterKind {
  if (value === MonsterKind.Spelling) {
    return MonsterKind.Spelling;
  }
  if (value === MonsterKind.Review) {
    return MonsterKind.Review;
  }
  if (value === MonsterKind.Elite) {
    return MonsterKind.Elite;
  }
  if (value === MonsterKind.Boss) {
    return MonsterKind.Boss;
  }
  return MonsterKind.Normal;
}

function monsterLevelFromRaw(value: string): MonsterLevel {
  if (value === MonsterLevel.Intermediate) {
    return MonsterLevel.Intermediate;
  }
  if (value === MonsterLevel.Advanced) {
    return MonsterLevel.Advanced;
  }
  if (value === MonsterLevel.Super) {
    return MonsterLevel.Super;
  }
  return MonsterLevel.Beginner;
}

function entryFromRaw(raw: RawMonsterEntry): MonsterEntry {
  const e: MonsterEntry = new MonsterEntry();
  e.name = raw.name;
  e.fill = raw.fill;
  e.stroke = raw.stroke;
  e.kind = monsterKindFromRaw(raw.kind);
  e.assetPath = raw.assetPath;
  e.level = monsterLevelFromRaw(raw.level);
  e.dialogue = dialogue(
    raw.dialogue.introLine.en,
    raw.dialogue.introLine.zh,
    raw.dialogue.defeatLine.en,
    raw.dialogue.defeatLine.zh,
  );
  return e;
}

function buildMonsterCatalog(raw: RawMonsterCatalogFile): MonsterEntry[] {
  const monsters: MonsterEntry[] = [];
  for (let i: number = 0; i < raw.monsters.length; i++) {
    monsters.push(entryFromRaw(raw.monsters[i]));
  }
  return monsters;
}

export function parseMonsterCatalogJson(jsonText: string): MonsterEntry[] {
  const raw: RawMonsterCatalogFile = JSON.parse(jsonText) as RawMonsterCatalogFile;
  return buildMonsterCatalog(raw);
}

export const MONSTER_CATALOG: MonsterEntry[] = buildMonsterCatalog(monsterCatalogJson as RawMonsterCatalogFile);

/** Level for a 1-based catalog index. */
export function monsterLevelForCatalogIndex(index1Based: number): MonsterLevel {
  if (index1Based <= 0 || MONSTER_CATALOG.length === 0) {
    return MonsterLevel.Beginner;
  }
  const idx0: number = (index1Based - 1) % MONSTER_CATALOG.length;
  return MONSTER_CATALOG[idx0].level;
}

/** Representative catalog index per level (today-plan slot wiring). */
export function monsterCatalogIndexForLevel(level: MonsterLevel): number {
  for (let i: number = 1; i <= MONSTER_CATALOG.length; i++) {
    if (monsterLevelForCatalogIndex(i) === level) {
      return i;
    }
  }
  return 1;
}

export function monsterCatalogIndicesForLevel(level: MonsterLevel): number[] {
  const out: number[] = [];
  for (let i: number = 1; i <= MONSTER_CATALOG.length; i++) {
    if (monsterLevelForCatalogIndex(i) === level) {
      out.push(i);
    }
  }
  if (out.length === 0) {
    out.push(monsterCatalogIndexForLevel(level));
  }
  return out;
}

export function levelBadgeZhForMonsterLevel(level: MonsterLevel): string {
  if (level === MonsterLevel.Beginner) {
    return '初';
  }
  if (level === MonsterLevel.Intermediate) {
    return '中';
  }
  if (level === MonsterLevel.Advanced) {
    return '高';
  }
  return 'Super';
}

export function battleLevelLabelForMonsterLevel(level: MonsterLevel): string {
  if (level === MonsterLevel.Beginner) {
    return 'L1';
  }
  if (level === MonsterLevel.Intermediate) {
    return 'L2';
  }
  if (level === MonsterLevel.Advanced) {
    return 'L3';
  }
  return 'L4';
}

export function getMonsterByIndex(index1Based: number): MonsterEntry {
  if (index1Based <= 0) {
    return MONSTER_CATALOG[0];
  }
  const idx0: number = (index1Based - 1) % MONSTER_CATALOG.length;
  return MONSTER_CATALOG[idx0];
}

export function getMonsterDialogueByIndex(index1Based: number): MonsterDialogue {
  return getMonsterByIndex(index1Based).dialogue;
}

export function monsterIndexForKind(kind: MonsterKind): number {
  if (kind === MonsterKind.Normal || kind === MonsterKind.Review) {
    return monsterCatalogIndexForLevel(MonsterLevel.Beginner);
  }
  if (kind === MonsterKind.Spelling) {
    return monsterCatalogIndexForLevel(MonsterLevel.Intermediate);
  }
  if (kind === MonsterKind.Elite) {
    return monsterCatalogIndexForLevel(MonsterLevel.Advanced);
  }
  return monsterCatalogIndexForLevel(MonsterLevel.Super);
}
