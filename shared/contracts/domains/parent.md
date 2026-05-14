# Parent API Contracts

Source: `shared/contracts/openapi/happyword-api.openapi.json`

All JSON routes are mounted under `/api/v1/family/{family_id}/**`. The `family_id` path segment is decorative for now (the session still scopes data), but callers must keep it in sync with the parent web shell (`/family/{family_id}/**`) and native clients should use the real family id when known.

## Auth and Account

| Method | Path |
| --- | --- |
| POST | `/api/v1/family/{family_id}/auth/request-code` |
| POST | `/api/v1/family/{family_id}/auth/verify-code` |
| POST | `/api/v1/family/{family_id}/auth/logout` |
| GET | `/api/v1/family/{family_id}/me` |
| GET | `/api/v1/family/{family_id}/account/status` |
| POST | `/api/v1/family/{family_id}/account/delete` |
| POST | `/api/v1/family/{family_id}/account/cancel-delete` |
| POST | `/api/v1/family/{family_id}/account/export` |

## Family, Devices, Reports, Wishlist

| Method | Path |
| --- | --- |
| GET | `/api/v1/family/{family_id}/devices` |
| GET | `/api/v1/family/{family_id}/children` |
| PUT | `/api/v1/family/{family_id}/children/{profile_id}` |
| DELETE | `/api/v1/family/{family_id}/children/{profile_id}` |
| GET | `/api/v1/family/{family_id}/children/{profile_id}/report` |
| GET | `/api/v1/family/{family_id}/children/{profile_id}/wishlist` |
| POST | `/api/v1/family/{family_id}/wishlist-items/{item_id}` |
| PUT | `/api/v1/family/{family_id}/wishlist-items/{item_id}` |
| DELETE | `/api/v1/family/{family_id}/wishlist-items/{item_id}` |
| GET | `/api/v1/family/{family_id}/redemption-requests` |
| POST | `/api/v1/family/{family_id}/redemption-requests/{request_id}/approve` |
| POST | `/api/v1/family/{family_id}/redemption-requests/{request_id}/reject` |
| GET | `/api/v1/family/{family_id}/inbox` |
| POST | `/api/v1/family/{family_id}/inbox/{msg_id}/read` |
| POST | `/api/v1/family/{family_id}/inbox/mark-all-read` |

## Family Pack Workbench

| Method | Path |
| --- | --- |
| GET | `/api/v1/family/{family_id}/family-packs` |
| POST | `/api/v1/family/{family_id}/family-packs` |
| GET | `/api/v1/family/{family_id}/family-packs/{pack_id}` |
| PATCH | `/api/v1/family/{family_id}/family-packs/{pack_id}` |
| POST | `/api/v1/family/{family_id}/family-packs/{pack_id}/archive` |
| POST | `/api/v1/family/{family_id}/family-packs/{pack_id}/unarchive` |
| GET | `/api/v1/family/{family_id}/family-packs/{pack_id}/draft` |
| PUT | `/api/v1/family/{family_id}/family-packs/{pack_id}/draft/words/{word_id}` |
| DELETE | `/api/v1/family/{family_id}/family-packs/{pack_id}/draft/words/{word_id}` |
| POST | `/api/v1/family/{family_id}/family-packs/{pack_id}/draft/words:batch-upsert` |
| POST | `/api/v1/family/{family_id}/family-packs/{pack_id}/import-image` |
| POST | `/api/v1/family/{family_id}/family-packs/{pack_id}/publish` |
| POST | `/api/v1/family/{family_id}/family-packs/{pack_id}/rollback` |
| GET | `/api/v1/family/{family_id}/family-packs/{pack_id}/versions` |

## Lesson photo import (family URL shape)

| Method | Path |
| --- | --- |
| POST | `/api/v1/family/{family_id}/lessons/import` |
| GET | `/api/v1/family/{family_id}/lesson-drafts` |
| GET | `/api/v1/family/{family_id}/lesson-drafts/{draft_id}` |
| PATCH | `/api/v1/family/{family_id}/lesson-drafts/{draft_id}` |
| PUT | `/api/v1/family/{family_id}/lesson-drafts/{draft_id}` |
| POST | `/api/v1/family/{family_id}/lesson-drafts/{draft_id}/approve` |
| POST | `/api/v1/family/{family_id}/lesson-drafts/{draft_id}/reject` |
