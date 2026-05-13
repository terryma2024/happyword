#!/usr/bin/env node
/**
 * Build the public preview manifest from Vercel deployments (the source of
 * truth) and upload it to Vercel Blob. The Blob object is the runtime
 * source for the public FastAPI proxy `GET /api/v1/preview-urls.json`
 * (see `server/app/services/preview_manifest_service.py`).
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
 * Historical note: this script used to ALSO write a copy of the manifest to
 * `docs/preview-urls.json` and the calling workflows committed that copy
 * back to `main`. That produced unnecessary churn on `main` (one bot commit
 * per PR sync that touched the URL set) without buying anything — runtime
 * traffic always read from Blob via the FastAPI proxy. The audit copy was
 * deleted in `chore: drop docs/preview-urls.json` (2026-05); the Blob is
 * now the single source of truth.
 *
 * Usage:
 *   node server/scripts/update_preview_manifest.mjs
 *
 * Required env:
 *   VERCEL_TOKEN           — Vercel API token (Account → Settings → Tokens).
 *   VERCEL_PROJECT_ID      — Vercel project id (e.g. prj_…).
 *   GITHUB_TOKEN           — GitHub token with `pull-requests: read`.
 *   GITHUB_REPOSITORY      — `owner/repo` (auto-set in GitHub Actions).
 *   BLOB_READ_WRITE_TOKEN  — Vercel Blob read/write token (Project → Storage).
 *
 * Optional env:
 *   VERCEL_ORG_ID                        — Vercel team / org id; required on team
 *                                          accounts so Vercel API resolves the
 *                                          project under the right scope.
 *   PREVIEW_MANIFEST_BLOB_PATH           — override the Blob object path
 *                                          (default `preview/preview-urls.json`).
 *   PREVIEW_MANIFEST_BLOB_CACHE_SECONDS  — Blob `cache-control: max-age` (default 60).
 *   PREVIEW_MANIFEST_MAX_DEPLOYMENT_PAGES — safety cap on Vercel pagination
 *                                          (default 50 × 100 = 5000 deployments).
 */

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

function withHttps(raw) {
  const url = raw || '';
  return url.startsWith('https://') ? url : `https://${url}`;
}

function deploymentUrl(d) {
  // Vercel `d.url` is the canonical hash hostname WITHOUT scheme — we always
  // emit `https://`. Keep this alongside the branch URL so debug tooling can
  // tell exactly which deployment a moving branch URL resolved to.
  return withHttps(d.url || '');
}

function branchSlug(branch) {
  return String(branch || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function aliasCandidates(deploy) {
  const raw = [
    ...(Array.isArray(deploy.alias) ? deploy.alias : []),
    ...(Array.isArray(deploy.aliases) ? deploy.aliases : []),
  ];
  if (typeof deploy.alias === 'string') raw.push(deploy.alias);
  if (typeof deploy.aliases === 'string') raw.push(deploy.aliases);
  return raw
    .map((item) => {
      if (typeof item === 'string') return item;
      if (item && typeof item.domain === 'string') return item.domain;
      if (item && typeof item.url === 'string') return item.url;
      return '';
    })
    .filter(Boolean);
}

export function requireBranchUrl({ branch, deploy }) {
  const slug = branchSlug(branch);
  const aliases = aliasCandidates(deploy);
  const match = aliases.find((alias) => {
    const host = alias.replace(/^https?:\/\//, '');
    return host.includes(`-git-${slug}-`) && host.endsWith('.vercel.app');
  });
  if (!match) {
    throw new Error(
      `Missing Vercel branch URL for branch "${branch}". ` +
        'Check that the preview deploy carries Git metadata and exposes the branch URL alias.',
    );
  }
  return withHttps(match);
}

export function makeManifestRow({ branch, deploy, pr }) {
  const branch_url = requireBranchUrl({ branch, deploy });
  const deploy_url = deploymentUrl(deploy);
  return {
    pr: pr.number,
    title: sanitiseTitle(pr.title),
    branch,
    url: branch_url,
    branch_url,
    deployment_url: deploy_url,
    deployment_id: deploy.uid || deploy.id || '',
    author: pr.user?.login || '?',
    head_sha: (deploy.meta?.githubCommitSha || pr.head?.sha || '').slice(0, 7),
    updated_at: new Date().toISOString(),
  };
}

async function assertBranchHealth(url) {
  const headers = {};
  const bypass = process.env.VERCEL_AUTOMATION_BYPASS_SECRET || '';
  if (bypass) headers['x-vercel-protection-bypass'] = bypass;
  const healthUrl = `${url.replace(/\/+$/, '')}/api/v1/health`;
  const res = await fetch(healthUrl, { headers });
  if (!res.ok) {
    throw new Error(`Branch URL health check failed for ${healthUrl}: HTTP ${res.status}`);
  }
  const body = await res.json().catch(() => null);
  if (!body || body.ok !== true) {
    throw new Error(`Branch URL health check returned unexpected body for ${healthUrl}`);
  }
}

async function uploadManifestToBlob({ payload, token }) {
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

  const { Octokit } = await import('@octokit/rest');
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
    const row = makeManifestRow({ branch, deploy, pr });
    await assertBranchHealth(row.branch_url);
    previews.push(row);
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
  const blobToken = mustEnv('BLOB_READ_WRITE_TOKEN');
  const [owner, repo] = ghRepo.split('/');
  if (!owner || !repo) {
    console.error(
      `GITHUB_REPOSITORY must be "owner/repo"; got "${ghRepo}".`,
    );
    process.exit(2);
  }

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
  console.log(`Built manifest with ${manifest.previews.length} previews.`);
  await uploadManifestToBlob({ payload, token: blobToken });
}

// Allow `import { pickNewestPerBranch }` from a unit test without invoking main.
const isMainModule = import.meta.url === `file://${process.argv[1]}`;
if (isMainModule) {
  main().catch((err) => {
    console.error(err.stack || err.message || String(err));
    process.exit(1);
  });
}
