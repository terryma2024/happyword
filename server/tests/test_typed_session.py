"""V0.6.1 — typed JWT subject + parent cookie session dep tests."""

import time

import pytest


def test_create_session_token_includes_role_prefix() -> None:
    from app.services.auth_service import create_session_token, decode_typed_token

    token = create_session_token(role="parent", identifier="parent-abc12345")
    typed = decode_typed_token(token)
    assert typed.role == "parent"
    assert typed.identifier == "parent-abc12345"
    assert typed.sub == "parent:parent-abc12345"


def test_decode_typed_token_admin() -> None:
    from app.services.auth_service import create_session_token, decode_typed_token

    typed = decode_typed_token(create_session_token(role="admin", identifier="root"))
    assert typed.role == "admin"
    assert typed.identifier == "root"


def test_decode_typed_token_device() -> None:
    from app.services.auth_service import create_session_token, decode_typed_token

    typed = decode_typed_token(create_session_token(role="device", identifier="bind-abc"))
    assert typed.role == "device"


def test_decode_typed_token_legacy_admin_token_rejected() -> None:
    """Old V0.5 admin tokens use bare `<username>` as sub. The typed decoder
    must refuse them (router falls back to current_user for those)."""
    from app.services.auth_service import JwtError, create_access_token, decode_typed_token

    legacy = create_access_token(subject="admin")
    with pytest.raises(JwtError):
        decode_typed_token(legacy)


def test_decode_typed_token_unknown_role_rejected() -> None:
    from jose import jwt

    from app.config import get_settings
    from app.services.auth_service import JwtError, decode_typed_token

    settings = get_settings()
    bad = jwt.encode(
        {"sub": "robot:r1", "iat": int(time.time()), "exp": int(time.time()) + 3600},
        settings.jwt_secret,
        algorithm="HS256",
    )
    with pytest.raises(JwtError):
        decode_typed_token(bad)


@pytest.mark.asyncio
async def test_current_parent_user_via_cookie(db: object) -> None:
    from fastapi import FastAPI
    from httpx import ASGITransport, AsyncClient

    from app.deps import current_parent_user
    from app.services.auth_service import create_session_token
    from app.services.family_service import create_family_for_parent

    family, user = await create_family_for_parent(email="cookie@example.com")
    token = create_session_token(role="parent", identifier=user.username)

    app = FastAPI()

    @app.get("/__test/me")
    async def _me(u=current_parent_user) -> dict:  # type: ignore[no-untyped-def]
        return {"id": u.username, "email": u.email}

    # Wire the dependency properly (FastAPI requires Depends).
    from fastapi import Depends

    @app.get("/__test/me2")
    async def _me2(u=Depends(current_parent_user)) -> dict:  # type: ignore[no-untyped-def]
        return {"id": u.username, "email": u.email}

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", cookies={"wm_session": token}
    ) as ac:
        r = await ac.get("/__test/me2")
    assert r.status_code == 200
    assert r.json()["email"] == "cookie@example.com"


@pytest.mark.asyncio
async def test_current_parent_user_via_bearer(db: object) -> None:
    from fastapi import Depends, FastAPI
    from httpx import ASGITransport, AsyncClient

    from app.deps import current_parent_user
    from app.services.auth_service import create_session_token
    from app.services.family_service import create_family_for_parent

    _, user = await create_family_for_parent(email="bearer@example.com")
    token = create_session_token(role="parent", identifier=user.username)

    app = FastAPI()

    @app.get("/__test/me")
    async def _me(u=Depends(current_parent_user)) -> dict:  # type: ignore[no-untyped-def]
        return {"id": u.username}

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.get(
            "/__test/me", headers={"Authorization": f"Bearer {token}"}
        )
    assert r.status_code == 200
    assert r.json()["id"] == user.username


@pytest.mark.asyncio
async def test_current_parent_user_no_credentials_returns_401(db: object) -> None:
    from fastapi import Depends, FastAPI
    from httpx import ASGITransport, AsyncClient

    from app.deps import current_parent_user

    app = FastAPI()

    @app.get("/__test/me")
    async def _me(u=Depends(current_parent_user)) -> dict:  # type: ignore[no-untyped-def]
        return {}

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        r = await ac.get("/__test/me")
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_current_parent_user_admin_token_returns_403(db: object) -> None:
    from datetime import UTC, datetime

    from fastapi import Depends, FastAPI
    from httpx import ASGITransport, AsyncClient

    from app.deps import current_parent_user
    from app.models.user import User, UserRole
    from app.services.auth_service import create_session_token, hash_password

    await User(
        username="root",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    ).insert()
    admin_token = create_session_token(role="admin", identifier="root")

    app = FastAPI()

    @app.get("/__test/me")
    async def _me(u=Depends(current_parent_user)) -> dict:  # type: ignore[no-untyped-def]
        return {}

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", cookies={"wm_session": admin_token}
    ) as ac:
        r = await ac.get("/__test/me")
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_current_parent_user_renews_old_cookie(db: object) -> None:
    """Spec §6.7: cookie issued >7 days ago is renewed on next request."""
    from datetime import UTC, datetime, timedelta

    from fastapi import Depends, FastAPI
    from httpx import ASGITransport, AsyncClient
    from jose import jwt

    from app.config import get_settings
    from app.deps import current_parent_user
    from app.services.family_service import create_family_for_parent

    _, user = await create_family_for_parent(email="renew@example.com")

    # Forge an old-iat token (10 days ago).
    settings = get_settings()
    old_iat = int((datetime.now(tz=UTC) - timedelta(days=10)).timestamp())
    old_token = jwt.encode(
        {
            "sub": f"parent:{user.username}",
            "iat": old_iat,
            "exp": old_iat + 30 * 86400,
        },
        settings.jwt_secret,
        algorithm="HS256",
    )

    app = FastAPI()

    @app.get("/__test/me")
    async def _me(u=Depends(current_parent_user)) -> dict:  # type: ignore[no-untyped-def]
        return {"id": u.username}

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", cookies={"wm_session": old_token}
    ) as ac:
        r = await ac.get("/__test/me")
    assert r.status_code == 200
    set_cookie = r.headers.get("set-cookie", "")
    assert "wm_session=" in set_cookie  # cookie was rotated


@pytest.mark.asyncio
async def test_current_parent_user_recent_cookie_not_renewed(db: object) -> None:
    from fastapi import Depends, FastAPI
    from httpx import ASGITransport, AsyncClient

    from app.deps import current_parent_user
    from app.services.auth_service import create_session_token
    from app.services.family_service import create_family_for_parent

    _, user = await create_family_for_parent(email="fresh@example.com")
    fresh_token = create_session_token(role="parent", identifier=user.username)

    app = FastAPI()

    @app.get("/__test/me")
    async def _me(u=Depends(current_parent_user)) -> dict:  # type: ignore[no-untyped-def]
        return {"id": u.username}

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", cookies={"wm_session": fresh_token}
    ) as ac:
        r = await ac.get("/__test/me")
    assert r.status_code == 200
    assert r.headers.get("set-cookie", "") == ""
