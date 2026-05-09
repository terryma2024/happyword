import { describe, it, expect } from '@ohos/hypium';
import { BuiltinPackLoader } from '../main/ets/services/BuiltinPackLoader';
import { Pack } from '../main/ets/models/Pack';
import { MonsterKind } from '../main/ets/data/MonsterCatalog';

// Hand-built JSON literals — ArkTS strict mode rejects untyped object
// literals like `JSON.stringify({...})`, so each fixture is a plain string.

const FRUIT_FOREST_JSON: string =
  '{"schema_version":1,"pack_id":"fruit-forest","name":"Fruit Forest",' +
  '"labelZh":"水果森林",' +
  '"scene":{"bgPrimary":"#FFF6E0","bgAccent":"#FFD49A",' +
  '"bossName":"Orchard Sentinel","bossCandidates":[4,5,6],' +
  '"monsterPlan":[{"kind":"normal","catalogIndex":0},' +
  '{"kind":"spelling","catalogIndex":1},' +
  '{"kind":"boss","catalogIndex":4}]},' +
  '"words":[' +
  '{"id":"fruit-apple","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1},' +
  '{"id":"fruit-banana","word":"banana","meaningZh":"香蕉","category":"fruit","difficulty":1},' +
  '{"id":"fruit-pear","word":"pear","meaningZh":"梨","category":"fruit","difficulty":1}' +
  ']}';

const NO_PACK_ID_JSON: string = '{"name":"X","words":[]}';

const SKIPPED_WORDS_JSON: string =
  '{"pack_id":"x","name":"X","scene":{},"words":[' +
  '{"id":"good","word":"g","meaningZh":"好","category":"x","difficulty":1},' +
  '{"id":"bad"},' +
  '{"word":"no-id"},' +
  '{"id":"good","word":"g","meaningZh":"好","category":"x","difficulty":1}' +
  ']}';

const NO_SCENE_JSON: string =
  '{"pack_id":"x","name":"X","words":[' +
  '{"id":"good","word":"g","meaningZh":"好","category":"x","difficulty":1}' +
  ']}';

export default function BuiltinPackLoaderTest() {
  describe('BuiltinPackLoader', () => {
    it('parses a builtin pack JSON into a Pack with full scene + words', 0, () => {
      const pack: Pack | undefined = BuiltinPackLoader.parsePackJson(FRUIT_FOREST_JSON);
      expect(pack !== undefined).assertTrue();
      const p: Pack = pack as Pack;
      expect(p.id).assertEqual('fruit-forest');
      expect(p.source).assertEqual('builtin');
      expect(p.labelZh).assertEqual('水果森林');
      expect(p.words.length).assertEqual(3);
      expect(p.scene.bossName).assertEqual('Orchard Sentinel');
      expect(p.scene.bossCandidates.length).assertEqual(3);
      expect(p.scene.monsterPlan.slots.length).assertEqual(3);
      expect(p.scene.monsterPlan.slots[2].kind).assertEqual(MonsterKind.Boss);
    });

    it('returns undefined for malformed JSON', 0, () => {
      const pack: Pack | undefined = BuiltinPackLoader.parsePackJson('{not-json');
      expect(pack === undefined).assertTrue();
    });

    it('returns undefined when pack_id is missing', 0, () => {
      expect(BuiltinPackLoader.parsePackJson(NO_PACK_ID_JSON) === undefined).assertTrue();
    });

    it('skips words with missing required fields and dedupes by id', 0, () => {
      const p: Pack = BuiltinPackLoader.parsePackJson(SKIPPED_WORDS_JSON) as Pack;
      expect(p.words.length).assertEqual(1);
      expect(p.words[0].id).assertEqual('good');
    });

    it('falls back to defaults when scene block is missing', 0, () => {
      const p: Pack = BuiltinPackLoader.parsePackJson(NO_SCENE_JSON) as Pack;
      expect(p.scene.bgPrimary).assertEqual('#FFFFFF');
      expect(p.scene.bgAccent).assertEqual('#FFFFFF');
      expect(p.scene.bossName).assertEqual('');
      expect(p.scene.bossCandidates.length).assertEqual(0);
      expect(p.scene.monsterPlan.slots.length).assertEqual(0);
    });
  });
}
