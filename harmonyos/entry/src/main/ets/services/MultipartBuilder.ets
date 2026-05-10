import util from '@ohos.util';

/**
 * MultipartBuilder — V0.5.8.
 *
 * Builds an RFC-7578 `multipart/form-data` request body from a single
 * binary field (a textbook photo). The HarmonyOS NetworkKit
 * `http.HttpRequest` accepts an `ArrayBuffer` for `extraData`, so we
 * assemble the preamble, the binary, and the closing boundary into one
 * contiguous buffer and let libcurl forward it.
 *
 * The builder is intentionally narrow — we only need single-image
 * uploads for `POST /api/v1/admin/lessons/import`. If we ever need
 * multi-part lesson imports we'll generalize this.
 */

/** Result of `buildSingleImageMultipart`. The caller copies `boundary`
 *  into the `Content-Type` header and sends `body` as `extraData`. */
export class MultipartResult {
  boundary: string = '';
  body: ArrayBuffer = new ArrayBuffer(0);
}

/** Build a multipart body containing one image field. The `boundary`
 *  override exists for deterministic tests; production callers omit it
 *  and a fresh random boundary is generated. */
export function buildSingleImageMultipart(
  fieldName: string,
  filename: string,
  mime: string,
  bytes: ArrayBuffer,
  boundaryOverride?: string,
): MultipartResult {
  const boundary: string = boundaryOverride !== undefined ? boundaryOverride : generateBoundary();
  const enc: util.TextEncoder = new util.TextEncoder('utf-8');

  // Preamble: boundary + Content-Disposition + Content-Type + blank line.
  // `\r\n` is required by RFC 7578 between every section.
  const safeFilename: string = escapeFilename(filename);
  const preamble: string =
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="${fieldName}"; filename="${safeFilename}"\r\n` +
    `Content-Type: ${mime}\r\n\r\n`;
  const epilogue: string = `\r\n--${boundary}--\r\n`;

  const preBytes: Uint8Array = enc.encodeInto(preamble);
  const epiBytes: Uint8Array = enc.encodeInto(epilogue);
  const imgBytes: Uint8Array = new Uint8Array(bytes);

  const total: number = preBytes.length + imgBytes.length + epiBytes.length;
  const out: ArrayBuffer = new ArrayBuffer(total);
  const view: Uint8Array = new Uint8Array(out);

  let offset: number = 0;
  view.set(preBytes, offset);
  offset += preBytes.length;
  view.set(imgBytes, offset);
  offset += imgBytes.length;
  view.set(epiBytes, offset);

  const result: MultipartResult = new MultipartResult();
  result.boundary = boundary;
  result.body = out;
  return result;
}

/** RFC 7578 only forbids the boundary inside the parts, so any
 *  unguessable random string of safe characters is fine. We use a
 *  hyphen-prefixed hex string so it's easy to spot in network logs. */
function generateBoundary(): string {
  let hex: string = '';
  for (let i = 0; i < 16; i++) {
    const b: number = Math.floor(Math.random() * 256);
    const s: string = b.toString(16);
    hex += s.length === 1 ? `0${s}` : s;
  }
  return `----HappyWordBoundary${hex}`;
}

/** Replace characters that would break the `Content-Disposition` header.
 *  HarmonyOS filenames can contain almost anything; replacing CR/LF and
 *  double-quote with underscores avoids header injection without
 *  requiring full RFC 5987 percent-encoding for our internal API.
 *  Implemented with a manual char-code scan because ArkTS strict mode
 *  is finicky about regex literals in some configurations. Exported so
 *  the unit test can pin the substitution table directly. */
export function escapeFilename(name: string): string {
  const CR_CODE: number = 0x0d;
  const LF_CODE: number = 0x0a;
  const DQUOTE_CODE: number = 0x22;
  const UNDERSCORE: string = '_';
  let out: string = '';
  for (let i: number = 0; i < name.length; i++) {
    const code: number = name.charCodeAt(i);
    if (code === CR_CODE || code === LF_CODE || code === DQUOTE_CODE) {
      out += UNDERSCORE;
    } else {
      out += name.charAt(i);
    }
  }
  return out;
}
