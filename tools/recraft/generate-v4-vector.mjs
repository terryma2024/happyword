#!/usr/bin/env node

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { basename, dirname, extname, join, resolve } from 'node:path';
import { homedir } from 'node:os';

const API_URL = 'https://external.api.recraft.ai/v1/images/generations';
const DEFAULT_MODEL = 'recraftv4_vector';
const DEFAULT_SIZE = '1:1';
const DEFAULT_OUT_DIR = 'generated/recraft';

function usage() {
  return `Usage:
  node tools/recraft/generate-v4-vector.mjs --prompt "..." [--out path] [--size 1:1]
  node tools/recraft/generate-v4-vector.mjs --prompt-file prompt.txt --out generated/recraft/pony.svg

Options:
  --prompt <text>        Prompt for Recraft V4 Vector.
  --prompt-file <path>   Read prompt from a UTF-8 text file.
  --out <path>           Output SVG path or directory. Defaults to ${DEFAULT_OUT_DIR}/recraft-v4-vector-<timestamp>.svg.
  --size <size>          Recraft size, e.g. 1:1, 4:3, 3:4. Defaults to ${DEFAULT_SIZE}.
  --n <number>           Number of SVGs to request. Defaults to 1.
  --json <path>          Save raw API response JSON.
  --api-key <key>        API key. Prefer RECRAFT_API_KEY env var instead.
  --help                 Show this help.

Key lookup order:
  1. --api-key
  2. RECRAFT_API_KEY environment variable
  3. ~/.codex/config.toml [mcp_servers.recraft.env] RECRAFT_API_KEY
`;
}

function parseArgs(argv) {
  const args = {
    size: DEFAULT_SIZE,
    n: 1,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      args.help = true;
    } else if (arg.startsWith('--')) {
      const key = arg.slice(2);
      const next = argv[i + 1];
      if (!next || next.startsWith('--')) {
        throw new Error(`Missing value for ${arg}`);
      }
      args[key] = next;
      i += 1;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return args;
}

async function readPrompt(args) {
  if (args.prompt && args['prompt-file']) {
    throw new Error('Use either --prompt or --prompt-file, not both.');
  }
  if (args.prompt) return args.prompt.trim();
  if (args['prompt-file']) {
    return (await readFile(resolve(args['prompt-file']), 'utf8')).trim();
  }
  throw new Error('Missing --prompt or --prompt-file.');
}

async function readCodexRecraftApiKey() {
  const configPath = join(homedir(), '.codex', 'config.toml');
  let text;
  try {
    text = await readFile(configPath, 'utf8');
  } catch {
    return undefined;
  }

  const sectionMatch = text.match(/\[mcp_servers\.recraft\.env\]([\s\S]*?)(?:\n\[|$)/);
  if (!sectionMatch) return undefined;

  const keyMatch = sectionMatch[1].match(/^\s*RECRAFT_API_KEY\s*=\s*"([^"]+)"/m);
  return keyMatch?.[1];
}

async function getApiKey(args) {
  return args['api-key'] || process.env.RECRAFT_API_KEY || readCodexRecraftApiKey();
}

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

function resolveOutputPath(outArg, index, total) {
  const fallback = join(DEFAULT_OUT_DIR, `recraft-v4-vector-${timestamp()}.svg`);
  const out = outArg || fallback;
  const absolute = resolve(out);
  const ext = extname(absolute).toLowerCase();

  if (ext === '.svg') {
    if (total === 1) return absolute;
    const base = absolute.slice(0, -4);
    return `${base}-${index + 1}.svg`;
  }

  return join(absolute, `recraft-v4-vector-${timestamp()}-${index + 1}.svg`);
}

async function download(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download SVG: HTTP ${response.status} ${await response.text()}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const prompt = await readPrompt(args);
  if (prompt.length > 1024) {
    throw new Error(`Prompt is ${prompt.length} characters; Recraft image prompts must be 1024 characters or less.`);
  }

  const apiKey = await getApiKey(args);
  if (!apiKey) {
    throw new Error('Missing Recraft API key. Set RECRAFT_API_KEY or configure the Codex recraft MCP server.');
  }

  const n = Number.parseInt(args.n, 10);
  if (!Number.isInteger(n) || n < 1 || n > 6) {
    throw new Error('--n must be an integer from 1 to 6.');
  }

  const response = await fetch(API_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      prompt,
      model: DEFAULT_MODEL,
      size: args.size,
      n,
      response_format: 'url',
    }),
  });

  const bodyText = await response.text();
  if (!response.ok) {
    throw new Error(`Recraft generation failed: HTTP ${response.status} ${bodyText}`);
  }

  const body = JSON.parse(bodyText);
  const items = body.data || [];
  if (items.length === 0) {
    throw new Error(`Recraft response did not include generated image data: ${bodyText}`);
  }

  const outputPaths = [];
  for (let i = 0; i < items.length; i += 1) {
    const url = items[i].url;
    if (!url) throw new Error(`Generated item ${i + 1} did not include a URL.`);

    const outputPath = resolveOutputPath(args.out, i, items.length);
    await mkdir(dirname(outputPath), { recursive: true });
    const svg = await download(url);
    await writeFile(outputPath, svg);
    outputPaths.push(outputPath);
  }

  if (args.json) {
    const jsonPath = resolve(args.json);
    await mkdir(dirname(jsonPath), { recursive: true });
    await writeFile(jsonPath, `${JSON.stringify(body, null, 2)}\n`);
  }

  console.log(`Generated ${outputPaths.length} Recraft V4 Vector SVG${outputPaths.length > 1 ? 's' : ''}:`);
  for (const outputPath of outputPaths) {
    console.log(`- ${outputPath} (${basename(outputPath)})`);
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
