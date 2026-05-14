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

Use **Refresh manifest** (top-right on DevMenu) after CI publishes an updated Blob mirror.

## Environments

| Mode | Use |
| --- | --- |
| **Local** | Machine reachable from the device or emulator (e.g. `10.0.2.2` for Android-style emulator loopback). |
| **Preview** | A Vercel preview deployment. Pick a row from the manifest cards (`*.vercel.app` URLs embedded in the JSON above). |
| **Staging** | Default shared hosted URL (`https://happyword.cool`) for normal API traffic. |
| **Production** | Reserved; disabled until a production URL ships in a future release. |

Tapping a card **applies** the environment immediately (health probe for Preview only, session reset, toast, navigation back to Home). There is no separate Apply button.

## Automation / server

The public preview manifest at `preview/preview-urls.json` in Vercel Blob is rebuilt from Vercel's deployments API by `server/scripts/update_preview_manifest.mjs`. Two workflows trigger the rebuild:

- `.github/workflows/server-ci.yml` (`update_manifest` job) — on PR open/sync/reopen, gated on `server_e2e` success.
- `.github/workflows/preview-manifest.yml` — on PR close, and via **workflow_dispatch** for manual repair / backfill.

A merged PR whose preview deployment hasn't been pruned by the weekly `vercel-prune.yml` cron stays in the manifest, because the source of truth is "what's alive on Vercel right now", not "what PR is currently open".

The Blob is the only output: the historical repo-tracked audit copy at `docs/preview-urls.json` was retired in 2026-05 because the bot-commit churn on `main` had no readers — the FastAPI proxy already served traffic out of Blob. `BLOB_READ_WRITE_TOKEN` must therefore be configured in GitHub Actions for the rebuild jobs to do anything (otherwise they skip with a warning), and the FastAPI backend must have `PREVIEW_MANIFEST_BLOB_URL` set to the public Blob URL printed by the manifest rebuild job.

**Server contract:** `GET /api/v1/public/preview-urls.json` is intentionally **unauthenticated** at the application layer (public router — no JWT, cookies, or API keys). Vercel Deployment Protection on *preview* deployments does not apply to this URL because the client always calls **production** `happyword.cool` for the manifest.
