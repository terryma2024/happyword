from datetime import datetime
from enum import StrEnum
from typing import Annotated

from beanie import Document, Indexed


class EmailVerificationStatus(StrEnum):
    PENDING = "pending"
    USED = "used"
    EXPIRED = "expired"


class EmailVerification(Document):
    """V0.6.1 — one OTP request per row.

    The clear-text 6-digit code is never stored; only its bcrypt hash. Each
    row tracks attempt count and is moved to `expired` once `expires_at` is
    reached or `attempts` hits `otp_max_attempts`. Successful verification
    moves status to `used`. Newer pending rows for the same email cause the
    older pending row to be moved to `expired`.
    """

    email: Annotated[str, Indexed()]
    code_hash: str
    status: EmailVerificationStatus = EmailVerificationStatus.PENDING
    attempts: int = 0
    created_at: datetime
    expires_at: datetime
    used_at: datetime | None = None

    class Settings:
        name = "email_verifications"
        indexes = [[("email", 1), ("status", 1), ("created_at", -1)]]
