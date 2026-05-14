# Word Stats Sync Protocol

Endpoint: `POST /api/v1/family/{family_id}/word-stats/sync`

The child device sends local `WordStatItem[]` plus `synced_through_ms`. The server accepts stats for the bound family/device context and returns accepted remote state.

Client rules:

- Keep local stats playable offline.
- Sync is additive/last-write-aware at the server service layer.
- Do not block battle completion on sync failure.
- Retry later when network returns.

Schema source: `components.schemas.WordStatsSyncIn`, `WordStatsSyncOut`, `WordStatsListOut` in `../openapi/happyword-api.openapi.json`.
