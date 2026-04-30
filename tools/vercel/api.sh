#!/usr/bin/env bash
# tools/vercel/api.sh
#
# Sourced helper library for Vercel REST API calls.
#
# Many Vercel CLI subcommands either don't expose what we need
# (`vercel inspect` won't show errorMessage on a failed deploy)
# or hang interactively (`vercel logs` follows by default and
# rarely terminates on its own). Calling the REST API directly
# is faster and scriptable.
#
# Functions exported (use via `source tools/vercel/api.sh`):
#
#   vercel_token              -> echo the bearer token from CLI auth.json
#   vercel_proj_id            -> echo projectId from .vercel/project.json
#   vercel_team_id            -> echo orgId from .vercel/project.json
#   vercel_api <method> <path-with-leading-slash> [json-body]
#                             -> authenticated curl, prints JSON body
#                                Automatically appends teamId query param.
#
# Requirements: jq, curl, an interactive `vercel login` session.
# Caller must `cd` into a directory that contains .vercel/project.json
# (typically `server/`) before using vercel_proj_id / vercel_team_id /
# vercel_api.

set -u

_VERCEL_AUTH_FILE_DEFAULT="$HOME/Library/Application Support/com.vercel.cli/auth.json"
VERCEL_AUTH_FILE="${VERCEL_AUTH_FILE:-$_VERCEL_AUTH_FILE_DEFAULT}"

vercel_token() {
    if [[ ! -f "$VERCEL_AUTH_FILE" ]]; then
        echo "vercel_token: cannot find $VERCEL_AUTH_FILE — run 'vercel login' first" >&2
        return 1
    fi
    jq -er .token "$VERCEL_AUTH_FILE"
}

_vercel_project_json() {
    if [[ ! -f .vercel/project.json ]]; then
        echo "vercel api helper: no .vercel/project.json in $(pwd) — run 'vercel link' from the deploy directory first" >&2
        return 1
    fi
    cat .vercel/project.json
}

vercel_proj_id() {
    _vercel_project_json | jq -er .projectId
}

vercel_team_id() {
    _vercel_project_json | jq -er .orgId
}

# Authenticated curl wrapper. Prepends https://api.vercel.com,
# attaches Bearer token, appends teamId query param.
#
# Usage: vercel_api GET   /v9/projects/<pid>
#        vercel_api PATCH /v9/projects/<pid> '{"rootDirectory":null}'
vercel_api() {
    local method="${1:-}"
    local path="${2:-}"
    local body="${3:-}"
    if [[ -z "$method" || -z "$path" ]]; then
        echo "usage: vercel_api <method> <path> [body]" >&2
        return 2
    fi

    local token team sep
    token="$(vercel_token)" || return $?
    team="$(vercel_team_id)" || return $?

    sep='?'
    [[ "$path" == *'?'* ]] && sep='&'

    local url="https://api.vercel.com${path}${sep}teamId=${team}"

    if [[ -n "$body" ]]; then
        curl -sS -X "$method" "$url" \
            -H "Authorization: Bearer $token" \
            -H 'Content-Type: application/json' \
            -d "$body"
    else
        curl -sS -X "$method" "$url" \
            -H "Authorization: Bearer $token"
    fi
}
