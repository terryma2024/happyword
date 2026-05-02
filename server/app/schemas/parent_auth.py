"""V0.6.1 — parent OTP API request / response shapes."""

from pydantic import BaseModel, EmailStr, Field


class RequestCodeIn(BaseModel):
    email: EmailStr


class VerifyCodeIn(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")


class RequestCodeOut(BaseModel):
    """Always 202: response intentionally does not reveal whether the email
    is known, to prevent enumeration."""

    status: str = "accepted"
    expires_in_minutes: int


class VerifyCodeOut(BaseModel):
    user_id: str
    family_id: str
    email: str
    display_name: str | None
    delivery_degraded: bool = False


class ParentMeOut(BaseModel):
    id: str
    email: str
    display_name: str | None
    family_id: str
    role: str
    timezone: str
