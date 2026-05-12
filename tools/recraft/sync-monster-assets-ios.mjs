#!/usr/bin/env node
// Sync expanded monster SVGs from HarmonyOS rawfile assets into the iOS asset catalog.
// Usage: node tools/recraft/sync-monster-assets-ios.mjs

import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

const roster = JSON.parse(await readFile('tools/recraft/monster-roster.json', 'utf8'));
const sourceRoot = 'harmonyos/entry/src/main/resources/rawfile/character';
const assetRoot = 'ios/WordMagicGame/Resources/Assets.xcassets';
let missing = 0;

for (const entry of roster) {
  const filename = `${entry.key}.svg`;
  const src = join(sourceRoot, filename);
  if (!existsSync(src)) {
    console.error(`[missing] ${src}`);
    missing += 1;
    continue;
  }

  const imageSet = join(assetRoot, `${entry.assetName}.imageset`);
  await mkdir(imageSet, { recursive: true });
  await copyFile(src, join(imageSet, filename));
  await writeFile(join(imageSet, 'Contents.json'), `${JSON.stringify({
    images: [{ filename, idiom: 'universal' }],
    info: { author: 'xcode', version: 1 },
    properties: { 'preserves-vector-representation': true },
  }, null, 2)}
`);
  console.log(`[sync] ${entry.assetName}`);
}

if (missing > 0) {
  console.error(`[FAIL] ${missing} monster assets are missing`);
  process.exit(1);
}
