# Check-ins Sync Protocol

Endpoint: `POST /api/v1/family/{family_id}/checkins/sync`

The child device sends local checked day keys, weekly-bonus day keys, and coin transactions. The server stores each day and transaction idempotently for the bound child profile and returns the merged cloud view.

Client rules:

- Keep check-ins and coin rewards playable offline.
- Sync only when the device is bound.
- Do not block battle completion on sync failure.
- Retry later when network returns.
- Treat `checked_day_keys` as a set.
- Treat `coin_txns[].txn_id` as the idempotency key for cloud coin transactions.

Schema source: `components.schemas.CheckInSyncIn`, `CheckInSyncOut`, and `CheckInListOut` in `../openapi/happyword-api.openapi.json`.
