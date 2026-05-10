# Admin Content API Contracts

Source: `shared/contracts/openapi/happyword-api.openapi.json`

## Endpoint Groups

| Group | Paths |
| --- | --- |
| Admin auth | `/api/v1/auth/login`, `/api/v1/auth/me` |
| Words | `/api/v1/admin/words`, `/api/v1/admin/words/{word_id}`, `/api/v1/admin/words/{word_id}/illustration`, `/api/v1/admin/words/{word_id}/audio` |
| Legacy packs | `/api/v1/admin/packs`, `/api/v1/admin/packs/current`, `/api/v1/admin/packs/{version}`, `/api/v1/admin/packs/publish`, `/api/v1/admin/packs/rollback` |
| Categories | `/api/v1/admin/categories`, `/api/v1/admin/categories/{category_id}` |
| LLM drafts | `/api/v1/admin/llm/scan-words`, `/api/v1/admin/words/{word_id}/generate-distractors`, `/api/v1/admin/words/{word_id}/generate-example`, `/api/v1/admin/drafts/**` |
| Lesson import | `/api/v1/admin/lessons/import`, `/api/v1/admin/lesson-drafts/**` |
| Global packs | `/api/v1/admin/global-packs/**` |
| Stats and cron | `/api/v1/admin/stats`, `/api/v1/admin/cron/extract-pending` |

## Native Client Priority

These contracts are not required for child native clients. They are required for server tests, admin web, future operations tooling, and regression checks.
