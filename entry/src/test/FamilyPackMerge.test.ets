import { describe, it, expect } from '@ohos/hypium';
import { WordEntry } from '../main/ets/models/WordEntry';
import {
  FamilyPackEntry,
  FamilyPacksBlob,
  mergeFamilyPacks,
  parseFamilyPacksBlob,
} from '../main/ets/services/FamilyPackMerge';

class OverlayWord {
  id: string = '';
  word?: string;
  meaningZh?: string;
  category?: string;
  difficulty?: number;
  hidden?: boolean;
}

function we(id: string, word: string, meaning: string, category: string, difficulty: number): WordEntry {
  const e: WordEntry = new WordEntry();
  e.id = id;
  e.word = word;
  e.meaningZh = meaning;
  e.category = category;
  e.difficulty = difficulty;
  return e;
}

function ow(id: string, meaningZh?: string, hidden?: boolean): OverlayWord {
  const w: OverlayWord = new OverlayWord();
  w.id = id;
  if (meaningZh !== undefined) {
    w.meaningZh = meaningZh;
  }
  if (hidden !== undefined) {
    w.hidden = hidden;
  }
  return w;
}

function ofull(id: string, word: string, meaning: string, category: string, difficulty: number): OverlayWord {
  const w: OverlayWord = new OverlayWord();
  w.id = id;
  w.word = word;
  w.meaningZh = meaning;
  w.category = category;
  w.difficulty = difficulty;
  return w;
}

function pack(packId: string, publishedAtMs: number, words: OverlayWord[]): FamilyPackEntry {
  const e: FamilyPackEntry = new FamilyPackEntry();
  e.packId = packId;
  e.name = packId;
  e.version = 1;
  e.schemaVersion = 5;
  e.publishedAtMs = publishedAtMs;
  e.words = words.slice() as object[];
  return e;
}

function blob(packs: FamilyPackEntry[]): FamilyPacksBlob {
  const b: FamilyPacksBlob = new FamilyPacksBlob();
  b.familyId = 'fam-aaaaaaaa';
  b.schemaVersion = 5;
  b.mergedAtMs = 1_700_000_000_000;
  b.etag = '"sha256(fake)"';
  b.packs = packs;
  return b;
}

export default function familyPackMergeTest() {
  describe('FamilyPackMerge', () => {
    it('merge_with_empty_overlay_returns_base_unchanged', 0, () => {
      const base: WordEntry[] = [
        we('apple', 'apple', '苹果', 'fruit', 1),
        we('cat', 'cat', '猫', 'animal', 1),
      ];
      const out: WordEntry[] = mergeFamilyPacks(base, blob([]));
      expect(out.length).assertEqual(2);
      expect(out[0].id).assertEqual('apple');
      expect(out[1].id).assertEqual('cat');
    });

    it('merge_single_pack_overrides_one_global_word', 0, () => {
      const base: WordEntry[] = [
        we('apple', 'apple', '苹果', 'fruit', 1),
        we('cat', 'cat', '猫', 'animal', 1),
      ];
      const overlay: OverlayWord[] = [ow('apple', '苹果(覆盖)')];
      const out: WordEntry[] = mergeFamilyPacks(
        base,
        blob([pack('pck-1', 1_700_000_000_000, overlay)]),
      );
      const apple: WordEntry | undefined = out.find((e: WordEntry): boolean => e.id === 'apple');
      const cat: WordEntry | undefined = out.find((e: WordEntry): boolean => e.id === 'cat');
      expect(apple !== undefined).assertTrue();
      expect(apple?.meaningZh).assertEqual('苹果(覆盖)');
      expect(apple?.word).assertEqual('apple');
      expect(apple?.category).assertEqual('fruit');
      expect(cat?.meaningZh).assertEqual('猫');
    });

    it('merge_multi_pack_same_word_id_latest_published_wins', 0, () => {
      const base: WordEntry[] = [we('apple', 'apple', '苹果', 'fruit', 1)];
      const older: OverlayWord[] = [ow('apple', 'OLD')];
      const newer: OverlayWord[] = [ow('apple', 'NEW')];
      const out: WordEntry[] = mergeFamilyPacks(
        base,
        blob([
          pack('pck-A', 1_700_000_000_000, older),
          pack('pck-B', 1_700_000_999_999, newer),
        ]),
      );
      expect(out.find((e: WordEntry): boolean => e.id === 'apple')?.meaningZh).assertEqual('NEW');
    });

    it('merge_hidden_id_in_any_pack_excludes_from_result', 0, () => {
      const base: WordEntry[] = [
        we('apple', 'apple', '苹果', 'fruit', 1),
        we('cat', 'cat', '猫', 'animal', 1),
      ];
      const visiblePack: OverlayWord[] = [ow('apple', 'visible')];
      const hidingPack: OverlayWord[] = [ow('apple', undefined, true)];
      const out: WordEntry[] = mergeFamilyPacks(
        base,
        blob([
          pack('pck-A', 1_700_000_000_000, visiblePack),
          pack('pck-B', 1_700_000_999_999, hidingPack),
        ]),
      );
      expect(out.find((e: WordEntry): boolean => e.id === 'apple')).assertEqual(undefined);
      expect(out.find((e: WordEntry): boolean => e.id === 'cat')?.id).assertEqual('cat');
    });

    it('merge_appends_family_only_custom_word', 0, () => {
      const base: WordEntry[] = [we('apple', 'apple', '苹果', 'fruit', 1)];
      const overlay: OverlayWord[] = [
        ofull('fam-aaaaaaaa-pencil', 'pencil', '铅笔', 'school', 2),
      ];
      const out: WordEntry[] = mergeFamilyPacks(
        base,
        blob([pack('pck-1', 1_700_000_000_000, overlay)]),
      );
      expect(out.length).assertEqual(2);
      const pencil: WordEntry | undefined = out.find((e: WordEntry): boolean => e.id === 'fam-aaaaaaaa-pencil');
      expect(pencil !== undefined).assertTrue();
      expect(pencil?.word).assertEqual('pencil');
      expect(pencil?.category).assertEqual('school');
    });

    it('merge_preserves_global_words_not_overridden_or_hidden', 0, () => {
      const base: WordEntry[] = [
        we('a', 'a', 'a-zh', 'cat-a', 1),
        we('b', 'b', 'b-zh', 'cat-b', 1),
        we('c', 'c', 'c-zh', 'cat-c', 1),
      ];
      const overlay: OverlayWord[] = [ow('a', 'a-overlay')];
      const out: WordEntry[] = mergeFamilyPacks(
        base,
        blob([pack('pck-1', 1_700_000_000_000, overlay)]),
      );
      const ids: string[] = out.map((e: WordEntry): string => e.id).sort();
      expect(ids.join(',')).assertEqual('a,b,c');
    });

    it('merge_tie_break_by_pack_id_when_published_at_equal', 0, () => {
      const base: WordEntry[] = [we('apple', 'apple', '苹果', 'fruit', 1)];
      const ts: number = 1_700_000_000_000;
      const out: WordEntry[] = mergeFamilyPacks(
        base,
        blob([
          pack('pck-zzz', ts, [ow('apple', 'Z')]),
          pack('pck-aaa', ts, [ow('apple', 'A')]),
        ]),
      );
      // Ties broken by packId ASC, so pck-aaa wins.
      expect(out.find((e: WordEntry): boolean => e.id === 'apple')?.meaningZh).assertEqual('A');
    });

    it('parseFamilyPacksBlob_handles_minimal_response', 0, () => {
      const body: string = '{"schema_version":5,"family_id":"fam-12345678","merged_at":"2026-05-01T08:00:00Z","packs":[{"pack_id":"pck-aaa","name":"水果","version":1,"schema_version":5,"published_at":"2026-05-01T07:30:00Z","words":[{"id":"apple","meaningZh":"苹果"}]}]}';
      const blobOut: FamilyPacksBlob | null = parseFamilyPacksBlob(body, '"etag-1"');
      expect(blobOut !== null).assertTrue();
      expect(blobOut?.familyId).assertEqual('fam-12345678');
      expect(blobOut?.packs.length).assertEqual(1);
      const first: FamilyPackEntry | undefined = blobOut?.packs[0];
      expect(first !== undefined).assertTrue();
      expect((first as FamilyPackEntry).publishedAtMs > 0).assertTrue();
    });

    it('parseFamilyPacksBlob_returns_null_for_garbage', 0, () => {
      expect(parseFamilyPacksBlob('not json', '"e"')).assertEqual(null);
      expect(parseFamilyPacksBlob('', '"e"')).assertEqual(null);
    });
  });
}
