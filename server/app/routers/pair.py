"""V0.6.2 — pair flow API + `/p/{token_short}` HTML landing.

Endpoints:
- POST `/api/v1/parent/pair/create` (cookie) — issue a PairToken
- GET `/api/v1/parent/pair/status/{token}` (cookie) — poll status
- DELETE `/api/v1/parent/pair/{token}` (cookie) — cancel pending token
- POST `/api/v1/pair/redeem` (no auth) — client posts { token | short_code,
  device_id } and receives a device JWT + binding/profile ids.
- GET `/p/{token_short}` (no auth) — landing page shown when a parent's QR
  is scanned by a generic camera app; tells them to open WordMagic.
"""

from __future__ import annotations

from collections import defaultdict
from time import time
from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, HTTPException, Path, Request, status
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from app.config import get_settings
from app.deps import current_parent_user
from app.schemas.pair import (
    PairCreateOut,
    PairRedeemIn,
    PairRedeemOut,
    PairStatusOut,
)
from app.services.pair_service import (
    PairServiceError,
    PairTokenAlreadyRedeemed,
    PairTokenExpired,
    PairTokenInvalid,
    cancel,
    create_pair,
    redeem,
)

if TYPE_CHECKING:
    from app.models.user import User

router = APIRouter(tags=["pair"])
templates = Jinja2Templates(directory="app/templates")


# In-process per-parent rate limiter — best-effort, single-process. Vercel
# serverless instances each keep their own counter; that's intentional
# because the back-end DB index gives us the absolute "no double-token in
# flight" guarantee. The limiter here just discourages spam.
_RATE_WINDOW_SECONDS = 600
_RATE_MAX_CREATES = 5
_rate_buckets: dict[str, list[float]] = defaultdict(list)


def _check_rate_limit(parent_id: str) -> None:
    now = time()
    cutoff = now - _RATE_WINDOW_SECONDS
    bucket = _rate_buckets[parent_id]
    bucket[:] = [t for t in bucket if t > cutoff]
    if len(bucket) >= _RATE_MAX_CREATES:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "error": {
                    "code": "RATE_LIMITED",
                    "message": "Too many pair-create attempts; wait a few minutes.",
                }
            },
        )
    bucket.append(now)


def _qr_payload_url(token: str) -> str:
    base = get_settings().parent_web_base_url.rstrip("/")
    return f"{base}/p/{token[:12]}"


@router.post(
    "/api/v1/parent/pair/create",
    response_model=PairCreateOut,
    status_code=status.HTTP_201_CREATED,
)
async def post_create_pair(
    user: User = Depends(current_parent_user),
) -> PairCreateOut:
    _check_rate_limit(user.username)
    pt = await create_pair(family_id=user.family_id or "", parent_id=user.username)
    return PairCreateOut(
        token=pt.token,
        short_code=pt.short_code,
        qr_payload_url=_qr_payload_url(pt.token),
        expires_at=pt.expires_at,
        status=pt.status.value,
    )


@router.get(
    "/api/v1/parent/pair/status/{token}",
    response_model=PairStatusOut,
)
async def get_pair_status(
    token: str = Path(min_length=8, max_length=64),
    user: User = Depends(current_parent_user),
) -> PairStatusOut:
    from app.models.pair_token import PairToken

    pt = await PairToken.find_one(
        PairToken.token == token, PairToken.family_id == (user.family_id or "")
    )
    if pt is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {"code": "TOKEN_INVALID", "message": "Pair token not found"}
            },
        )
    return PairStatusOut(
        token=pt.token,
        short_code=pt.short_code,
        status=pt.status.value,
        expires_at=pt.expires_at,
        redeemed_at=pt.redeemed_at,
        redeemed_binding_id=pt.redeemed_binding_id,
        cancelled_at=pt.cancelled_at,
    )


@router.delete(
    "/api/v1/parent/pair/{token}",
    response_model=PairStatusOut,
)
async def delete_pair(
    token: str = Path(min_length=8, max_length=64),
    user: User = Depends(current_parent_user),
) -> PairStatusOut:
    try:
        pt = await cancel(token=token, family_id=user.family_id or "")
    except PairTokenInvalid as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {"code": "TOKEN_INVALID", "message": "Pair token not found"}
            },
        ) from e
    return PairStatusOut(
        token=pt.token,
        short_code=pt.short_code,
        status=pt.status.value,
        expires_at=pt.expires_at,
        redeemed_at=pt.redeemed_at,
        redeemed_binding_id=pt.redeemed_binding_id,
        cancelled_at=pt.cancelled_at,
    )


@router.post(
    "/api/v1/pair/redeem",
    response_model=PairRedeemOut,
    status_code=status.HTTP_200_OK,
)
async def post_redeem(
    payload: PairRedeemIn,
    request: Request,
) -> PairRedeemOut:
    if not payload.token and not payload.short_code:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "error": {
                    "code": "BAD_REQUEST",
                    "message": "Either token or short_code is required",
                }
            },
        )
    user_agent = request.headers.get("user-agent", "")
    try:
        binding, child, device_token = await redeem(
            token=payload.token,
            short_code=payload.short_code,
            device_id=payload.device_id,
            user_agent=user_agent,
        )
    except PairTokenExpired as e:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={
                "error": {"code": "TOKEN_EXPIRED", "message": "Pair token has expired"}
            },
        ) from e
    except PairTokenAlreadyRedeemed as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "error": {
                    "code": "TOKEN_REDEEMED",
                    "message": "Pair token already used",
                }
            },
        ) from e
    except PairTokenInvalid as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {"code": "TOKEN_INVALID", "message": "Pair token not found"}
            },
        ) from e
    except PairServiceError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": {"code": "PAIR_FAILED", "message": str(e)}},
        ) from e

    return PairRedeemOut(
        binding_id=binding.binding_id,
        family_id=binding.family_id,
        child_profile_id=child.profile_id,
        nickname=child.nickname,
        avatar_emoji=child.avatar_emoji,
        device_token=device_token,
    )


@router.get("/p/{token_short}", response_class=HTMLResponse)
async def get_landing(request: Request, token_short: str) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "pair/landing.html",
        {"user": None, "token_short": token_short},
    )
