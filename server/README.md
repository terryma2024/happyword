# happyword-server

Content backend for WordMagicGame. See [V0.5 design spec](../docs/superpowers/specs/2026-04-30-v0.5-content-backend-design.md).

## Local dev

```bash
cd server
uv sync
cp .env.local.example .env.local      # then fill in MONGODB_URI etc
uv run uvicorn app.main:app --reload --port 8000
```

The HarmonyOS emulator reaches the host machine at `http://10.0.2.2:8000` —
this is the default for the client's debug build (see
`entry/src/main/ets/services/RemoteWordPackConfig.ets`).

## Tests

```bash
uv run pytest -v
uv run ruff check .
uv run ruff format --check .
uv run mypy app
```

All tests run offline — Mongo is mocked by `mongomock-motor`, HTTP by injected `HttpRequester` stubs on the client side.

## Deploy

See [V0.5 spec §9](../docs/superpowers/specs/2026-04-30-v0.5-content-backend-design.md#9-vercel-部署拓扑).

```bash
cd server
vercel link
vercel env add MONGODB_URI     # or use the Marketplace integration which injects it; repeat for the rest in §9.3
vercel --prod
```
