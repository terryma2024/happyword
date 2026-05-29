import { describe, it, expect } from '@ohos/hypium';
import { Pack, PackSource, SceneMetadata } from '../main/ets/models/Pack';
import { PackLibrary } from '../main/ets/services/PackLibrary';
import { WordEntry } from '../main/ets/models/WordEntry';

function mkPack(
  id: string,
  source: PackSource,
  wordCount: number,
  scene?: SceneMetadata,
): Pack {
  const p: Pack = new Pack();
  p.id = id;
  p.name = id;
  p.source = source;
  p.publishedAtMs = source === 'builtin' ? 0 : 1000;
  if (scene !== undefined) p.scene = scene;
  for (let i = 0; i < wordCount; i++) {
    const w: WordEntry = new WordEntry();
    w.id = `${id}-w${i}`;
    w.word = `w${i}`;
    w.meaningZh = '词';
    w.category = 'x';
    w.difficulty = 1;
    p.words.push(w);
  }
  return p;
}

export default function PackLibraryTest() {
  describe('PackLibrary', () => {
    it('union prioritises family > global > builtin on same id', 0, () => {
      const lib: PackLibrary = new PackLibrary();
      const builtin: Pack = mkPack('shared', 'builtin', 1);
      const global_: Pack = mkPack('shared', 'global', 2);
      const family: Pack = mkPack('shared', 'family', 3);
      lib.setBuiltins([builtin]);
      lib.setGlobals([global_]);
      lib.setFamilies([family]);
      const all: Pack[] = lib.allPacks();
      expect(all.length).assertEqual(1);
      expect(all[0].source).assertEqual('family');
      expect(all[0].words.length).assertEqual(3);
    });

    it('global pack without scene inherits scene from same-id builtin', 0, () => {
      const lib: PackLibrary = new PackLibrary();
      const builtinScene: SceneMetadata = new SceneMetadata();
      builtinScene.bgPrimary = '#FFF6E0';
      builtinScene.bgAccent = '#FFD49A';
      builtinScene.bossName = 'Orchard Sentinel';
      builtinScene.storyEn = 'A builtin story waits under the trees.';
      const builtin: Pack = mkPack('fruit-forest', 'builtin', 1, builtinScene);
      const globalNoScene: Pack = mkPack('fruit-forest', 'global', 2);
      lib.setBuiltins([builtin]);
      lib.setGlobals([globalNoScene]);
      let got: Pack | undefined = undefined;
      const all: Pack[] = lib.allPacks();
      for (let i = 0; i < all.length; i++) {
        if (all[i].id === 'fruit-forest') {
          got = all[i];
          break;
        }
      }
      expect(got !== undefined).assertTrue();
      const g: Pack = got as Pack;
      expect(g.source).assertEqual('global');
      expect(g.scene.bgPrimary).assertEqual('#FFF6E0');
      expect(g.scene.bossName).assertEqual('Orchard Sentinel');
      expect(g.scene.storyEn).assertEqual('A builtin story waits under the trees.');
    });

    it('pack story survives when builtin scene fills missing battle styling', 0, () => {
      const lib: PackLibrary = new PackLibrary();
      const builtinScene: SceneMetadata = new SceneMetadata();
      builtinScene.bgPrimary = '#FFF6E0';
      builtinScene.bgAccent = '#FFD49A';
      builtinScene.bossName = 'Orchard Sentinel';
      const builtin: Pack = mkPack('fruit-forest', 'builtin', 1, builtinScene);
      const storyOnlyScene: SceneMetadata = new SceneMetadata();
      storyOnlyScene.storyEn = 'A global little story leads the path.';
      const globalWithStory: Pack = mkPack('fruit-forest', 'global', 2, storyOnlyScene);
      lib.setBuiltins([builtin]);
      lib.setGlobals([globalWithStory]);
      const got: Pack = lib.allPacks()[0];
      expect(got.scene.bgPrimary).assertEqual('#FFF6E0');
      expect(got.scene.bossName).assertEqual('Orchard Sentinel');
      expect(got.scene.storyEn).assertEqual('A global little story leads the path.');
    });

    it('family pack with no same-id builtin falls back to hashed default palette', 0, () => {
      const lib: PackLibrary = new PackLibrary();
      const family: Pack = mkPack('fam-12345-rabbits', 'family', 3);
      lib.setFamilies([family]);
      const got: Pack = lib.allPacks()[0];
      expect(got.scene.bgPrimary !== '#FFFFFF').assertTrue();
      expect(got.scene.bossName.length > 0).assertTrue();
    });

    it('refresh() rebuilds keyed union and dedupes', 0, () => {
      const lib: PackLibrary = new PackLibrary();
      lib.setBuiltins([mkPack('a', 'builtin', 1), mkPack('b', 'builtin', 1)]);
      lib.setGlobals([mkPack('a', 'global', 1), mkPack('c', 'global', 1)]);
      const all: Pack[] = lib.allPacks();
      const ids: string[] = [];
      for (let i = 0; i < all.length; i++) ids.push(all[i].id);
      ids.sort();
      expect(JSON.stringify(ids)).assertEqual('["a","b","c"]');
    });

    it('byId returns the merged record', 0, () => {
      const lib: PackLibrary = new PackLibrary();
      lib.setBuiltins([mkPack('x', 'builtin', 1)]);
      const got: Pack | undefined = lib.byId('x');
      expect(got !== undefined).assertTrue();
      const p: Pack = got as Pack;
      expect(p.id).assertEqual('x');
    });

    it('fallbackSceneFor is deterministic per id', 0, () => {
      const a: SceneMetadata = PackLibrary.fallbackSceneFor('foo');
      const b: SceneMetadata = PackLibrary.fallbackSceneFor('foo');
      expect(a.bgPrimary).assertEqual(b.bgPrimary);
      expect(a.bossName).assertEqual(b.bossName);
    });
  });
}
