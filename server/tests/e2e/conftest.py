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


def _strip_env(name: str) -> str:
    return os.environ.get(name, "").strip()


@pytest.fixture(scope="session")
def base_url() -> str:
    url = _strip_env("E2E_BASE_URL")
    if not url:
        pytest.skip("E2E_BASE_URL is not set")
    return url.rstrip("/")


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
    with httpx.Client(
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
    return device_redeem(
        base_url=base_url, parent_http=http, device_id=device_id
    )


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
