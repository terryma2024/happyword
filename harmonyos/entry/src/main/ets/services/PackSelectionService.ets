import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';

import { StringPreferencesLike } from './WrongAnswerStore';

/**
 * V0.6.5 — owns the device-local active-pack selection, pin state, and
 * perfect-adventure counters. Selection is a device-only concept (NOT
 * synced to the server) so it lives in its own preferences slot
 * `wordmagic_pack_selection`.
 *
 * The home page chip row reads `getActiveIds()`. ConfigPage drives
 * `setActiveIds([...])` and `togglePin(...)`. BattlePage calls
 * `recordPerfectAdventure(packId, candidateProvider)` on a flawless run;
 * after PERFECT_THRESHOLD perfects on an unpinned pack the service
 * swaps it for the next candidate (Task 18 spec §6.1).
 */

const PREFS_NAME: string = 'wordmagic_pack_selection';
const KEY_BLOB: string = 'selection_v1';

export const MAX_ACTIVE_PACKS: number = 5;
export const PERFECT_THRESHOLD: number = 3;

interface RawSelection {
  schemaVersion?: number;
  activePackIds?: string[];
  pinnedPackIds?: string[];
  perfectScoresByPack?: Record<string, number>;
}

class RealPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;
  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }
  async getString(k: string): Promise<string> {
    try {
      const v: preferences.ValueType = await this.handle.get(k, '');
      return typeof v === 'string' ? v : '';
    } catch (err) {
      console.error(`PackSelectionService.getString: ${JSON.stringify(err as BusinessError)}`);
      return '';
    }
  }
  async putString(k: string, v: string): Promise<void> {
    try {
      await this.handle.put(k, v);
    } catch (err) {
      console.error(`PackSelectionService.putString: ${JSON.stringify(err as BusinessError)}`);
    }
  }
  async flush(): Promise<void> {
    try {
      await this.handle.flush();
    } catch (err) {
      console.error(`PackSelectionService.flush: ${JSON.stringify(err as BusinessError)}`);
    }
  }
}

export interface PackCandidateProvider {
  /** Return the next id to swap into the active set, or undefined if exhausted. */
  next(activeIds: Set<string>): string | undefined;
}

export class PerfectAdventureResult {
  rotated: boolean = false;
  swappedOutId: string = '';
  swappedInId: string = '';
}

export class PackSelectionService {
  private prefs?: StringPreferencesLike;
  private activeIds: string[] = [];
  private pinnedIds: Set<string> = new Set<string>();
  private perfectScores: Map<string, number> = new Map<string, number>();

  injectPreferences(p: StringPreferencesLike): void {
    this.prefs = p;
  }

  async init(ctx: common.UIAbilityContext, defaults: string[]): Promise<void> {
    if (this.prefs === undefined) {
      try {
        const real: preferences.Preferences = await preferences.getPreferences(ctx, PREFS_NAME);
        this.prefs = new RealPrefs(real);
      } catch (err) {
        console.error(`PackSelectionService.init: ${JSON.stringify(err as BusinessError)}`);
      }
    }
    await this.initWithDefaults(defaults);
  }

  async initWithDefaults(defaults: string[]): Promise<void> {
    const raw: string = this.prefs !== undefined ? await this.prefs.getString(KEY_BLOB) : '';
    if (raw.length === 0) {
      this.activeIds = defaults.slice(0, MAX_ACTIVE_PACKS);
      this.pinnedIds = new Set<string>();
      this.perfectScores = new Map<string, number>();
      await this.persist();
      return;
    }
    try {
      const parsed: RawSelection = JSON.parse(raw) as RawSelection;
      this.activeIds = Array.isArray(parsed.activePackIds)
        ? parsed.activePackIds.slice(0, MAX_ACTIVE_PACKS)
        : defaults.slice(0, MAX_ACTIVE_PACKS);
      const pinned: string[] = Array.isArray(parsed.pinnedPackIds) ? parsed.pinnedPackIds : [];
      this.pinnedIds = new Set<string>();
      for (let i = 0; i < pinned.length; i++) this.pinnedIds.add(pinned[i]);
      this.perfectScores = new Map<string, number>();
      const counts: Record<string, number> = parsed.perfectScoresByPack ?? {};
      const keys: string[] = Object.keys(counts);
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i];
        const v: number = counts[k];
        if (typeof v === 'number') this.perfectScores.set(k, v);
      }
    } catch (_err) {
      this.activeIds = defaults.slice(0, MAX_ACTIVE_PACKS);
      this.pinnedIds = new Set<string>();
      this.perfectScores = new Map<string, number>();
      await this.persist();
    }
  }

  getActiveIds(): string[] {
    return this.activeIds.slice();
  }

  async setActiveIds(ids: string[]): Promise<void> {
    if (ids.length > MAX_ACTIVE_PACKS) {
      throw new Error(`active set exceeds ${MAX_ACTIVE_PACKS}`);
    }
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < ids.length; i++) {
      if (seen.has(ids[i])) {
        throw new Error(`duplicate id: ${ids[i]}`);
      }
      seen.add(ids[i]);
    }
    this.activeIds = ids.slice();
    const next: Set<string> = new Set<string>();
    this.pinnedIds.forEach((id: string): void => {
      if (seen.has(id)) next.add(id);
    });
    this.pinnedIds = next;
    await this.persist();
  }

  isPinned(id: string): boolean {
    return this.pinnedIds.has(id);
  }

  pinnedIdsList(): string[] {
    const out: string[] = [];
    this.pinnedIds.forEach((id: string): void => {
      out.push(id);
    });
    return out;
  }

  async togglePin(id: string): Promise<void> {
    if (this.activeIds.indexOf(id) < 0) return;
    if (this.pinnedIds.has(id)) this.pinnedIds.delete(id);
    else this.pinnedIds.add(id);
    await this.persist();
  }

  perfectScore(id: string): number {
    return this.perfectScores.get(id) ?? 0;
  }

  /**
   * Drop ids not present in `availableIds` from active + pinned and
   * persist. Called after PackLibrary refresh so a deleted family pack
   * shrinks the active row immediately.
   */
  pruneAgainstLibrary(availableIds: Set<string>): void {
    this.activeIds = this.activeIds.filter((id: string): boolean => availableIds.has(id));
    const next: Set<string> = new Set<string>();
    this.pinnedIds.forEach((id: string): void => {
      if (availableIds.has(id)) next.add(id);
    });
    this.pinnedIds = next;
    this.persist().catch((_err: BusinessError): void => {});
  }

  /**
   * Record a flawless adventure on `packId`. Increments the perfect
   * counter; once an unpinned active pack reaches PERFECT_THRESHOLD,
   * swaps it for the next candidate from `provider`. Pinned packs are
   * never rotated. Exhausted candidate pools simply freeze the active
   * set (counter remains at the threshold so a later candidate triggers
   * the rotation).
   */
  async recordPerfectAdventure(
    packId: string,
    provider: PackCandidateProvider,
  ): Promise<PerfectAdventureResult> {
    const out: PerfectAdventureResult = new PerfectAdventureResult();
    const cur: number = this.perfectScores.get(packId) ?? 0;
    this.perfectScores.set(packId, cur + 1);

    if (this.activeIds.indexOf(packId) < 0) {
      await this.persist();
      return out;
    }
    if (this.pinnedIds.has(packId)) {
      await this.persist();
      return out;
    }
    if (cur + 1 < PERFECT_THRESHOLD) {
      await this.persist();
      return out;
    }

    const activeSet: Set<string> = new Set<string>();
    for (let i = 0; i < this.activeIds.length; i++) activeSet.add(this.activeIds[i]);
    const candidateId: string | undefined = provider.next(activeSet);
    if (candidateId === undefined) {
      await this.persist();
      return out;
    }

    const idx: number = this.activeIds.indexOf(packId);
    if (idx >= 0) {
      this.activeIds.splice(idx, 1);
    }
    this.activeIds.push(candidateId);
    this.perfectScores.set(packId, 0);
    out.rotated = true;
    out.swappedOutId = packId;
    out.swappedInId = candidateId;
    await this.persist();
    return out;
  }

  async persist(): Promise<void> {
    if (this.prefs === undefined) return;
    const counts: Record<string, number> = {};
    this.perfectScores.forEach((v: number, k: string): void => {
      counts[k] = v;
    });
    const wire: RawSelection = {
      schemaVersion: 1,
      activePackIds: this.activeIds.slice(),
      pinnedPackIds: this.pinnedIdsList(),
      perfectScoresByPack: counts,
    };
    await this.prefs.putString(KEY_BLOB, JSON.stringify(wire));
    await this.prefs.flush();
  }
}
