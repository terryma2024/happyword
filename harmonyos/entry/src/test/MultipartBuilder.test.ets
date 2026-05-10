import { describe, it, expect } from '@ohos/hypium';
import util from '@ohos.util';
import {
  buildSingleImageMultipart,
  escapeFilename,
  MultipartResult,
} from '../main/ets/services/MultipartBuilder';

function decodeAscii(buf: ArrayBuffer): string {
  // util.TextDecoder is the canonical UTF-8 decoder on HarmonyOS; the
  // preamble we generate is pure ASCII so the result is identical to a
  // byte-by-byte fromCharCode loop, but TextDecoder sidesteps any
  // ArkTS quirks around `Uint8Array` indexing inside tight loops.
  const dec: util.TextDecoder = util.TextDecoder.create('utf-8');
  return dec.decodeToString(new Uint8Array(buf));
}

function makeBytes(values: number[]): ArrayBuffer {
  const buf: ArrayBuffer = new ArrayBuffer(values.length);
  const view: Uint8Array = new Uint8Array(buf);
  for (let i: number = 0; i < values.length; i++) {
    view[i] = values[i];
  }
  return buf;
}

/** Naïve substring search over Uint8Array — fine for tiny test inputs. */
function indexOfBytes(haystack: Uint8Array, needle: Uint8Array): number {
  if (needle.length === 0) {
    return 0;
  }
  for (let i: number = 0; i + needle.length <= haystack.length; i++) {
    let match: boolean = true;
    for (let j: number = 0; j < needle.length; j++) {
      if (haystack[i + j] !== needle[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      return i;
    }
  }
  return -1;
}

export default function multipartBuilderTest(): void {
  describe('MultipartBuilder.buildSingleImageMultipart', () => {
    it('emits boundary, headers, payload, and closing boundary', 0, () => {
      const payload: ArrayBuffer = makeBytes([0xff, 0xd8, 0xff, 0xe0]);
      const r: MultipartResult = buildSingleImageMultipart(
        'image',
        'lesson.jpg',
        'image/jpeg',
        payload,
        '----TestBoundaryABC',
      );
      // Compare bytes directly rather than through util.TextDecoder; ArkTS's
      // decodeToString silently swaps stray bytes (in particular the
      // 0xff/0xd8/0xff/0xe0 JPEG marker we splice into the middle) for the
      // U+FFFD replacement character, which then breaks every substring
      // assertion that follows. Byte-level equality avoids the round-trip
      // and matches what libcurl will actually transmit.
      const view: Uint8Array = new Uint8Array(r.body);
      const enc: util.TextEncoder = new util.TextEncoder('utf-8');
      const expectedPreamble: Uint8Array = enc.encodeInto(
        '------TestBoundaryABC\r\n' +
          'Content-Disposition: form-data; name="image"; filename="lesson.jpg"\r\n' +
          'Content-Type: image/jpeg\r\n\r\n',
      );
      const expectedEpilogue: Uint8Array = enc.encodeInto('\r\n------TestBoundaryABC--\r\n');
      // Total length = preamble + payload + epilogue.
      expect(view.length).assertEqual(expectedPreamble.length + 4 + expectedEpilogue.length);
      // Preamble must appear verbatim at the start.
      let preambleOk: boolean = true;
      for (let i: number = 0; i < expectedPreamble.length; i++) {
        if (view[i] !== expectedPreamble[i]) {
          preambleOk = false;
          break;
        }
      }
      expect(preambleOk).assertTrue();
      // Closing boundary marker at the tail.
      let epilogueOk: boolean = true;
      const tailStart: number = view.length - expectedEpilogue.length;
      for (let i: number = 0; i < expectedEpilogue.length; i++) {
        if (view[tailStart + i] !== expectedEpilogue[i]) {
          epilogueOk = false;
          break;
        }
      }
      expect(epilogueOk).assertTrue();
      expect(r.boundary).assertEqual('----TestBoundaryABC');
    });

    it('preserves binary bytes byte-for-byte', 0, () => {
      const payload: ArrayBuffer = makeBytes([0x00, 0x01, 0xff, 0xfe, 0x7f, 0x80]);
      const r: MultipartResult = buildSingleImageMultipart(
        'image',
        'a.jpg',
        'image/jpeg',
        payload,
        '----B',
      );
      const enc: util.TextEncoder = new util.TextEncoder('utf-8');
      const preamble: Uint8Array = enc.encodeInto(
        '------B\r\nContent-Disposition: form-data; name="image"; filename="a.jpg"\r\nContent-Type: image/jpeg\r\n\r\n',
      );
      const view: Uint8Array = new Uint8Array(r.body);
      // Binary bytes must appear unchanged immediately after the preamble.
      const start: number = preamble.length;
      expect(view[start + 0]).assertEqual(0x00);
      expect(view[start + 1]).assertEqual(0x01);
      expect(view[start + 2]).assertEqual(0xff);
      expect(view[start + 3]).assertEqual(0xfe);
      expect(view[start + 4]).assertEqual(0x7f);
      expect(view[start + 5]).assertEqual(0x80);
    });

    it('generates a fresh random boundary when none is supplied', 0, () => {
      const a: MultipartResult = buildSingleImageMultipart(
        'image',
        'a.jpg',
        'image/jpeg',
        makeBytes([0x01]),
      );
      const b: MultipartResult = buildSingleImageMultipart(
        'image',
        'a.jpg',
        'image/jpeg',
        makeBytes([0x01]),
      );
      expect(a.boundary.length > 0).assertTrue();
      expect(b.boundary.length > 0).assertTrue();
      // 16 random bytes → 2^128 collision space; equality across two
      // calls is overwhelmingly unlikely and would indicate a regression.
      expect(a.boundary === b.boundary).assertFalse();
    });

    it('escapeFilename replaces CR / LF / dquote with underscores', 0, () => {
      // Pin the substitution table directly so a regression in the
      // sanitizer can't sneak in via an untested code path.
      expect(escapeFilename('plain.jpg')).assertEqual('plain.jpg');
      expect(escapeFilename('evil"\r\nX-Injected: yes.jpg'))
        .assertEqual('evil___X-Injected: yes.jpg');
      expect(escapeFilename('a"b.jpg')).assertEqual('a_b.jpg');
      expect(escapeFilename('a\rb\nc.jpg')).assertEqual('a_b_c.jpg');
    });

    it('embeds the escaped filename in the multipart body', 0, () => {
      // We rely on `escapeFilename` (covered by its own dedicated test
      // above) to scrub CR / LF / double-quote out of the filename, and
      // here we verify the same scrubbed value actually lands in the
      // emitted Content-Disposition header. Use String.fromCharCode for
      // the special chars so the test framework can't fold the literal
      // away at compile time.
      const evilName: string =
        'evil' + String.fromCharCode(0x22) +
        String.fromCharCode(0x0d) + String.fromCharCode(0x0a) +
        'X-Injected: yes.jpg';
      const r: MultipartResult = buildSingleImageMultipart(
        'image',
        evilName,
        'image/jpeg',
        makeBytes([0x41]),
        '----B',
      );
      const view: Uint8Array = new Uint8Array(r.body);
      const enc: util.TextEncoder = new util.TextEncoder('utf-8');
      const expected: Uint8Array = enc.encodeInto(
        'filename="evil___X-Injected: yes.jpg"',
      );
      expect(indexOfBytes(view, expected) >= 0).assertTrue();
    });
  });
}
