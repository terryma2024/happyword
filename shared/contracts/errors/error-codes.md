# Error Codes

This file is curated from router helpers and tests. When adding a new structured error, update this file in the same change.

## Current Code Families

| Code family | HTTP status | Owner |
| --- | --- | --- |
| `*_NOT_FOUND` | 404 | words, categories, packs, drafts, devices, redemptions |
| `*_CONFLICT` | 409 | duplicate words, already bound/redeemed/reviewed flows |
| `*_INVALID` | 400 or 422 | malformed request or domain validation failure |
| `*_UNAUTHORIZED` | 401 or 403 | auth, device token, parent session |
| `*_GONE` | 410 | expired pair tokens, removed bindings, expired auth codes |
| `LLM_*` | 502 or 503 | OpenAI/LLM service failures |
| `ASSET_*` | 400, 404, 415, 413 | illustration/audio upload and deletion |

## Required Follow-Up

Task 9 extracts concrete code constants from routers and tests into this table. Until then, this file documents parsing and ownership rules rather than an exhaustive enum.
