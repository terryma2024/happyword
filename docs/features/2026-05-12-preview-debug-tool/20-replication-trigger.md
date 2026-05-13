# Replication Trigger

## Harmony Stabilization Gate

- [ ] Preview manifest resolves `branch_url` and keeps `deployment_url`.
- [ ] Debug session id persists in DevMenu.
- [ ] Preview requests include `x-hw-debug-session` only in Preview mode.
- [ ] `HW_NET_DEBUG` logs are visible during manual reproduction.
- [ ] Server trace and client log can be correlated by session id and correlation id.
- [ ] Harmony tests/build/linter pass with `0` `ArkTS:WARN`.

## Delta Letter

Replicate the same semantics on iOS and Android:

- Preview branch URL is the default endpoint.
- Deployment URL is preserved only for analysis.
- Bypass and debug headers are sent only in Preview.
- Debug UI is debug-only and absent from release.
- Network logs are summaries only and do not expose secrets.

## Human Approval

replication_approved: false
approved_by:
approved_at:
