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
  '"storyEn":"Tiny lanterns glow as fruit friends guide each new word.",' +
  '"storyZh":"果林里的小灯亮起，水果朋友带孩子认识新的单词。",' +
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

const SENTENCE_READY_WORD_JSONS: string[] = [
  '{"id":"w01","word":"apple","meaningZh":"苹果","category":"fruit","difficulty":1,"distractors":["banana","pear"],"example":{"en":"The apple is red.","zh":"苹果是红色的。"}}',
  '{"id":"w02","word":"banana","meaningZh":"香蕉","category":"fruit","difficulty":1,"distractors":["apple","pear"],"example":{"en":"The banana is yellow.","zh":"香蕉是黄色的。"}}',
  '{"id":"w03","word":"orange","meaningZh":"橙子","category":"fruit","difficulty":1,"distractors":["apple","banana"],"example":{"en":"The orange is sweet.","zh":"橙子很甜。"}}',
  '{"id":"w04","word":"grape","meaningZh":"葡萄","category":"fruit","difficulty":1,"distractors":["pear","peach"],"example":{"en":"A grape rolls away.","zh":"一颗葡萄滚走了。"}}',
  '{"id":"w05","word":"pear","meaningZh":"梨","category":"fruit","difficulty":1,"distractors":["grape","apple"],"example":{"en":"The pear tastes sweet.","zh":"梨尝起来很甜。"}}',
  '{"id":"w06","word":"peach","meaningZh":"桃子","category":"fruit","difficulty":1,"distractors":["pear","mango"],"example":{"en":"The peach grows on a tree.","zh":"桃子长在树上。"}}',
  '{"id":"w07","word":"lemon","meaningZh":"柠檬","category":"fruit","difficulty":1,"distractors":["mango","melon"],"example":{"en":"The lemon smells fresh.","zh":"柠檬闻起来清新。"}}',
  '{"id":"w08","word":"mango","meaningZh":"芒果","category":"fruit","difficulty":1,"distractors":["lemon","melon"],"example":{"en":"The mango is in my bowl.","zh":"芒果在我的碗里。"}}',
  '{"id":"w09","word":"melon","meaningZh":"瓜","category":"fruit","difficulty":1,"distractors":["mango","cherry"],"example":{"en":"We share a melon.","zh":"我们分享一个瓜。"}}',
  '{"id":"w10","word":"cherry","meaningZh":"樱桃","category":"fruit","difficulty":1,"distractors":["melon","plum"],"example":{"en":"The cherry is on the cake.","zh":"樱桃在蛋糕上。"}}',
  '{"id":"w11","word":"strawberry","meaningZh":"草莓","category":"fruit","difficulty":1,"distractors":["pineapple","kiwi"],"example":{"en":"The strawberry is red.","zh":"草莓是红色的。"}}',
  '{"id":"w12","word":"pineapple","meaningZh":"菠萝","category":"fruit","difficulty":1,"distractors":["strawberry","kiwi"],"example":{"en":"The pineapple has leaves.","zh":"菠萝有叶子。"}}',
  '{"id":"w13","word":"watermelon","meaningZh":"西瓜","category":"fruit","difficulty":1,"distractors":["blueberry","pineapple"],"example":{"en":"We cut a watermelon.","zh":"我们切西瓜。"}}',
  '{"id":"w14","word":"kiwi","meaningZh":"猕猴桃","category":"fruit","difficulty":1,"distractors":["blueberry","strawberry"],"example":{"en":"I eat a kiwi today.","zh":"我今天吃猕猴桃。"}}',
  '{"id":"w15","word":"blueberry","meaningZh":"蓝莓","category":"fruit","difficulty":1,"distractors":["kiwi","watermelon"],"example":{"en":"A blueberry is small.","zh":"蓝莓很小。"}}',
];

function fifteenWordPackJson(): string {
  let words: string = '';
  for (let i: number = 0; i < SENTENCE_READY_WORD_JSONS.length; i++) {
    if (i > 0) {
      words += ',';
    }
    words += SENTENCE_READY_WORD_JSONS[i];
  }
  return '{"pack_id":"sentence-ready","name":"Sentence Ready","scene":{},"words":[' + words + ']}';
}

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
      expect(p.scene.storyEn).assertEqual('Tiny lanterns glow as fruit friends guide each new word.');
      expect(p.scene.storyZh).assertEqual('果林里的小灯亮起，水果朋友带孩子认识新的单词。');
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

    it('preservesFifteenSentenceClozeReadyWords', 0, () => {
      const p: Pack = BuiltinPackLoader.parsePackJson(fifteenWordPackJson()) as Pack;
      expect(p.words.length).assertEqual(15);
      for (let i: number = 0; i < p.words.length; i++) {
        const ex = p.words[i].example;
        const distractors = p.words[i].distractors;
        expect(ex !== undefined).assertTrue();
        expect(distractors !== undefined).assertTrue();
        if (ex !== undefined) {
          expect(ex.en.length > 0).assertTrue();
          expect(ex.zh.length > 0).assertTrue();
        }
        if (distractors !== undefined) {
          expect(distractors.length >= 2).assertTrue();
        }
      }
    });
  });
}
