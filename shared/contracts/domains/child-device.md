# Child Device API Contracts

Source: `shared/contracts/openapi/happyword-api.openapi.json`

All routes are mounted under `/api/v1/family/{family_id}/**` and authenticated with the device Bearer token (`current_device_binding`). The path `family_id` is decorative today but must match the binding's family in future hardening; clients should send the real id from binding context.

## Endpoints

| Method | Path | Contract notes |
| --- | --- | --- |
| PUT | `/api/v1/family/{family_id}/profile` | Upsert child self profile for the bound device. |
| GET | `/api/v1/family/{family_id}/family-packs/latest.json` | Device-token authenticated family pack feed. Supports 200, 204, 304 and `ETag`. |
| HEAD | `/api/v1/family/{family_id}/family-packs/latest.json` | ETag-only family pack revalidation. |
| GET | `/api/v1/family/{family_id}/packs/latest.json` | Merged global + family pack feed (`ChildPacksMergedOut`). Supports optional `X-Family-Id` tenant guard. |
| HEAD | `/api/v1/family/{family_id}/packs/latest.json` | ETag-only merged pack revalidation. |
| POST | `/api/v1/family/{family_id}/word-stats/sync` | Push local word stat deltas and receive server accepted state. |
| GET | `/api/v1/family/{family_id}/word-stats` | Pull current word stats for the bound device/family context. |
| GET | `/api/v1/family/{family_id}/wishlist` | Pull cloud wishlist visible to child device. |
| POST | `/api/v1/family/{family_id}/wishlist/sync-custom` | Sync child-created custom wish items. |
| POST | `/api/v1/family/{family_id}/redemption-requests` | Child requests wish redemption. |
| GET | `/api/v1/family/{family_id}/redemption-requests` | Child lists own redemption requests. |
| GET | `/api/v1/family/{family_id}/redemption-requests/poll` | Child polls redemption status. |
| POST | `/api/v1/family/{family_id}/unbind` | Bound device unbind flow. |

## Tenant Boundary

Native clients may carry family context for UX, but authorization must come from `device_token -> DeviceBinding -> family_id` on the server. Do not trust a client-submitted `family_id` as the sole authorization boundary.
