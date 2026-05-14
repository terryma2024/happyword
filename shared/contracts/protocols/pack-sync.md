# Pack Sync Protocol

## Layers

| Layer | Endpoint | Auth | Cache key idea |
| --- | --- | --- | --- |
| built-in | shipped app asset | none | app bundle version |
| global | `GET /api/v1/public/global-packs/latest.json` | anonymous | ETag + fetchedAt |
| family | `GET /api/v1/family/{family_id}/family-packs/latest.json` | device token | ETag + fetchedAt |
| merged (optional) | `GET /api/v1/family/{family_id}/packs/latest.json` | device token | ETag + fetchedAt |

## Status Handling

| HTTP status | Meaning | Client action |
| --- | --- | --- |
| 200 | New payload available | Replace cached layer and record `ETag`. |
| 204 | No packs published for this layer | Clear cached layer for the requesting context. |
| 304 | Cache still current | Keep cached layer. |
| 401 / 403 | Device auth invalid | Keep local playable fallback; surface binding problem in parent/account UI. |
| 410 | Binding or token gone | Clear cloud credentials after user confirmation or server-directed unbind flow. |
| 5xx / network | Temporary failure | Keep cached layer and built-in fallback. |

## Merge Semantics

Client effective library is `family > global > built-in` by `pack_id`. `shared/` must not provide a runtime merge implementation; native clients implement the merge and verify against fixtures.
