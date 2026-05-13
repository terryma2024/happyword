---
name: preview-client-server-debug
description: Use when debugging WordMagicGame native clients connecting to a Vercel Preview domain, branch URL, PR preview, or preview-only server/database issue.
---

# Preview Client/Server Debug

Use this skill for problems where HarmonyOS, iOS, or Android connects to a Vercel Preview backend and the failure might involve routing, Deployment Protection, request headers, server runtime logs, or Mongo state.

## Hard Rules

- Do not run E2E during the debug/fix loop. Use unit tests, builds, static checks, targeted smoke requests, and manual reproduction. Re-enable E2E only after the fix PR exists.
- Never print secrets from `~/.env`. Use `tools/debug/preview_debug.py`; it reads secrets silently and redacts command examples.
- Use the stable `branch_url` for client routing. Keep `deployment_url` and `deployment_id` in notes so the exact deploy remains traceable.
- Debug APIs must be Preview-only. If `/api/v1/debug/*` returns 404, treat that as expected unless `PREVIEW_DEBUG_ENABLED=true` and `VERCEL_ENV!=production`.

## Workflow

1. Restate the symptom, target platform, preview domain/PR/branch, and expected behavior. If any of those are missing and cannot be inferred, ask one concise clarification.
2. Resolve the preview:
   ```sh
   python3 tools/debug/preview_debug.py resolve --pr <number>
   python3 tools/debug/preview_debug.py resolve --branch <branch>
   python3 tools/debug/preview_debug.py resolve --domain <preview-url>
   ```
3. Create a server debug session:
   ```sh
   python3 tools/debug/preview_debug.py create-session --pr <number> --problem "<short symptom>"
   ```
   Copy only the returned `x-hw-debug-session` value into the debug client UI.
4. Start Vercel runtime log streaming in a separate terminal:
   ```sh
   python3 tools/debug/preview_debug.py vercel-logs --url <branch_url>
   ```
5. Start client logs:
   ```sh
   python3 tools/debug/preview_debug.py client-logs --platform harmonyos
   python3 tools/debug/preview_debug.py client-logs --platform android
   python3 tools/debug/preview_debug.py client-logs --platform ios
   ```
6. Run the client reproduction plan manually or with platform UI automation that is not E2E.
7. Pull traces and DB rows:
   ```sh
   python3 tools/debug/preview_debug.py traces --base-url <branch_url> --session-id <dbg_id>
   python3 tools/debug/preview_debug.py mongo-find --collection debug_traces --query '{"session_id":"<dbg_id>"}'
   ```
8. Classify the root cause before editing code: client route/header issue, Vercel protection/build/runtime issue, server app bug, or DB/data mismatch.
9. Fix code with focused tests. Deploy a new preview, keep using the branch URL, and only then let PR CI/E2E validate.

## Platform Notes

- HarmonyOS: DevMenu is opened from debug builds via Settings / version triple-tap. Set Preview, bypass secret, and debug session there.
- Android: use the debug developer row. Release must hide DevMenu, bypass, and debug session controls.
- iOS: use the debug-only Settings Debug button. Release must hide Preview and debug controls.

## Useful Existing Skills

- Use Vercel CLI/API guidance when a preview returns 401/404/500/504 before the app handler.
- Use GitHub CI guidance only after a repair PR exists and E2E is allowed to resume.
