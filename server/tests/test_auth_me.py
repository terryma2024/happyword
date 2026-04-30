from datetime import UTC, datetime

import pytest
from httpx import AsyncClient

from app.models.user import User, UserRole
from app.services.auth_service import create_access_token, hash_password


@pytest.fixture
async def alice_token(db: object) -> str:
    await User(
        username="alice",
        password_hash=hash_password("x"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    ).insert()
    return create_access_token(subject="alice", expires_in=60)


@pytest.mark.asyncio
async def test_me_returns_user_info_with_valid_token(
    client: AsyncClient, alice_token: str
) -> None:
    resp = await client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {alice_token}"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["username"] == "alice"
    assert body["role"] == "admin"


@pytest.mark.asyncio
async def test_me_without_token_returns_401(client: AsyncClient) -> None:
    resp = await client.get("/api/v1/auth/me")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_me_with_garbage_token_returns_401(client: AsyncClient) -> None:
    resp = await client.get(
        "/api/v1/auth/me", headers={"Authorization": "Bearer NOT_A_JWT"}
    )
    assert resp.status_code == 401
