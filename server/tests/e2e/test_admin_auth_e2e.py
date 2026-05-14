"""Admin auth E2E (AAUTH-1..5)."""

import os

import httpx
import pytest

from tests.e2e._utils.auth import admin_headers


@pytest.mark.e2e
def test_admin_login_success(admin_token: str) -> None:
    """AAUTH-1: bootstrap creds → 200 + non-empty access_token."""
    assert isinstance(admin_token, str)
    assert len(admin_token) > 20


@pytest.mark.e2e
def test_admin_login_wrong_password(http: httpx.Client) -> None:
    """AAUTH-2: known user, wrong password → 401 UNAUTHORIZED."""
    user = os.environ.get("E2E_ADMIN_USER", "").strip()
    if not user:
        pytest.skip("E2E_ADMIN_USER not set")
    r = http.post(
        "/api/v1/admin/auth/login",
        json={"username": user, "password": "wrong-password-e2e"},
    )
    assert r.status_code == 401
    assert r.json()["detail"]["error"]["code"] == "UNAUTHORIZED"


@pytest.mark.e2e
def test_admin_login_unknown_user(http: httpx.Client, run_id: str) -> None:
    """AAUTH-3: unknown username → 401 UNAUTHORIZED."""
    r = http.post(
        "/api/v1/admin/auth/login",
        json={"username": f"nope-e2e-{run_id}", "password": "x"},
    )
    assert r.status_code == 401
    assert r.json()["detail"]["error"]["code"] == "UNAUTHORIZED"


@pytest.mark.e2e
def test_admin_me_with_token(http: httpx.Client, admin_token: str) -> None:
    """AAUTH-4: /auth/me with bearer token → 200 + role admin."""
    r = http.get("/api/v1/admin/auth/me", headers=admin_headers(admin_token))
    assert r.status_code == 200
    body = r.json()
    assert body["role"] == "admin"
    assert isinstance(body["username"], str) and body["username"]


@pytest.mark.e2e
def test_admin_me_without_token(http: httpx.Client) -> None:
    """AAUTH-5: /auth/me with no Authorization header → 401."""
    r = http.get("/api/v1/admin/auth/me")
    assert r.status_code == 401
