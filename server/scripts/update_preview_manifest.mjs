#!/usr/bin/env node
/**
 * Updates docs/preview-urls.json from a GitHub pull_request webhook payload.
 * Usage: node server/scripts/update_preview_manifest.mjs <event-json-path> <github-token>
 */
import { readFile, writeFile } from 'node:fs/promises';
import { Octokit } from '@octokit/rest';

const MANIFEST_PATH = 'docs/preview-urls.json';
const SCHEMA_VERSION = 1;
const PREVIEWS_CAP = 50;

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
    const url = await resolveDeployUrl(owner, repo, pr.head.sha, token);
    if (!url) {
      console.warn(`No deploy URL yet for PR #${pr.number}; will retry next event.`);
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
 * Resolves the Vercel preview URL from GitHub Deployments API for the PR head SHA.
 */
async function resolveDeployUrl(owner, repo, sha, token) {
  const oct = new Octokit({ auth: token });
  const deployments = await oct.paginate(oct.rest.repos.listDeployments, {
    owner,
    repo,
    sha,
    per_page: 100,
  });
  for (const d of deployments.sort((a, b) => b.id - a.id)) {
    const statuses = await oct.paginate(oct.rest.repos.listDeploymentStatuses, {
      owner,
      repo,
      deployment_id: d.id,
      per_page: 100,
    });
    for (const s of statuses) {
      const url = s.environment_url || s.target_url;
      if (s.state === 'success' && url && url.includes('git-')) {
        return url;
      }
    }
  }
  return null;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
