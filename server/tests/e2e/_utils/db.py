"""Direct MongoDB helpers used only by the E2E test driver.

These helpers connect via ``E2E_MONGODB_URI`` / ``E2E_MONGO_DB_NAME`` —
deliberately *not* the application's ``MONGODB_URI``. The deployment
itself never reads E2E_*, so production code paths stay untouched.
"""

from __future__ import annotations

import bcrypt
from motor.motor_asyncio import AsyncIOMotorDatabase

MongoDB = AsyncIOMotorDatabase[dict[str, object]]


async def inject_otp_code(
    db: MongoDB,
    *,
    email: str,
    plain_code: str = "123456",
) -> None:
    """Replace the latest pending OTP row's ``code_hash`` with ``bcrypt(plain_code)``.

    The deployment generates a real CSPRNG code on ``request-code`` but we
    never receive it (SMTP is intentionally unconfigured in E2E). Rather
    than adding a backdoor endpoint, we mutate the bcrypt hash here so the
    test can verify with a known plaintext.

    Raises:
        AssertionError: if no pending row exists for ``email``.
    """
    row = await db["email_verifications"].find_one(
        {"email": email}, sort=[("created_at", -1)]
    )
    assert row is not None, f"No email_verifications row for {email!r}"
    code_hash = bcrypt.hashpw(plain_code.encode("utf-8"), bcrypt.gensalt()).decode(
        "utf-8"
    )
    await db["email_verifications"].update_one(
        {"_id": row["_id"]},
        {"$set": {"code_hash": code_hash}},
    )


async def expire_otp_row(
    db: MongoDB,
    *,
    email: str,
) -> None:
    """Backdate ``expires_at`` on the latest OTP row so verify-code returns 410."""
    from datetime import UTC, datetime, timedelta

    past = datetime.now(tz=UTC) - timedelta(hours=1)
    row = await db["email_verifications"].find_one(
        {"email": email}, sort=[("created_at", -1)]
    )
    assert row is not None, f"No email_verifications row for {email!r}"
    await db["email_verifications"].update_one(
        {"_id": row["_id"]},
        {"$set": {"expires_at": past}},
    )


async def expire_pair_token(
    db: MongoDB,
    *,
    token: str,
) -> None:
    """Backdate a pair token so redeem returns 410 TOKEN_EXPIRED."""
    from datetime import UTC, datetime, timedelta

    past = datetime.now(tz=UTC) - timedelta(hours=1)
    await db["pair_tokens"].update_one(
        {"token": token},
        {"$set": {"expires_at": past}},
    )
