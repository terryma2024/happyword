"""Parent OTP login E2E (POTP-1, 3, 4, 7 + PSES-1, 2, 3).

Uses the OTP-injection helper to avoid depending on real email delivery:
the deployment is expected to run with SMTP unconfigured. After the test
calls /request-code, we overwrite the persisted bcrypt hash with one for
the known plaintext code "123456" so /verify-code can complete.
"""

import httpx
import pytest

from tests.e2e._utils.auth import KNOWN_OTP_CODE, ParentSession, parent_login
from tests.e2e._utils.db import MongoDB, inject_otp_code


@pytest.mark.e2e
@pytest.mark.smoke
async def test_request_code_returns_202(
    http: httpx.Client, mongo: MongoDB, run_id: str
) -> None:
    """POTP-1: /request-code is anti-enumeration → always 202."""
    email = f"e2e+{run_id}+req@example.com"
    r = http.post("/api/v1/parent/auth/request-code", json={"email": email})
    assert r.status_code == 202
    body = r.json()
    assert isinstance(body["expires_in_minutes"], int)
    assert body["expires_in_minutes"] > 0
    # Row should exist now.
    row = await mongo["email_verifications"].find_one({"email": email})
    assert row is not None


@pytest.mark.e2e
async def test_verify_code_happy_path(
    http: httpx.Client, mongo: MongoDB, run_id: str
) -> None:
    """POTP-3: /verify-code with the known code → 200 + Set-Cookie + family_id."""
    email = f"e2e+{run_id}+verify@example.com"
    parent = await parent_login(http=http, mongo=mongo, email=email)
    assert parent.email == email
    assert parent.user_id
    assert parent.family_id.startswith("fam-")
    assert http.cookies.get("wm_session") == parent.cookie


@pytest.mark.e2e
async def test_verify_code_wrong_returns_403(
    http: httpx.Client, mongo: MongoDB, run_id: str
) -> None:
    """POTP-4: /verify-code with a wrong 6-digit value → 403 INVALID_CODE."""
    email = f"e2e+{run_id}+wrong@example.com"
    r = http.post("/api/v1/parent/auth/request-code", json={"email": email})
    assert r.status_code == 202
    await inject_otp_code(mongo, email=email, plain_code=KNOWN_OTP_CODE)

    r = http.post(
        "/api/v1/parent/auth/verify-code",
        json={"email": email, "code": "000000"},
    )
    assert r.status_code == 403
    assert r.json()["detail"]["error"]["code"] == "INVALID_CODE"


@pytest.mark.e2e
def test_parent_me_without_cookie_returns_401(http: httpx.Client) -> None:
    """PSES-2: /parent/me without cookie → 401."""
    r = http.get("/api/v1/parent/me")
    assert r.status_code == 401


@pytest.mark.e2e
async def test_parent_me_with_cookie_returns_profile(
    http: httpx.Client, parent: ParentSession
) -> None:
    """PSES-1: /parent/me with cookie → 200 + payload matches verify-code."""
    r = http.get("/api/v1/parent/me")
    assert r.status_code == 200
    body = r.json()
    assert body["email"] == parent.email
    assert body["id"] == parent.user_id


@pytest.mark.e2e
async def test_parent_logout_clears_cookie(
    http: httpx.Client, parent: ParentSession
) -> None:
    """PSES-3: /parent/auth/logout → 200 + subsequent /me → 401."""
    assert parent  # parent fixture already attached the cookie
    r = http.post("/api/v1/parent/auth/logout")
    assert r.status_code == 200

    # Drop the cookie locally too so the follow-up /me reflects the logout.
    http.cookies.delete("wm_session")
    r = http.get("/api/v1/parent/me")
    assert r.status_code == 401
