#!/usr/bin/env node
/**
 * Prune Vercel deployments per branch, keeping only the newest deployment for
 * each non-protected branch. Protected branches (default: main, master) are
 * skipped entirely. Any deployment currently aliased to the production domain
 * is always preserved, regardless of branch. Deployments without git metadata
 * (manual `vercel deploy`, etc.) are skipped — we can't safely group them.
 *
 * When run inside a git checkout with `origin`, the script lists remote heads
 * (`git ls-remote --heads <remote>`). Any deployment group whose branch name is
 * absent from that list is treated as orphaned (branch deleted on the host) and
 * **all** deployments in that group are deleted — except the production-aliased
 * uid, which is always preserved. If git is unavailable or
 * `--skip-remote-branch-check` is passed, only the usual per-branch "keep
 * newest" / protected-branch rules apply.
 *
 * `--prune-main` treats the **`main`** branch like a non-protected branch: keep
 * only the newest deployment (still preserving the production-aliased uid).
 * Other entries in `--keep-branches` (e.g. `master`) are unchanged.
 *
 * Usage:
 *   node server/scripts/vercel_prune_branch_deployments.mjs           # dry-run
 *   node server/scripts/vercel_prune_branch_deployments.mjs --apply   # actually delete
 *
 * Flags:
 *   --apply                       Perform deletions (otherwise dry-run only).
 *   --keep-branches main,master   Comma-separated branches to skip entirely.
 *                                 Default: main,master.
 *   --project <name-or-id>        Override Vercel project. Default: read from
 *                                 server/.vercel/project.json.
 *   --team <id>                   Override Vercel team / org id. Default: read
 *                                 from server/.vercel/project.json.
 *   --include-no-git              Also prune deployments missing git metadata
 *                                 (group them under the synthetic branch
 *                                 "<no-git>"). Off by default.
 *   --skip-remote-branch-check    Do not call git; never treat branches as
 *                                 deleted-on-remote (CI without checkout, etc.).
 *   --git-remote <name>           Remote for ls-remote (default: origin, or
 *                                 VERCEL_PRUNE_GIT_REMOTE).
 *   --prune-main                  On branch main only: keep newest deployment;
 *                                 delete older mains (production alias preserved).
 *   --json                        Emit machine-readable summary on stdout
 *                                 instead of the human-friendly table.
 *
 * Required env:
 *   VERCEL_TOKEN       — Vercel API token (Account → Settings → Tokens).
 *
 * Optional env (used when --project/--team are not passed AND
 * server/.vercel/project.json is unavailable, e.g. in CI):
 *   VERCEL_PROJECT_ID  — Vercel project id (e.g. prj_…).
 *   VERCEL_ORG_ID      — Vercel team / org id (e.g. team_…).
 *
 * Exit codes:
 *   0  success (dry-run or apply)
 *   1  unexpected error / API failure
 *   2  missing required input (token, project)
 */

import { execFile } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
// server/scripts/ → server/ → repo root
const REPO_ROOT = resolve(SCRIPT_DIR, '..', '..');
const PROJECT_JSON = resolve(REPO_ROOT, 'server', '.vercel', 'project.json');

const VERCEL_API = 'https://api.vercel.com';

function parseArgs(argv) {
  const args = {
    apply: false,
    keepBranches: ['main', 'master'],
    project: null,
    team: null,
    includeNoGit: false,
    skipRemoteBranchCheck: false,
    gitRemote:
      (typeof process.env.VERCEL_PRUNE_GIT_REMOTE === 'string' &&
        process.env.VERCEL_PRUNE_GIT_REMOTE.trim()) ||
      'origin',
    pruneMain: false,
    json: false,
  };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case '--apply':
        args.apply = true;
        break;
      case '--prune-main':
        args.pruneMain = true;
        break;
      case '--include-no-git':
        args.includeNoGit = true;
        break;
      case '--skip-remote-branch-check':
        args.skipRemoteBranchCheck = true;
        break;
      case '--json':
        args.json = true;
        break;
      case '--keep-branches':
        args.keepBranches = String(argv[++i] || '')
          .split(',')
          .map((s) => s.trim())
          .filter(Boolean);
        break;
      case '--git-remote':
        args.gitRemote = String(argv[++i] || '').trim() || 'origin';
        break;
      case '--project':
        args.project = argv[++i] || null;
        break;
      case '--team':
        args.team = argv[++i] || null;
        break;
      case '-h':
      case '--help':
        printHelpAndExit(0);
        break;
      default:
        console.error(`Unknown argument: ${arg}`);
        printHelpAndExit(2);
    }
  }
  return args;
}

function printHelpAndExit(code) {
  // Trim away the leading shebang & jsdoc by re-using the docblock literally.
  // Keeping it short on purpose: the file header is the canonical reference.
  console.log(
    [
      'Usage: vercel_prune_branch_deployments.mjs [--apply] [--keep-branches a,b] [--project ID]',
      '       [--team ID] [--include-no-git] [--skip-remote-branch-check] [--git-remote origin]',
      '       [--prune-main] [--json]',
      '',
      'See file header for full docs. Requires VERCEL_TOKEN env.',
    ].join('\n'),
  );
  process.exit(code);
}

async function loadProjectMeta(args) {
  // Resolution order (highest priority first):
  //   1. CLI flags --project / --team
  //   2. Env vars VERCEL_PROJECT_ID / VERCEL_ORG_ID  (CI-friendly; matches the
  //      same secret names server-ci.yml already uses)
  //   3. server/.vercel/project.json (gitignored; written by `vercel link`)
  let projectId = args.project || process.env.VERCEL_PROJECT_ID || null;
  let teamId = args.team || process.env.VERCEL_ORG_ID || null;
  if (!projectId || !teamId) {
    try {
      const raw = await readFile(PROJECT_JSON, 'utf8');
      const parsed = JSON.parse(raw);
      projectId = projectId || parsed.projectId || parsed.projectName;
      teamId = teamId || parsed.orgId || null;
    } catch (err) {
      if (!projectId) {
        throw new Error(
          `Could not read ${PROJECT_JSON} (${err.code || err.message}); ` +
            'pass --project / --team explicitly or set VERCEL_PROJECT_ID / VERCEL_ORG_ID.',
        );
      }
    }
  }
  if (!projectId) {
    throw new Error(
      'Missing project id; pass --project, set VERCEL_PROJECT_ID, ' +
        'or run from a `vercel link`-ed checkout.',
    );
  }
  return { projectId, teamId };
}

function teamQuery(teamId) {
  return teamId ? `&teamId=${encodeURIComponent(teamId)}` : '';
}

async function vercelFetch(path, token, init = {}) {
  const url = `${VERCEL_API}${path}`;
  const res = await fetch(url, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    const snippet = body.length > 400 ? `${body.slice(0, 400)}…` : body;
    throw new Error(`Vercel API ${init.method || 'GET'} ${path} → ${res.status}: ${snippet}`);
  }
  if (res.status === 204) return null;
  return res.json();
}

async function listAllDeployments({ projectId, teamId, token }) {
  const all = [];
  // Vercel paginates by `until` (created-time cursor, descending).
  let until = null;
  // Hard safety cap so a misbehaving API can't infinite-loop us.
  const MAX_PAGES = 200;
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

async function findProductionAliasedUid({ projectId, teamId, token }) {
  // /v9/projects/<id> includes `alias` (production aliases) + `targets.production`.
  const path = `/v9/projects/${encodeURIComponent(projectId)}?${teamQuery(teamId).slice(1)}`;
  try {
    const data = await vercelFetch(path, token);
    const prodUid = data?.targets?.production?.id;
    if (prodUid) return prodUid;
  } catch (err) {
    console.warn(
      `[warn] could not resolve production deployment via /v9/projects: ${err.message}; ` +
        'falling back to "deployment with most aliases".',
    );
  }
  return null;
}

/**
 * Returns a Set of branch names currently present on `gitRemote`, or `null` if
 * git is unavailable / ls-remote failed (caller falls back to legacy rules only).
 */
async function loadRemoteBranchNames({ cwd, remote }) {
  try {
    await execFileAsync('git', ['rev-parse', '--is-inside-work-tree'], {
      cwd,
    });
  } catch {
    return null;
  }
  try {
    const { stdout } = await execFileAsync(
      'git',
      ['ls-remote', '--heads', remote],
      { cwd, maxBuffer: 50 * 1024 * 1024 },
    );
    const names = new Set();
    for (const line of stdout.split(/\r?\n/)) {
      if (!line.trim()) continue;
      const tab = line.indexOf('\t');
      if (tab === -1) continue;
      const ref = line.slice(tab + 1).trim();
      const prefix = 'refs/heads/';
      if (!ref.startsWith(prefix)) continue;
      names.add(ref.slice(prefix.length));
    }
    if (names.size === 0) {
      console.warn(
        `[warn] git ls-remote --heads ${remote} returned no refs — refusing orphan-branch deletion.`,
      );
      return null;
    }
    return names;
  } catch (err) {
    console.warn(
      `[warn] git ls-remote failed (${remote}): ${err.message}; orphan-branch deletion skipped.`,
    );
    return null;
  }
}

function groupByBranch(deployments, includeNoGit) {
  const groups = new Map();
  for (const d of deployments) {
    const meta = d.meta || {};
    const branch =
      meta.githubCommitRef ||
      meta.gitlabCommitRef ||
      meta.bitbucketCommitRef ||
      null;
    if (!branch) {
      if (!includeNoGit) continue;
      const key = '<no-git>';
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(d);
      continue;
    }
    if (!groups.has(branch)) groups.set(branch, []);
    groups.get(branch).push(d);
  }
  // Newest first for each group.
  for (const list of groups.values()) {
    list.sort((a, b) => (b.created || 0) - (a.created || 0));
  }
  return groups;
}

function summarizeDeployment(d) {
  return {
    uid: d.uid,
    url: d.url,
    state: d.state,
    target: d.target || 'preview',
    branch:
      d.meta?.githubCommitRef ||
      d.meta?.gitlabCommitRef ||
      d.meta?.bitbucketCommitRef ||
      null,
    sha: (d.meta?.githubCommitSha ||
      d.meta?.gitlabCommitSha ||
      d.meta?.bitbucketCommitSha ||
      '').slice(0, 7),
    created: d.created ? new Date(d.created).toISOString() : null,
  };
}

async function deleteDeployment({ uid, token, teamId }) {
  // v13 delete supports both `id` and `url`; we use uid (`dpl_...`).
  const path = `/v13/deployments/${encodeURIComponent(uid)}?${teamQuery(teamId).slice(1)}`;
  await vercelFetch(path, token, { method: 'DELETE' });
}

function plural(n, word) {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}

async function main() {
  const args = parseArgs(process.argv);
  const token = process.env.VERCEL_TOKEN;
  if (!token) {
    console.error('Missing VERCEL_TOKEN env (Vercel → Account → Settings → Tokens).');
    process.exit(2);
  }
  const { projectId, teamId } = await loadProjectMeta(args);
  const keepSet = new Set(args.keepBranches);

  if (!args.json) {
    console.log(
      `Project: ${projectId}` +
        (teamId ? ` (team ${teamId})` : '') +
        `\nKeep-branches: ${[...keepSet].join(', ') || '(none)'}` +
        (args.pruneMain && keepSet.has('main')
          ? '\n--prune-main: branch `main` keeps only its newest deployment (prod alias preserved)'
          : '') +
        `\nMode: ${args.apply ? 'APPLY (will delete)' : 'dry-run (use --apply to delete)'}`,
    );
  }

  const skipGit = args.skipRemoteBranchCheck;
  const [deployments, prodUid, remoteBranches] = await Promise.all([
    listAllDeployments({ projectId, teamId, token }),
    findProductionAliasedUid({ projectId, teamId, token }),
    skipGit
      ? Promise.resolve(null)
      : loadRemoteBranchNames({ cwd: REPO_ROOT, remote: args.gitRemote }),
  ]);

  if (!args.json && !skipGit) {
    if (remoteBranches) {
      console.log(
        `Git ${args.gitRemote}: ${remoteBranches.size} remote branch heads — ` +
          'Vercel branches not in this set are treated as deleted and fully removed.',
      );
    } else {
      console.warn(
        '[warn] Remote branch list unavailable — orphan-branch deletion skipped.',
      );
    }
  }

  const groups = groupByBranch(deployments, args.includeNoGit);

  const plan = {
    project: projectId,
    team: teamId,
    productionUid: prodUid,
    remoteBranchCheck: Boolean(remoteBranches),
    gitRemote: args.gitRemote,
    pruneMain: args.pruneMain,
    branches: [],
    deleteUids: [],
    keepUids: [],
  };

  for (const [branch, list] of [...groups.entries()].sort((a, b) =>
    a[0].localeCompare(b[0]),
  )) {
    const isProtected = keepSet.has(branch);
    const pruneMainApplied =
      args.pruneMain && branch === 'main' && keepSet.has('main');
    const effectiveProtected = isProtected && !pruneMainApplied;
    const newest = list[0];
    const olderUids = list.slice(1).map((d) => d.uid);
    let toDelete = [];
    let toKeep = [];

    const branchDeletedRemote =
      remoteBranches !== null &&
      branch !== '<no-git>' &&
      !remoteBranches.has(branch);

    if (branchDeletedRemote) {
      // Branch no longer exists on origin — remove every preview deployment for it.
      toDelete = list.map((d) => d.uid);
      toKeep = [];
    } else if (effectiveProtected) {
      // Keep ALL deployments on protected branches — they may be production
      // rollback candidates or shared previews.
      toKeep = list.map((d) => d.uid);
    } else {
      toKeep = [newest.uid];
      toDelete = olderUids;
    }

    // Production-aliased deployment is sacred no matter which branch it claims.
    if (prodUid) {
      toDelete = toDelete.filter((uid) => uid !== prodUid);
      if (!toKeep.includes(prodUid) && list.some((d) => d.uid === prodUid)) {
        toKeep.push(prodUid);
      }
    }

    plan.branches.push({
      branch,
      protected: isProtected,
      effectiveProtected,
      pruneMainApplied,
      branchDeletedRemote,
      total: list.length,
      keep: toKeep.length,
      delete: toDelete.length,
      newest: summarizeDeployment(newest),
      deleteSamples: list
        .filter((d) => toDelete.includes(d.uid))
        .slice(0, 3)
        .map(summarizeDeployment),
    });
    plan.keepUids.push(...toKeep);
    plan.deleteUids.push(...toDelete);
  }

  if (args.json) {
    console.log(JSON.stringify(plan, null, 2));
  } else {
    printPlan(plan);
  }

  if (!args.apply) {
    if (!args.json) {
      console.log(
        `\nDry-run only — re-run with --apply to actually delete ` +
          `${plural(plan.deleteUids.length, 'deployment')}.`,
      );
    }
    return;
  }

  if (plan.deleteUids.length === 0) {
    if (!args.json) console.log('\nNothing to delete. Done.');
    return;
  }

  if (!args.json) console.log(`\nDeleting ${plural(plan.deleteUids.length, 'deployment')}…`);
  let ok = 0;
  let failed = 0;
  for (const uid of plan.deleteUids) {
    try {
      await deleteDeployment({ uid, token, teamId });
      ok += 1;
      if (!args.json) process.stdout.write('.');
    } catch (err) {
      failed += 1;
      if (!args.json) process.stdout.write('x');
      console.error(`\n  failed ${uid}: ${err.message}`);
    }
  }
  if (!args.json) {
    console.log(`\nDone: ${ok} deleted, ${failed} failed.`);
  }
  if (failed > 0) process.exit(1);
}

function printPlan(plan) {
  if (plan.productionUid) {
    console.log(`Production-aliased uid (always preserved): ${plan.productionUid}`);
  } else {
    console.log('Production-aliased uid: <unknown>; preserving aliased deployments only by branch rule.');
  }
  console.log('');
  // Header
  const head = ['Branch', 'Total', 'Keep', 'Delete', 'Status', 'Newest URL'];
  const rows = plan.branches.map((b) => {
    let status = 'clean';
    if (b.branchDeletedRemote) status = 'deleted-remote';
    else if (b.effectiveProtected) status = 'protected';
    else if (b.pruneMainApplied && b.delete > 0) status = 'prune-main';
    else if (b.delete > 0) status = 'prune';
    return [
      b.branch,
      String(b.total),
      String(b.keep),
      String(b.delete),
      status,
      b.newest?.url || '-',
    ];
  });
  const widths = head.map((h, i) =>
    Math.max(h.length, ...rows.map((r) => r[i].length)),
  );
  const fmt = (cols) => cols.map((c, i) => c.padEnd(widths[i])).join('  ');
  console.log(fmt(head));
  console.log(widths.map((w) => '-'.repeat(w)).join('  '));
  for (const r of rows) console.log(fmt(r));
  console.log('');
  console.log(
    `Totals: ${plan.keepUids.length} kept, ${plan.deleteUids.length} to delete.`,
  );
}

main().catch((err) => {
  console.error(err.stack || err.message || String(err));
  process.exit(1);
});
