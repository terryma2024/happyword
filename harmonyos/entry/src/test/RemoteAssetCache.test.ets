import { describe, it, expect } from '@ohos/hypium';
import {
  RemoteAssetCache,
  AssetFsAdapter,
  AssetHttpFetcher,
  AssetKind,
  ASSET_DIR_ILLUSTRATIONS,
  ASSET_DIR_AUDIO,
  ILLUSTRATION_LRU_CAP,
  AUDIO_LRU_CAP,
} from '../main/ets/services/RemoteAssetCache';

class FakeFs implements AssetFsAdapter {
  readonly storage: Map<string, ArrayBuffer> = new Map<string, ArrayBuffer>();
  readonly listings: Map<string, string[]> = new Map<string, string[]>();

  async ensureDir(dir: string): Promise<void> {
    if (!this.listings.has(dir)) {
      this.listings.set(dir, []);
    }
  }

  async exists(path: string): Promise<boolean> {
    return this.storage.has(path);
  }

  async writeBytes(path: string, bytes: ArrayBuffer): Promise<void> {
    if (!this.storage.has(path)) {
      const parent: string = path.substring(0, path.lastIndexOf('/'));
      const existing: string[] = this.listings.get(parent) ?? [];
      const fileName: string = path.substring(path.lastIndexOf('/') + 1);
      if (existing.indexOf(fileName) < 0) {
        existing.push(fileName);
      }
      this.listings.set(parent, existing);
    }
    this.storage.set(path, bytes);
  }

  async readBytes(path: string): Promise<ArrayBuffer> {
    const got: ArrayBuffer | undefined = this.storage.get(path);
    if (got === undefined) {
      throw new Error(`FakeFs: no such file ${path}`);
    }
    return got;
  }

  async deletePath(path: string): Promise<void> {
    this.storage.delete(path);
    const parent: string = path.substring(0, path.lastIndexOf('/'));
    const fileName: string = path.substring(path.lastIndexOf('/') + 1);
    const existing: string[] = this.listings.get(parent) ?? [];
    const next: string[] = [];
    for (let i = 0; i < existing.length; i++) {
      if (existing[i] !== fileName) {
        next.push(existing[i]);
      }
    }
    this.listings.set(parent, next);
  }

  async listDir(dir: string): Promise<string[]> {
    return (this.listings.get(dir) ?? []).slice();
  }
}

class FakeFetcher implements AssetHttpFetcher {
  readonly responses: Map<string, ArrayBuffer> = new Map<string, ArrayBuffer>();
  readonly errored: Set<string> = new Set<string>();
  fetchCalls: number = 0;

  async fetchBinary(url: string): Promise<ArrayBuffer | undefined> {
    this.fetchCalls += 1;
    if (this.errored.has(url)) {
      return undefined;
    }
    return this.responses.get(url);
  }
}

function makeBytes(label: string): ArrayBuffer {
  const bytes: Uint8Array = new Uint8Array(label.length);
  for (let i = 0; i < label.length; i++) {
    bytes[i] = label.charCodeAt(i);
  }
  return bytes.buffer;
}

const ROOT: string = '/sandbox/asset-cache';

export default function remoteAssetCacheTest(): void {
  describe('RemoteAssetCache', () => {
    it('returnsUndefinedForEmptyUrl', 0, async () => {
      const fs: FakeFs = new FakeFs();
      const f: FakeFetcher = new FakeFetcher();
      const c: RemoteAssetCache = new RemoteAssetCache(fs, f, ROOT);
      const out: string | undefined = await c.resolve('', AssetKind.Illustration);
      expect(out === undefined).assertTrue();
      expect(f.fetchCalls).assertEqual(0);
    });

    it('downloadsAndCachesIllustrationUrlOnFirstResolve', 0, async () => {
      const fs: FakeFs = new FakeFs();
      const f: FakeFetcher = new FakeFetcher();
      const url: string = 'https://blob/illustrations/fruit-apple-aaaaaaaa.png';
      f.responses.set(url, makeBytes('apple-bytes'));
      const c: RemoteAssetCache = new RemoteAssetCache(fs, f, ROOT);
      const path1: string | undefined = await c.resolve(url, AssetKind.Illustration);
      expect(path1 !== undefined).assertTrue();
      if (path1 !== undefined) {
        expect(path1.indexOf(`${ROOT}/${ASSET_DIR_ILLUSTRATIONS}/`) === 0).assertTrue();
        expect(path1.endsWith('.png')).assertTrue();
        expect(await fs.exists(path1)).assertTrue();
      }
      const path2: string | undefined = await c.resolve(url, AssetKind.Illustration);
      expect(path1 !== undefined).assertTrue();
      if (path1 !== undefined) {
        expect(path2).assertEqual(path1);
      }
      expect(f.fetchCalls).assertEqual(1);
    });

    it('downloadsMp3AsAudio', 0, async () => {
      const fs: FakeFs = new FakeFs();
      const f: FakeFetcher = new FakeFetcher();
      const url: string = 'https://blob/audio/fruit-apple-aaaaaaaa.mp3';
      f.responses.set(url, makeBytes('apple-mp3'));
      const c: RemoteAssetCache = new RemoteAssetCache(fs, f, ROOT);
      const path: string | undefined = await c.resolve(url, AssetKind.Audio);
      expect(path !== undefined).assertTrue();
      if (path !== undefined) {
        expect(path.indexOf(`${ROOT}/${ASSET_DIR_AUDIO}/`) === 0).assertTrue();
        expect(path.endsWith('.mp3')).assertTrue();
      }
    });

    it('returnsUndefinedOnDownloadFailure', 0, async () => {
      const fs: FakeFs = new FakeFs();
      const f: FakeFetcher = new FakeFetcher();
      const url: string = 'https://blob/missing.png';
      f.errored.add(url);
      const c: RemoteAssetCache = new RemoteAssetCache(fs, f, ROOT);
      const out: string | undefined = await c.resolve(url, AssetKind.Illustration);
      expect(out === undefined).assertTrue();
      // Failed downloads must NOT poison the cache; subsequent
      // resolve() calls retry exactly once per resolve invocation.
      const out2: string | undefined = await c.resolve(url, AssetKind.Illustration);
      expect(out2 === undefined).assertTrue();
      expect(f.fetchCalls).assertEqual(2);
    });

    it('evictsLeastRecentlyUsedIllustrationOnceCapExceeded', 0, async () => {
      const fs: FakeFs = new FakeFs();
      const f: FakeFetcher = new FakeFetcher();
      const c: RemoteAssetCache = new RemoteAssetCache(fs, f, ROOT);
      const total: number = ILLUSTRATION_LRU_CAP + 5;
      const paths: (string | undefined)[] = [];
      for (let i = 0; i < total; i++) {
        const url: string = `https://blob/illustrations/word-${i}.png`;
        f.responses.set(url, makeBytes(`bytes-${i}`));
        const got: string | undefined = await c.resolve(url, AssetKind.Illustration);
        paths.push(got);
      }
      // The first 5 (oldest) entries must have been evicted from disk
      // because the cache only holds ILLUSTRATION_LRU_CAP entries.
      const evictedCount: number = 5;
      let stillPresent: number = 0;
      for (let i = 0; i < evictedCount; i++) {
        const p: string | undefined = paths[i];
        if (p !== undefined && (await fs.exists(p))) {
          stillPresent += 1;
        }
      }
      expect(stillPresent).assertEqual(0);
      let kept: number = 0;
      for (let i = evictedCount; i < total; i++) {
        const p: string | undefined = paths[i];
        if (p !== undefined && (await fs.exists(p))) {
          kept += 1;
        }
      }
      expect(kept).assertEqual(ILLUSTRATION_LRU_CAP);
    });

    it('illustrationAndAudioCapsAreSeparate', 0, () => {
      // Sanity guard against regressions that would treat them as one bucket.
      expect(ILLUSTRATION_LRU_CAP).assertEqual(50);
      expect(AUDIO_LRU_CAP).assertEqual(100);
    });

    it('refetchesWhenDiskFileDisappeared', 0, async () => {
      const fs: FakeFs = new FakeFs();
      const f: FakeFetcher = new FakeFetcher();
      const url: string = 'https://blob/illustrations/ghost.png';
      f.responses.set(url, makeBytes('ghost-bytes'));
      const c: RemoteAssetCache = new RemoteAssetCache(fs, f, ROOT);
      const first: string | undefined = await c.resolve(url, AssetKind.Illustration);
      expect(first !== undefined).assertTrue();
      if (first !== undefined) {
        // Simulate the OS reclaiming the file (e.g. user clears storage).
        await fs.deletePath(first);
        const second: string | undefined = await c.resolve(url, AssetKind.Illustration);
        expect(second !== undefined).assertTrue();
        expect(f.fetchCalls).assertEqual(2);
      }
    });
  });
}
