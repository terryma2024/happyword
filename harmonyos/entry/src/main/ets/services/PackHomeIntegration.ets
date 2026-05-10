import { common } from '@kit.AbilityKit';
import { Pack, SceneMetadata } from '../models/Pack';
import { AdventureRegion, MonsterPlan, MonsterSlot } from '../models/AdventureRegion';
import { ADVENTURE_REGIONS } from '../data/AdventureCatalog';
import { WordEntry } from '../models/WordEntry';
import { PackLibrary } from './PackLibrary';
import {
  PackSelectionService,
  PackCandidateProvider,
  MAX_ACTIVE_PACKS,
} from './PackSelectionService';
import { WordPackBootstrapper } from './WordPackBootstrapper';

/**
 * V0.6.5.1 — shared glue between the unified Pack model and the
 * legacy AdventureRegion render type used by HomePage / ResultPage.
 *
 * No state of its own; every function is a pure adapter or a thin
 * cold-start helper. ConfigPage and HomePage both call these so the
 * default-active-set + active-Pack[] resolution stays in one place.
 */

/**
 * Bundle returned by `loadHomeIntegration`. The caller pins it as a
 * single field on the page struct so subsequent UI events can hand
 * to ConfigPage or BattlePage without re-doing the cold-start work.
 */
export class HomeIntegrationBundle {
  library: PackLibrary = new PackLibrary();
  selection: PackSelectionService = new PackSelectionService();
}

/**
 * One-shot cold-start for the home page: builds the PackLibrary from
 * builtins + cached globals/families, initialises the
 * PackSelectionService with builtin ids as the default active set
 * (first install), then prunes selection against the available pack
 * ids so a removed family pack never lingers as a chip.
 */
export async function loadHomeIntegration(
  ctx: common.UIAbilityContext,
): Promise<HomeIntegrationBundle> {
  const lib: PackLibrary = await WordPackBootstrapper.bootstrapPackLibrary(ctx);
  const selection: PackSelectionService = new PackSelectionService();
  await selection.init(ctx, lib.builtinIds());
  selection.pruneAgainstLibrary(toIdSet(lib.allPacks()));
  const out: HomeIntegrationBundle = new HomeIntegrationBundle();
  out.library = lib;
  out.selection = selection;
  return out;
}

function toIdSet(packs: Pack[]): Set<string> {
  const s: Set<string> = new Set<string>();
  for (let i = 0; i < packs.length; i++) s.add(packs[i].id);
  return s;
}

/**
 * Resolve the current active Pack[] from selection + library. Active
 * ids that no longer resolve (delete-while-running edge) are dropped.
 * Order follows the persisted selection so chip layout is stable.
 */
export function resolveActivePacks(bundle: HomeIntegrationBundle): Pack[] {
  const ids: string[] = bundle.selection.getActiveIds();
  const out: Pack[] = [];
  for (let i = 0; i < ids.length; i++) {
    const p: Pack | undefined = bundle.library.byId(ids[i]);
    if (p !== undefined) out.push(p);
  }
  return out;
}

/**
 * Synthesize a Pack from one of the bundled AdventureRegion entries.
 * Used as the first-paint fallback in HomePage before
 * `loadHomeIntegration` resolves — AppStorage is empty on a cold
 * launch, so the chip row would otherwise pop in. The synthetic
 * Pack carries no words; HomePage replaces it with a real Pack on
 * first user tap.
 */
export function fallbackPackFromRegion(region: AdventureRegion): Pack {
  const p: Pack = new Pack();
  p.id = region.id;
  p.name = region.displayName;
  p.labelZh = '';
  p.source = 'builtin';
  p.version = 0;
  p.publishedAtMs = 0;
  const scene: SceneMetadata = new SceneMetadata();
  scene.bgPrimary = region.bgPrimary;
  scene.bgAccent = region.bgAccent;
  scene.bossName = region.bossName;
  const plan: MonsterPlan = new MonsterPlan();
  const srcSlots: MonsterSlot[] = region.monsterPlan.slots;
  for (let i = 0; i < srcSlots.length; i++) {
    const ms: MonsterSlot = new MonsterSlot();
    ms.kind = srcSlots[i].kind;
    ms.catalogIndex = srcSlots[i].catalogIndex;
    plan.slots.push(ms);
  }
  scene.monsterPlan = plan;
  scene.bossCandidates = region.bossCandidates.slice();
  p.scene = scene;
  p.words = [];
  return p;
}

/** First-paint fallback Pack list (the bundled 5 regions). */
export function fallbackPacks(): Pack[] {
  const out: Pack[] = [];
  for (let i = 0; i < ADVENTURE_REGIONS.length; i++) {
    out.push(fallbackPackFromRegion(ADVENTURE_REGIONS[i]));
  }
  return out;
}

/**
 * `PackCandidateProvider` implementation used by BattlePage when it
 * calls `recordPerfectAdventure`. Walks the library in deterministic
 * order (builtins → globals → families) and returns the first pack
 * id that is not currently active.
 */
export class LibraryCandidateProvider implements PackCandidateProvider {
  private readonly ordered: Pack[];
  constructor(library: PackLibrary) {
    // PackLibrary.allPacks already merges with family > global > builtin
    // priority; for candidate selection we just need a stable iteration
    // order so the next() call is deterministic across launches.
    this.ordered = library.allPacks();
  }
  next(activeIds: Set<string>): string | undefined {
    for (let i = 0; i < this.ordered.length; i++) {
      const id: string = this.ordered[i].id;
      if (!activeIds.has(id)) return id;
    }
    return undefined;
  }
}

/**
 * Build a WordEntry[] index keyed by id. Useful for ResultPage and
 * the BattlePage today-mode repo build path.
 */
export function indexWordsById(words: WordEntry[]): Map<string, WordEntry> {
  const m: Map<string, WordEntry> = new Map<string, WordEntry>();
  for (let i = 0; i < words.length; i++) m.set(words[i].id, words[i]);
  return m;
}

/** Re-export so callers that already import `MAX_ACTIVE_PACKS` from here keep working. */
export const PACK_PICKER_LIMIT: number = MAX_ACTIVE_PACKS;
