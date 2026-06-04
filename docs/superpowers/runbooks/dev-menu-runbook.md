# Developer menu — backend environment

For **debug builds only**, testers can change which backend the HarmonyOS app talks to.

## Open the menu

1. Build and install a **debug** HAP (`hvigorw assembleHap`).
2. On the **home** screen, **triple-tap** the small grey version label (top-left). There is no Settings entry — triple-tap is the only path.

Release builds do not show the version label tap target.

## Manifest fetch (preview list)

The DevMenu loads PR preview rows from:

`GET https://happyword.com.cn/api/v1/public/preview-urls.json`

That URL is **fixed** in code (`PREVIEW_MANIFEST_JSON_URL` in `RemoteWordPackConfig.ets`). It does **not** follow the backend environment you selected, and the GET carries **no** `x-vercel-protection-bypass` header — you only need normal HTTPS reachability to production.

Use **Refresh manifest** (top-right on DevMenu) after the server-side manifest
source changes. The production endpoint returns CloudBase production and
staging rows by default; `PREVIEW_MANIFEST_INLINE_JSON` is now only an optional
override.

## Environments

| Mode | Use |
| --- | --- |
| **Local** | Machine reachable from the device or emulator (e.g. `<android-emulator-host>` for Android-style emulator loopback). |
| **Preview** | A manifest row. After Vercel Preview retirement this list contains CloudBase production/staging rows only. |
| **Staging** | Default shared hosted URL (`https://happyword.com.cn`) for normal API traffic. |
| **Production** | Reserved; disabled until a production URL ships in a future release. |

Tapping a card **applies** the environment immediately (health probe for Preview only, session reset, toast, navigation back to Home). There is no separate Apply button.

## Automation / server

The public manifest no longer reads Vercel Blob and no workflow rebuilds
`preview/preview-urls.json`. The default response is defined in
`server/app/services/preview_manifest_service.py`:

- `HappyWord Production` -> `https://happyword.com.cn`
- `CloudBase Staging` -> the shared `happyword-server-staging` CloudBase Run
  default domain

Set `PREVIEW_MANIFEST_INLINE_JSON` only when you need to temporarily override
those rows from runtime configuration.

PR-specific CloudBase previews are not automatic. Keep using the shared
CloudBase staging row until service quota, route discovery, data isolation, and
cleanup are implemented for on-demand PR previews.

CloudBase staging smoke runs automatically for PRs that touch `server/**` or
`.github/workflows/server-ci.yml`. The `server-ci` job deploys the PR's packaged
`server/` artifact to the shared `happyword-server-staging` CloudBase Run
service, waits for that revision to receive traffic, then resets the shared E2E
database and runs the HTTP E2E suite against `CLOUDBASE_STAGING_BASE_URL`.

**Server contract:** `GET /api/v1/public/preview-urls.json` is intentionally **unauthenticated** at the application layer (public router — no JWT, cookies, or API keys). The client always calls **production** `happyword.com.cn` for the manifest, independent of the currently selected backend.
