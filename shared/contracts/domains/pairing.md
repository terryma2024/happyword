# Pairing API Contracts

Source: `shared/contracts/openapi/happyword-api.openapi.json`

## Endpoints

| Method | Path | Contract notes |
| --- | --- | --- |
| POST | `/api/v1/parent/pair/create` | Parent creates a pair token and short code. |
| GET | `/api/v1/parent/pair/status/{token}` | Parent polls pair token status. |
| DELETE | `/api/v1/parent/pair/{token}` | Parent cancels a pair token. |
| POST | `/api/v1/pair/redeem` | Child device redeems token or 6-digit short code. |
| GET | `/p/{token_short}` | Public landing page for QR / short-code pairing. Documentation-only for API clients. |

## Native Client Priority

HarmonyOS already supports QR, gallery QR, and manual short-code entry. iOS and Android should implement manual short-code first, then QR scanning.
