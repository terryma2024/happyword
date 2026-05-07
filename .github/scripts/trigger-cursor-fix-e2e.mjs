#!/usr/bin/env node
// Triggered by:
//   - .github/workflows/server-ci.yml (auto, when `server / e2e (preview)` fails)
//   - .github/workflows/cursor-autofix-e2e.yml (manual, workflow_dispatch)
//
// Spawns a Cursor Cloud Agent against the PR's head branch and asks it to
// commit the fix back to that branch (no new PR).
//
// Guards:
//   1. Per-SHA debounce — at most one Cursor agent per (PR, head SHA), keyed
//      by a hidden marker comment. Bypass via FORCE_TRIGGER=1.
//   2. Per-PR round cap (MAX_ROUNDS) — once that many marker comments exist
//      on the PR (auto + manual combined), refuse to trigger another agent.
//   3. Unfixable failure filter — if the pytest log clearly indicates an
//      environmental / deployment problem, refuse to trigger and explain why.
//      Bypass via FORCE_TRIGGER=1.

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
  TRIGGER_SOURCE = "auto",
  TRIGGER_REASON = "",
  FORCE_TRIGGER = "0",
} = process.env;

// Treat unset / empty-string / non-numeric as "use default 20". Necessary
// because the manual workflow passes MAX_ROUNDS="" when the user leaves the
// input blank — and Number("") === 0 would silently block every dispatch.
//
// 20 is the long-running-PR friendly default (raised from the original 10
// after a long-lived branch hit the cap mid-debug). Tighten by setting
// MAX_ROUNDS in workflow env if a particular PR proves pathological.
const DEFAULT_MAX_ROUNDS = 20;
const _maxRoundsRaw = (process.env.MAX_ROUNDS ?? "").trim();
const _maxRoundsParsed = Number(_maxRoundsRaw);
const MAX_ROUNDS =
  _maxRoundsRaw === "" || !Number.isFinite(_maxRoundsParsed) || _maxRoundsParsed < 1
    ? DEFAULT_MAX_ROUNDS
    : Math.floor(_maxRoundsParsed);
const FORCE = FORCE_TRIGGER === "1" || FORCE_TRIGGER.toLowerCase() === "true";
const SOURCE = TRIGGER_SOURCE === "manual" ? "manual" : "auto";

const MARKER = `<!-- cursor-autofix-triggered:${PR_HEAD_SHA} -->`;
// Loose marker — matches any prior trigger on this PR regardless of SHA.
// Used for round-cap counting.
const MARKER_RE = /<!--\s*cursor-autofix-triggered:[^>]+-->/g;

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

async function listAllComments() {
  const out = [];
  for (let page = 1; page <= 10; page += 1) {
    const batch = await gh(
      `/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments?per_page=100&page=${page}`
    );
    out.push(...batch);
    if (batch.length < 100) break;
  }
  return out;
}

function countMarkers(comments) {
  let total = 0;
  let sameSha = 0;
  for (const c of comments) {
    const body = typeof c.body === "string" ? c.body : "";
    const matches = body.match(MARKER_RE) ?? [];
    total += matches.length;
    if (body.includes(MARKER)) sameSha += 1;
  }
  return { total, sameSha };
}

function readLogSnippet() {
  // Cap context to keep prompt size sane. Keep head + tail because pytest's
  // useful info is split between the failure summary (top) and the FAILED list
  // (bottom).
  const MAX = 24 * 1024;
  try {
    const raw = fs.readFileSync(LOG_RESOLVED, "utf8");
    if (raw.length <= MAX) return { snippet: raw, present: true };
    const head = raw.slice(0, 6 * 1024);
    const tail = raw.slice(-(MAX - head.length));
    return {
      snippet: `${head}\n... [TRUNCATED ${raw.length - MAX} bytes from middle] ...\n${tail}`,
      present: true,
    };
  } catch (err) {
    return {
      snippet: `(could not read pytest log at ${LOG_RESOLVED}: ${err.message})`,
      present: false,
    };
  }
}

// Conservative classifier: only return unfixable when the log clearly screams
// "environment / deployment problem" — never on assertion failures or bugs.
// Bypass with FORCE_TRIGGER=1.
function classifyFailure({ snippet, present }) {
  if (!present) {
    return { fixable: true, reason: null };
  }

  const indicators = [
    {
      name: "E2E_BASE_URL not configured",
      re: /E2E_BASE_URL[^\n]{0,80}(not\s+set|empty|missing|undefined|''|""|=$)/i,
    },
    {
      name: "Vercel preview URL unavailable",
      re: /(no preview url|preview url is empty|preview not ready|preview deployment.{0,40}(not ready|failed))/i,
    },
    {
      name: "Vercel deployment failure (server-side)",
      re: /(vercel deployment.{0,30}failed|vercel.{0,40}internal (server )?error|deployment_error)/i,
    },
    {
      name: "MongoDB unreachable (env-side)",
      re: /(ServerSelectionTimeoutError|MongoNetworkError|pymongo\.errors\.NetworkTimeout|ECONNREFUSED.{0,80}27017|connection refused.{0,40}mongo)/i,
    },
    {
      name: "Backend totally unreachable (502/503/504 on every call)",
      re: /(httpx\.ConnectError|httpx\.ReadTimeout|gateway timeout|bad gateway|service unavailable).{0,200}(httpx\.ConnectError|httpx\.ReadTimeout|gateway timeout|bad gateway|service unavailable)/is,
    },
    {
      // Preview has Deployment Protection (Vercel Authentication / Password
      // Protection / Trusted IPs) enabled, AND the runner did not present a
      // valid `x-vercel-protection-bypass` header — so every API call is
      // intercepted with a 401 + the Vercel SSO HTML page. Symptom in the
      // pytest log: every test errors/fails with a `<title>Authentication
      // Required</title>` payload. No code change can fix this — the operator
      // must add the `VERCEL_AUTOMATION_BYPASS_SECRET` repo secret (minted in
      // Vercel project settings → Deployment Protection → "Protection Bypass
      // for Automation"), which the workflow already forwards to pytest as
      // `E2E_VERCEL_PROTECTION_BYPASS`. See server/README.md → "CI integration".
      name: "Vercel deployment protection blocking requests (missing/invalid VERCEL_AUTOMATION_BYPASS_SECRET)",
      re: /<title>Authentication Required<\/title>[\s\S]{0,4000}(vercel\.com\/sso-api|x-vercel-protection-bypass|Vercel Authentication)/i,
    },
    {
      name: "No tests collected",
      re: /(no tests ran in|0 (test cases?|items) collected|collected 0 items)/i,
    },
  ];

  for (const ind of indicators) {
    if (ind.re.test(snippet)) {
      return { fixable: false, reason: ind.name };
    }
  }
  return { fixable: true, reason: null };
}

function buildPrompt(logSnippet) {
  return [
    `An end-to-end (E2E) test job failed for an open pull request. Investigate and fix the failures.`,
    ``,
    `PR: ${PR_URL} (#${PR_NUMBER})`,
    `Branch: \`${PR_HEAD_REF}\``,
    `Head SHA: \`${PR_HEAD_SHA}\``,
    `Failed Actions run: ${RUN_URL}`,
    `Trigger source: ${SOURCE}${TRIGGER_REASON ? ` (${TRIGGER_REASON})` : ""}`,
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
    `4. **Commit your changes directly to branch \`${PR_HEAD_REF}\` and push.** Do NOT create a new branch and do NOT open a new pull request — the fix must land as additional commits on the existing PR #${PR_NUMBER}. Use a clear commit message that includes a one-sentence root-cause summary and references PR #${PR_NUMBER}.`,
    ``,
    `If the failure is purely environmental and no code change can resolve it, push a single commit that adds a brief written explanation (e.g. updates a comment in the failing test or a TODO note in the PR description area), still on \`${PR_HEAD_REF}\`. Never open a separate PR.`,
  ].join("\n");
}

function agentWebUrl(agentId) {
  // Cursor Cloud Agents detail URL pattern (cursor.com/agents/<id>).
  // If Cursor changes this path, update here; the dashboard root always works
  // as a fallback.
  return agentId ? `https://cursor.com/agents/${agentId}` : `https://cursor.com/dashboard/cloud-agents`;
}

async function postPrComment(body) {
  await gh(`/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments`, {
    method: "POST",
    body: JSON.stringify({ body }),
  });
}

async function postMarkerComment({ agentId, runId, roundsAfter }) {
  const url = agentWebUrl(agentId);
  const body = [
    MARKER,
    `🤖 **Cursor Cloud autofix triggered** (${SOURCE}, round ${roundsAfter}/${MAX_ROUNDS}) for failing \`server / e2e (preview)\` job.`,
    ``,
    `- Failed Actions run: ${RUN_URL}`,
    `- Head SHA: \`${PR_HEAD_SHA}\``,
    `- Cursor agent: [\`${agentId ?? "unknown"}\`](${url})`,
    `- Cursor run: \`${runId ?? "unknown"}\``,
    TRIGGER_REASON ? `- Manual reason: ${TRIGGER_REASON}` : null,
    ``,
    `Open the agent: ${url}`,
    `When ready, the agent will commit & push the fix **directly to \`${PR_HEAD_REF}\`** (no new PR).`,
    ``,
    `_Per-SHA debounce active — re-running the workflow on the same commit will not start a second agent (override with \`force=true\` in manual dispatch)._`,
  ]
    .filter((line) => line !== null)
    .join("\n");
  await postPrComment(body);
}

function logCiSummary({ kind, agentId, runId, reason }) {
  if (!process.env.GITHUB_STEP_SUMMARY) return;
  const url = agentWebUrl(agentId);
  let lines;
  if (kind === "dispatched") {
    lines = [
      `### Cursor Cloud autofix dispatched (${SOURCE})`,
      ``,
      `- Agent: [\`${agentId}\`](${url})`,
      `- Run: \`${runId}\``,
      `- Source CI run: ${RUN_URL}`,
      `- PR: ${PR_URL} (head \`${PR_HEAD_SHA}\`)`,
      ``,
    ];
  } else {
    lines = [
      `### Cursor Cloud autofix skipped (${kind})`,
      ``,
      `- Reason: ${reason}`,
      `- PR: ${PR_URL} (head \`${PR_HEAD_SHA}\`)`,
      ``,
    ];
  }
  try {
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, lines.join("\n"));
  } catch {
    /* best-effort */
  }
}

async function dispatchAgent(prompt) {
  // We must explicitly pass `cloud:` — if both `local:` and `cloud:` are
  // omitted the SDK silently defaults to a local runtime, which is useless
  // inside a CI job that's about to exit.
  // Note: Agent.create is async in @cursor/sdk >=1.0 — it must be awaited;
  // otherwise `agent.send` is undefined (we'd be calling it on a Promise).
  // Schema (per @cursor/sdk options.d.ts CloudAgentOptions):
  //   repos[]: { url, startingRef?, prUrl? }
  //   workOnCurrentBranch / autoCreatePR / skipReviewerRequest live at
  //   cloud-level, NOT per-repo.
  //
  // We deliberately:
  //   - workOnCurrentBranch: true  → commit directly to PR_HEAD_REF instead
  //                                  of cutting a new branch.
  //   - autoCreatePR:        false → do NOT open a new PR; the fix lands as
  //                                  another commit on the existing PR.
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
      workOnCurrentBranch: true,
      autoCreatePR: false,
      skipReviewerRequest: true,
    },
  });

  let agentId = null;
  let runId = null;
  try {
    const run = await agent.send(prompt);
    agentId = agent.agentId ?? null;
    runId = run?.id ?? null;
    // Intentionally do NOT call run.wait(): a cloud E2E autofix can take many
    // minutes; we want CI to exit quickly. The cloud-side run keeps executing
    // independently.
  } finally {
    await agent[Symbol.asyncDispose]?.();
  }
  return { agentId, runId };
}

async function main() {
  const comments = await listAllComments();
  const { total: priorRounds, sameSha } = countMarkers(comments);
  console.log(
    `PR #${PR_NUMBER}: ${priorRounds} prior autofix round(s); ${sameSha} for current SHA. Cap=${MAX_ROUNDS}, force=${FORCE}, source=${SOURCE}.`
  );

  // Round cap (per PR, across all SHAs).
  if (priorRounds >= MAX_ROUNDS) {
    const reason = `MAX_ROUNDS (${MAX_ROUNDS}) reached on PR #${PR_NUMBER}; ${priorRounds} agent(s) already triggered.`;
    console.log(`Skipping: ${reason}`);
    logCiSummary({ kind: "round-cap", reason });
    if (priorRounds === MAX_ROUNDS) {
      await postPrComment(
        [
          `⚠️ **Cursor Cloud autofix paused** — round cap reached (${MAX_ROUNDS}).`,
          ``,
          `Re-enable by removing some \`<!-- cursor-autofix-triggered:* -->\` marker comments above, or raise \`MAX_ROUNDS\` in \`.github/scripts/trigger-cursor-fix-e2e.mjs\`.`,
        ].join("\n")
      );
    }
    return;
  }

  // Per-SHA debounce.
  if (sameSha > 0 && !FORCE) {
    console.log(`Skipping: agent already dispatched for SHA ${PR_HEAD_SHA}; use FORCE_TRIGGER=1 to override.`);
    logCiSummary({
      kind: "duplicate-sha",
      reason: `Already triggered for SHA ${PR_HEAD_SHA}.`,
    });
    return;
  }

  // Unfixable filter.
  const log = readLogSnippet();
  const verdict = classifyFailure(log);
  if (!verdict.fixable && !FORCE) {
    const reason = `Log indicates environmental issue: ${verdict.reason}.`;
    console.log(`Skipping: ${reason}`);
    logCiSummary({ kind: "unfixable", reason });
    await postPrComment(
      [
        `🛑 **Cursor Cloud autofix skipped** for SHA \`${PR_HEAD_SHA}\` — the failure looks environmental, not a code bug.`,
        ``,
        `- Detected indicator: **${verdict.reason}**`,
        `- Source CI run: ${RUN_URL}`,
        ``,
        `Investigate the deployment / CI configuration. To force a Cursor agent anyway, use the manual dispatch with \`force=true\`.`,
      ].join("\n")
    );
    return;
  }

  const prompt = buildPrompt(log.snippet);
  const { agentId, runId } = await dispatchAgent(prompt);

  console.log(`Spawned Cursor Cloud agent agentId=${agentId} runId=${runId}`);
  console.log(`Track progress: ${agentWebUrl(agentId)}`);
  logCiSummary({ kind: "dispatched", agentId, runId });

  await postMarkerComment({ agentId, runId, roundsAfter: priorRounds + 1 });
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
