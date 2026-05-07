#!/usr/bin/env node
// Triggered by .github/workflows/server-ci.yml when `server / e2e (preview)` fails.
// Spawns a Cursor Cloud Agent against this repo + PR branch with the failing
// pytest log as context, asks it to open a fix PR targeting the PR branch.
//
// Debounce: posts a hidden marker comment on the PR. If a comment with the
// same marker for the same head SHA already exists, the run no-ops. This
// guarantees one Cursor Cloud Agent per (PR, commit SHA), even if the workflow
// is re-run.

import fs from "node:fs";
import process from "node:process";
import { Agent } from "@cursor/sdk";

const REQUIRED_ENV = [
  "CURSOR_API_KEY",
  "GITHUB_TOKEN",
  "GITHUB_REPOSITORY",
  "PR_NUMBER",
  "PR_URL",
  "PR_HEAD_SHA",
  "PR_HEAD_REF",
  "REPO_URL",
  "RUN_URL",
];

for (const key of REQUIRED_ENV) {
  if (!process.env[key]) {
    console.error(`Missing required env: ${key}`);
    process.exit(1);
  }
}

const {
  CURSOR_API_KEY,
  GITHUB_TOKEN,
  GITHUB_REPOSITORY,
  PR_NUMBER,
  PR_URL,
  PR_HEAD_SHA,
  PR_HEAD_REF,
  REPO_URL,
  RUN_URL,
  E2E_LOG_FILE = "artifacts/e2e-pytest.log",
} = process.env;

const MARKER = `<!-- cursor-autofix-triggered:${PR_HEAD_SHA} -->`;
const LOG_RESOLVED = fs.existsSync(E2E_LOG_FILE)
  ? E2E_LOG_FILE
  : `${process.env.GITHUB_WORKSPACE ?? ".."}/${E2E_LOG_FILE}`;

async function gh(pathname, init = {}) {
  const url = `https://api.github.com${pathname}`;
  const res = await fetch(url, {
    ...init,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${GITHUB_TOKEN}`,
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "happyword-cursor-autofix",
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`GitHub ${init.method ?? "GET"} ${pathname} -> ${res.status}: ${body}`);
  }
  return res.json();
}

async function alreadyTriggered() {
  // Paginate manually: GitHub returns max 100 per page; PRs rarely exceed a few hundred comments.
  for (let page = 1; page <= 5; page += 1) {
    const comments = await gh(
      `/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments?per_page=100&page=${page}`
    );
    if (comments.some((c) => typeof c.body === "string" && c.body.includes(MARKER))) {
      return true;
    }
    if (comments.length < 100) break;
  }
  return false;
}

function readLogSnippet() {
  // Cap context to keep prompt size sane. Keep head + tail because pytest's
  // useful info is split between the failure summary (top) and the FAILED list
  // (bottom).
  const MAX = 24 * 1024;
  try {
    const raw = fs.readFileSync(LOG_RESOLVED, "utf8");
    if (raw.length <= MAX) return raw;
    const head = raw.slice(0, 6 * 1024);
    const tail = raw.slice(-(MAX - head.length));
    return `${head}\n... [TRUNCATED ${raw.length - MAX} bytes from middle] ...\n${tail}`;
  } catch (err) {
    return `(could not read pytest log at ${LOG_RESOLVED}: ${err.message})`;
  }
}

function buildPrompt(logSnippet) {
  return [
    `An end-to-end (E2E) test job failed for an open pull request. Investigate and fix the failures.`,
    ``,
    `PR: ${PR_URL} (#${PR_NUMBER})`,
    `Branch: \`${PR_HEAD_REF}\``,
    `Head SHA: \`${PR_HEAD_SHA}\``,
    `Failed Actions run: ${RUN_URL}`,
    ``,
    `Repository layout:`,
    `- E2E tests live under \`server/tests/e2e/\` (pytest, marker \`@pytest.mark.e2e\`).`,
    `- Suite is run with \`uv run pytest -v -m e2e\` per \`server/README.md\`.`,
    `- The CI job runs against a Vercel Preview deployment of this PR; \`scripts/e2e_reset_db.py\` resets a per-PR Mongo DB before each run.`,
    ``,
    `Pytest output (possibly truncated, head + tail kept):`,
    "```",
    logSnippet,
    "```",
    ``,
    `Please:`,
    `1. Diagnose the failure from the log above; reproduce locally if reasonable.`,
    `2. Distinguish a real bug from environment / flake (preview not ready, Mongo reset issues, missing E2E secrets). Do NOT modify CI secrets or workflow files unless the failure is clearly caused by a wrong workflow definition.`,
    `3. Apply the smallest fix that makes the failing E2E case(s) pass while keeping the rest of the suite green. Prefer fixing production code over weakening assertions.`,
    `4. Open a pull request **targeting branch \`${PR_HEAD_REF}\`** (NOT main). Reference PR #${PR_NUMBER} in the description and include a one-paragraph root-cause summary.`,
    ``,
    `If the failure is purely environmental and no code change can resolve it, open the PR with a brief written explanation and a TODO checklist instead of forcing a code change.`,
  ].join("\n");
}

function agentWebUrl(agentId) {
  // Cursor Cloud Agents detail URL pattern (cursor.com/agents/<id>).
  // If Cursor changes this path, update here; the dashboard root always works
  // as a fallback.
  return agentId ? `https://cursor.com/agents/${agentId}` : `https://cursor.com/dashboard/cloud-agents`;
}

async function postMarkerComment({ agentId, runId }) {
  const url = agentWebUrl(agentId);
  const body = [
    MARKER,
    `🤖 **Cursor Cloud autofix triggered** for failing \`server / e2e (preview)\` job.`,
    ``,
    `- Failed Actions run: ${RUN_URL}`,
    `- Head SHA: \`${PR_HEAD_SHA}\``,
    `- Cursor agent: [\`${agentId ?? "unknown"}\`](${url})`,
    `- Cursor run: \`${runId ?? "unknown"}\``,
    ``,
    `Open the agent: ${url}`,
    `When ready, the agent will open a follow-up PR against \`${PR_HEAD_REF}\`.`,
    ``,
    `_This run is debounced — re-running the workflow on the same commit will not start a second agent._`,
  ].join("\n");
  await gh(`/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments`, {
    method: "POST",
    body: JSON.stringify({ body }),
  });
}

async function main() {
  if (await alreadyTriggered()) {
    console.log(`Cursor autofix already triggered for SHA ${PR_HEAD_SHA}; skipping.`);
    return;
  }

  const logSnippet = readLogSnippet();
  const prompt = buildPrompt(logSnippet);

  // We must explicitly pass `cloud:` — if both `local:` and `cloud:` are
  // omitted the SDK silently defaults to a local runtime, which is useless
  // inside a CI job that's about to exit.
  // Note: Agent.create is async in @cursor/sdk >=1.0 — it must be awaited;
  // otherwise `agent.send` is undefined (we'd be calling it on a Promise).
  // Schema (per @cursor/sdk options.d.ts CloudAgentOptions):
  //   repos[]: { url, startingRef?, prUrl? }
  //   autoCreatePR / skipReviewerRequest live at cloud-level, NOT per-repo.
  const agent = await Agent.create({
    apiKey: CURSOR_API_KEY,
    cloud: {
      repos: [
        {
          url: REPO_URL,
          startingRef: PR_HEAD_REF,
          prUrl: PR_URL,
        },
      ],
      autoCreatePR: true,
      // Quiet PR notifications — humans review the resulting PR explicitly.
      skipReviewerRequest: true,
    },
  });

  let agentId = null;
  let runId = null;
  try {
    const run = await agent.send(prompt);
    agentId = agent.agentId ?? null;
    runId = run?.id ?? null;
    const url = agentWebUrl(agentId);
    console.log(`Spawned Cursor Cloud agent agentId=${agentId} runId=${runId}`);
    console.log(`Track progress: ${url}`);
    // Surface the URL in the GitHub Actions step summary so it shows up at the
    // top of the failed run page next to the workflow log.
    if (process.env.GITHUB_STEP_SUMMARY) {
      const summary = [
        `### Cursor Cloud autofix dispatched`,
        ``,
        `- Agent: [\`${agentId}\`](${url})`,
        `- Run: \`${runId}\``,
        `- Failed CI run: ${RUN_URL}`,
        ``,
      ].join("\n");
      try {
        fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
      } catch {
        /* best-effort */
      }
    }
    // Intentionally do NOT call run.wait(): a cloud E2E autofix can take many
    // minutes; we want CI to exit quickly. The cloud-side run keeps executing
    // independently. The IDs above are recorded in the PR comment for tracking.
  } finally {
    await agent[Symbol.asyncDispose]?.();
  }

  await postMarkerComment({ agentId, runId });
  console.log("Posted marker comment on PR.");
}

main()
  .then(() => {
    // Force exit: the SDK may keep open background watchers / keep-alive
    // sockets even after agent.close() / asyncDispose, which would block Node
    // from exiting and hang the CI step indefinitely. We have no further work,
    // so exit explicitly with success.
    process.exit(0);
  })
  .catch((err) => {
    console.error(`Cursor autofix trigger failed: ${err?.stack ?? err}`);
    process.exit(1);
  });
