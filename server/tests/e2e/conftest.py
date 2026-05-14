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
    return url.rstrip("/")


@pytest.fixture(scope="session", autouse=True)
def _preview_protection_preflight(base_url: str) -> None:
    """Detect "Vercel Deployment Protection blocks the runner" up-front.

    Runs once per session. Hits the public health endpoint with the same
    bypass headers tests use; if Vercel's SSO HTML page comes back, the
    bypass secret is missing or wrong (CI secret
    ``VERCEL_AUTOMATION_BYPASS_SECRET`` not configured) and *every* test
    would otherwise fail with confusing ``401`` responses (52 multi-KB
    SSO HTML dumps in the report). Skip the whole suite with a single
    actionable message instead — this turns the failure mode from a red
    CI job (52 ERRORs) into a clean skipped outcome that leaves the rest
    of server-ci green while still surfacing the actionable hint.
    """
    # Vercel Functions on a cold start can take 20+ seconds to serve the
    # first request (Python venv create + uv install + 25 router imports +
    # Beanie init_beanie + bootstrap_admin + seed_categories run serially in
    # the FastAPI lifespan). 60s comfortably covers that and matches the
    # Pro plan's function maxDuration ceiling. This preflight is also our
    # warm-up: by absorbing the cold start here once per session, the
    # per-test ``http`` fixture below sees a warm function and rarely
    # bumps into its own timeout.
    try:
        resp = httpx.get(
            f"{base_url}/api/v1/public/health",
            headers=vercel_bypass_headers(),
            timeout=60.0,
            follow_redirects=False,
        )
    except httpx.HTTPError:
        # Network / DNS / TLS failures are surfaced naturally by the
        # per-test fixtures; do not pre-empt them here.
        return
    if looks_like_protection_page(resp):
        bypass_set = bool(_strip_env("E2E_VERCEL_PROTECTION_BYPASS"))
        hint = (
            "the secret is set but Vercel rejected it (rotated / wrong project?)"
            if bypass_set
            else "the secret is empty — set the GitHub Actions repo secret "
            "VERCEL_AUTOMATION_BYPASS_SECRET (Project → Settings → "
            "Deployment Protection → Protection Bypass for Automation)"
        )
        pytest.skip(
            "Vercel Deployment Protection is intercepting requests to "
            f"{base_url}; {hint}. "
            "See server/tests/e2e/_utils/vercel.py for details.",
            allow_module_level=True,
        )


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
    # 60s = Vercel Pro plan's function maxDuration ceiling. Headroom
    # mainly protects against (a) the rare cold start that the autouse
    # ``_preview_protection_preflight`` warm-up didn't catch (e.g. when
    # Vercel rotates the underlying container mid-suite) and (b) tests
    # that intentionally exercise heavy endpoints like the 250-item
    # bulk-sync path. 15s was the previous value and produced
    # ``httpx.ReadTimeout`` on every cold-start collision.
    with httpx.Client(
        base_url=base_url,
        timeout=60.0,
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
