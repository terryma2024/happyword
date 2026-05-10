# WordMagicGame Shared Contracts

`shared/contracts/` is the cross-platform contract home for HarmonyOS, iOS, Android, and the FastAPI server.

## What Belongs Here

- Generated OpenAPI snapshots for JSON APIs.
- Human-readable domain indexes for app-facing and admin-facing API groups.
- Protocol notes for sync flows that need more detail than an endpoint list.
- Error envelope and error-code documentation.
- Links to golden fixtures under `shared/fixtures/`.

## What Does Not Belong Here

- Shared client runtime code.
- Generated Swift, Kotlin, ArkTS, or Python clients.
- UI components or business logic imported by native clients.
- Server implementation code.

## Source of Truth

The server source of truth is `server/app/main.py` plus the included routers and Pydantic schemas.

Generated files:

- `openapi/happyword-api.openapi.json`
- `openapi/happyword-api.paths.txt`
- `openapi/happyword-api.sha256`

Regenerate after server API changes:

```bash
cd server && uv run python ../tools/contracts/export_openapi.py
```

Check contract freshness:

```bash
cd server && uv run python ../tools/contracts/check_contracts.py
cd server && uv run pytest tests/test_shared_contracts.py -q
```

## Domain Indexes

- `domains/public.md`: public app resources and unauthenticated endpoints.
- `domains/child-device.md`: child device endpoints authenticated by device token.
- `domains/pairing.md`: parent-to-child device pairing.
- `domains/parent.md`: parent account, family, wishlist, inbox, and child report APIs.
- `domains/admin-content.md`: content/admin APIs.
- `domains/web-routes.md`: HTML parent web routes; documentation-only for native clients.
