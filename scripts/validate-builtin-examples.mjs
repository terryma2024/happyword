#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const repoRoot = process.cwd();
const packDir = path.join(
  repoRoot,
  'harmonyos',
  'entry',
  'src',
  'main',
  'resources',
  'rawfile',
  'data',
  'builtin',
);

const packFiles = [
  'fruit-forest.json',
  'school-castle.json',
  'home-cottage.json',
  'animal-safari.json',
  'ocean-realm.json',
];

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function sentenceContainsWord(sentence, word) {
  const normalizedWord = word.trim().replace(/\s+/g, '\\s+');
  const pattern = new RegExp(`(^|[^A-Za-z])${escapeRegExp(normalizedWord)}([^A-Za-z]|$)`, 'i');
  return pattern.test(sentence);
}

const failures = [];

for (const fileName of packFiles) {
  const filePath = path.join(packDir, fileName);
  const body = fs.readFileSync(filePath, 'utf8');
  const pack = JSON.parse(body);
  if (!Array.isArray(pack.words)) {
    failures.push(`${fileName}: words is not an array`);
    continue;
  }
  for (const word of pack.words) {
    const id = typeof word.id === 'string' ? word.id : '<missing-id>';
    const example = word.example;
    if (example === undefined || example === null) {
      failures.push(`${fileName}:${id}: missing example`);
      continue;
    }
    if (typeof example.en !== 'string' || example.en.trim().length === 0) {
      failures.push(`${fileName}:${id}: missing example.en`);
    } else if (!sentenceContainsWord(example.en, word.word)) {
      failures.push(`${fileName}:${id}: example.en must contain "${word.word}"`);
    }
    if (typeof example.zh !== 'string' || example.zh.trim().length === 0) {
      failures.push(`${fileName}:${id}: missing example.zh`);
    }
  }
}

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(failure);
  }
  process.exit(1);
}

console.log(`Validated examples for ${packFiles.length} builtin packs.`);
