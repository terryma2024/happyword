# WordMagicGame Shared Contracts

`shared/` contains cross-client contracts and golden fixtures only.

## Contents

- `contracts/`: OpenAPI snapshots, JSON schemas, error-code docs, and sync protocol docs.
- `fixtures/`: golden payloads used by HarmonyOS, iOS, Android, and server tests.

## Rules

- Do not put shared client runtime code here.
- Do not introduce a cross-platform UI or business-logic framework here.
- Native clients implement their own platform code and verify behavior against these contracts and fixtures.
