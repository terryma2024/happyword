# Server scripts

## update_preview_manifest.mjs

Node 20 script invoked by `.github/workflows/preview-manifest.yml` to keep `docs/preview-urls.json` in sync with open PRs. It lives next to other automation scripts even though it is JavaScript, not Python.
