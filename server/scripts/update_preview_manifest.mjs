#!/usr/bin/env node
/**
 * Build `docs/preview-urls.json` from Vercel deployments (the source of truth)
 * and cross-reference each branch with GitHub to attach PR metadata.
 *
 * Per non-protected branch with a successful Vercel preview deployment:
 *   - Pick the newest READY non-production deployment.
 *   - Find the most recent PR with `head:branch` (state=all, sorted by created
 *     desc; an open PR wins ties because GitHub returns it first when present).
 *   - Emit one manifest row.
 *
 * Branches without a matching PR are skipped — the manifest tracks "PRs with
 * alive previews", not "every branch that ever deployed". Protected branches
 * (main / master) and any deployment with `target === 'production'` are
 * skipped because the manifest is for preview testing, not staging.
 *
 * The manifest reflects "what previews are alive on Vercel right now",
 * regardless of whether the source PR is open or merged. Entries vanish
 * automatically after the weekly `vercel-prune.yml` cron deletes a deployment;
 * no separate cleanup is needed.
 *
 * Usage:
 *   node server/scripts/update_preview_manifest.mjs
 *
 * Required env:
 *   VERCEL_TOKEN       — Vercel API token (Account → Settings → Tokens).
 *   VERCEL_PROJECT_ID  — Vercel project id (e.g. prj_…).
 *   GITHUB_TOKEN       — GitHub token with `pull-requests: read`.
 *   GITHUB_REPOSITORY  — `owner/repo` (auto-set in GitHub Actions).
 *
 * Optional env:
 *   VERCEL_ORG_ID                       — Vercel team / org id; required on team
 *                                         accounts so Vercel API resolves the
 *                                         project under the right scope.
 *   PREVIEW_MANIFEST_OUTPUT_PATH        — override output path (default
 *                                         `docs/preview-urls.json`); set in unit
 *                                         tests / dry-runs to redirect output.
 *   PREVIEW_MANIFEST_MAX_DEPLOYMENT_PAGES — safety cap on Vercel pagination
 *                                         (default 50 × 100 = 5000 deployments).
 */
import { writeFile } from 'node:fs/promises';
import { Octokit } from '@octokit/rest';

const SCHEMA_VERSION = 1;
const PREVIEWS_CAP = 50;
const TITLE_MAX = 80;
const PROTECTED_BRANCHES = new Set(['main', 'master']);
const VERCEL_API = 'https://api.vercel.com';
const BLOB_API = 'https://blob.vercel-storage.com';
const DEFAULT_BLOB_PATH = 'preview/preview-urls.json';
const DEFAULT_BLOB_CACHE_SECONDS = 60;

function mustEnv(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`Missing required env: ${name}`);
    process.exit(2);
  }
  return v;
}

function teamQuery(teamId) {
  return teamId ? `&teamId=${encodeURIComponent(teamId)}` : '';
}

async function vercelFetch(path, token) {
  const res = await fetch(`${VERCEL_API}${path}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    const snippet = body.length > 400 ? `${body.slice(0, 400)}…` : body;
    throw new Error(`Vercel API GET ${path} → ${res.status}: ${snippet}`);
  }
  return res.json();
}

async function listAllVercelDeployments({ projectId, teamId, token }) {
  const all = [];
  let until = null;
  const MAX_PAGES = Number(process.env.PREVIEW_MANIFEST_MAX_DEPLOYMENT_PAGES || 50);
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const cursor = until ? `&until=${until}` : '';
    const path =
      `/v6/deployments?projectId=${encodeURIComponent(projectId)}` +
      `&limit=100${cursor}${teamQuery(teamId)}`;
    const data = await vercelFetch(path, token);
    const batch = data.deployments || [];
    all.push(...batch);
    const next = data.pagination && data.pagination.next;
    if (!next || batch.length === 0) break;
    until = next;
  }
  return all;
}

/**
 * Group deployments by `meta.githubCommitRef` (or other VCS equivalents) and
 * pick the newest READY non-production deployment per branch. Protected
 * branches (`main`, `master`) and deployments without git metadata are
 * skipped.
 */
export function pickNewestPerBranch(deployments) {
  const groups = new Map();
  for (const d of deployments) {
    const meta = d.meta || {};
    const branch =
      meta.githubCommitRef ||
      meta.gitlabCommitRef ||
      meta.bitbucketCommitRef ||
      null;
    if (!branch) continue;
    if (PROTECTED_BRANCHES.has(branch)) continue;
    if (d.target === 'production') continue;
    if (d.state !== 'READY') continue;
    const prev = groups.get(branch);
    if (!prev || (d.created || 0) > (prev.created || 0)) {
      groups.set(branch, d);
    }
  }
  return groups;
}

async function findPrForBranch({ oct, owner, repo, branch }) {
  // GitHub list-pulls is the cheapest path for "PR by head branch".
  // state=all picks up merged + closed PRs as well as open ones; we then
  // sort by created_at desc so a re-opened branch (rare) yields the latest
  // PR. An open PR with the same head naturally wins because state=all
  // returns open ones too — we just take whichever is newest.
  const items = await oct.paginate(oct.rest.pulls.list, {
    owner,
    repo,
    state: 'all',
    head: `${owner}:${branch}`,
    per_page: 100,
  });
  if (items.length === 0) return null;
  items.sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
  );
  return items[0];
}

function sanitiseTitle(raw) {
  return (raw || '').replace(/[\r\n]+/g, ' ').slice(0, TITLE_MAX);
}

function deployUrl(d) {
  // Vercel `d.url` is the canonical hash hostname WITHOUT scheme — we always
  // emit `https://`. We deliberately do NOT prefer `d.alias[*]` (the git-based
  // alias like `happyword-git-<branch>-<team>.vercel.app`) because aliases
  // are mutable: a tester bookmarking the alias would silently get the next
  // deployment for that branch, defeating the whole point of pinning a row
  // to a specific PR head SHA.
  const url = d.url || '';
  return url.startsWith('https://') ? url : `https://${url}`;
}

async function uploadManifestToBlob({ payload, token }) {
  if (!token) {
    console.log('BLOB_READ_WRITE_TOKEN not set; skipping Blob mirror upload.');
    return null;
  }

  const blobPath = process.env.PREVIEW_MANIFEST_BLOB_PATH || DEFAULT_BLOB_PATH;
  const cacheSeconds = Number(
    process.env.PREVIEW_MANIFEST_BLOB_CACHE_SECONDS || DEFAULT_BLOB_CACHE_SECONDS,
  );
  const url = `${BLOB_API}/${blobPath.replace(/^\/+/, '')}`;
  const res = await fetch(url, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      access: 'public',
      'x-api-version': '7',
      'x-content-type': 'application/json',
      'x-add-random-suffix': '0',
      'x-allow-overwrite': '1',
      'x-cache-control-max-age': String(cacheSeconds),
    },
    body: payload,
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    const snippet = body.length > 400 ? `${body.slice(0, 400)}…` : body;
    throw new Error(`Vercel Blob PUT ${blobPath} → ${res.status}: ${snippet}`);
  }

  const body = await res.json();
  const publicUrl = body.url;
  if (typeof publicUrl !== 'string' || !publicUrl) {
    throw new Error(`Vercel Blob did not return a public URL for ${blobPath}`);
  }
  console.log(`Uploaded Blob mirror: ${publicUrl}`);
  return publicUrl;
}

async function buildManifestRows({
  vercelToken,
  projectId,
  teamId,
  ghToken,
  owner,
  repo,
}) {
  const deployments = await listAllVercelDeployments({
    projectId,
    teamId,
    token: vercelToken,
  });
  console.log(`Fetched ${deployments.length} Vercel deployments.`);

  const newestByBranch = pickNewestPerBranch(deployments);
  console.log(
    `Eligible non-protected branches with a READY preview: ${newestByBranch.size}`,
  );

  const oct = new Octokit({ auth: ghToken });
  const previews = [];
  for (const [branch, deploy] of newestByBranch) {
    let pr;
    try {
      pr = await findPrForBranch({ oct, owner, repo, branch });
    } catch (err) {
      console.warn(`branch=${branch}: PR lookup failed (${err.message}); skipping.`);
      continue;
    }
    if (!pr) {
      console.log(`branch=${branch}: no matching PR; skipping.`);
      continue;
    }
    previews.push({
      pr: pr.number,
      title: sanitiseTitle(pr.title),
      branch,
      url: deployUrl(deploy),
      author: pr.user?.login || '?',
      head_sha: (deploy.meta?.githubCommitSha || pr.head?.sha || '').slice(0, 7),
      updated_at: new Date().toISOString(),
    });
  }

  previews.sort((a, b) => b.pr - a.pr);
  return previews.slice(0, PREVIEWS_CAP);
}

async function main() {
  const vercelToken = mustEnv('VERCEL_TOKEN');
  const projectId = mustEnv('VERCEL_PROJECT_ID');
  const teamId = process.env.VERCEL_ORG_ID || null;
  const ghToken = mustEnv('GITHUB_TOKEN');
  const ghRepo = mustEnv('GITHUB_REPOSITORY');
  const [owner, repo] = ghRepo.split('/');
  if (!owner || !repo) {
    console.error(
      `GITHUB_REPOSITORY must be "owner/repo"; got "${ghRepo}".`,
    );
    process.exit(2);
  }
  const outputPath =
    process.env.PREVIEW_MANIFEST_OUTPUT_PATH || 'docs/preview-urls.json';

  const previews = await buildManifestRows({
    vercelToken,
    projectId,
    teamId,
    ghToken,
    owner,
    repo,
  });

  const manifest = {
    schema_version: SCHEMA_VERSION,
    updated_at: new Date().toISOString(),
    previews,
  };
  const payload = `${JSON.stringify(manifest, null, 2)}\n`;
  await writeFile(outputPath, payload);
  console.log(`Wrote ${outputPath} with ${manifest.previews.length} previews.`);
  await uploadManifestToBlob({
    payload,
    token: process.env.BLOB_READ_WRITE_TOKEN || '',
  });
}

// Allow `import { pickNewestPerBranch }` from a unit test without invoking main.
const isMainModule = import.meta.url === `file://${process.argv[1]}`;
if (isMainModule) {
  main().catch((err) => {
    console.error(err.stack || err.message || String(err));
    process.exit(1);
  });
}
