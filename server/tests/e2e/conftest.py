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
from tests.e2e._utils.client import make_client
from tests.e2e._utils.db import MongoDB


def _strip_env(name: str) -> str:
    return os.environ.get(name, "").strip()


def _looks_like_vercel_sso_challenge(resp: httpx.Response) -> bool:
    """Return True iff the response is the Vercel deployment-protection
    SSO HTML page (HTTP 401 + ``text/html`` + the "Authentication Required"
    challenge body, optionally with the documented ``vercel-sso-api`` /
    ``sso-api`` redirect markers).

    Used by the session-level preflight to convert the wall of confusing
    fixture errors that follow into one actionable failure.
    """
    if resp.status_code != 401:
        return False
    ctype = resp.headers.get("content-type", "")
    if "text/html" not in ctype.lower():
        return False
    body = resp.text or ""
    return ("Authentication Required" in body) or ("/sso-api?" in body)


@pytest.fixture(scope="session")
def base_url() -> str:
    url = _strip_env("E2E_BASE_URL")
    if not url:
        pytest.skip("E2E_BASE_URL is not set")
    url = url.rstrip("/")

    # Preflight: detect Vercel deployment-protection SSO challenge once,
    # up-front, and surface it as a single, actionable failure instead of
    # 50+ confusing JSONDecodeError / 401-HTML stack traces in fixtures.
    # ``make_client`` already attaches the bypass headers when
    # ``VERCEL_AUTOMATION_BYPASS_SECRET`` is set, so a successful preflight
    # confirms the bypass path is wired correctly end-to-end.
    try:
        with make_client(url, timeout=10.0) as probe:
            resp = probe.get("/api/v1/health")
    except httpx.HTTPError as exc:
        pytest.fail(
            f"E2E preflight: could not reach {url}/api/v1/health "
            f"({exc!r}). The preview deployment may not be ready, or "
            "the URL is wrong. Check the 'Detect Vercel preview URL' step "
            "and the deployment dashboard."
        )

    if _looks_like_vercel_sso_challenge(resp):
        bypass_set = bool(_strip_env("VERCEL_AUTOMATION_BYPASS_SECRET"))
        if bypass_set:
            pytest.fail(
                f"E2E preflight: target {url} is protected by Vercel "
                "Authentication and rejected the bypass headers — the "
                "VERCEL_AUTOMATION_BYPASS_SECRET we sent is invalid or "
                "no longer matches the value configured under Vercel "
                "Project → Settings → Deployment Protection → Protection "
                "Bypass for Automation. Regenerate the token and update "
                "the GitHub repo secret of the same name."
            )
        pytest.fail(
            f"E2E preflight: target {url} is protected by Vercel "
            "Authentication (the SSO HTML challenge was returned for "
            "/api/v1/health) and VERCEL_AUTOMATION_BYPASS_SECRET is not "
            "set. Add the GitHub repo secret of that name (Vercel → "
            "Project → Settings → Deployment Protection → Protection "
            "Bypass for Automation), or disable Vercel Authentication on "
            "Preview deployments. See server/README.md → 'Required "
            "environment variables'."
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

    Built via ``make_client`` so the Vercel deployment-protection bypass
    headers are attached automatically when
    ``VERCEL_AUTOMATION_BYPASS_SECRET`` is set in CI.
    """
    with make_client(base_url) as client:
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
