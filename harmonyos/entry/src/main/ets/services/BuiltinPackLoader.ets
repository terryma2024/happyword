import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@ohos.base';

import { Pack, SceneMetadata } from '../models/Pack';
import { WordEntry, ExampleSentence } from '../models/WordEntry';
import { MonsterPlan, MonsterSlot } from '../models/AdventureRegion';
import { MonsterKind, monsterIndexForKind } from '../data/MonsterCatalog';

/**
 * BuiltinPackLoader — reads the 5 bundled pack rawfiles under
 * `entry/src/main/resources/rawfile/data/builtin/*.json` and converts them into
 * V0.6.5 Pack instances (with `source = 'builtin'`).
 *
 * The pure parser `parsePackJson` is the unit-test entrypoint; `loadAll` is the
 * production entrypoint used by `WordPackBootstrapper` at app start.
 *
 * V0.6.5 — replaces the single category-keyed `data/words_v1.json` rawfile with
 * five per-pack files, each carrying its own scene metadata so the battle
 * screen can theme itself per pack without hardcoded mappings.
 */

const BUILTIN_PACK_FILES: string[] = [
  'data/builtin/fruit-forest.json',
  'data/builtin/school-castle.json',
  'data/builtin/home-cottage.json',
  'data/builtin/animal-safari.json',
  'data/builtin/ocean-realm.json',
];

interface RawSlot {
  kind?: string;
  catalogIndex?: number;
}

interface RawScene {
  bgPrimary?: string;
  bgAccent?: string;
  bossName?: string;
  bossCandidates?: number[];
  monsterPlan?: RawSlot[];
  storyEn?: string;
  storyZh?: string;
  spellbookCoverUrl?: string;
}

interface RawExample {
  en?: string;
  zh?: string;
}

interface RawWord {
  id?: string;
  word?: string;
  meaningZh?: string;
  category?: string;
  difficulty?: number;
  distractors?: string[];
  example?: RawExample;
  illustrationUrl?: string;
  audioUrl?: string;
}

interface RawBuiltinPack {
  pack_id?: string;
  name?: string;
  labelZh?: string;
  scene?: RawScene;
  words?: RawWord[];
}

export class BuiltinPackLoader {
  /** Pure parser used by tests; no IO. Returns undefined on malformed input. */
  static parsePackJson(jsonText: string): Pack | undefined {
    let raw: RawBuiltinPack;
    try {
      raw = JSON.parse(jsonText) as RawBuiltinPack;
    } catch (_err) {
      return undefined;
    }
    if (raw === null || raw === undefined) {
      return undefined;
    }
    if (typeof raw.pack_id !== 'string' || raw.pack_id.length === 0) {
      return undefined;
    }
    const pack: Pack = new Pack();
    pack.id = raw.pack_id;
    pack.name = typeof raw.name === 'string' ? raw.name : raw.pack_id;
    pack.labelZh = typeof raw.labelZh === 'string' ? raw.labelZh : '';
    pack.source = 'builtin';
    pack.scene = BuiltinPackLoader.parseScene(raw.scene);
    pack.words = BuiltinPackLoader.parseWords(raw.words);
    return pack;
  }

  private static parseScene(raw: RawScene | undefined): SceneMetadata {
    const scene: SceneMetadata = new SceneMetadata();
    if (raw === undefined || raw === null) {
      return scene;
    }
    if (typeof raw.bgPrimary === 'string') scene.bgPrimary = raw.bgPrimary;
    if (typeof raw.bgAccent === 'string') scene.bgAccent = raw.bgAccent;
    if (typeof raw.bossName === 'string') scene.bossName = raw.bossName;
    if (typeof raw.spellbookCoverUrl === 'string' && raw.spellbookCoverUrl.length > 0) {
      scene.spellbookCoverUrl = raw.spellbookCoverUrl;
    }
    if (Array.isArray(raw.bossCandidates)) {
      const cleaned: number[] = [];
      for (let i = 0; i < raw.bossCandidates.length; i++) {
        const n: number = raw.bossCandidates[i];
        if (typeof n === 'number' && Number.isFinite(n)) cleaned.push(n);
      }
      scene.bossCandidates = cleaned;
    }
    if (typeof raw.storyZh === 'string' && raw.storyZh.length > 0) {
      scene.storyZh = raw.storyZh;
    }
    if (typeof raw.storyEn === 'string' && raw.storyEn.length > 0) {
      scene.storyEn = raw.storyEn;
    }
    if (Array.isArray(raw.monsterPlan)) {
      const plan: MonsterPlan = new MonsterPlan();
      const slots: MonsterSlot[] = [];
      for (let i = 0; i < raw.monsterPlan.length; i++) {
        const r: RawSlot = raw.monsterPlan[i];
        const slot: MonsterSlot = new MonsterSlot();
        slot.kind = BuiltinPackLoader.parseKind(r.kind);
        slot.catalogIndex = typeof r.catalogIndex === 'number' && Number.isFinite(r.catalogIndex)
          ? r.catalogIndex
          : monsterIndexForKind(slot.kind);
        slots.push(slot);
      }
      plan.slots = slots;
      scene.monsterPlan = plan;
    }
    return scene;
  }

  private static parseKind(s: string | undefined): MonsterKind {
    if (s === 'spelling') return MonsterKind.Spelling;
    if (s === 'review') return MonsterKind.Review;
    if (s === 'elite') return MonsterKind.Elite;
    if (s === 'boss') return MonsterKind.Boss;
    return MonsterKind.Normal;
  }

  private static parseWords(raw: RawWord[] | undefined): WordEntry[] {
    if (!Array.isArray(raw)) return [];
    const out: WordEntry[] = [];
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < raw.length; i++) {
      const r: RawWord = raw[i];
      const e: WordEntry = new WordEntry();
      e.id = typeof r.id === 'string' ? r.id : '';
      e.word = typeof r.word === 'string' ? r.word : '';
      e.meaningZh = typeof r.meaningZh === 'string' ? r.meaningZh : '';
      e.category = typeof r.category === 'string' ? r.category : '';
      e.difficulty = typeof r.difficulty === 'number' && Number.isFinite(r.difficulty)
        ? r.difficulty
        : 1;
      if (Array.isArray(r.distractors)) {
        const cleaned: string[] = [];
        for (let j = 0; j < r.distractors.length; j++) {
          const d: string = r.distractors[j];
          if (typeof d === 'string' && d.length > 0) cleaned.push(d);
        }
        if (cleaned.length > 0) e.distractors = cleaned;
      }
      if (r.example !== undefined && r.example !== null) {
        const ex: ExampleSentence = new ExampleSentence();
        ex.en = typeof r.example.en === 'string' ? r.example.en : '';
        ex.zh = typeof r.example.zh === 'string' ? r.example.zh : '';
        if (ex.en.length > 0 || ex.zh.length > 0) e.example = ex;
      }
      if (typeof r.illustrationUrl === 'string' && r.illustrationUrl.length > 0) {
        e.illustrationUrl = r.illustrationUrl;
      }
      if (typeof r.audioUrl === 'string' && r.audioUrl.length > 0) {
        e.audioUrl = r.audioUrl;
      }
      if (!e.isValid()) continue;
      if (seen.has(e.id)) continue;
      seen.add(e.id);
      out.push(e);
    }
    return out;
  }

  /**
   * Read all 5 builtin rawfiles and return them in the order declared in
   * `BUILTIN_PACK_FILES` (fruit → school → home → animal → ocean).
   *
   * Files that fail to read or parse are skipped with a console.error so
   * one corrupt file cannot brick the home-page chip row.
   */
  static async loadAll(ctx: common.UIAbilityContext): Promise<Pack[]> {
    const packs: Pack[] = [];
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    for (let i = 0; i < BUILTIN_PACK_FILES.length; i++) {
      const path: string = BUILTIN_PACK_FILES[i];
      try {
        const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(path);
        const text: string = decoder.decodeToString(bytes);
        const pack: Pack | undefined = BuiltinPackLoader.parsePackJson(text);
        if (pack !== undefined) packs.push(pack);
      } catch (err) {
        const be: BusinessError = err as BusinessError;
        console.error(`BuiltinPackLoader: ${path} failed: ${JSON.stringify(be)}`);
      }
    }
    return packs;
  }
}
