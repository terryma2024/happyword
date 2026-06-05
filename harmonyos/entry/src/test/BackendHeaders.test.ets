import { describe, it, expect } from '@ohos/hypium';
import {
  mergeHeaders,
} from '../main/ets/services/BackendHeaders';

/**
 * Pure-function tests for BackendHeaders.
 */
export default function backendHeadersTest(): void {
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
