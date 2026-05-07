"""HTTP login helpers for the E2E test driver.

These talk to the deployed server only — no in-process FastAPI imports.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

from tests.e2e._utils.client import make_client
from tests.e2e._utils.db import MongoDB, inject_otp_code

if TYPE_CHECKING:
    import httpx

KNOWN_OTP_CODE = "123456"


@dataclass
class ParentSession:
    """A logged-in parent: cookie is already attached to the shared http client."""

    email: str
    cookie: str
    user_id: str
    family_id: str


@dataclass
class DeviceSession:
    """A redeemed device binding: ``device_token`` is the JWT for ``Authorization``."""

    device_id: str
    device_token: str
    binding_id: str
    family_id: str
    child_profile_id: str
    nickname: str | None


def admin_login(http: httpx.Client, *, username: str, password: str) -> str:
    """Return the bearer token for an admin login. Raises on non-200."""
    r = http.post(
        "/api/v1/auth/login",
        json={"username": username, "password": password},
    )
    if r.status_code != 200:
        raise AssertionError(
            f"admin login failed ({r.status_code}): {r.text}"
        )
    body = r.json()
    token = body["access_token"]
    assert isinstance(token, str) and len(token) > 20
    return token


async def parent_login(
    *,
    http: httpx.Client,
    mongo: MongoDB,
    email: str,
) -> ParentSession:
    """Run the OTP login flow end-to-end.

    1. POST /parent/auth/request-code → 202.
    2. Overwrite the row's ``code_hash`` with bcrypt(KNOWN_OTP_CODE).
    3. POST /parent/auth/verify-code → 200 + Set-Cookie.

    The session cookie is attached to the shared ``http`` client so any
    subsequent call in the same test is automatically authenticated.
    """
    r = http.post("/api/v1/parent/auth/request-code", json={"email": email})
    if r.status_code != 202:
        raise AssertionError(
            f"request-code failed ({r.status_code}): {r.text}"
        )

    await inject_otp_code(mongo, email=email, plain_code=KNOWN_OTP_CODE)

    r = http.post(
        "/api/v1/parent/auth/verify-code",
        json={"email": email, "code": KNOWN_OTP_CODE},
    )
    if r.status_code != 200:
        raise AssertionError(
            f"verify-code failed ({r.status_code}): {r.text}"
        )
    body = r.json()
    cookie_value = r.cookies.get("wm_session")
    assert cookie_value, "wm_session cookie must be present after verify-code"

    # httpx.Client already absorbed the `Set-Cookie` (with the server's
    # domain attribute). We delete-then-set so subsequent tests that read
    # `http.cookies.get("wm_session")` see exactly one entry; otherwise
    # the auto-absorbed cookie + a domain-less manual one collide and
    # `Cookies.get` raises `CookieConflict`.
    http.cookies.delete("wm_session")
    http.cookies.set("wm_session", cookie_value)

    return ParentSession(
        email=email,
        cookie=cookie_value,
        user_id=body["user_id"],
        family_id=body["family_id"],
    )


def device_redeem(
    *,
    base_url: str,
    parent_http: httpx.Client,
    device_id: str,
) -> DeviceSession:
    """Have the (already-logged-in) parent issue a pair token, then redeem
    it from a clean anonymous client so the parent's cookie does not leak
    into the redeem call.
    """
    r = parent_http.post("/api/v1/parent/pair/create")
    if r.status_code != 201:
        raise AssertionError(
            f"pair/create failed ({r.status_code}): {r.text}"
        )
    token = r.json()["token"]

    with make_client(base_url) as anon:
        r = anon.post(
            "/api/v1/pair/redeem",
            json={"token": token, "device_id": device_id},
        )
    if r.status_code != 200:
        raise AssertionError(
            f"pair/redeem failed ({r.status_code}): {r.text}"
        )
    body = r.json()

    return DeviceSession(
        device_id=device_id,
        device_token=body["device_token"],
        binding_id=body["binding_id"],
        family_id=body["family_id"],
        child_profile_id=body["child_profile_id"],
        nickname=body.get("nickname"),
    )


def device_headers(device: DeviceSession) -> dict[str, str]:
    """Authorization headers for a device's API calls."""
    return {"Authorization": f"Bearer {device.device_token}"}


def admin_headers(token: str) -> dict[str, str]:
    """Authorization headers for an admin's API calls."""
    return {"Authorization": f"Bearer {token}"}
