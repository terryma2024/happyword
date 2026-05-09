import { Pack, SceneMetadata } from '../models/Pack';

/**
 * V0.6.5 — PackLibrary composes the three pack source layers (builtin /
 * global / family) into a single Pack[]. Override priority:
 *   family > global > builtin on identical pack id.
 *
 * Scene fallback (spec §5.4):
 *   1. own non-empty scene -> keep
 *   2. else look up same-id builtin's scene
 *   3. else hash(id) % FALLBACK_PALETTE.length
 *
 * The library is purely in-memory; persistence belongs to PackSelectionService.
 */

function paletteEntry(bgPrimary: string, bgAccent: string, bossName: string): SceneMetadata {
  const s: SceneMetadata = new SceneMetadata();
  s.bgPrimary = bgPrimary;
  s.bgAccent = bgAccent;
  s.bossName = bossName;
  return s;
}

const FALLBACK_PALETTE: SceneMetadata[] = [
  paletteEntry('#FFF6E0', '#FFD49A', 'Orchard Sentinel'),
  paletteEntry('#E8F0FE', '#AECBFA', 'Clock Wizard'),
  paletteEntry('#FFF1E6', '#F4B98A', 'Toy Knight'),
  paletteEntry('#F0F8E8', '#A4D274', 'Meadow Beast'),
  paletteEntry('#E8F4F8', '#6EB7CC', 'Sea Sovereign'),
];

/**
 * Hash a string to a non-negative 32-bit int via djb2. Used to stably
 * pick a fallback palette index for family packs.
 */
function djb2Hash(s: string): number {
  let h: number = 5381;
  for (let i: number = 0; i < s.length; i++) {
    h = ((h << 5) - h) + s.charCodeAt(i);
    h = h | 0;
  }
  return h < 0 ? -h : h;
}

function isEmptyScene(s: SceneMetadata): boolean {
  return s.bgPrimary === '#FFFFFF' && s.bgAccent === '#FFFFFF' && s.bossName === '';
}

export class PackLibrary {
  private builtins: Pack[] = [];
  private globals: Pack[] = [];
  private families: Pack[] = [];

  setBuiltins(packs: Pack[]): void {
    this.builtins = packs.slice();
  }
  setGlobals(packs: Pack[]): void {
    this.globals = packs.slice();
  }
  setFamilies(packs: Pack[]): void {
    this.families = packs.slice();
  }

  builtinIds(): string[] {
    const out: string[] = [];
    for (let i = 0; i < this.builtins.length; i++) {
      out.push(this.builtins[i].id);
    }
    return out;
  }

  /** Returns the builtin packs in their declared (rawfile) order. */
  builtinPacks(): Pack[] {
    return this.builtins.slice();
  }

  /** Union the three layers, family-priority, with scene fallback. */
  allPacks(): Pack[] {
    const builtinById: Map<string, Pack> = new Map<string, Pack>();
    for (let i = 0; i < this.builtins.length; i++) {
      builtinById.set(this.builtins[i].id, this.builtins[i]);
    }
    const out: Map<string, Pack> = new Map<string, Pack>();
    for (let i = 0; i < this.builtins.length; i++) {
      out.set(this.builtins[i].id, this.builtins[i]);
    }
    for (let i = 0; i < this.globals.length; i++) {
      const g: Pack = this.globals[i];
      const merged: Pack = PackLibrary.applySceneFallback(g, builtinById);
      out.set(g.id, merged);
    }
    for (let i = 0; i < this.families.length; i++) {
      const f: Pack = this.families[i];
      const merged: Pack = PackLibrary.applySceneFallback(f, builtinById);
      out.set(f.id, merged);
    }
    const list: Pack[] = [];
    out.forEach((p: Pack): void => {
      list.push(p);
    });
    return list;
  }

  byId(id: string): Pack | undefined {
    const list: Pack[] = this.allPacks();
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) return list[i];
    }
    return undefined;
  }

  /** Public for test visibility — returns a deterministic fallback scene for any id. */
  static fallbackSceneFor(id: string): SceneMetadata {
    const idx: number = djb2Hash(id) % FALLBACK_PALETTE.length;
    return FALLBACK_PALETTE[idx];
  }

  private static applySceneFallback(p: Pack, builtinById: Map<string, Pack>): Pack {
    if (!isEmptyScene(p.scene)) return p;
    const sib: Pack | undefined = builtinById.get(p.id);
    if (sib !== undefined && !isEmptyScene(sib.scene)) {
      const merged: Pack = new Pack();
      merged.id = p.id;
      merged.name = p.name;
      merged.labelZh = p.labelZh;
      merged.source = p.source;
      merged.version = p.version;
      merged.publishedAtMs = p.publishedAtMs;
      merged.scene = sib.scene;
      merged.words = p.words.slice();
      return merged;
    }
    const merged: Pack = new Pack();
    merged.id = p.id;
    merged.name = p.name;
    merged.labelZh = p.labelZh;
    merged.source = p.source;
    merged.version = p.version;
    merged.publishedAtMs = p.publishedAtMs;
    merged.scene = PackLibrary.fallbackSceneFor(p.id);
    merged.words = p.words.slice();
    return merged;
  }
}
