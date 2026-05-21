#!/usr/bin/env bash
set -euo pipefail

DEFAULT_STAGING_BASE_URL="https://happyword-server-staging-255236-5-1429584068.sh.run.tcloudbase.com"
DEFAULT_PROD_BASE_URL="https://happyword-server-255236-5-1429584068.sh.run.tcloudbase.com"

STAGING_BASE_URL="${CLOUDBASE_STAGING_BASE_URL:-$DEFAULT_STAGING_BASE_URL}"
PROD_BASE_URL="${CLOUDBASE_PROD_BASE_URL:-$DEFAULT_PROD_BASE_URL}"
EXPECT_PREVIEW_TITLE="${CLOUDBASE_EXPECT_PREVIEW_TITLE:-}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

trim_trailing_slash() {
  printf '%s' "${1%/}"
}

fetch() {
  local label="$1"
  local base_url="$2"
  local path="$3"
  local output="$4"

  local url
  url="$(trim_trailing_slash "$base_url")$path"
  local status
  status="$(curl -fsS -o "$output" -w '%{http_code} %{time_total}' "$url")"
  printf '%-18s %-36s %s\n' "$label" "$path" "$status"
}

check_preview_title() {
  local label="$1"
  local manifest_path="$2"

  node - "$manifest_path" "$EXPECT_PREVIEW_TITLE" "$label" <<'NODE'
const fs = require("fs");

const [manifestPath, expectedTitle, label] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const previews = Array.isArray(manifest.previews) ? manifest.previews : [];
if (!expectedTitle) {
  const titles = previews.map((row) => row && row.title).filter(Boolean);
  console.log(`${label} preview rows: ${titles.length}${titles[0] ? `; first=${titles[0]}` : ""}`);
  process.exit(0);
}
if (!previews.some((row) => row && row.title === expectedTitle)) {
  console.error(`${label} preview manifest is missing title: ${expectedTitle}`);
  process.exit(1);
}
console.log(`${label} preview manifest contains title: ${expectedTitle}`);
NODE
}

smoke_base() {
  local label="$1"
  local base_url="$2"
  local prefix="$WORK_DIR/$label"

  echo "== $label: $(trim_trailing_slash "$base_url") =="
  fetch "$label" "$base_url" "/api/v1/public/health" "$prefix-health.json"
  fetch "$label" "$base_url" "/api/v1/public/packs/latest.json" "$prefix-packs.json"
  fetch "$label" "$base_url" "/privacy" "$prefix-privacy.html"
  fetch "$label" "$base_url" "/admin/login" "$prefix-admin.html"
  fetch "$label" "$base_url" "/family/login" "$prefix-family.html"
  fetch "$label" "$base_url" "/api/v1/public/preview-urls.json" "$prefix-preview.json"
  check_preview_title "$label" "$prefix-preview.json"
}

smoke_base "staging" "$STAGING_BASE_URL"
smoke_base "production" "$PROD_BASE_URL"
