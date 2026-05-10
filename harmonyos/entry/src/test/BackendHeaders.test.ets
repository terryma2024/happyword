import { describe, it, expect } from '@ohos/hypium';
import {
  buildVercelBypassHeader,
  mergeHeaders,
  VERCEL_BYPASS_HEADER,
} from '../main/ets/services/BackendHeaders';
import { BackendEnv } from '../main/ets/services/BackendEnv';

/**
 * Pure-function tests for BackendHeaders. Mirrors the server e2e
 * driver's branch logic (`server/tests/e2e/_utils/vercel.py`):
 *   - empty secret  → no header (any env)
 *   - non-preview   → no header (even with secret)
 *   - preview+secret → x-vercel-protection-bypass attached
 */
export default function backendHeadersTest(): void {
  describe('BackendHeaders.buildVercelBypassHeader', () => {
    it('returnsEmptyForNonPreviewEnvEvenWithSecret', 0, () => {
      const h: Record<string, string> = buildVercelBypassHeader(
        BackendEnv.STAGING,
        'super-secret',
      );
      expect(Object.keys(h).length).assertEqual(0);
    });

    it('returnsEmptyForLocalEnv', 0, () => {
      const h: Record<string, string> = buildVercelBypassHeader(
        BackendEnv.LOCAL,
        'super-secret',
      );
      expect(Object.keys(h).length).assertEqual(0);
    });

    it('returnsEmptyForProdEnv', 0, () => {
      const h: Record<string, string> = buildVercelBypassHeader(
        BackendEnv.PROD,
        'super-secret',
      );
      expect(Object.keys(h).length).assertEqual(0);
    });

    it('returnsEmptyForPreviewWithEmptySecret', 0, () => {
      const h: Record<string, string> = buildVercelBypassHeader(
        BackendEnv.PREVIEW,
        '',
      );
      expect(Object.keys(h).length).assertEqual(0);
    });

    it('attachesBypassHeaderForPreviewWithSecret', 0, () => {
      const h: Record<string, string> = buildVercelBypassHeader(
        BackendEnv.PREVIEW,
        'super-secret',
      );
      expect(h[VERCEL_BYPASS_HEADER]).assertEqual('super-secret');
      expect(Object.keys(h).length).assertEqual(1);
    });

    it('usesCanonicalLowercaseHeaderName', 0, () => {
      // Vercel checks the lowercase name. Don't accidentally rename
      // the constant — server e2e helper hardcodes the same string.
      expect(VERCEL_BYPASS_HEADER).assertEqual('x-vercel-protection-bypass');
    });

    it('returnsEmptyForUnknownEnvString', 0, () => {
      // Defensive — `env` is a free string in the AppStorage cache so
      // a corrupt value should NOT accidentally attach the header.
      const h: Record<string, string> = buildVercelBypassHeader(
        'garbage-env',
        'super-secret',
      );
      expect(Object.keys(h).length).assertEqual(0);
    });
  });

  describe('BackendHeaders.mergeHeaders', () => {
    it('mergesDisjointKeysFromBothInputs', 0, () => {
      const base: Record<string, string> = { 'Accept': 'application/json' };
      const extra: Record<string, string> = { 'X-Foo': 'bar' };
      const out: Record<string, string> = mergeHeaders(base, extra);
      expect(out['Accept']).assertEqual('application/json');
      expect(out['X-Foo']).assertEqual('bar');
      expect(Object.keys(out).length).assertEqual(2);
    });

    it('extraOverridesBaseOnCollision', 0, () => {
      const base: Record<string, string> = { 'Authorization': 'Bearer old' };
      const extra: Record<string, string> = { 'Authorization': 'Bearer new' };
      const out: Record<string, string> = mergeHeaders(base, extra);
      expect(out['Authorization']).assertEqual('Bearer new');
    });

    it('doesNotMutateInputs', 0, () => {
      const base: Record<string, string> = { 'Accept': 'application/json' };
      const extra: Record<string, string> = { 'X-Foo': 'bar' };
      mergeHeaders(base, extra);
      expect(Object.keys(base).length).assertEqual(1);
      expect(Object.keys(extra).length).assertEqual(1);
      // Confirm no cross-contamination.
      const baseHasFoo: boolean = base['X-Foo'] !== undefined;
      const extraHasAccept: boolean = extra['Accept'] !== undefined;
      expect(baseHasFoo).assertEqual(false);
      expect(extraHasAccept).assertEqual(false);
    });

    it('handlesEmptyExtra', 0, () => {
      const base: Record<string, string> = { 'Accept': 'application/json' };
      const extra: Record<string, string> = {};
      const out: Record<string, string> = mergeHeaders(base, extra);
      expect(out['Accept']).assertEqual('application/json');
      expect(Object.keys(out).length).assertEqual(1);
    });

    it('handlesEmptyBase', 0, () => {
      const base: Record<string, string> = {};
      const extra: Record<string, string> = { 'X-Foo': 'bar' };
      const out: Record<string, string> = mergeHeaders(base, extra);
      expect(out['X-Foo']).assertEqual('bar');
      expect(Object.keys(out).length).assertEqual(1);
    });
  });
}
