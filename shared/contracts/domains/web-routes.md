# Parent Web Routes

These routes are HTML routes served by FastAPI templates. They are not native-client JSON contracts, but they are kept here so monorepo route ownership is visible.

`{family_id}` is a path segment. Pre-login pages use the decorative `_` placeholder (for example `/family/_/login` from the apex redirect); after login, routes use the real Mongo `family_id`.

| Method | Path |
| --- | --- |
| GET | `/family/{family_id}/login` |
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
