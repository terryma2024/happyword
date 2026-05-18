import { describe, it, expect } from '@ohos/hypium';
import {
  AppendOutcome,
  PackCandidateProvider,
  PackSelectionService,
  PerfectAdventureResult,
} from '../main/ets/services/PackSelectionService';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

class MemPrefs implements StringPreferencesLike {
  store: Map<string, string> = new Map<string, string>();
  async getString(k: string): Promise<string> {
    return this.store.get(k) ?? '';
  }
  async putString(k: string, v: string): Promise<void> {
    this.store.set(k, v);
  }
  async flush(): Promise<void> {}
}

const DEFAULTS: string[] = [
  'fruit-forest',
  'school-castle',
  'home-cottage',
  'animal-safari',
  'ocean-realm',
];

class StubCandidate {
  id: string = '';
  source: string = '';
  publishedAtMs: number = 0;
}

class StubCandidateProvider implements PackCandidateProvider {
  packs: StubCandidate[] = [];

  next(activeIds: Set<string>): string | undefined {
    const avail: StubCandidate[] = [];
    for (let i = 0; i < this.packs.length; i++) {
      if (!activeIds.has(this.packs[i].id)) avail.push(this.packs[i]);
    }
    avail.sort((a: StubCandidate, b: StubCandidate): number => {
      const sa: number = a.source === 'family' ? 0 : (a.source === 'global' ? 1 : 2);
      const sb: number = b.source === 'family' ? 0 : (b.source === 'global' ? 1 : 2);
      if (sa !== sb) return sa - sb;
      if (a.publishedAtMs !== b.publishedAtMs) return b.publishedAtMs - a.publishedAtMs;
      if (a.id < b.id) return -1;
      if (a.id > b.id) return 1;
      return 0;
    });
    return avail.length === 0 ? undefined : avail[0].id;
  }
}

function mkCandidate(id: string, source: string, publishedAtMs: number): StubCandidate {
  const c: StubCandidate = new StubCandidate();
  c.id = id;
  c.source = source;
  c.publishedAtMs = publishedAtMs;
  return c;
}

export default function PackSelectionServiceTest() {
  describe('PackSelectionService active set', () => {
    it('first launch seeds the 5 builtin defaults', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      await svc.initWithDefaults(DEFAULTS);
      expect(JSON.stringify(svc.getActiveIds())).assertEqual(JSON.stringify(DEFAULTS));
      done();
    });

    it('reload from prefs restores active + pinned + perfect counts', 0, async (done: () => void) => {
      const prefs: MemPrefs = new MemPrefs();
      const svc1: PackSelectionService = new PackSelectionService();
      svc1.injectPreferences(prefs);
      await svc1.initWithDefaults(DEFAULTS);
      await svc1.togglePin('fruit-forest');

      const svc2: PackSelectionService = new PackSelectionService();
      svc2.injectPreferences(prefs);
      await svc2.initWithDefaults(DEFAULTS);
      expect(svc2.isPinned('fruit-forest')).assertTrue();
      expect(JSON.stringify(svc2.getActiveIds())).assertEqual(JSON.stringify(DEFAULTS));
      done();
    });

    it('setActiveIds rejects sets larger than 10', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      await svc.initWithDefaults(DEFAULTS);
      let threw: boolean = false;
      try {
        await svc.setActiveIds([
          'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k',
        ]);
      } catch (_err) {
        threw = true;
      }
      expect(threw).assertTrue();
      done();
    });

    it('setActiveIds rejects duplicates', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      await svc.initWithDefaults(DEFAULTS);
      let threw: boolean = false;
      try {
        await svc.setActiveIds(['a', 'a', 'b']);
      } catch (_err) {
        threw = true;
      }
      expect(threw).assertTrue();
      done();
    });

    it('togglePin only stores ids that exist in active set', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      await svc.initWithDefaults(DEFAULTS);
      await svc.togglePin('fruit-forest');
      expect(svc.isPinned('fruit-forest')).assertTrue();
      await svc.togglePin('fruit-forest');
      expect(svc.isPinned('fruit-forest')).assertFalse();
      await svc.togglePin('not-a-pack');
      expect(svc.isPinned('not-a-pack')).assertFalse();
      done();
    });

    it('pruneAgainstLibrary drops missing ids and stale pinned ids', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      await svc.initWithDefaults(DEFAULTS);
      await svc.togglePin('fruit-forest');
      const avail: Set<string> = new Set<string>();
      avail.add('school-castle');
      avail.add('animal-safari');
      svc.pruneAgainstLibrary(avail);
      expect(svc.getActiveIds().length).assertEqual(2);
      expect(svc.isPinned('fruit-forest')).assertFalse();
      done();
    });

    it('setActiveIds drops pinned ids no longer active', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      await svc.initWithDefaults(DEFAULTS);
      await svc.togglePin('fruit-forest');
      await svc.setActiveIds(['school-castle', 'animal-safari']);
      expect(svc.isPinned('fruit-forest')).assertFalse();
      done();
    });
  });

  describe('PackSelectionService appendOrRotate (V0.8.3)', () => {
    it('appendOrRotateAtUnderCapJustAppends', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      const nine: string[] = [
        'fruit-forest', 'school-castle', 'home-cottage', 'animal-safari', 'ocean-realm',
        'a', 'b', 'c', 'd',
      ];
      await svc.setActiveIds(nine);
      const out: AppendOutcome = await svc.appendOrRotate('space-station');
      expect(out.result).assertEqual('activated');
      expect(out.autoClosed === null).assertTrue();
      expect(svc.getActiveIds().indexOf('space-station') >= 0).assertTrue();
      expect(svc.getActiveIds().length).assertEqual(10);
      done();
    });

    it('appendOrRotateAtCapClosesEarliestNonPinned', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      const ten: string[] = [
        'fruit-forest', 'school-castle', 'home-cottage', 'animal-safari', 'ocean-realm',
        'a', 'b', 'c', 'd', 'e',
      ];
      await svc.setActiveIds(ten);
      await svc.togglePin('home-cottage');
      const out: AppendOutcome = await svc.appendOrRotate('space-station');
      expect(out.result).assertEqual('activated');
      expect(out.autoClosed).assertEqual('fruit-forest');
      const ids: string[] = svc.getActiveIds();
      expect(ids.indexOf('fruit-forest')).assertEqual(-1);
      expect(ids.indexOf('space-station') >= 0).assertTrue();
      expect(ids.indexOf('home-cottage') >= 0).assertTrue();
      expect(ids.length).assertEqual(10);
      done();
    });

    it('appendOrRotateAtCapAllPinnedRefuses', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      const ten: string[] = [
        'fruit-forest', 'school-castle', 'home-cottage', 'animal-safari', 'ocean-realm',
        'a', 'b', 'c', 'd', 'e',
      ];
      await svc.setActiveIds(ten);
      for (let i = 0; i < ten.length; i++) {
        await svc.togglePin(ten[i]);
      }
      const before: string = JSON.stringify(svc.getActiveIds());
      const out: AppendOutcome = await svc.appendOrRotate('space-station');
      expect(out.result).assertEqual('refused-all-pinned');
      expect(out.autoClosed === null).assertTrue();
      expect(JSON.stringify(svc.getActiveIds())).assertEqual(before);
      expect(svc.getActiveIds().indexOf('space-station')).assertEqual(-1);
      done();
    });

    it('appendOrRotateNoOpOnAlreadyActive', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      await svc.initWithDefaults(DEFAULTS);
      const before: string = JSON.stringify(svc.getActiveIds());
      const out: AppendOutcome = await svc.appendOrRotate('fruit-forest');
      expect(out.result).assertEqual('activated');
      expect(out.autoClosed === null).assertTrue();
      expect(JSON.stringify(svc.getActiveIds())).assertEqual(before);
      done();
    });
  });

  describe('PackSelectionService rotation', () => {
    it('three perfects on an unpinned pack swap it for next candidate', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      await svc.initWithDefaults(DEFAULTS);
      const provider: StubCandidateProvider = new StubCandidateProvider();
      provider.packs = [
        mkCandidate('fam-1', 'family', 5000),
        mkCandidate('glob-1', 'global', 4000),
      ];
      let r: PerfectAdventureResult = await svc.recordPerfectAdventure('fruit-forest', provider);
      expect(r.rotated).assertFalse();
      r = await svc.recordPerfectAdventure('fruit-forest', provider);
      expect(r.rotated).assertFalse();
      r = await svc.recordPerfectAdventure('fruit-forest', provider);
      expect(r.rotated).assertTrue();
      expect(r.swappedInId).assertEqual('fam-1');
      expect(svc.getActiveIds().indexOf('fruit-forest')).assertEqual(-1);
      expect(svc.getActiveIds().indexOf('fam-1') >= 0).assertTrue();
      done();
    });

    it('pinned packs never rotate even on 5+ perfects', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      await svc.initWithDefaults(DEFAULTS);
      await svc.togglePin('fruit-forest');
      const provider: StubCandidateProvider = new StubCandidateProvider();
      provider.packs = [mkCandidate('fam-1', 'family', 5000)];
      for (let i = 0; i < 5; i++) {
        const r: PerfectAdventureResult = await svc.recordPerfectAdventure('fruit-forest', provider);
        expect(r.rotated).assertFalse();
      }
      expect(svc.getActiveIds().indexOf('fruit-forest') >= 0).assertTrue();
      done();
    });

    it('exhausted candidate pool freezes the set instead of rotating', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      await svc.initWithDefaults(DEFAULTS);
      const provider: StubCandidateProvider = new StubCandidateProvider();
      for (let i = 0; i < 3; i++) {
        const r: PerfectAdventureResult = await svc.recordPerfectAdventure('fruit-forest', provider);
        expect(r.rotated).assertFalse();
      }
      expect(svc.getActiveIds().indexOf('fruit-forest') >= 0).assertTrue();
      expect(svc.perfectScore('fruit-forest')).assertEqual(3);
      done();
    });

    it('preserves family > global > builtin priority in candidate selection', 0, async (done: () => void) => {
      const svc: PackSelectionService = new PackSelectionService();
      svc.injectPreferences(new MemPrefs());
      await svc.initWithDefaults(DEFAULTS);
      const provider: StubCandidateProvider = new StubCandidateProvider();
      provider.packs = [
        mkCandidate('builtin-extra', 'builtin', 9000),
        mkCandidate('global-extra', 'global', 8000),
        mkCandidate('family-extra', 'family', 1000),
      ];
      for (let i = 0; i < 3; i++) {
        await svc.recordPerfectAdventure('fruit-forest', provider);
      }
      expect(svc.getActiveIds().indexOf('family-extra') >= 0).assertTrue();
      done();
    });
  });
}
