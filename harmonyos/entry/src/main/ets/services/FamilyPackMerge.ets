import { ExampleSentence, WordEntry } from '../models/WordEntry';

/**
 * V0.6.3 — pure functions for the family-pack overlay model.
 *
 * Server returns the merged JSON shape `FamilyPacksMergedOut`:
 *   {
 *     schema_version: number,
 *     family_id: string,
 *     merged_at: string,
 *     packs: [
 *       { pack_id, name, version, schema_version, words: [...] },
 *       ...
 *     ]
 *   }
 *
 * Each `pack.words[]` carries either a fully-described entry (custom or
 * global override) or a `{ id, hidden: true }` marker. `mergeFamilyPacks`
 * implements §7.6 of the V0.6 spec:
 *
 *   1. collect hidden_ids across all packs
 *   2. for each non-hidden entry, keep the latest-published-pack version
 *   3. emit base words minus hidden_ids, with overlay entries replacing
 *      same-id base entries
 *   4. append family-only entries (e.g. `fam-...-`) at the end
 *
 * The function is pure; tests exercise it without touching @ohos.data.preferences
 * or NetworkKit. Network/cache plumbing lives in `FamilyPackService.ets`.
 */

export class FamilyPackEntry {
  packId: string = '';
  name: string = '';
  version: number = 0;
  schemaVersion: number = 0;
  publishedAtMs: number = 0;
  words: object[] = [];
}

export class FamilyPacksBlob {
  schemaVersion: number = 0;
  familyId: string = '';
  mergedAtMs: number = 0;
  etag: string = '';
  packs: FamilyPackEntry[] = [];
}

interface RawMergedJson {
  schema_version?: number;
  family_id?: string;
  merged_at?: string;
  packs?: RawPack[];
}

interface RawPack {
  pack_id?: string;
  name?: string;
  version?: number;
  schema_version?: number;
  published_at?: string;  // ISO; may be absent — falls back to merged_at
  words?: object[];
}

interface RawWord {
  id?: string;
  word?: string;
  meaningZh?: string;
  meaning_zh?: string;
  category?: string;
  difficulty?: number;
  hidden?: boolean;
  distractors?: string[];
  exampleEn?: string;
  example_en?: string;
  exampleZh?: string;
  example_zh?: string;
  illustrationUrl?: string;
  illustration_url?: string;
  audioUrl?: string;
  audio_url?: string;
}

/** Parse the server JSON into our typed blob. Returns null on structural
 *  failure; partial / unknown fields are tolerated. */
export function parseFamilyPacksBlob(body: string, etag: string): FamilyPacksBlob | null {
  if (body.length === 0) {
    return null;
  }
  let raw: RawMergedJson;
  try {
    raw = JSON.parse(body) as RawMergedJson;
  } catch (_err) {
    return null;
  }
  if (raw === null || raw === undefined) {
    return null;
  }
  const blob: FamilyPacksBlob = new FamilyPacksBlob();
  blob.schemaVersion = typeof raw.schema_version === 'number' ? raw.schema_version : 1;
  blob.familyId = typeof raw.family_id === 'string' ? raw.family_id : '';
  const mergedAt: number = parseIsoMs(raw.merged_at);
  blob.mergedAtMs = mergedAt;
  blob.etag = etag;
  if (Array.isArray(raw.packs)) {
    for (let i = 0; i < raw.packs.length; i++) {
      const p: RawPack = raw.packs[i];
      const e: FamilyPackEntry = new FamilyPackEntry();
      e.packId = typeof p.pack_id === 'string' ? p.pack_id : '';
      e.name = typeof p.name === 'string' ? p.name : '';
      e.version = typeof p.version === 'number' ? p.version : 0;
      e.schemaVersion = typeof p.schema_version === 'number' ? p.schema_version : 0;
      const publishedAt: number = parseIsoMs(p.published_at);
      e.publishedAtMs = publishedAt > 0 ? publishedAt : mergedAt;
      e.words = Array.isArray(p.words) ? p.words.slice() : [];
      blob.packs.push(e);
    }
  }
  return blob;
}

/** Best-effort ISO-8601 → ms parser. Returns 0 on failure. */
function parseIsoMs(iso: string | undefined): number {
  if (typeof iso !== 'string' || iso.length === 0) {
    return 0;
  }
  const parsed: number = Date.parse(iso);
  if (Number.isNaN(parsed)) {
    return 0;
  }
  return parsed;
}

class OverlayEntry {
  word: WordEntry;
  publishedAtMs: number;
  packId: string;

  constructor(word: WordEntry, publishedAtMs: number, packId: string) {
    this.word = word;
    this.publishedAtMs = publishedAtMs;
    this.packId = packId;
  }
}

/**
 * Apply the §7.6 multi-pack overlay rules to a base repo.
 *
 * Algorithm:
 *
 *   hidden_ids = union of {entry.id : entry.hidden in any pack}
 *   for each pack ordered by (publishedAtMs DESC, packId ASC):
 *     for each non-hidden entry:
 *       if entry.id not yet in latest_overlay: latest_overlay[id] = entry
 *   out = []
 *   for entry in base:
 *     if entry.id in hidden_ids: continue
 *     if entry.id in latest_overlay: out.push(latest_overlay[id])
 *     else: out.push(entry)
 *   for id, entry in latest_overlay where id not in (base.ids ∪ hidden_ids):
 *     out.push(entry)
 *   return out
 */
export function mergeFamilyPacks(base: WordEntry[], blob: FamilyPacksBlob): WordEntry[] {
  if (blob.packs.length === 0) {
    return base.slice();
  }

  const hiddenIds: Set<string> = new Set<string>();
  const candidates: FamilyPackEntry[] = blob.packs.slice();
  candidates.sort((a: FamilyPackEntry, b: FamilyPackEntry): number => {
    if (a.publishedAtMs !== b.publishedAtMs) {
      return b.publishedAtMs - a.publishedAtMs;  // DESC by published time
    }
    if (a.packId < b.packId) {
      return -1;
    }
    if (a.packId > b.packId) {
      return 1;
    }
    return 0;
  });

  for (let i = 0; i < blob.packs.length; i++) {
    const p: FamilyPackEntry = blob.packs[i];
    for (let j = 0; j < p.words.length; j++) {
      const r: RawWord = p.words[j] as RawWord;
      if (r.hidden === true && typeof r.id === 'string') {
        hiddenIds.add(r.id);
      }
    }
  }

  const latestOverlay: Map<string, OverlayEntry> = new Map<string, OverlayEntry>();
  for (let i = 0; i < candidates.length; i++) {
    const p: FamilyPackEntry = candidates[i];
    for (let j = 0; j < p.words.length; j++) {
      const r: RawWord = p.words[j] as RawWord;
      if (r.hidden === true) {
        continue;
      }
      if (typeof r.id !== 'string' || r.id.length === 0) {
        continue;
      }
      if (latestOverlay.has(r.id)) {
        continue;
      }
      const wordObj: WordEntry | null = hydrateOverlay(r);
      if (wordObj === null) {
        continue;
      }
      latestOverlay.set(r.id, new OverlayEntry(wordObj, p.publishedAtMs, p.packId));
    }
  }

  const out: WordEntry[] = [];
  const baseIds: Set<string> = new Set<string>();
  for (let i = 0; i < base.length; i++) {
    const e: WordEntry = base[i];
    baseIds.add(e.id);
    if (hiddenIds.has(e.id)) {
      continue;
    }
    if (latestOverlay.has(e.id)) {
      const overlay: OverlayEntry | undefined = latestOverlay.get(e.id);
      if (overlay !== undefined) {
        // Overlay entries that omit core fields fall back to the base values.
        out.push(mergeOverlayWithBase(e, overlay.word));
        continue;
      }
    }
    out.push(e);
  }
  latestOverlay.forEach((overlay: OverlayEntry, id: string): void => {
    if (baseIds.has(id) || hiddenIds.has(id)) {
      return;
    }
    out.push(overlay.word);
  });

  return out;
}

function pickStr(primary: string | undefined, fallback: string | undefined): string {
  if (typeof primary === 'string' && primary.length > 0) {
    return primary;
  }
  if (typeof fallback === 'string' && fallback.length > 0) {
    return fallback;
  }
  return '';
}

function pickStrNullable(primary: string | undefined, fallback: string | undefined): string | undefined {
  if (typeof primary === 'string' && primary.length > 0) {
    return primary;
  }
  if (typeof fallback === 'string' && fallback.length > 0) {
    return fallback;
  }
  return undefined;
}

function hydrateOverlay(raw: RawWord): WordEntry | null {
  if (typeof raw.id !== 'string' || raw.id.length === 0) {
    return null;
  }
  const out: WordEntry = new WordEntry();
  out.id = raw.id;
  out.word = typeof raw.word === 'string' ? raw.word : '';
  out.meaningZh = pickStr(raw.meaningZh, raw.meaning_zh);
  out.category = typeof raw.category === 'string' ? raw.category : '';
  out.difficulty = typeof raw.difficulty === 'number' ? raw.difficulty : 0;
  if (Array.isArray(raw.distractors)) {
    out.distractors = raw.distractors.slice();
  }
  const ex: ExampleSentence = new ExampleSentence();
  const en: string | undefined = pickStrNullable(raw.exampleEn, raw.example_en);
  const zh: string | undefined = pickStrNullable(raw.exampleZh, raw.example_zh);
  if (en !== undefined || zh !== undefined) {
    ex.en = en !== undefined ? en : '';
    ex.zh = zh !== undefined ? zh : '';
    out.example = ex;
  }
  const illust: string | undefined = pickStrNullable(raw.illustrationUrl, raw.illustration_url);
  if (illust !== undefined) {
    out.illustrationUrl = illust;
  }
  const audio: string | undefined = pickStrNullable(raw.audioUrl, raw.audio_url);
  if (audio !== undefined) {
    out.audioUrl = audio;
  }
  return out;
}

function mergeOverlayWithBase(base: WordEntry, overlay: WordEntry): WordEntry {
  // Family-pack entries may omit core fields when they are pure-id pulls
  // (source=global on the server). Treat empty/zero fields as "use base".
  const out: WordEntry = new WordEntry();
  out.id = overlay.id;
  out.word = overlay.word.length > 0 ? overlay.word : base.word;
  out.meaningZh = overlay.meaningZh.length > 0 ? overlay.meaningZh : base.meaningZh;
  out.category = overlay.category.length > 0 ? overlay.category : base.category;
  out.difficulty = overlay.difficulty > 0 ? overlay.difficulty : base.difficulty;
  out.distractors = overlay.distractors !== undefined ? overlay.distractors : base.distractors;
  out.example = overlay.example !== undefined ? overlay.example : base.example;
  out.illustrationUrl = overlay.illustrationUrl !== undefined ? overlay.illustrationUrl : base.illustrationUrl;
  out.audioUrl = overlay.audioUrl !== undefined ? overlay.audioUrl : base.audioUrl;
  out.image = base.image;
  out.audio = base.audio;
  return out;
}
