# Parent web password login — design spec

- **Date:** 2026-05-17
- **Status:** Approved (inline implementation)
- **Scope:** Server parent web shell (`/family/login`, `/family/{family_id}/account`)

## Decisions

| Topic | Decision |
| --- | --- |
| Login UI | Password login block after OAuth buttons (last option) |
| Set password | Requires fresh OTP to bound email (even right after OTP registration) |
| Change password | Old password + new password |
| Forgot password | No dedicated page; OTP/OAuth login then reset via set-password flow |
| Unregistered email + password login | Explicit confirm → OTP register; password from login form discarded |
| Enumeration | Accept explicit `EMAIL_NOT_REGISTERED` on password login |
| Password policy | ≥ 8 characters |
| Lockout | Per-email failed password attempts; reuse `otp_max_attempts` (5); lock 15 min |

## Routes

### JSON

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/api/v1/family/_/auth/password-login` | Pre-login password login |
| POST | `/api/v1/family/{family_id}/account/password/request-otp` | Send OTP to session user's email (set/reset) |
| POST | `/api/v1/family/{family_id}/account/password/set` | Set/reset password (OTP + new password) |
| POST | `/api/v1/family/{family_id}/account/password/change` | Change password (old + new) |

### HTML

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/family/_/auth/password-login` | Form password login |
| POST | `/family/{family_id}/account/password/request-otp` | Send OTP from settings |
| POST | `/family/{family_id}/account/password/set` | Set/reset from settings |
| POST | `/family/{family_id}/account/password/change` | Change from settings |

## Data model

`User.password_failed_attempts: int = 0`, `User.password_locked_until: datetime | None = None`; reuse `password_hash`.
