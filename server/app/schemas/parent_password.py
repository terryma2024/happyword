"""Parent password login and account password API shapes."""

from pydantic import BaseModel, EmailStr, Field


class PasswordLoginIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=256)


class PasswordLoginOut(BaseModel):
    user_id: str
    family_id: str
    email: str
    display_name: str | None


class PasswordSetIn(BaseModel):
    code: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")
    new_password: str = Field(min_length=8, max_length=256)
    confirm_password: str = Field(min_length=8, max_length=256)


class PasswordChangeIn(BaseModel):
    old_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=8, max_length=256)
    confirm_password: str = Field(min_length=8, max_length=256)


class PasswordOkOut(BaseModel):
    ok: bool = True
