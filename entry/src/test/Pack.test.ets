import { describe, it, expect } from '@ohos/hypium';
import { Pack, PackSource, SceneMetadata } from '../main/ets/models/Pack';
import { MonsterPlan, MonsterSlot } from '../main/ets/models/AdventureRegion';
import { MonsterKind } from '../main/ets/data/MonsterCatalog';

export default function PackTest() {
  describe('Pack', () => {
    it('default Pack has empty fields and builtin source', 0, () => {
      const p: Pack = new Pack();
      expect(p.id).assertEqual('');
      const expectedSource: PackSource = 'builtin';
      expect(p.source).assertEqual(expectedSource);
      expect(p.scene.bgPrimary).assertEqual('#FFFFFF');
      expect(p.scene.monsterPlan.slots.length).assertEqual(0);
      expect(p.words.length).assertEqual(0);
    });

    it('SceneMetadata can carry monster plan + boss candidates', 0, () => {
      const scene: SceneMetadata = new SceneMetadata();
      scene.bgPrimary = '#FFF6E0';
      scene.bossName = 'Orchard Sentinel';
      scene.bossCandidates = [4, 5, 6];
      const slot: MonsterSlot = new MonsterSlot();
      slot.kind = MonsterKind.Boss;
      slot.catalogIndex = 5;
      const plan: MonsterPlan = new MonsterPlan();
      plan.slots = [slot];
      scene.monsterPlan = plan;
      expect(scene.bossCandidates.length).assertEqual(3);
      expect(scene.monsterPlan.slots[0].kind).assertEqual(MonsterKind.Boss);
    });

    it('Pack source typedef accepts all three layers', 0, () => {
      const p: Pack = new Pack();
      const builtin: PackSource = 'builtin';
      const global_: PackSource = 'global';
      const family: PackSource = 'family';
      p.source = builtin;
      expect(p.source).assertEqual('builtin');
      p.source = global_;
      expect(p.source).assertEqual('global');
      p.source = family;
      expect(p.source).assertEqual('family');
    });
  });
}
