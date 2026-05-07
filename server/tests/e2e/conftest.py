"""Shared fixtures for the E2E test suite.

All fixtures gracefully ``pytest.skip`` when the required environment
isn't available, so the suite is safe to run in any environment without
a deployed target.
"""

import os
import uuid
from collections.abc import AsyncIterator, Iterator

import httpx
import pytest
from motor.motor_asyncio import AsyncIOMotorClient

from tests.e2e._utils.auth import (
    DeviceSession,
    ParentSession,
    admin_login,
    device_redeem,
    parent_login,
)
from tests.e2e._utils.db import MongoDB
from tests.e2e._utils.vercel import ENV_VAR as BYPASS_ENV_VAR
from tests.e2e._utils.vercel import make_client


def _strip_env(name: str) -> str:
    return os.environ.get(name, "").strip()


def _looks_like_vercel_sso(resp: httpx.Response) -> bool:
    """Heuristic: does ``resp`` look like a Vercel deployment-protection
    SSO challenge rather than an actual API response?

    Vercel intercepts anonymous traffic to protected previews with a
    401/403 HTML page whose body contains ``Authentication Required`` and
    a redirect to ``vercel.com/sso-api``. We only want to match on those
    very specific markers so a real API 401 (e.g. ``/parent/me`` without
    cookie) still fails the test as intended.
    """
    if resp.status_code not in (401, 403):
        return False
    ctype = resp.headers.get("content-type", "").lower()
    if "text/html" not in ctype:
        return False
    body = resp.text
    return "Authentication Required" in body and "vercel.com/sso-api" in body


@pytest.fixture(scope="session")
def base_url() -> str:
    url = _strip_env("E2E_BASE_URL")
    if not url:
        pytest.skip("E2E_BASE_URL is not set")
    url = url.rstrip("/")

    # Reachability probe: when the Vercel preview has Deployment
    # Protection enabled and the bypass token is missing/invalid, every
    # subsequent test would fail with a confusing
    # ``AssertionError: ...failed (401): <!doctype html>...`` instead of a
    # clean diagnostic. Detect the SSO challenge once and skip the whole
    # session with an actionable hint, matching the convention used by
    # the other env-driven fixtures below.
    try:
        with make_client(base_url=url, timeout=10.0, follow_redirects=False) as probe:
            health = probe.get("/api/v1/health")
    except httpx.RequestError as exc:
        pytest.skip(f"E2E_BASE_URL {url!r} is unreachable: {exc}")
    if _looks_like_vercel_sso(health):
        bypass_set = bool(_strip_env(BYPASS_ENV_VAR))
        hint = (
            "the token is rejected by the edge (rotated / wrong project?)"
            if bypass_set
            else (
                f"{BYPASS_ENV_VAR} is empty — add the "
                "VERCEL_AUTOMATION_BYPASS_SECRET repository secret "
                "(Vercel Project → Settings → Deployment Protection → "
                "Protection Bypass for Automation) so the test runner "
                "can attach the x-vercel-protection-bypass header"
            )
        )
        pytest.skip(
            "Vercel Deployment Protection is intercepting anonymous "
            f"requests to {url} with an SSO challenge: {hint}."
        )
    return url


@pytest.fixture(scope="session")
def run_id() -> str:
    """Per-session UUID prefix to namespace all fabricated identifiers."""
    return uuid.uuid4().hex[:12]


@pytest.fixture
def http(base_url: str) -> Iterator[httpx.Client]:
    """Function-scoped HTTP client.

    Function scope means each test starts with a clean cookie jar — the
    parent fixture re-attaches the session cookie when needed.
    """
    with make_client(
        base_url=base_url,
        timeout=15.0,
        follow_redirects=False,
    ) as client:
        yield client


@pytest.fixture
async def mongo() -> AsyncIterator[MongoDB]:
    """Direct MongoDB handle to the same database the deployment is talking to.

    Used for OTP injection and per-test cleanup. Skips when the URI/db name
    is not configured so the rest of the suite can still run.
    """
    uri = _strip_env("E2E_MONGODB_URI")
    name = _strip_env("E2E_MONGO_DB_NAME")
    if not uri or not name:
        pytest.skip("E2E_MONGODB_URI / E2E_MONGO_DB_NAME not set")
    client: AsyncIOMotorClient[dict[str, object]] = AsyncIOMotorClient(uri)
    try:
        yield client[name]
    finally:
        client.close()


@pytest.fixture
def admin_token(http: httpx.Client) -> str:
    user = _strip_env("E2E_ADMIN_USER")
    password = _strip_env("E2E_ADMIN_PASS")
    if not user or not password:
        pytest.skip("E2E_ADMIN_USER / E2E_ADMIN_PASS not set")
    return admin_login(http, username=user, password=password)


@pytest.fixture
async def parent(
    http: httpx.Client,
    mongo: MongoDB,
    run_id: str,
    request: pytest.FixtureRequest,
) -> ParentSession:
    test_slug = request.node.name.replace("[", "_").replace("]", "_")
    email = f"e2e+{run_id}+{test_slug}@example.com"
    return await parent_login(http=http, mongo=mongo, email=email)


@pytest.fixture
def device(
    http: httpx.Client,
    parent: ParentSession,
    base_url: str,
    run_id: str,
    request: pytest.FixtureRequest,
) -> DeviceSession:
    test_slug = request.node.name.replace("[", "_").replace("]", "_")
    device_id = f"e2e-{run_id}-{test_slug}"
    return device_redeem(base_url=base_url, parent_http=http, device_id=device_id)


# Re-export the session dataclasses so tests can ``from .conftest import …``
# without reaching into _utils.
__all__ = [
    "DeviceSession",
    "ParentSession",
    "admin_token",
    "base_url",
    "device",
    "http",
    "mongo",
    "parent",
    "run_id",
]
