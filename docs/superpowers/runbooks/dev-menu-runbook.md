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

`.github/workflows/preview-manifest.yml` updates `docs/preview-urls.json` when PRs open, sync, reopen, or close. Manual runs use **workflow_dispatch** (no PR payload → script exits without changing the file).
