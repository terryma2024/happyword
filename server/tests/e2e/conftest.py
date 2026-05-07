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
from tests.e2e._utils.vercel import (
    looks_like_protection_page,
    vercel_bypass_headers,
)


def _strip_env(name: str) -> str:
    return os.environ.get(name, "").strip()


@pytest.fixture(scope="session")
def base_url() -> str:
    url = _strip_env("E2E_BASE_URL")
    if not url:
        pytest.skip("E2E_BASE_URL is not set")
    url = url.rstrip("/")

    # Preflight: probe the unauthenticated /api/v1/health endpoint once and,
    # if Vercel's deployment-protection HTML page comes back, fail the entire
    # session with a single actionable error instead of letting all 50 e2e
    # cases each emit a multi-KB SSO HTML dump. Symptom we are guarding
    # against: VERCEL_AUTOMATION_BYPASS_SECRET repo secret is missing or
    # invalid, so the bypass header is empty/wrong and every API call is
    # intercepted at the edge. See server/README.md → "CI integration" for
    # how to mint the secret.
    headers = vercel_bypass_headers()
    try:
        with httpx.Client(
            base_url=url,
            timeout=10.0,
            follow_redirects=False,
            headers=headers,
        ) as probe:
            resp = probe.get("/api/v1/health")
    except httpx.HTTPError:
        # Network / DNS / TLS failures are surfaced naturally by the per-test
        # fixtures; do not pre-empt them here.
        return url
    if looks_like_protection_page(resp):
        bypass_set = bool(headers)
        msg = (
            "Vercel deployment protection is intercepting every request to "
            f"{url} with the SSO HTML page (HTTP 401). "
        )
        if not bypass_set:
            msg += (
                "The E2E_VERCEL_PROTECTION_BYPASS env var is empty — add the "
                "VERCEL_AUTOMATION_BYPASS_SECRET repo secret in GitHub "
                "(mint it under Vercel project → Settings → Deployment "
                "Protection → 'Protection Bypass for Automation'). "
                "See server/README.md → 'CI integration' for the full list "
                "of required secrets."
            )
        else:
            msg += (
                "The bypass header is set but Vercel still rejected the "
                "request — the secret is likely stale or doesn't match the "
                "current 'Protection Bypass for Automation' value. Re-mint "
                "it in Vercel project settings and update the "
                "VERCEL_AUTOMATION_BYPASS_SECRET repo secret."
            )
        pytest.fail(msg, pytrace=False)
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

    When the deployed target is a Vercel preview with deployment
    protection turned on, ``E2E_VERCEL_PROTECTION_BYPASS`` injects the
    ``x-vercel-protection-bypass`` header on every request so the test
    driver is waved through to the real Function instead of being
    intercepted by Vercel's SSO HTML page.
    """
    with httpx.Client(
        base_url=base_url,
        timeout=15.0,
        follow_redirects=False,
        headers=vercel_bypass_headers(),
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
