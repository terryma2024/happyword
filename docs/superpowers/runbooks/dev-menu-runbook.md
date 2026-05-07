# Developer menu — backend environment

For **debug builds only**, testers can change which backend the HarmonyOS app talks to.

## Open the menu

1. Build and install a **debug** HAP (`hvigorw assembleHap`).
2. In the app, open **Settings** (gear).
3. Scroll to **Developer** → **Backend environment**.

Release builds do not show this row.

## Environments

| Mode | Use |
| --- | --- |
| **Local** | Machine reachable from the device or emulator (e.g. `10.0.2.2` for Android-style emulator loopback). |
| **Preview** | A Vercel preview deployment. Pick a row from the manifest (from `docs/preview-urls.json` on `main`) or paste a `https://*.vercel.app` URL. |
| **Staging** | Default shared staging URL (`https://happyword.vercel.app`). |
| **Production** | Reserved; disabled until a production URL ships in a future release. |

Tap **Apply** after changing the environment. Cloud session data for the previous backend is cleared on purpose; local learning progress stays on device.

## Manifest refresh

The app caches `docs/preview-urls.json` from the GitHub `main` branch. Use **Refresh manifest** on the DevMenu page when a new PR preview should appear.

## Automation

`docs/preview-urls.json` is rebuilt from Vercel's deployments API by `server/scripts/update_preview_manifest.mjs`. Two workflows trigger the rebuild:

- `.github/workflows/server-ci.yml` (`update_manifest` job) — on PR open/sync/reopen, gated on `server_e2e` success.
- `.github/workflows/preview-manifest.yml` — on PR close, and via **workflow_dispatch** for manual repair / backfill (now performs a full rebuild rather than no-op).

A merged PR whose preview deployment hasn't been pruned by the weekly `vercel-prune.yml` cron stays in the manifest, because the source of truth is "what's alive on Vercel right now", not "what PR is currently open".
