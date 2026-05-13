# Parity Checklist

| Capability | HarmonyOS | iOS | Android |
| --- | --- | --- | --- |
| Preview manifest uses `branch_url` for active routing | [x] | [x] | [x] |
| Deployment URL/id/SHA preserved for analysis | [x] | [x] | [x] |
| Debug session id can be entered in debug UI | [x] | [x] | [x] |
| `x-hw-debug-session` sent only for Preview | [x] | [x] | [x] |
| Vercel bypass header sent only for Preview | [x] | [x] | [x] |
| Request/response summary log marker | [x] `HW_NET_DEBUG` | [x] `HW_NET_DEBUG` | [x] `HW_NET_DEBUG` |
| Release UI hides debug controls | [x] DevMenu debug-only path | [x] `#if DEBUG` | [x] debug route only |
| Unit tests cover routing/header/manifest semantics | [ ] | [x] | [x] |

## Remaining Manual Checks

- [ ] Correlate one real HarmonyOS debug session with server traces.
- [ ] Correlate one real iOS debug session with server traces.
- [ ] Correlate one real Android debug session with server traces.
- [ ] Confirm Vercel branch URL health validation in the deployment workflow.
