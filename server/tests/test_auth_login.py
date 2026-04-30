from collections.abc import AsyncIterator
from datetime import UTC, datetime

import pytest
from httpx import AsyncClient

from app.models.user import User, UserRole
from app.services.auth_service import hash_password


@pytest.fixture
async def alice(db: object) -> AsyncIterator[User]:
    u = User(
        username="alice",
        password_hash=hash_password("wonderland"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


@pytest.mark.asyncio
async def test_login_success_returns_jwt(client: AsyncClient, alice: User) -> None:
    resp = await client.post(
        "/api/v1/auth/login",
        json={"username": "alice", "password": "wonderland"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["token_type"] == "bearer"
    assert body["expires_in"] > 0
    assert isinstance(body["access_token"], str) and len(body["access_token"]) > 20


@pytest.mark.asyncio
async def test_login_wrong_password_returns_401(client: AsyncClient, alice: User) -> None:
    resp = await client.post(
        "/api/v1/auth/login",
        json={"username": "alice", "password": "WRONG"},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_login_unknown_user_returns_401(client: AsyncClient) -> None:
    resp = await client.post(
        "/api/v1/auth/login",
        json={"username": "nobody", "password": "x"},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_login_missing_field_returns_422(client: AsyncClient) -> None:
    resp = await client.post("/api/v1/auth/login", json={"username": "alice"})
    assert resp.status_code == 422
