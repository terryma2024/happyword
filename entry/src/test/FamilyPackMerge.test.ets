import { describe, it, expect } from '@ohos/hypium';
import { WordEntry } from '../main/ets/models/WordEntry';
import {
  FamilyPackEntry,
  FamilyPacksBlob,
  mergeFamilyPacks,
  parseFamilyPacksBlob,
} from '../main/ets/services/FamilyPackMerge';

function we(id: string, word: string, meaning: string, category: string, difficulty: number): WordEntry {
  const e: WordEntry = new WordEntry();
  e.id = id;
  e.word = word;
  e.meaningZh = meaning;
  e.category = category;
  e.difficulty = difficulty;
  return e;
}

function pack(packId: string, publishedAtMs: number, words: object[]): FamilyPackEntry {
  const e: FamilyPackEntry = new FamilyPackEntry();
  e.packId = packId;
  e.name = packId;
  e.version = 1;
  e.schemaVersion = 5;
  e.publishedAtMs = publishedAtMs;
  e.words = words;
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
      const overlay: object[] = [
        { id: 'apple', meaningZh: '苹果(覆盖)' } as object,
      ];
      const out: WordEntry[] = mergeFamilyPacks(
        base,
        blob([pack('pck-1', 1_700_000_000_000, overlay)]),
      );
      const apple: WordEntry | undefined = out.find((e: WordEntry): boolean => e.id === 'apple');
      const cat: WordEntry | undefined = out.find((e: WordEntry): boolean => e.id === 'cat');
      expect(apple !== undefined).assertTrue();
      expect(apple?.meaningZh).assertEqual('苹果(覆盖)');
      // word/category/difficulty inherited from base when overlay omits them.
      expect(apple?.word).assertEqual('apple');
      expect(apple?.category).assertEqual('fruit');
      expect(cat?.meaningZh).assertEqual('猫');
    });

    it('merge_multi_pack_same_word_id_latest_published_wins', 0, () => {
      const base: WordEntry[] = [we('apple', 'apple', '苹果', 'fruit', 1)];
      const older: object[] = [{ id: 'apple', meaningZh: 'OLD' } as object];
      const newer: object[] = [{ id: 'apple', meaningZh: 'NEW' } as object];
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
      const visiblePack: object[] = [{ id: 'apple', meaningZh: 'visible' } as object];
      const hidingPack: object[] = [{ id: 'apple', hidden: true } as object];
      const out: WordEntry[] = mergeFamilyPacks(
        base,
        blob([
          pack('pck-A', 1_700_000_000_000, visiblePack),
          pack('pck-B', 1_700_000_999_999, hidingPack),
        ]),
      );
      // Hidden wins even though pck-A still has a non-hidden version.
      expect(out.find((e: WordEntry): boolean => e.id === 'apple')).assertEqual(undefined);
      expect(out.find((e: WordEntry): boolean => e.id === 'cat')?.id).assertEqual('cat');
    });

    it('merge_appends_family_only_custom_word', 0, () => {
      const base: WordEntry[] = [we('apple', 'apple', '苹果', 'fruit', 1)];
      const overlay: object[] = [
        {
          id: 'fam-aaaaaaaa-pencil',
          word: 'pencil',
          meaningZh: '铅笔',
          category: 'school',
          difficulty: 2,
        } as object,
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
      const overlay: object[] = [{ id: 'a', meaningZh: 'a-overlay' } as object];
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
          pack('pck-zzz', ts, [{ id: 'apple', meaningZh: 'Z' } as object]),
          pack('pck-aaa', ts, [{ id: 'apple', meaningZh: 'A' } as object]),
        ]),
      );
      // Ties broken by packId ASC, so pck-aaa wins.
      expect(out.find((e: WordEntry): boolean => e.id === 'apple')?.meaningZh).assertEqual('A');
    });

    it('parseFamilyPacksBlob_handles_minimal_response', 0, () => {
      const body: string = JSON.stringify({
        schema_version: 5,
        family_id: 'fam-12345678',
        merged_at: '2026-05-01T08:00:00Z',
        packs: [
          {
            pack_id: 'pck-aaa',
            name: '水果',
            version: 1,
            schema_version: 5,
            published_at: '2026-05-01T07:30:00Z',
            words: [{ id: 'apple', meaningZh: '苹果' }],
          },
        ],
      });
      const blobOut: FamilyPacksBlob | null = parseFamilyPacksBlob(body, '"etag-1"');
      expect(blobOut !== null).assertTrue();
      expect(blobOut?.familyId).assertEqual('fam-12345678');
      expect(blobOut?.packs.length).assertEqual(1);
      expect(blobOut?.packs[0].publishedAtMs > 0).assertTrue();
    });

    it('parseFamilyPacksBlob_returns_null_for_garbage', 0, () => {
      expect(parseFamilyPacksBlob('not json', '"e"')).assertEqual(null);
      expect(parseFamilyPacksBlob('', '"e"')).assertEqual(null);
    });
  });
}
