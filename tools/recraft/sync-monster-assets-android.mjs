#!/usr/bin/env node
// Sync expanded monster SVGs from HarmonyOS rawfile assets into Android raw resources.
// Usage: node tools/recraft/sync-monster-assets-android.mjs

import { copyFile, mkdir, readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

const roster = JSON.parse(await readFile('tools/recraft/monster-roster.json', 'utf8'));
const sourceRoot = 'harmonyos/entry/src/main/resources/rawfile/character';
const rawRoot = 'android/app/src/main/res/raw';
let missing = 0;

function androidRawName(key) {
  return `character_${key.replaceAll('-', '_')}.svg`;
}

await mkdir(rawRoot, { recursive: true });

for (const entry of roster) {
  const src = join(sourceRoot, `${entry.key}.svg`);
  if (!existsSync(src)) {
    console.error(`[missing] ${src}`);
    missing += 1;
    continue;
  }

  const filename = androidRawName(entry.key);
  await copyFile(src, join(rawRoot, filename));
  console.log(`[sync] ${filename}`);
}

if (missing > 0) {
  console.error(`[FAIL] ${missing} monster assets are missing`);
  process.exit(1);
}
