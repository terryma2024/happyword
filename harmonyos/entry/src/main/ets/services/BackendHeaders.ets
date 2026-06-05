/**
 * Pure helper — merges two header dicts, with `extra` taking
 * precedence on key collision. Exposed so unit tests can verify
 * collision handling without touching AppStorage.
 */
export function mergeHeaders(
  base: Record<string, string>,
  extra: Record<string, string>,
): Record<string, string> {
  const out: Record<string, string> = {};
  const baseKeys: string[] = Object.keys(base);
  for (let i = 0; i < baseKeys.length; i++) {
    const k: string = baseKeys[i];
    out[k] = base[k];
  }
  const extraKeys: string[] = Object.keys(extra);
  for (let i = 0; i < extraKeys.length; i++) {
    const k: string = extraKeys[i];
    out[k] = extra[k];
  }
  return out;
}
