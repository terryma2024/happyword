# Parent Web Routes

These routes are HTML routes served by FastAPI templates. They are not native-client JSON contracts, but they are kept here so monorepo route ownership is visible.

`{family_id}` is a path segment. Pre-login HTML entry is **`GET /family/login`** (canonical). `GET /family/{family_id}/login` (including `/family/_/login`) **308-redirects** to `/family/login` for bookmarks. Pre-login **forms** still post to `/family/_/auth/*` with decorative `_` until a session exists; after login, routes use the real Mongo `family_id`.

| Method | Path |
| --- | --- |
| GET | `/family/login` |
| GET | `/family/{family_id}/login` → `308` `/family/login` |
| GET | `/family/{family_id}/verify` |
| POST | `/family/{family_id}/auth/request-code` |
| POST | `/family/{family_id}/auth/verify-code` |
| POST | `/family/{family_id}/auth/logout` |
| GET | `/family/{family_id}/` |
| GET | `/family/{family_id}/redemptions` |
| POST | `/family/{family_id}/redemptions/{request_id}/approve` |
| POST | `/family/{family_id}/redemptions/{request_id}/reject` |
| GET | `/family/{family_id}/devices/add` |
| GET | `/family/{family_id}/devices/add/status` |
| POST | `/family/{family_id}/devices/add/cancel` |
| GET | `/family/{family_id}/devices/{binding_id}` |
| GET | `/family/{family_id}/inbox` |
| GET | `/family/{family_id}/account` |
| POST | `/family/{family_id}/account/delete` |
| POST | `/family/{family_id}/account/cancel-delete` |
| GET | `/family/{family_id}/packs` |
| GET | `/family/{family_id}/packs/{pack_id}` |
