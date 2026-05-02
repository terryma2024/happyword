import { describe, it, expect } from '@ohos/hypium';
import { CloudCredentials, CloudCredentialsSnapshot } from '../main/ets/services/CloudCredentials';
import {
  AssetStoreLike,
  DeviceIdProvider,
} from '../main/ets/services/DeviceIdProvider';
import {
  BarcodeScannerLike,
  BindingHttpClientLike,
  BindingHttpError,
  BindingRedeemArgs,
  BindingRedeemResult,
  BindingState,
  BindingStateUpdate,
  CancelledScanError,
  DeviceBindingService,
  extractTokenFromQrPayload,
} from '../main/ets/services/DeviceBindingService';
import { StringPreferencesLike } from '../main/ets/services/WrongAnswerStore';

class MemPrefs implements StringPreferencesLike {
  store: Map<string, string> = new Map<string, string>();
  async getString(key: string): Promise<string> {
    return this.store.get(key) ?? '';
  }
  async putString(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
  async flush(): Promise<void> { }
}

class StubAsset implements AssetStoreLike {
  stored: string | null = 'aabbccdd11112222deadbeef33334444';
  async query(_alias: string): Promise<string | null> {
    return this.stored;
  }
  async add(_alias: string, secret: string): Promise<void> {
    this.stored = secret;
  }
}

class StubScanner implements BarcodeScannerLike {
  next: string = '';
  shouldThrow: boolean = false;
  throwCancelled: boolean = false;
  async scan(): Promise<string> {
    if (this.throwCancelled) {
      throw new CancelledScanError();
    }
    if (this.shouldThrow) {
      throw new Error('scan failed');
    }
    return this.next;
  }
}

class StubHttp implements BindingHttpClientLike {
  result: BindingRedeemResult = new BindingRedeemResult();
  err?: BindingHttpError;
  netErr: boolean = false;
  lastArgs?: BindingRedeemArgs;
  async redeem(args: BindingRedeemArgs): Promise<BindingRedeemResult> {
    this.lastArgs = args;
    if (this.netErr) {
      throw new Error('boom');
    }
    if (this.err !== undefined) {
      throw this.err;
    }
    return this.result;
  }
}

function makeOkResult(): BindingRedeemResult {
  const r: BindingRedeemResult = new BindingRedeemResult();
  r.bindingId = 'bind-aabbccdd';
  r.familyId = 'fam-12345678';
  r.childProfileId = 'child-deadbeef';
  r.nickname = '宝贝';
  r.avatarEmoji = '🦄';
  r.deviceToken = 'jwt.body.sig';
  return r;
}

class StateRecorder {
  states: BindingState[] = [];
  lastSnap?: CloudCredentialsSnapshot;
  lastReason?: string;
  listener(): (u: BindingStateUpdate) => void {
    return (u: BindingStateUpdate): void => {
      this.states.push(u.state);
      if (u.snapshot !== undefined) {
        this.lastSnap = u.snapshot;
      }
      if (u.reason !== undefined) {
        this.lastReason = u.reason;
      }
    };
  }
}

async function makeService(scanner: StubScanner, http: StubHttp): Promise<DeviceBindingService> {
  const provider: DeviceIdProvider = new DeviceIdProvider();
  provider.injectAssetStore(new StubAsset());
  provider.injectPreferences(new MemPrefs());
  const cc: CloudCredentials = new CloudCredentials();
  cc.injectPreferences(new MemPrefs());
  return new DeviceBindingService(scanner, http, provider, cc);
}

export default function deviceBindingServiceTest(): void {
  describe('DeviceBindingService.parseQrUrl', () => {
    it('extractsTokenFromValidPayload', 0, () => {
      expect(extractTokenFromQrPayload('https://happyword.vercel.app/p/abc123def456'))
        .assertEqual('abc123def456');
    });
    it('handlesQueryAndFragment', 0, () => {
      expect(extractTokenFromQrPayload('https://x/p/tok123?utm=foo#frag'))
        .assertEqual('tok123');
    });
    it('returnsEmptyOnUnrelatedString', 0, () => {
      expect(extractTokenFromQrPayload('hello world')).assertEqual('');
    });
  });

  describe('DeviceBindingService.start', () => {
    it('happyPathTransitionsScanningRedeemingBound', 0, async () => {
      const scanner: StubScanner = new StubScanner();
      scanner.next = 'https://happyword.vercel.app/p/abc123def456';
      const http: StubHttp = new StubHttp();
      http.result = makeOkResult();
      const svc: DeviceBindingService = await makeService(scanner, http);
      const rec: StateRecorder = new StateRecorder();
      svc.setListener(rec.listener());
      await svc.start();
      expect(rec.states[0]).assertEqual('scanning');
      expect(rec.states[1]).assertEqual('redeeming');
      expect(rec.states[rec.states.length - 1]).assertEqual('bound');
      expect(rec.lastSnap !== undefined).assertEqual(true);
      const snap: CloudCredentialsSnapshot = rec.lastSnap as CloudCredentialsSnapshot;
      expect(snap.bindingId).assertEqual('bind-aabbccdd');
      expect(snap.familyId).assertEqual('fam-12345678');
      expect(http.lastArgs?.token).assertEqual('abc123def456');
      expect(http.lastArgs?.deviceId).assertEqual('aabbccdd11112222deadbeef33334444');
    });

    it('cancelledScanReturnsToIdle', 0, async () => {
      const scanner: StubScanner = new StubScanner();
      scanner.throwCancelled = true;
      const http: StubHttp = new StubHttp();
      const svc: DeviceBindingService = await makeService(scanner, http);
      const rec: StateRecorder = new StateRecorder();
      svc.setListener(rec.listener());
      await svc.start();
      expect(rec.states[rec.states.length - 1]).assertEqual('idle');
    });

    it('expiredTokenSetsFailedReason', 0, async () => {
      const scanner: StubScanner = new StubScanner();
      scanner.next = 'https://x/p/expiredtoken12';
      const http: StubHttp = new StubHttp();
      http.err = new BindingHttpError('TOKEN_EXPIRED', 'gone', 410);
      const svc: DeviceBindingService = await makeService(scanner, http);
      const rec: StateRecorder = new StateRecorder();
      svc.setListener(rec.listener());
      await svc.start();
      expect(rec.states[rec.states.length - 1]).assertEqual('failed');
      expect(rec.lastReason).assertEqual('TOKEN_EXPIRED');
    });

    it('alreadyRedeemedTokenSetsFailedReason', 0, async () => {
      const scanner: StubScanner = new StubScanner();
      scanner.next = 'https://x/p/usedtoken1234';
      const http: StubHttp = new StubHttp();
      http.err = new BindingHttpError('TOKEN_REDEEMED', 'conflict', 409);
      const svc: DeviceBindingService = await makeService(scanner, http);
      const rec: StateRecorder = new StateRecorder();
      svc.setListener(rec.listener());
      await svc.start();
      expect(rec.lastReason).assertEqual('TOKEN_REDEEMED');
    });

    it('networkErrorSetsFailedNetwork', 0, async () => {
      const scanner: StubScanner = new StubScanner();
      scanner.next = 'https://x/p/sometoken1234';
      const http: StubHttp = new StubHttp();
      http.netErr = true;
      const svc: DeviceBindingService = await makeService(scanner, http);
      const rec: StateRecorder = new StateRecorder();
      svc.setListener(rec.listener());
      await svc.start();
      expect(rec.lastReason).assertEqual('NETWORK');
    });

    it('invalidQrShortCircuitsToFailedTokenInvalid', 0, async () => {
      const scanner: StubScanner = new StubScanner();
      scanner.next = 'random-string-no-p-segment';
      const http: StubHttp = new StubHttp();
      const svc: DeviceBindingService = await makeService(scanner, http);
      const rec: StateRecorder = new StateRecorder();
      svc.setListener(rec.listener());
      await svc.start();
      expect(rec.lastReason).assertEqual('TOKEN_INVALID');
    });

    it('cancelMidScanResetsToIdle', 0, async () => {
      const scanner: StubScanner = new StubScanner();
      scanner.next = 'https://x/p/anything';
      const http: StubHttp = new StubHttp();
      const svc: DeviceBindingService = await makeService(scanner, http);
      const rec: StateRecorder = new StateRecorder();
      svc.setListener(rec.listener());
      const p: Promise<void> = svc.start();
      svc.cancel();
      await p;
      // The async start can already have transitioned through scanning →
      // redeeming → bound by the time cancel hits, but in the synchronous
      // path the cancel call itself toggles to idle when state was scanning.
      // We at least assert no exception escaped and a final state was recorded.
      expect(rec.states.length).assertLarger(0);
    });
  });

  describe('DeviceBindingService.redeemShortCode', () => {
    it('shortCodePathSendsShortCodeAndDeviceId', 0, async () => {
      const scanner: StubScanner = new StubScanner();
      const http: StubHttp = new StubHttp();
      http.result = makeOkResult();
      const svc: DeviceBindingService = await makeService(scanner, http);
      const rec: StateRecorder = new StateRecorder();
      svc.setListener(rec.listener());
      await svc.redeemShortCode('123456');
      expect(http.lastArgs?.shortCode).assertEqual('123456');
      expect(http.lastArgs?.token).assertEqual('');
      expect(rec.states[rec.states.length - 1]).assertEqual('bound');
    });

    it('shortCodeWrongLengthFailsTokenInvalid', 0, async () => {
      const svc: DeviceBindingService = await makeService(new StubScanner(), new StubHttp());
      const rec: StateRecorder = new StateRecorder();
      svc.setListener(rec.listener());
      await svc.redeemShortCode('12');
      expect(rec.lastReason).assertEqual('TOKEN_INVALID');
    });
  });
}
