import { CloudCredentials, CloudCredentialsSnapshot } from './CloudCredentials';
import { ParentFetchAdapter, ParentFetchResult } from './ParentApiClient';
import { StringPreferencesLike } from './WrongAnswerStore';

/**
 * V0.6.6 — client adapter for the cloud wishlist + redemption flow.
 *
 * Responsibilities:
 *  - Fetch the bound child's active cloud items (overlay on top of the
 *    local catalog).
 *  - Submit a redemption request and persist the pending entry locally
 *    so the page can render the overlay across navigations.
 *  - Apply server-side decisions returned by ParentRedemptionPoll.
 *
 * Transport failures never throw out of the public API; they degrade to
 * `unbound` / empty results so the unbound branch keeps working.
 */

const HEADER_AUTH: string = 'Authorization';
const HEADER_CONTENT_TYPE: string = 'Content-Type';
const HEADER_ACCEPT: string = 'Accept';
const CONTENT_JSON: string = 'application/json';
const PREFS_KEY_PENDING: string = 'pending_redemptions_v1';
const PREFS_KEY_LAST_POLL_MS: string = 'redemption_poll_since_ms';

export class CloudWishlistItem {
  itemId: string = '';
  childProfileId: string = '';
  displayName: string = '';
  costCoins: number = 0;
  iconEmoji: string = '🎁';
  state: string = 'active';
  isParentCurated: boolean = true;
  createdBy: string = 'parent';
}

export class PendingRedemption {
  requestId: string = '';
  wishlistItemId: string = '';
  displayName: string = '';
  costCoins: number = 0;
  requestedAtMs: number = 0;
}

export class RedemptionDecision {
  requestId: string = '';
  wishlistItemId: string = '';
  status: string = '';            // approved | rejected | expired
  costCoinsAtRequest: number = 0;
  decidedAtMs: number = 0;
}

/**
 * V0.6.6 — minimal seam consumed by ParentRedemptionPoll. CloudWishlistService
 * implements this directly; tests can supply a stub without dragging in the
 * full service constructor (CloudCredentials / ParentFetchAdapter / baseUrl).
 *
 * Defined here (not in ParentRedemptionPoll.ets) so CloudWishlistService can
 * declare `implements RedemptionPollSource` without creating a circular
 * import — ArkTS strict mode (`arkts-no-structural-typing`) refuses to pass
 * the service to `new ParentRedemptionPoll(svc)` unless the implements
 * relationship is declared explicitly.
 */
export interface RedemptionPollSource {
  pollDecisions(): Promise<RedemptionDecision[]>;
}

interface RawCloudWishlistItem {
  item_id?: string;
  child_profile_id?: string;
  display_name?: string;
  cost_coins?: number;
  icon_emoji?: string;
  state?: string;
  is_parent_curated?: boolean;
  created_by?: string;
}

interface RawWishlistListOut {
  items?: RawCloudWishlistItem[];
}

interface RawRedemption {
  request_id?: string;
  child_profile_id?: string;
  wishlist_item_id?: string;
  cost_coins_at_request?: number;
  requested_at?: string;
  status?: string;
  decided_at?: string | null;
}

interface RawRedemptionPollOut {
  items?: RawRedemption[];
  server_now_ms?: number;
}

interface RawSubmitOut {
  request_id?: string;
  wishlist_item_id?: string;
  cost_coins_at_request?: number;
  status?: string;
}

interface RawPendingEntry {
  request_id?: string;
  wishlist_item_id?: string;
  display_name?: string;
  cost_coins?: number;
  requested_at_ms?: number;
}

interface RawPendingShape {
  pending?: RawPendingEntry[];
}

class PendingPersistEntry {
  request_id: string = '';
  wishlist_item_id: string = '';
  display_name: string = '';
  cost_coins: number = 0;
  requested_at_ms: number = 0;
}

class PendingPersistShape {
  pending: PendingPersistEntry[] = [];
}

class RedemptionRequestBody {
  wishlist_item_id: string = '';
}

export class CloudWishlistService implements RedemptionPollSource {
  private readonly credentials: CloudCredentials;
  private readonly adapter: ParentFetchAdapter;
  private readonly baseUrl: string;
  private prefs?: StringPreferencesLike;
  private nowMs: () => number = (): number => Date.now();
  private cached: CloudWishlistItem[] = [];
  private pending: PendingRedemption[] = [];
  private hydrated: boolean = false;

  constructor(
    credentials: CloudCredentials,
    adapter: ParentFetchAdapter,
    baseUrl: string,
  ) {
    this.credentials = credentials;
    this.adapter = adapter;
    this.baseUrl = CloudWishlistService.trim(baseUrl);
  }

  injectPreferences(p: StringPreferencesLike): void {
    this.prefs = p;
  }

  injectClock(now: () => number): void {
    this.nowMs = now;
  }

  /**
   * Replace the in-memory cache from preferences. Callers should invoke
   * this once during attach so a cold-start render finds the previous
   * pending entries before any network round-trip completes.
   */
  async hydrate(): Promise<void> {
    if (this.hydrated) {
      return;
    }
    this.hydrated = true;
    if (this.prefs === undefined) {
      return;
    }
    const raw: string = await this.prefs.getString(PREFS_KEY_PENDING);
    if (raw.length === 0) {
      return;
    }
    let parsed: RawPendingShape | null = null;
    try {
      parsed = JSON.parse(raw) as RawPendingShape;
    } catch (_err) {
      return;
    }
    if (parsed === null || !Array.isArray(parsed.pending)) {
      return;
    }
    const list: RawPendingEntry[] = parsed.pending;
    for (let i = 0; i < list.length; i++) {
      const e: RawPendingEntry = list[i];
      const p: PendingRedemption = new PendingRedemption();
      p.requestId = e.request_id !== undefined ? e.request_id : '';
      p.wishlistItemId = e.wishlist_item_id !== undefined ? e.wishlist_item_id : '';
      p.displayName = e.display_name !== undefined ? e.display_name : '';
      p.costCoins = typeof e.cost_coins === 'number' ? e.cost_coins : 0;
      p.requestedAtMs = typeof e.requested_at_ms === 'number' ? e.requested_at_ms : 0;
      if (p.requestId.length > 0 && p.wishlistItemId.length > 0) {
        this.pending.push(p);
      }
    }
  }

  /** Returns the cloud-overlay items currently cached (last fetch). */
  cachedItems(): CloudWishlistItem[] {
    const out: CloudWishlistItem[] = [];
    for (let i = 0; i < this.cached.length; i++) {
      out.push(this.cached[i]);
    }
    return out;
  }

  pendingFor(itemId: string): PendingRedemption | undefined {
    for (let i = 0; i < this.pending.length; i++) {
      if (this.pending[i].wishlistItemId === itemId) {
        return this.pending[i];
      }
    }
    return undefined;
  }

  pendingList(): PendingRedemption[] {
    return this.pending.slice();
  }

  /**
   * Pull the active items for the bound child profile. Returns true on a
   * successful refresh (cache populated). Unbound returns false; transport
   * failures also return false but leave the previous cache in place.
   */
  async refreshList(): Promise<boolean> {
    const snap: CloudCredentialsSnapshot = await this.credentials.load();
    if (!snap.isBound() || snap.deviceToken.length === 0) {
      return false;
    }
    const url: string = `${this.baseUrl}/api/v1/child/wishlist`;
    const headers: Record<string, string> = {};
    headers[HEADER_ACCEPT] = CONTENT_JSON;
    headers[HEADER_AUTH] = `Bearer ${snap.deviceToken}`;
    let res: ParentFetchResult;
    try {
      res = await this.adapter.get(url, headers);
    } catch (_err) {
      return false;
    }
    if (res.status !== 200) {
      return false;
    }
    let parsed: RawWishlistListOut | null = null;
    try {
      parsed = JSON.parse(res.body) as RawWishlistListOut;
    } catch (_err) {
      return false;
    }
    if (parsed === null || !Array.isArray(parsed.items)) {
      return false;
    }
    const items: RawCloudWishlistItem[] = parsed.items;
    const next: CloudWishlistItem[] = [];
    for (let i = 0; i < items.length; i++) {
      const r: RawCloudWishlistItem = items[i];
      const it: CloudWishlistItem = new CloudWishlistItem();
      it.itemId = r.item_id !== undefined ? r.item_id : '';
      it.childProfileId = r.child_profile_id !== undefined ? r.child_profile_id : '';
      it.displayName = r.display_name !== undefined ? r.display_name : '';
      it.costCoins = typeof r.cost_coins === 'number' ? r.cost_coins : 0;
      it.iconEmoji = r.icon_emoji !== undefined ? r.icon_emoji : '🎁';
      it.state = r.state !== undefined ? r.state : 'active';
      it.isParentCurated = r.is_parent_curated === true;
      it.createdBy = r.created_by !== undefined ? r.created_by : 'parent';
      if (it.itemId.length > 0) {
        next.push(it);
      }
    }
    this.cached = next;
    return true;
  }

  /**
   * Submit a redemption request and persist a local pending entry so the
   * overlay survives navigation. Returns the requestId on success or
   * empty string on failure (item inactive, network error, or unbound).
   */
  async requestRedemption(itemId: string, displayName: string, costCoins: number): Promise<string> {
    const snap: CloudCredentialsSnapshot = await this.credentials.load();
    if (!snap.isBound() || snap.deviceToken.length === 0) {
      return '';
    }
    const url: string = `${this.baseUrl}/api/v1/child/redemption-requests`;
    const headers: Record<string, string> = {};
    headers[HEADER_CONTENT_TYPE] = CONTENT_JSON;
    headers[HEADER_ACCEPT] = CONTENT_JSON;
    headers[HEADER_AUTH] = `Bearer ${snap.deviceToken}`;
    const reqBody: RedemptionRequestBody = new RedemptionRequestBody();
    reqBody.wishlist_item_id = itemId;
    const body: string = JSON.stringify(reqBody);

    let res: ParentFetchResult;
    try {
      res = await this.adapter.post(url, headers, body);
    } catch (_err) {
      return '';
    }
    if (res.status !== 201) {
      return '';
    }
    let parsed: RawSubmitOut | null = null;
    try {
      parsed = JSON.parse(res.body) as RawSubmitOut;
    } catch (_err) {
      return '';
    }
    if (parsed === null || parsed.request_id === undefined) {
      return '';
    }
    const reqId: string = parsed.request_id;
    const itemFromBody: string = parsed.wishlist_item_id !== undefined ? parsed.wishlist_item_id : itemId;
    const cost: number = typeof parsed.cost_coins_at_request === 'number'
      ? parsed.cost_coins_at_request : costCoins;
    const p: PendingRedemption = new PendingRedemption();
    p.requestId = reqId;
    p.wishlistItemId = itemFromBody;
    p.displayName = displayName;
    p.costCoins = cost;
    p.requestedAtMs = this.nowMs();
    this.pending.push(p);
    await this.persistPending();
    return reqId;
  }

  /**
   * Drop a pending entry by request id; used after the page has rendered
   * the GiftBox / dismissed the overlay following a polled decision.
   */
  async resolvePending(requestId: string): Promise<void> {
    const next: PendingRedemption[] = [];
    for (let i = 0; i < this.pending.length; i++) {
      if (this.pending[i].requestId !== requestId) {
        next.push(this.pending[i]);
      }
    }
    this.pending = next;
    await this.persistPending();
  }

  /**
   * Poll for decisions newer than the persisted cursor. Updates cursor
   * to the server-reported `server_now_ms` on success. Returns the list
   * of decisions to be applied by the caller (so the caller can run the
   * UI flow itself: gift box, toast, etc.).
   */
  async pollDecisions(): Promise<RedemptionDecision[]> {
    const snap: CloudCredentialsSnapshot = await this.credentials.load();
    if (!snap.isBound() || snap.deviceToken.length === 0) {
      return [];
    }
    const sinceMs: number = await this.readSince();
    const url: string =
      `${this.baseUrl}/api/v1/child/redemption-requests/poll?since_ms=${sinceMs}`;
    const headers: Record<string, string> = {};
    headers[HEADER_ACCEPT] = CONTENT_JSON;
    headers[HEADER_AUTH] = `Bearer ${snap.deviceToken}`;
    let res: ParentFetchResult;
    try {
      res = await this.adapter.get(url, headers);
    } catch (_err) {
      return [];
    }
    if (res.status !== 200) {
      return [];
    }
    let parsed: RawRedemptionPollOut | null = null;
    try {
      parsed = JSON.parse(res.body) as RawRedemptionPollOut;
    } catch (_err) {
      return [];
    }
    if (parsed === null) {
      return [];
    }
    const out: RedemptionDecision[] = [];
    if (Array.isArray(parsed.items)) {
      const rows: RawRedemption[] = parsed.items;
      for (let i = 0; i < rows.length; i++) {
        const r: RawRedemption = rows[i];
        const d: RedemptionDecision = new RedemptionDecision();
        d.requestId = r.request_id !== undefined ? r.request_id : '';
        d.wishlistItemId = r.wishlist_item_id !== undefined ? r.wishlist_item_id : '';
        d.status = r.status !== undefined ? r.status : '';
        d.costCoinsAtRequest = typeof r.cost_coins_at_request === 'number'
          ? r.cost_coins_at_request : 0;
        d.decidedAtMs = parseDecidedAtMs(r.decided_at);
        if (d.requestId.length > 0) {
          out.push(d);
        }
      }
    }
    if (typeof parsed.server_now_ms === 'number' && parsed.server_now_ms > 0) {
      await this.writeSince(parsed.server_now_ms);
    }
    return out;
  }

  private async persistPending(): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    const wire: PendingPersistEntry[] = [];
    for (let i = 0; i < this.pending.length; i++) {
      const p: PendingRedemption = this.pending[i];
      const e: PendingPersistEntry = new PendingPersistEntry();
      e.request_id = p.requestId;
      e.wishlist_item_id = p.wishlistItemId;
      e.display_name = p.displayName;
      e.cost_coins = p.costCoins;
      e.requested_at_ms = p.requestedAtMs;
      wire.push(e);
    }
    const payload: PendingPersistShape = new PendingPersistShape();
    payload.pending = wire;
    await this.prefs.putString(PREFS_KEY_PENDING, JSON.stringify(payload));
    await this.prefs.flush();
  }

  private async readSince(): Promise<number> {
    if (this.prefs === undefined) {
      return 0;
    }
    const raw: string = await this.prefs.getString(PREFS_KEY_LAST_POLL_MS);
    if (raw.length === 0) {
      return 0;
    }
    const n: number = Number.parseInt(raw, 10);
    return Number.isNaN(n) ? 0 : n;
  }

  private async writeSince(ms: number): Promise<void> {
    if (this.prefs === undefined) {
      return;
    }
    await this.prefs.putString(PREFS_KEY_LAST_POLL_MS, String(ms));
    await this.prefs.flush();
  }

  private static trim(url: string): string {
    if (url.length === 0) {
      return url;
    }
    return url[url.length - 1] === '/' ? url.substring(0, url.length - 1) : url;
  }
}

function parseDecidedAtMs(raw: string | null | undefined): number {
  if (raw === null || raw === undefined || raw.length === 0) {
    return 0;
  }
  const ms: number = Date.parse(raw);
  return Number.isNaN(ms) ? 0 : ms;
}
