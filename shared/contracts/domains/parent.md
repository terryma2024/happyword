# Parent API Contracts

Source: `shared/contracts/openapi/happyword-api.openapi.json`

## Auth and Account

| Method | Path |
| --- | --- |
| POST | `/api/v1/parent/auth/request-code` |
| POST | `/api/v1/parent/auth/verify-code` |
| POST | `/api/v1/parent/auth/logout` |
| GET | `/api/v1/parent/me` |
| GET | `/api/v1/parent/account/status` |
| POST | `/api/v1/parent/account/delete` |
| POST | `/api/v1/parent/account/cancel-delete` |
| POST | `/api/v1/parent/account/export` |

## Family, Devices, Reports, Wishlist

| Method | Path |
| --- | --- |
| GET | `/api/v1/parent/devices` |
| GET | `/api/v1/parent/children` |
| PUT | `/api/v1/parent/children/{profile_id}` |
| DELETE | `/api/v1/parent/children/{profile_id}` |
| GET | `/api/v1/parent/children/{profile_id}/report` |
| GET | `/api/v1/parent/children/{profile_id}/wishlist` |
| POST | `/api/v1/parent/wishlist-items/{item_id}` |
| PUT | `/api/v1/parent/wishlist-items/{item_id}` |
| DELETE | `/api/v1/parent/wishlist-items/{item_id}` |
| GET | `/api/v1/parent/redemption-requests` |
| POST | `/api/v1/parent/redemption-requests/{request_id}/approve` |
| POST | `/api/v1/parent/redemption-requests/{request_id}/reject` |
| GET | `/api/v1/parent/inbox` |
| POST | `/api/v1/parent/inbox/{msg_id}/read` |
| POST | `/api/v1/parent/inbox/mark-all-read` |

## Family Pack Workbench

| Method | Path |
| --- | --- |
| GET | `/api/v1/parent/family-packs` |
| POST | `/api/v1/parent/family-packs` |
| GET | `/api/v1/parent/family-packs/{pack_id}` |
| PATCH | `/api/v1/parent/family-packs/{pack_id}` |
| POST | `/api/v1/parent/family-packs/{pack_id}/archive` |
| POST | `/api/v1/parent/family-packs/{pack_id}/unarchive` |
| GET | `/api/v1/parent/family-packs/{pack_id}/draft` |
| PUT | `/api/v1/parent/family-packs/{pack_id}/draft/words/{word_id}` |
| DELETE | `/api/v1/parent/family-packs/{pack_id}/draft/words/{word_id}` |
| POST | `/api/v1/parent/family-packs/{pack_id}/publish` |
| POST | `/api/v1/parent/family-packs/{pack_id}/rollback` |
| GET | `/api/v1/parent/family-packs/{pack_id}/versions` |
