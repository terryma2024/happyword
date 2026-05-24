# Developer menu — backend environment

For **debug builds only**, testers can change which backend the HarmonyOS app talks to.

## Open the menu

1. Build and install a **debug** HAP (`hvigorw assembleHap`).
2. On the **home** screen, **triple-tap** the small grey version label (top-left). There is no Settings entry — triple-tap is the only path.

Release builds do not show the version label tap target.

## Manifest fetch (preview list)

The DevMenu loads PR preview rows from:

`GET https://happyword.cool/api/v1/public/preview-urls.json`

That URL is **fixed** in code (`PREVIEW_MANIFEST_JSON_URL` in `RemoteWordPackConfig.ets`). It does **not** follow the backend environment you selected, and the GET carries **no** `x-vercel-protection-bypass` header — you only need normal HTTPS reachability to production.

Use **Refresh manifest** (top-right on DevMenu) after the server-side manifest
source changes. During the CloudBase migration, production can serve the
manifest from `PREVIEW_MANIFEST_INLINE_JSON`; otherwise it falls back to the
legacy Vercel Blob mirror.

## Environments

| Mode | Use |
| --- | --- |
| **Local** | Machine reachable from the device or emulator (e.g. `<android-emulator-host>` for Android-style emulator loopback). |
| **Preview** | A manifest row. During M8A this is usually the shared `CloudBase Staging` row (`*.tcloudbase.com`); legacy Vercel preview rows (`*.vercel.app`) remain accepted until Vercel Preview is retired. |
| **Staging** | Default shared hosted URL (`https://happyword.cool`) for normal API traffic. |
| **Production** | Reserved; disabled until a production URL ships in a future release. |

Tapping a card **applies** the environment immediately (health probe for Preview only, session reset, toast, navigation back to Home). There is no separate Apply button.

## Automation / server

The public preview manifest can now come from either source:

- `PREVIEW_MANIFEST_INLINE_JSON` on the FastAPI server. This is the M8A
  CloudBase path and can publish a single shared `CloudBase Staging` row
  without Vercel Blob.
- `PREVIEW_MANIFEST_BLOB_URL`, the legacy Vercel Blob mirror. This remains as a
  compatibility fallback until the Vercel Preview path is retired.

The legacy Vercel Blob manifest at `preview/preview-urls.json` can still be
rebuilt from Vercel's deployments API by
`server/scripts/update_preview_manifest.mjs`. During the transition,
`server-ci` still deploys Vercel Preview and refreshes this Blob mirror for PRs,
while CloudBase staging is available as an opt-in smoke target. Use
`.github/workflows/preview-manifest.yml` for legacy PR close cleanup or manual
repair / backfill while Vercel Preview remains available.

A merged PR whose preview deployment hasn't been pruned by the weekly `vercel-prune.yml` cron stays in the manifest, because the source of truth is "what's alive on Vercel right now", not "what PR is currently open".

For the legacy path, the Blob is the only output: the historical repo-tracked
audit copy at `docs/preview-urls.json` was retired in 2026-05 because the
bot-commit churn on `main` had no readers — the FastAPI proxy already served
traffic out of Blob. `BLOB_READ_WRITE_TOKEN` must therefore be configured in
GitHub Actions for the rebuild jobs to do anything (otherwise they skip with a
warning), and the FastAPI backend must have `PREVIEW_MANIFEST_BLOB_URL` set to
the public Blob URL printed by the manifest rebuild job.

PR-specific CloudBase previews are not automatic in M8A. Keep using the shared
CloudBase staging row until service quota, route discovery, data isolation, and
cleanup are implemented for on-demand PR previews.

CloudBase staging smoke is opt-in: run `server-ci` manually or add the
`cloudbase-smoke` label to a PR after `CLOUDBASE_STAGING_BASE_URL` points at a
healthy staging service.

**Server contract:** `GET /api/v1/public/preview-urls.json` is intentionally **unauthenticated** at the application layer (public router — no JWT, cookies, or API keys). Vercel Deployment Protection on *preview* deployments does not apply to this URL because the client always calls **production** `happyword.cool` for the manifest.
