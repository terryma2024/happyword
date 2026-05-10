# Parent Web Routes

These routes are HTML routes served by FastAPI templates. They are not native-client JSON contracts, but they are kept here so monorepo route ownership is visible.

| Method | Path |
| --- | --- |
| GET | `/parent/login` |
| GET | `/parent/verify` |
| POST | `/parent/auth/request-code` |
| POST | `/parent/auth/verify-code` |
| POST | `/parent/auth/logout` |
| GET | `/parent/` |
| GET | `/parent` |
| GET | `/parent/redemptions` |
| POST | `/parent/redemptions/{request_id}/approve` |
| POST | `/parent/redemptions/{request_id}/reject` |
| GET | `/parent/devices/add` |
| GET | `/parent/devices/add/status` |
| POST | `/parent/devices/add/cancel` |
| GET | `/parent/devices/{binding_id}` |
| GET | `/parent/inbox` |
| GET | `/parent/account` |
| POST | `/parent/account/delete` |
| POST | `/parent/account/cancel-delete` |
