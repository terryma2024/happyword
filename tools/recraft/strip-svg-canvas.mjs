#!/usr/bin/env node
// Recraft V4 vector outputs always start with a single full-canvas
// <path d="M 0 0 L W 0 L W H L 0 H L 0 0 z" fill="rgb(...)"...></path>
// rectangle that fills the entire viewBox in an off-white colour.
// For UI icons that we want to render on a coloured button (or
// composited over a layered launcher background), this opaque base
// behaves like a white tile and visibly obscures the underlying fill.
//
// This tool removes only that first canvas-rect element and writes
// the cleaned SVG back. Idempotent — running twice on the same file
// is a no-op.
//
// Usage:
//   node tools/recraft/strip-svg-canvas.mjs --in <svg> [--out <svg>]
//
// If --out is omitted the input file is updated in place.

import { readFile, writeFile } from 'node:fs/promises';

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--help' || a === '-h') {
      args.help = true;
      continue;
    }
    if (!a.startsWith('--')) {
      throw new Error(`Unknown argument: ${a}`);
    }
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) {
      throw new Error(`Missing value for ${a}`);
    }
    args[key] = next;
    i += 1;
  }
  return args;
}

// Match the first <path ...d="M 0 0 ... L 0 0 z" ...></path> where the
// path traces the entire canvas (starts at 0 0 and ends at 0 0 z).
// Recraft sometimes emits extra mid-edge L points (e.g. scroll.svg uses
// `L 2048 1346.01 L 2048 1349.26 L 2048 2048 L 0 2048 ... L 0 0 z`),
// so we only require that the path starts with `M 0 0 ` and ends with
// `L 0 0 z` and contains nothing but coordinate / L tokens in between.
const CANVAS_RECT_PATTERN =
  /<path[^>]*\bd="M\s+0\s+0\s+(?:L\s+\d+(?:\.\d+)?\s+\d+(?:\.\d+)?\s+)+L\s+0\s+0\s*z"[^>]*><\/path>/;

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log('Usage: strip-svg-canvas.mjs --in <svg> [--out <svg>]');
    return;
  }
  const inFile = args.in;
  if (!inFile) {
    throw new Error('Missing --in.');
  }
  const outFile = args.out || inFile;

  const original = await readFile(inFile, 'utf8');
  const cleaned = original.replace(CANVAS_RECT_PATTERN, '');
  if (cleaned === original) {
    console.log(`[skip] ${inFile} (no canvas rect found)`);
    return;
  }
  await writeFile(outFile, cleaned);
  console.log(`[ok] stripped canvas rect: ${inFile} -> ${outFile}`);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
