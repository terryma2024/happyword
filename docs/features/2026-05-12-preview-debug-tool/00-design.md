# Preview Client-Server Debug Tool

## Intent

Provide a debug-only workflow for issues that appear when HarmonyOS, iOS, or Android clients connect to a Vercel Preview backend. The workflow starts from a problem description plus a preview branch/domain/PR, then correlates client request logs, Vercel runtime logs, Mongo traces, and selected Mongo business data.

## Stable Preview Routing

- Preview manifest rows expose both stable and deployment-specific identifiers:
  - `branch_url`: stable Vercel Git branch URL; clients use this by default.
  - `deployment_url`: commit/deployment URL; debug reports keep this for exact rollback.
  - `deployment_id` and `head_sha`: immutable deployment metadata.
- Manifest refresh fails when a branch URL cannot be found or does not pass `GET /api/v1/health`; it does not silently fall back to a changing deployment URL.
- Vercel protection bypass remains preview-only and is never sent by production/staging/local routes.

## Debug Session

- Server debug endpoints exist only when `PREVIEW_DEBUG_ENABLED` is truthy and `VERCEL_ENV` is not `production`.
- Every debug endpoint requires `Authorization: Bearer $PREVIEW_DEBUG_SECRET`.
- A session has TTL, target preview URL, branch/deployment metadata, creator, and active/stopped state.
- Request tracing happens only when the incoming request includes `x-hw-debug-session: <session_id>` and that session is active.
- Captured traces include method, path, status, timing, correlation id, redacted headers, and bounded request/response summaries.
- The server emits one-line `HW_PREVIEW_DEBUG_TRACE` JSON to runtime logs for Vercel log filtering.

## Secret Handling

- Local scripts read `~/.env` silently.
- Skill output, command previews, and logs must never print secret values.
- Redaction always covers authorization, cookies, Vercel bypass, device token, JWT-like fields, password, secret, and OpenAI key fields.
- Mongo data queries are local read-only allowlist queries from `tools/debug/preview_debug.py`; no public arbitrary DB query API is added.

## Client Behavior

- Debug builds expose Preview routing and debug session controls in DevMenu.
- All three clients attach `x-hw-debug-session` only for Preview routes and only when a session id is configured.
- Debug builds emit `HW_NET_DEBUG` request/response summaries so client logs can be correlated with server traces.
- Release builds must not expose DevMenu debug controls, and must not send bypass/debug headers outside Preview.

## Debug Workflow

1. Analyze the issue description and clarify only when reproduction-critical data is missing.
2. Resolve the preview from domain, branch, or PR.
3. Create a server debug session.
4. Turn on client-side debug logging and enter the session id.
5. Follow a narrow reproduction plan.
6. Collect client logs, Vercel logs, Mongo traces, and allowlisted business data.
7. Analyze before changing code.
8. Fix and deploy a new preview or open a PR.
9. Resume E2E only after the repair PR exists.

## Non-Goals

- No changes to the children's main gameplay flow.
- No arbitrary public database query endpoint.
- No E2E execution inside the debug/fix loop.
