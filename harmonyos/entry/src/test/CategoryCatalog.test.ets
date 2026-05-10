import { describe, it, expect } from '@ohos/hypium';
import { CategoryCatalog, CategoryRow } from '../main/ets/services/CategoryCatalog';

const PACK_V4: string = '{"version":2,"schema_version":4,"published_at":"2026-05-01T00:00:00Z",'
  + '"words":[{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1}],'
  + '"categories":['
  + '{"id":"fruit","labelEn":"Fruit","labelZh":"水果","storyZh":"水果之国的故事..."},'
  + '{"id":"school-supplies","labelEn":"School","labelZh":"学校用品"}'
  + ']}';

const PACK_V1: string = '{"version":1,"schema_version":1,"words":['
  + '{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1}'
  + ']}';

export default function categoryCatalogTest(): void {
  describe('CategoryCatalog.parsePackCategories', () => {
    it('parsesAllRowsAtSchemaV4', 0, () => {
      const rows: CategoryRow[] = CategoryCatalog.parsePackCategories(PACK_V4);
      expect(rows.length).assertEqual(2);
      expect(rows[0].id).assertEqual('fruit');
      expect(rows[0].labelEn).assertEqual('Fruit');
      expect(rows[0].labelZh).assertEqual('水果');
      expect(rows[0].storyZh).assertEqual('水果之国的故事...');
      expect(rows[1].id).assertEqual('school-supplies');
      expect(rows[1].storyZh).assertEqual(undefined);
    });

    it('returnsEmptyWhenCategoriesAbsent', 0, () => {
      expect(CategoryCatalog.parsePackCategories(PACK_V1).length).assertEqual(0);
    });

    it('returnsEmptyOnMalformedJson', 0, () => {
      expect(CategoryCatalog.parsePackCategories('{not json').length).assertEqual(0);
    });

    it('returnsEmptyOnEmptyString', 0, () => {
      expect(CategoryCatalog.parsePackCategories('').length).assertEqual(0);
    });

    it('skipsRowsMissingId', 0, () => {
      const broken: string = '{"version":3,"schema_version":4,"words":[],"categories":['
        + '{"labelEn":"NoId","labelZh":"无ID"},'
        + '{"id":"ok","labelEn":"OK","labelZh":"好"}]}';
      const rows: CategoryRow[] = CategoryCatalog.parsePackCategories(broken);
      expect(rows.length).assertEqual(1);
      expect(rows[0].id).assertEqual('ok');
    });

    it('treatsEmptyStoryZhAsAbsent', 0, () => {
      const pack: string = '{"version":3,"schema_version":4,"words":[],"categories":['
        + '{"id":"x","labelEn":"X","labelZh":"X","storyZh":""}]}';
      const rows: CategoryRow[] = CategoryCatalog.parsePackCategories(pack);
      expect(rows.length).assertEqual(1);
      expect(rows[0].storyZh).assertEqual(undefined);
    });
  });

  describe('CategoryCatalog instance', () => {
    it('lookupReturnsRowById', 0, () => {
      const cat: CategoryCatalog = new CategoryCatalog();
      cat.setRows(CategoryCatalog.parsePackCategories(PACK_V4));
      expect(cat.size()).assertEqual(2);
      const fruit: CategoryRow | undefined = cat.getById('fruit');
      expect(fruit !== undefined).assertTrue();
      if (fruit !== undefined) {
        expect(fruit.labelZh).assertEqual('水果');
      }
      expect(cat.getById('missing') === undefined).assertTrue();
    });

    it('replacesRowsOnSubsequentSetRows', 0, () => {
      const cat: CategoryCatalog = new CategoryCatalog();
      cat.setRows(CategoryCatalog.parsePackCategories(PACK_V4));
      expect(cat.size()).assertEqual(2);
      cat.setRows([]);
      expect(cat.size()).assertEqual(0);
      expect(cat.getById('fruit') === undefined).assertTrue();
    });
  });
}
