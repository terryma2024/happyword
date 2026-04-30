#!/usr/bin/env bash
# tools/vercel/env-bootstrap.sh
#
# Idempotently push the V0.5 server's required environment variables
# into the linked Vercel project for the chosen target (production by
# default). Safe to re-run: env vars that already exist are skipped.
#
# What this script DOES NOT manage:
#   - MONGODB_URI         (auto-injected by the Marketplace MongoDB
#                          Atlas integration)
#   - OPENAI_API_KEY      (manual once via 'vercel env add' — you
#                          may want to type the key live, not pipe
#                          it via shell history)
#   - BLOB_READ_WRITE_TOKEN (auto-injected by Vercel Blob)
#
# What it DOES manage (the deterministic + secret values we need):
#   - MONGO_DB_NAME            'happyword'
#   - JWT_EXPIRE_HOURS         '24'
#   - ADMIN_BOOTSTRAP_USER     'admin'
#   - CORS_ALLOW_ORIGINS       '*'
#   - LOG_LEVEL                'info'
#   - JWT_SECRET               openssl rand -hex 32       (saved to
#                              /tmp/jwt_secret.txt for retrieval)
#   - ADMIN_BOOTSTRAP_PASS     openssl rand -base64 24 trimmed to
#                              32 alnum chars (saved to
#                              /tmp/admin_pass.txt mode 600 for
#                              one-shot retrieval, then YOU should
#                              copy to a password manager and rm it)
#
# Usage (from repo root, with `vercel link` already done in server/):
#   bash tools/vercel/env-bootstrap.sh                     # production
#   bash tools/vercel/env-bootstrap.sh preview             # preview scope
#   bash tools/vercel/env-bootstrap.sh production --force  # overwrite all
#
# --force will rm-then-add every key (use only on truly fresh / staging
# projects; this rotates the JWT secret AND the admin password).

set -u

cd "$(dirname "$0")/../.."
REPO_ROOT="$(pwd)"

if [[ ! -f "$REPO_ROOT/server/.vercel/project.json" ]]; then
    echo "env-bootstrap: server/.vercel/project.json missing — run 'cd server && vercel link' first" >&2
    exit 2
fi

TARGET="${1:-production}"
FORCE="${2:-}"
case "$TARGET" in
    production|preview|development) ;;
    *) echo "env-bootstrap: unknown target '$TARGET' (production|preview|development)" >&2; exit 2 ;;
esac

cd "$REPO_ROOT/server"

# Currently-set env keys for this target. The CLI prints a banner +
# a "name value environments created" header row, then one row per
# var. Each var row starts with whitespace + an uppercase identifier.
# Match those specifically so banners / blank lines / hint text at
# the bottom don't pollute the key list.
EXISTING_KEYS="$(vercel env ls "$TARGET" 2>/dev/null \
    | grep -E '^[[:space:]]+[A-Z][A-Z0-9_]*[[:space:]]' \
    | awk '{print $1}' || true)"

# add_env <key> <value>
add_env() {
    local key="$1"
    local value="$2"

    if [[ "$FORCE" == "--force" ]]; then
        # rm is interactive in some CLI versions; pipe a 'y'.
        echo y | vercel env rm "$key" "$TARGET" >/dev/null 2>&1 || true
    elif echo "$EXISTING_KEYS" | grep -qx "$key"; then
        echo "  [skip] $key already set in $TARGET"
        return 0
    fi

    if [[ -z "$value" ]]; then
        echo "  [skip] $key has empty value, refusing to push" >&2
        return 1
    fi

    if echo -n "$value" | vercel env add "$key" "$TARGET" >/dev/null 2>&1; then
        echo "  [add]  $key -> $TARGET"
    else
        echo "  [FAIL] $key -> $TARGET" >&2
        return 1
    fi
}

# Generate secrets only when we actually need to push them.
# Returning the value via stdout, with empty meaning "skip — already
# set in Vercel and we should NOT touch /tmp files (they may be stale
# from another project and pushing them would silently corrupt prod)".
maybe_gen_jwt_secret() {
    if [[ "$FORCE" != "--force" ]] && echo "$EXISTING_KEYS" | grep -qx 'JWT_SECRET'; then
        return 0
    fi
    umask 077
    local secret
    secret="$(openssl rand -hex 32)"
    printf '%s\n' "$secret" > /tmp/jwt_secret.txt
    chmod 600 /tmp/jwt_secret.txt
    echo "[env-bootstrap] generated JWT_SECRET -> /tmp/jwt_secret.txt (64 hex chars)" >&2
    printf '%s' "$secret"
}

maybe_gen_admin_pass() {
    if [[ "$FORCE" != "--force" ]] && echo "$EXISTING_KEYS" | grep -qx 'ADMIN_BOOTSTRAP_PASS'; then
        return 0
    fi
    umask 077
    local pass
    pass="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)"
    printf '%s\n' "$pass" > /tmp/admin_pass.txt
    chmod 600 /tmp/admin_pass.txt
    echo "[env-bootstrap] generated ADMIN_BOOTSTRAP_PASS -> /tmp/admin_pass.txt (32 alnum chars)" >&2
    echo "[env-bootstrap] *** copy /tmp/admin_pass.txt into your password manager NOW," >&2
    echo "[env-bootstrap] *** then 'rm /tmp/admin_pass.txt'." >&2
    printf '%s' "$pass"
}

JWT_SECRET="$(maybe_gen_jwt_secret)"
ADMIN_PASS="$(maybe_gen_admin_pass)"

echo "[env-bootstrap] pushing env vars to target=$TARGET (force=${FORCE:-false})"
add_env MONGO_DB_NAME       'happyword'
add_env JWT_EXPIRE_HOURS    '24'
add_env ADMIN_BOOTSTRAP_USER 'admin'
add_env CORS_ALLOW_ORIGINS  '*'
add_env LOG_LEVEL           'info'

if [[ -n "$JWT_SECRET" ]]; then
    add_env JWT_SECRET "$JWT_SECRET"
else
    echo "  [skip] JWT_SECRET already set in $TARGET (not regenerated)"
fi
if [[ -n "$ADMIN_PASS" ]]; then
    add_env ADMIN_BOOTSTRAP_PASS "$ADMIN_PASS"
else
    echo "  [skip] ADMIN_BOOTSTRAP_PASS already set in $TARGET (not regenerated)"
fi

echo
echo "[env-bootstrap] final state ($TARGET):"
vercel env ls "$TARGET" 2>/dev/null | awk 'NR<=2 || NR>2'
