# Pairing API Contracts

Source: `shared/contracts/openapi/happyword-api.openapi.json`

## Endpoints

| Method | Path | Contract notes |
| --- | --- | --- |
| POST | `/api/v1/family/{family_id}/pair/create` | Parent creates a pair token and short code (cookie session). |
| GET | `/api/v1/family/{family_id}/pair/status/{token}` | Parent polls pair token status (cookie session). |
| DELETE | `/api/v1/family/{family_id}/pair/{token}` | Parent cancels a pair token (cookie session). |
| POST | `/api/v1/public/pair/redeem` | Child device redeems token or 6-digit short code (no auth). |
| GET | `/p/{token_short}` | Public landing page for QR / short-code pairing. Documentation-only for API clients. |

## Native Client Priority

HarmonyOS already supports QR, gallery QR, and manual short-code entry. iOS and Android should implement manual short-code first, then QR scanning.
