# WordMagicGame Shared Contracts

`shared/` contains cross-client contracts and golden fixtures only.

## Contents

- `contracts/`: OpenAPI snapshots, JSON schemas, error-code docs, and sync protocol docs.
- `fixtures/`: golden payloads used by HarmonyOS, iOS, Android, and server tests.

## Rules

- Do not put shared client runtime code here.
- Do not introduce a cross-platform UI or business-logic framework here.
- Native clients implement their own platform code and verify behavior against these contracts and fixtures.

## Contract Update Checklist

When adding or changing a server API:

1. Update or add server tests for the API behavior.
2. Run `cd server && uv run python ../tools/contracts/export_openapi.py`.
3. Update the relevant `shared/contracts/domains/*.md` file.
4. Update protocol docs if the change affects sync, auth, or caching.
5. Add or update golden fixtures when native clients need an example payload.
6. Run `cd server && uv run pytest tests/test_shared_contracts.py -q`.
7. If `server/` changed, run `cd server && uv run pytest` before committing.
