# Child Device API Contracts

Source: `shared/contracts/openapi/happyword-api.openapi.json`

## Endpoints

| Method | Path | Contract notes |
| --- | --- | --- |
| PUT | `/api/v1/child/profile` | Upsert child self profile for the bound device. |
| GET | `/api/v1/child/family-packs/latest.json` | Device-token authenticated family pack feed. Supports 200, 204, 304 and `ETag`. |
| HEAD | `/api/v1/child/family-packs/latest.json` | ETag-only family pack revalidation. |
| POST | `/api/v1/child/word-stats/sync` | Push local word stat deltas and receive server accepted state. |
| GET | `/api/v1/child/word-stats` | Pull current word stats for the bound device/family context. |
| GET | `/api/v1/child/wishlist` | Pull cloud wishlist visible to child device. |
| POST | `/api/v1/child/wishlist/sync-custom` | Sync child-created custom wish items. |
| POST | `/api/v1/child/redemption-requests` | Child requests wish redemption. |
| GET | `/api/v1/child/redemption-requests` | Child lists own redemption requests. |
| GET | `/api/v1/child/redemption-requests/poll` | Child polls redemption status. |
| POST | `/api/v1/child/unbind` | Bound device unbind flow. |

## Tenant Boundary

Native clients may carry family context for UX, but authorization must come from `device_token -> DeviceBinding -> family_id` on the server. Do not trust a client-submitted `family_id` as the authorization boundary.
