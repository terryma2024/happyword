from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status

from app.config import get_settings
from app.deps import current_user
from app.models.user import User
from app.schemas.auth import LoginRequest, LoginResponse, MeResponse
from app.services.auth_service import create_access_token, verify_password

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


@router.post("/login", response_model=LoginResponse)
async def login(req: LoginRequest) -> LoginResponse:
    user = await User.find_one(User.username == req.username)
    if user is None or not verify_password(req.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": {"code": "UNAUTHORIZED", "message": "Invalid credentials"}},
        )
    user.last_login_at = datetime.now(tz=UTC)
    await user.save()
    settings = get_settings()
    expires = settings.jwt_expire_hours * 3600
    token = create_access_token(subject=user.username, expires_in=expires)
    return LoginResponse(access_token=token, expires_in=expires)


@router.get("/me", response_model=MeResponse)
async def me(user: User = Depends(current_user)) -> MeResponse:
    return MeResponse(
        username=user.username,
        role=user.role.value,
        last_login_at=user.last_login_at,
    )
