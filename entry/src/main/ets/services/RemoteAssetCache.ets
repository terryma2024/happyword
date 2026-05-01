import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@ohos.base';
import { buffer } from '@kit.ArkTS';

/**
 * RemoteAssetCache — lazy on-disk LRU cache for word illustration / audio URLs
 * (V0.5.D). The cache is keyed by URL; each kind has its own bucket and its
 * own LRU cap. Misses trigger a single fetch via {@link AssetHttpFetcher};
 * failures resolve to undefined so the rendering layer can fall back to
 * bundled SVG / TTS without blocking on the network.
 *
 * Tests inject the filesystem adapter and HTTP fetcher; production code uses
 * the {@link RemoteAssetCache.forContext} factory which wires real
 * `@kit.CoreFileKit` + `@kit.NetworkKit` implementations. Production v1
 * packs (which is what currently ships) carry no Blob URLs, so consumers
 * can treat `resolve()` returning undefined as the steady-state path.
 */

export enum AssetKind {
  Illustration = 'illustration',
  Audio = 'audio',
}

export const ASSET_DIR_ILLUSTRATIONS: string = 'illustrations';
export const ASSET_DIR_AUDIO: string = 'audio';
export const ILLUSTRATION_LRU_CAP: number = 50;
export const AUDIO_LRU_CAP: number = 100;
const FETCH_TIMEOUT_MS: number = 6000;
// HarmonyOS file APIs raise this code when mkdir hits an existing directory.
const FS_ERR_FILE_EXISTS: number = 13900015;
// HarmonyOS file APIs raise this code when unlink hits a missing file.
const FS_ERR_NO_SUCH_FILE: number = 13900002;

export interface AssetFsAdapter {
  ensureDir(dir: string): Promise<void>;
  exists(path: string): Promise<boolean>;
  writeBytes(path: string, bytes: ArrayBuffer): Promise<void>;
  readBytes(path: string): Promise<ArrayBuffer>;
  deletePath(path: string): Promise<void>;
  listDir(dir: string): Promise<string[]>;
}

export interface AssetHttpFetcher {
  fetchBinary(url: string): Promise<ArrayBuffer | undefined>;
}

class IndexEntry {
  url: string = '';
  fileName: string = '';
  lastAccessedMs: number = 0;
}

export class RemoteAssetCache {
  private readonly fsAdapter: AssetFsAdapter;
  private readonly fetcher: AssetHttpFetcher;
  private readonly root: string;
  private readonly indexes: Map<AssetKind, Map<string, IndexEntry>> =
    new Map<AssetKind, Map<string, IndexEntry>>();
  private bootstrapped: boolean = false;

  constructor(fsAdapter: AssetFsAdapter, fetcher: AssetHttpFetcher, root: string) {
    this.fsAdapter = fsAdapter;
    this.fetcher = fetcher;
    this.root = RemoteAssetCache.trimTrailingSlash(root);
    this.indexes.set(AssetKind.Illustration, new Map<string, IndexEntry>());
    this.indexes.set(AssetKind.Audio, new Map<string, IndexEntry>());
  }

  static forContext(ctx: common.UIAbilityContext): RemoteAssetCache {
    const fsAdapter: AssetFsAdapter = new RealAssetFs();
    const fetcher: AssetHttpFetcher = new RealAssetFetcher();
    const root: string = `${ctx.filesDir}/asset-cache`;
    return new RemoteAssetCache(fsAdapter, fetcher, root);
  }

  async resolve(url: string, kind: AssetKind): Promise<string | undefined> {
    if (url.length === 0) {
      return undefined;
    }
    await this.ensureBootstrapped();

    const index: Map<string, IndexEntry> | undefined = this.indexes.get(kind);
    if (index === undefined) {
      return undefined;
    }
    const cached: IndexEntry | undefined = index.get(url);
    if (cached !== undefined) {
      const cachedPath: string = this.pathFor(kind, cached.fileName);
      if (await this.fsAdapter.exists(cachedPath)) {
        cached.lastAccessedMs = Date.now();
        return cachedPath;
      }
      // Disk file vanished (e.g. user cleared storage). Drop the
      // index entry so we re-fetch below.
      index.delete(url);
    }

    const bytes: ArrayBuffer | undefined = await this.fetcher.fetchBinary(url);
    if (bytes === undefined) {
      return undefined;
    }
    const fileName: string = RemoteAssetCache.fileNameFor(url);
    const fullPath: string = this.pathFor(kind, fileName);
    try {
      await this.fsAdapter.writeBytes(fullPath, bytes);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      console.error(`RemoteAssetCache.write failed for ${fullPath}: ${JSON.stringify(be)}`);
      return undefined;
    }
    const entry: IndexEntry = new IndexEntry();
    entry.url = url;
    entry.fileName = fileName;
    entry.lastAccessedMs = Date.now();
    index.set(url, entry);
    await this.evictIfNeeded(kind);
    return fullPath;
  }

  private async ensureBootstrapped(): Promise<void> {
    if (this.bootstrapped) {
      return;
    }
    this.bootstrapped = true;
    await this.fsAdapter.ensureDir(this.root);
    await this.fsAdapter.ensureDir(`${this.root}/${ASSET_DIR_ILLUSTRATIONS}`);
    await this.fsAdapter.ensureDir(`${this.root}/${ASSET_DIR_AUDIO}`);
    // We deliberately do NOT rebuild url -> fileName mappings from the
    // listing because we don't store URLs on disk. A cold-start process
    // simply re-fetches assets the first time they're requested again —
    // fine for V0.5.D where ≤ 150 small files total.
  }

  private pathFor(kind: AssetKind, fileName: string): string {
    const bucket: string = kind === AssetKind.Illustration
      ? ASSET_DIR_ILLUSTRATIONS
      : ASSET_DIR_AUDIO;
    return `${this.root}/${bucket}/${fileName}`;
  }

  private async evictIfNeeded(kind: AssetKind): Promise<void> {
    const cap: number = kind === AssetKind.Illustration ? ILLUSTRATION_LRU_CAP : AUDIO_LRU_CAP;
    const index: Map<string, IndexEntry> | undefined = this.indexes.get(kind);
    if (index === undefined || index.size <= cap) {
      return;
    }
    const ordered: IndexEntry[] = [];
    index.forEach((e: IndexEntry): void => {
      ordered.push(e);
    });
    ordered.sort((a: IndexEntry, b: IndexEntry): number => a.lastAccessedMs - b.lastAccessedMs);
    const overflow: number = index.size - cap;
    for (let i = 0; i < overflow; i++) {
      const victim: IndexEntry = ordered[i];
      const path: string = this.pathFor(kind, victim.fileName);
      try {
        await this.fsAdapter.deletePath(path);
      } catch (err) {
        const be: BusinessError = err as BusinessError;
        console.error(`RemoteAssetCache.evict failed for ${path}: ${JSON.stringify(be)}`);
      }
      index.delete(victim.url);
    }
  }

  private static trimTrailingSlash(p: string): string {
    let end: number = p.length;
    while (end > 0 && p.charAt(end - 1) === '/') {
      end -= 1;
    }
    return p.substring(0, end);
  }

  private static fileNameFor(url: string): string {
    const dotIdx: number = url.lastIndexOf('.');
    const rawExt: string = dotIdx > 0 ? url.substring(dotIdx + 1).toLowerCase() : 'bin';
    // Defensive: if the URL has a trailing query (?v=2), strip it from the ext.
    const qIdx: number = rawExt.indexOf('?');
    const cleanExt: string = qIdx >= 0 ? rawExt.substring(0, qIdx) : rawExt;
    const safeExt: string = cleanExt.length === 0 || cleanExt.length > 5 ? 'bin' : cleanExt;
    const hash: string = RemoteAssetCache.hashUrl(url);
    return `${hash}.${safeExt}`;
  }

  // FNV-1a 32-bit hash, hex-encoded (8 chars). We only need a stable
  // collision-resistant key for cache file names; cryptographic strength
  // is not required so we avoid pulling in @ohos.security.cryptoFramework.
  private static hashUrl(url: string): string {
    let h: number = 0x811c9dc5;
    for (let i = 0; i < url.length; i++) {
      h ^= url.charCodeAt(i);
      h = Math.imul(h, 0x01000193) >>> 0;
    }
    return h.toString(16).padStart(8, '0');
  }
}

class RealAssetFs implements AssetFsAdapter {
  async ensureDir(dir: string): Promise<void> {
    try {
      await fs.mkdir(dir, true);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      if (be.code !== FS_ERR_FILE_EXISTS) {
        throw err as Error;
      }
    }
  }

  async exists(path: string): Promise<boolean> {
    try {
      return await fs.access(path);
    } catch (_err) {
      return false;
    }
  }

  async writeBytes(path: string, bytes: ArrayBuffer): Promise<void> {
    let file: fs.File | undefined;
    try {
      file = await fs.open(
        path,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
      );
      await fs.write(file.fd, bytes);
    } catch (err) {
      throw err as Error;
    } finally {
      if (file !== undefined) {
        try {
          await fs.close(file);
        } catch (closeErr) {
          console.error(
            `RealAssetFs.writeBytes close failed: ${JSON.stringify(closeErr as BusinessError)}`,
          );
        }
      }
    }
  }

  async readBytes(path: string): Promise<ArrayBuffer> {
    let file: fs.File | undefined;
    try {
      file = await fs.open(path, fs.OpenMode.READ_ONLY);
      const stat: fs.Stat = await fs.stat(path);
      const bufRef: ArrayBuffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, bufRef);
      return bufRef;
    } catch (err) {
      throw err as Error;
    } finally {
      if (file !== undefined) {
        try {
          await fs.close(file);
        } catch (closeErr) {
          console.error(
            `RealAssetFs.readBytes close failed: ${JSON.stringify(closeErr as BusinessError)}`,
          );
        }
      }
    }
  }

  async deletePath(path: string): Promise<void> {
    try {
      await fs.unlink(path);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      if (be.code !== FS_ERR_NO_SUCH_FILE) {
        throw err as Error;
      }
    }
  }

  async listDir(dir: string): Promise<string[]> {
    try {
      return await fs.listFile(dir);
    } catch (_err) {
      return [];
    }
  }
}

class RealAssetFetcher implements AssetHttpFetcher {
  async fetchBinary(url: string): Promise<ArrayBuffer | undefined> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: FETCH_TIMEOUT_MS,
        readTimeout: FETCH_TIMEOUT_MS,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      });
      if (resp.responseCode !== 200) {
        return undefined;
      }
      const result: string | Object | ArrayBuffer = resp.result;
      if (result instanceof ArrayBuffer) {
        return result;
      }
      if (result instanceof Uint8Array) {
        return result.buffer.slice(0);
      }
      if (typeof result === 'string') {
        return buffer.from(result, 'utf-8').buffer;
      }
      return undefined;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      console.error(`RealAssetFetcher.fetchBinary failed for ${url}: ${JSON.stringify(be)}`);
      return undefined;
    } finally {
      req.destroy();
    }
  }
}
