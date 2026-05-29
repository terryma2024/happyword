import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { StringPreferencesLike } from './WrongAnswerStore';

export const SPELLBOOK_REWARD_PREFS_NAME: string = 'wordmagic_spellbook_rewards';
export const SPELLBOOK_REWARD_PREFS_KEY: string = 'snapshot_v1';

export class SpellbookRewardSnapshot {
  version: number = 1;
  claimedPackIds: string[] = [];
}

interface SpellbookRewardSnapshotJson {
  version?: number;
  claimedPackIds?: string[];
}

class RealSpellbookRewardPrefs implements StringPreferencesLike {
  private readonly handle: preferences.Preferences;

  constructor(handle: preferences.Preferences) {
    this.handle = handle;
  }

  async getString(key: string): Promise<string> {
    try {
      const value: preferences.ValueType = await this.handle.get(key, '');
      return typeof value === 'string' ? value : '';
    } catch (err) {
      console.error(`SpellbookRewardStore.getString failed: ${JSON.stringify(err as BusinessError)}`);
      return '';
    }
  }

  async putString(key: string, value: string): Promise<void> {
    try {
      await this.handle.put(key, value);
    } catch (err) {
      console.error(`SpellbookRewardStore.putString failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  async flush(): Promise<void> {
    try {
      await this.handle.flush();
    } catch (err) {
      console.error(`SpellbookRewardStore.flush failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
}

export class SpellbookRewardStore {
  private prefs?: StringPreferencesLike;
  private snapshot: SpellbookRewardSnapshot = new SpellbookRewardSnapshot();
  private ready: boolean = false;

  injectPreferencesForTest(prefs: StringPreferencesLike): void {
    this.prefs = prefs;
    this.ready = true;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.ready && this.prefs !== undefined) {
      return;
    }
    try {
      const real: preferences.Preferences =
        await preferences.getPreferences(ctx, SPELLBOOK_REWARD_PREFS_NAME);
      this.prefs = new RealSpellbookRewardPrefs(real);
      this.ready = true;
      await this.load();
    } catch (err) {
      console.error(`SpellbookRewardStore.init failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }

  async load(): Promise<SpellbookRewardSnapshot> {
    if (this.prefs === undefined) {
      this.snapshot = new SpellbookRewardSnapshot();
      return this.snapshotCopy();
    }
    const raw: string = await this.prefs.getString(SPELLBOOK_REWARD_PREFS_KEY);
    this.snapshot = parseSpellbookRewardSnapshot(raw);
    return this.snapshotCopy();
  }

  hasClaimed(packId: string): boolean {
    if (packId.length === 0) {
      return false;
    }
    return this.snapshot.claimedPackIds.indexOf(packId) >= 0;
  }

  async claimPackId(packId: string): Promise<boolean> {
    if (packId.length === 0 || this.hasClaimed(packId)) {
      return false;
    }
    this.snapshot.claimedPackIds.push(packId);
    await this.persist();
    return true;
  }

  private async persist(): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(SPELLBOOK_REWARD_PREFS_KEY, serializeSpellbookRewardSnapshot(this.snapshot));
    await this.prefs.flush();
  }

  private snapshotCopy(): SpellbookRewardSnapshot {
    const out: SpellbookRewardSnapshot = new SpellbookRewardSnapshot();
    out.version = this.snapshot.version;
    out.claimedPackIds = this.snapshot.claimedPackIds.slice();
    return out;
  }
}

export function parseSpellbookRewardSnapshot(raw: string): SpellbookRewardSnapshot {
  const out: SpellbookRewardSnapshot = new SpellbookRewardSnapshot();
  if (raw.length === 0) {
    return out;
  }
  let parsed: SpellbookRewardSnapshotJson;
  try {
    parsed = JSON.parse(raw) as SpellbookRewardSnapshotJson;
  } catch (err) {
    console.error(`parseSpellbookRewardSnapshot failed: ${JSON.stringify(err as BusinessError)}`);
    return out;
  }
  if (parsed === null || parsed === undefined) {
    return out;
  }
  if (typeof parsed.version === 'number' && Number.isFinite(parsed.version)) {
    out.version = parsed.version;
  }
  if (Array.isArray(parsed.claimedPackIds)) {
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < parsed.claimedPackIds.length; i++) {
      const id: string = parsed.claimedPackIds[i];
      if (typeof id === 'string' && id.length > 0 && !seen.has(id)) {
        seen.add(id);
        out.claimedPackIds.push(id);
      }
    }
  }
  return out;
}

export function serializeSpellbookRewardSnapshot(snapshot: SpellbookRewardSnapshot): string {
  return JSON.stringify(snapshot);
}
