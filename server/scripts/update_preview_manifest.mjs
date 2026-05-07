#!/usr/bin/env node
/**
 * Updates docs/preview-urls.json from a GitHub pull_request webhook payload.
 * Usage: node server/scripts/update_preview_manifest.mjs <event-json-path> <github-token>
 *
 * Polls the GitHub Deployments API: Vercel often finishes *after* this workflow
 * starts, so a single read would miss the preview URL. Override wait behaviour with:
 *   PREVIEW_MANIFEST_POLL_INTERVAL_MS (default 30000)
 *   PREVIEW_MANIFEST_POLL_MAX_ATTEMPTS (default 30)  → ~15 min at defaults
 */
import { readFile, writeFile } from 'node:fs/promises';
import { Octokit } from '@octokit/rest';

const MANIFEST_PATH = 'docs/preview-urls.json';
const SCHEMA_VERSION = 1;
const PREVIEWS_CAP = 50;

const POLL_INTERVAL_MS = Number(process.env.PREVIEW_MANIFEST_POLL_INTERVAL_MS || 30000);
const POLL_MAX_ATTEMPTS = Number(process.env.PREVIEW_MANIFEST_POLL_MAX_ATTEMPTS || 30);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  const eventPath = process.argv[2] || process.env.GITHUB_EVENT_PATH;
  const token = process.argv[3] || process.env.GITHUB_TOKEN;
  if (!eventPath || !token) {
    console.error('Usage: update_preview_manifest.mjs <event-json> <token>');
    process.exit(2);
  }

  const event = JSON.parse(await readFile(eventPath, 'utf8'));
  const pr = event.pull_request;
  if (!pr) {
    console.log('No pull_request in payload; skipping.');
    process.exit(0);
  }
  const action = event.action;
  const owner = event.repository.owner.login;
  const repo = event.repository.name;

  let manifest = await loadManifest();

  if (action === 'closed' && pr) {
    manifest.previews = manifest.previews.filter((r) => r.pr !== pr.number);
  } else if (pr && ['opened', 'synchronize', 'reopened'].includes(action)) {
    const url = await resolveDeployUrlWithPoll(owner, repo, pr.head.sha, token, pr.number);
    if (!url) {
      console.warn(`No deploy URL for PR #${pr.number} after polling; manifest timestamp only.`);
    } else {
      manifest.previews = manifest.previews.filter((r) => r.pr !== pr.number);
      manifest.previews.unshift({
        pr: pr.number,
        title: (pr.title || '').replace(/[\r\n]+/g, ' ').slice(0, 80),
        branch: pr.head.ref,
        url,
        author: pr.user.login,
        head_sha: pr.head.sha.slice(0, 7),
        updated_at: new Date().toISOString(),
      });
    }
  }

  manifest.previews.sort((a, b) => b.pr - a.pr);
  manifest.previews = manifest.previews.slice(0, PREVIEWS_CAP);
  manifest.updated_at = new Date().toISOString();
  manifest.schema_version = SCHEMA_VERSION;

  await writeFile(MANIFEST_PATH, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`Wrote ${MANIFEST_PATH} with ${manifest.previews.length} previews.`);
}

async function loadManifest() {
  try {
    const raw = await readFile(MANIFEST_PATH, 'utf8');
    const parsed = JSON.parse(raw);
    if (parsed.schema_version === SCHEMA_VERSION && Array.isArray(parsed.previews)) {
      return parsed;
    }
  } catch (_err) {
    /* fall through */
  }
  return { schema_version: SCHEMA_VERSION, updated_at: null, previews: [] };
}

/**
 * Poll until a successful *.vercel.app deployment appears for the commit SHA.
 */
async function resolveDeployUrlWithPoll(owner, repo, sha, token, prNumber) {
  for (let attempt = 1; attempt <= POLL_MAX_ATTEMPTS; attempt++) {
    const url = await resolveDeployUrlOnce(owner, repo, sha, token);
    if (url) {
      console.log(`resolveDeployUrl: success on attempt ${attempt}/${POLL_MAX_ATTEMPTS}`);
      return url;
    }
    console.warn(
      `resolveDeployUrl: PR #${prNumber} attempt ${attempt}/${POLL_MAX_ATTEMPTS} — no Vercel preview yet; ` +
        `sleep ${POLL_INTERVAL_MS}ms`,
    );
    if (attempt < POLL_MAX_ATTEMPTS) {
      await sleep(POLL_INTERVAL_MS);
    }
  }
  return null;
}

/** Typical hostname: happyword-git-<branch>-terrymas-projects.vercel.app */
function isVercelPreviewUrl(url) {
  return (
    typeof url === 'string' && url.startsWith('https://') && url.includes('.vercel.app')
  );
}

/**
 * Resolves the Vercel preview URL from GitHub Deployments API for the PR head SHA.
 * Prefers URLs that still carry the usual git-based hostname segment (legacy filter).
 */
async function resolveDeployUrlOnce(owner, repo, sha, token) {
  const oct = new Octokit({ auth: token });
  const deployments = await oct.paginate(oct.rest.repos.listDeployments, {
    owner,
    repo,
    sha,
    per_page: 100,
  });
  const sorted = deployments.sort((a, b) => b.id - a.id);
  const candidates = [];
  for (const d of sorted) {
    const statuses = await oct.paginate(oct.rest.repos.listDeploymentStatuses, {
      owner,
      repo,
      deployment_id: d.id,
      per_page: 100,
    });
    for (const s of statuses) {
      const url = s.environment_url || s.target_url;
      if (s.state === 'success' && url && isVercelPreviewUrl(url)) {
        candidates.push({ url, gitLike: url.includes('git-') });
      }
    }
  }
  const preferred = candidates.find((c) => c.gitLike);
  if (preferred) {
    return preferred.url;
  }
  return candidates.length > 0 ? candidates[0].url : null;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
