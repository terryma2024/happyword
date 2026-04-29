#!/usr/bin/env node
// Wraps `rsvg-convert -w <px> -h <px>` to rasterize a Recraft-generated
// SVG into a PNG at a given pixel size. Used by icons-to-launcher.sh
// (and direct invocations) to produce 1024x1024 / 216x216 launcher
// artefacts from the generated SVGs without depending on a Node SVG
// library. Requires librsvg's `rsvg-convert` on PATH (Homebrew:
// `brew install librsvg`).

import { mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';
import { spawnSync } from 'node:child_process';

function usage() {
  return [
    'Usage:',
    '  node tools/recraft/svg-to-png.mjs --in <svg> --out <png> --size <px>',
    '',
    'Options:',
    '  --in <path>    Input SVG file.',
    '  --out <path>   Output PNG file (parent directory created if missing).',
    '  --size <px>    Output square pixel size, e.g. 1024 or 216.',
    '  --help         Show this help.',
  ].join('\n');
}

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

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }
  const inFile = args.in;
  const outFile = args.out;
  const size = Number.parseInt(args.size, 10);
  if (!inFile || !outFile || !Number.isInteger(size) || size <= 0) {
    console.error(usage());
    throw new Error('Missing or invalid --in / --out / --size.');
  }
  await mkdir(dirname(outFile), { recursive: true });
  const r = spawnSync(
    'rsvg-convert',
    ['-w', String(size), '-h', String(size), '-o', outFile, inFile],
    { stdio: 'inherit' },
  );
  if (r.error) {
    throw new Error(`Failed to spawn rsvg-convert: ${r.error.message}`);
  }
  if (r.status !== 0) {
    throw new Error(`rsvg-convert exited with code ${r.status}`);
  }
  console.log(`[ok] ${inFile} -> ${outFile} (${size}x${size})`);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
