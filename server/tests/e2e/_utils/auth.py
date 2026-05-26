"""HTTP login helpers for the E2E test driver.

These talk to the deployed server only — no in-process FastAPI imports.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import TYPE_CHECKING

import httpx

from tests.e2e._utils.db import MongoDB, inject_otp_code
from tests.e2e._utils.vercel import vercel_bypass_headers

if TYPE_CHECKING:
    from collections.abc import Callable

KNOWN_OTP_CODE = "123456"
_REQUEST_CODE_ATTEMPTS = 3
_REQUEST_CODE_RETRY_DELAY_SECONDS = 1.0


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
        "/api/v1/admin/auth/login",
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


def _request_parent_login_code(
    http: httpx.Client,
    *,
    email: str,
    sleep: Callable[[float], None] = time.sleep,
) -> httpx.Response:
    last_error: httpx.HTTPError | None = None
    for attempt in range(1, _REQUEST_CODE_ATTEMPTS + 1):
        try:
            response = http.post(
                "/api/v1/family/_/auth/request-code",
                json={"email": email},
            )
        except httpx.HTTPError as exc:
            last_error = exc
        else:
            if response.status_code < 500 or attempt == _REQUEST_CODE_ATTEMPTS:
                return response

        if attempt < _REQUEST_CODE_ATTEMPTS:
            sleep(_REQUEST_CODE_RETRY_DELAY_SECONDS)

    raise AssertionError(f"request-code failed after retries: {last_error!r}")


async def parent_login(
    *,
    http: httpx.Client,
    mongo: MongoDB,
    email: str,
) -> ParentSession:
    """Run the OTP login flow end-to-end.

    1. POST /api/v1/family/_/auth/request-code → 202.
    2. Overwrite the row's ``code_hash`` with bcrypt(KNOWN_OTP_CODE).
    3. POST /api/v1/family/_/auth/verify-code → 200 + Set-Cookie.

    The session cookie is attached to the shared ``http`` client so any
    subsequent call in the same test is automatically authenticated.
    """
    r = _request_parent_login_code(http, email=email)
    if r.status_code != 202:
        raise AssertionError(
            f"request-code failed ({r.status_code}): {r.text}"
        )

    await inject_otp_code(mongo, email=email, plain_code=KNOWN_OTP_CODE)

    r = http.post(
        "/api/v1/family/_/auth/verify-code",
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
    r = parent_http.post("/api/v1/family/_/pair/create")
    if r.status_code != 201:
        raise AssertionError(
            f"pair/create failed ({r.status_code}): {r.text}"
        )
    token = r.json()["token"]

    with httpx.Client(
        base_url=base_url,
        timeout=15.0,
        headers=vercel_bypass_headers(),
    ) as anon:
        r = anon.post(
            "/api/v1/public/pair/redeem",
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
