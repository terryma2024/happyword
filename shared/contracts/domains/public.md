# Public API Contracts

Source: `shared/contracts/openapi/happyword-api.openapi.json`

## Endpoints

| Method | Path | Contract notes |
| --- | --- | --- |
| GET | `/api/v1/health` | Public health check. Namespaced path only; `/health` is not valid. |
| GET | `/api/v1/preview-urls.json` | Preview manifest consumed by debug DevMenu. |
| GET | `/api/v1/packs/latest.json` | Legacy/latest public pack JSON. Supports `If-None-Match`; returns `ETag`. |
| GET | `/api/v1/public/global-packs/latest.json` | Current global pack feed. Supports `If-None-Match`; returns 200, 204, or 304. |
| HEAD | `/api/v1/public/global-packs/latest.json` | ETag-only global pack revalidation. |

## Native Client Priority

HarmonyOS already consumes preview manifest, legacy pack cache, and global packs. iOS and Android should implement global pack sync before legacy pack sync unless they need V0.5 compatibility.
