# Error Codes

This file is curated from router helpers, service exceptions, and tests. When adding a new structured error, update this file in the same change.

## Current Codes

| Code | HTTP status | Endpoint group | Meaning |
| --- | --- | --- | --- |
| `ALREADY_DECIDED` | 409 | Parent redemptions | Redemption request already has a final decision. |
| `BAD_REQUEST` | 400 | Pairing | Redeem request omitted both token and short code. |
| `BINDING_NOT_FOUND` | 404 | Device auth / parent web | Device binding does not exist. |
| `BINDING_REVOKED` | 404 | Device auth | Device binding exists but has been revoked. |
| `CHILD_NOT_FOUND` | 404 | Child profile / parent children | Child profile is missing or not owned by the caller. |
| `CODE_EXPIRED` | 410 | Parent auth | Verification code expired. |
| `CRON_SECRET_NOT_CONFIGURED` | 503 | Admin cron | Cron secret is not configured. |
| `DRAFT_VALIDATION_FAILED` | 422 | Family packs | Draft rows failed validation before publish (details in payload `rows`). |
| `DUPLICATE_ID` | 409 | Admin words | Word id already exists. |
| `EMPTY_BODY` | 400 | Admin assets / parent family pack import | Uploaded body is empty (image/audio/import). |
| `EMPTY_PACK` | 409 | Family/global packs | Pack publish attempted without publishable words. |
| `EMPTY_UPLOAD` | 400 | Admin LLM | Uploaded image body is empty. |
| `FAMILY_MISMATCH` | 403 | Child word stats | Device is attempting to access a different family. |
| `FAMILY_REQUIRED` | 400 | Family lessons | Lesson import/review requires a real `family_id` path segment (not `_`). |
| `FORBIDDEN` | 403 | Auth dependencies | Authenticated principal lacks the required role. |
| `IMAGE_TOO_LARGE` | 413 | Admin LLM | Uploaded image exceeds configured size limit. |
| `INVALID_CODE` | 403 | Parent auth | Verification code is incorrect. |
| `INVALID_NICKNAME` | 400 | Child profile | Nickname failed domain validation. |
| `INVALID_PAYLOAD` | 400 or 422 | Family/global packs | Pack draft payload failed domain validation. |
| `ITEM_INACTIVE` | 409 | Wishlist | Wishlist item exists but is inactive. |
| `ITEM_NOT_FOUND` | 404 | Wishlist service | Wishlist item does not exist. |
| `LLM_CALL_FAILED` | 502 | Admin LLM | Upstream LLM call failed. |
| `LLM_NOT_CONFIGURED` | 503 | Admin LLM | LLM provider or key is not configured. |
| `LESSON_APPROVE_INVALID` | 422 | Family lessons | Lesson draft approve failed while upserting family-pack rows (see `errors` array). |
| `NAME_TAKEN` | 409 | Family/global packs | Pack name or id conflicts with an existing pack. |
| `NO_PREVIOUS_VERSION` | 409 | Family/global packs | Rollback requested but no previous version exists. |
| `PACK_FULL` | 409 | Family/global packs | Draft pack exceeds the word limit. |
| `PACK_NOT_FOUND` | 404 | Family/global packs | Pack definition or published version does not exist. |
| `PARENT_LOGIN_SUSPENDED` | 403 | Parent auth / deps | Parent account login is suspended by an administrator; OTP session invalid. |
| `PAIR_FAILED` | 400 | Pairing | Pair service rejected redeem operation. |
| `PROFILE_NOT_FOUND` | 404 | Wishlist service | Child profile does not exist for wishlist operation. |
| `RATE_LIMITED` | 429 | Pairing | Too many pair-token create requests. |
| `REDEMPTION_NOT_FOUND` | 404 | Parent redemptions | Redemption request does not exist. |
| `REQUEST_NOT_FOUND` | 404 | Redemption service | Redemption request does not exist. |
| `ROLE_MISMATCH` | 403 | Parent auth | Email belongs to a non-parent account. |
| `TENANT_MISMATCH` | 403 | Child family packs | `X-Family-Id` hint does not match the device binding’s family. |
| `TOKEN_EXPIRED` | 410 | Pairing | Pair token expired. |
| `TOKEN_INVALID` | 404 | Pairing | Pair token or short code does not exist. |
| `TOKEN_REDEEMED` | 409 | Pairing | Pair token was already redeemed. |
| `TOO_MANY_ATTEMPTS` | 410 | Parent auth | Verification code was locked after too many failed attempts. |
| `UNAUTHORIZED` | 401 | Auth dependencies | Missing or invalid token/session. |
| `UNSUPPORTED_MEDIA_TYPE` | 415 | Admin LLM | Uploaded file type is unsupported. |
| `USER_NOT_FOUND` | 404 | Account deletion | Parent account no longer exists. |
| `WISHLIST_ITEM_NOT_FOUND` | 404 | Wishlist / redemptions | Wishlist item does not exist or is not visible. |
| `WORD_LIMIT_EXCEEDED` | 409 | Family/global packs | Draft pack would exceed allowed word count. |
| `WORD_NOT_FOUND` | 404 | Admin words | Requested word does not exist or is deleted. |

Native clients should treat unknown codes as displayable server errors and log the raw code for diagnostics.
