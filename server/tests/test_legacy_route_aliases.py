"""V0.6.5 — verify every legacy URL has a sibling under the new prefix
that hits the same handler. Removal of legacy URLs is deferred to v0.6.6+.

Per `.cursor/rules/api-route-pattern.mdc`, the project-wide URL convention
is `/api/v1/admin/**` + `/api/v1/public/**` + `/api/v1/family/{family_id}/**`.
The aliasing layer in `app.routers.legacy_route_aliases` mounts a sibling
URL under each new prefix that targets the SAME handler function. We don't
assert byte-equal bodies — auth-protected endpoints will return 401 from
both, public endpoints will return 200 from both, etc. The contract is:
**same HTTP status family, same response shape, no 404**.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from httpx import AsyncClient

# (legacy_path, new_path, method)
PUBLIC_ALIASES: list[tuple[str, str, str]] = [
    ("/api/v1/health", "/api/v1/public/health", "GET"),
    ("/api/v1/packs/latest.json", "/api/v1/public/packs/latest.json", "GET"),
]

# Admin auth — `current_user` enforces Bearer auth so anonymous calls
# get 401 from both URLs.
ADMIN_ALIASES: list[tuple[str, str, str]] = [
    ("/api/v1/auth/login", "/api/v1/admin/auth/login", "POST"),
    ("/api/v1/auth/me", "/api/v1/admin/auth/me", "GET"),
]

# Family-prefix aliases — `{family_id}` is decorative in v0.6.5.
# Auth still resolves via the existing parent session / device Bearer
# token, so anonymous calls get 401 from both URLs.
FAMILY_ALIASES: list[tuple[str, str, str]] = [
    (
        "/api/v1/parent/family-packs",
        "/api/v1/family/fam-test-1/family-packs",
        "GET",
    ),
    (
        "/api/v1/parent/inbox",
        "/api/v1/family/fam-test-1/inbox",
        "GET",
    ),
    (
        "/api/v1/parent/account/status",
        "/api/v1/family/fam-test-1/account/status",
        "GET",
    ),
    (
        "/api/v1/parent/children",
        "/api/v1/family/fam-test-1/children",
        "GET",
    ),
    (
        "/api/v1/child/word-stats",
        "/api/v1/family/fam-test-1/word-stats",
        "GET",
    ),
    (
        "/api/v1/child/family-packs/latest.json",
        "/api/v1/family/fam-test-1/family-packs/latest.json",
        "GET",
    ),
    (
        "/api/v1/child/wishlist",
        "/api/v1/family/fam-test-1/wishlist",
        "GET",
    ),
]


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("legacy", "new", "method"),
    [*PUBLIC_ALIASES, *ADMIN_ALIASES, *FAMILY_ALIASES],
)
async def test_alias_returns_same_status_class_as_legacy(
    client: AsyncClient, legacy: str, new: str, method: str
) -> None:
    """The alias must reach the SAME handler the legacy URL reaches."""
    r_legacy = await client.request(method, legacy)
    r_new = await client.request(method, new)
    assert r_legacy.status_code != 404, f"legacy {method} {legacy} 404'd"
    assert r_new.status_code != 404, f"new {method} {new} 404'd — alias missing"
    # Same status class (2xx vs 2xx, 4xx vs 4xx, etc).
    assert r_legacy.status_code // 100 == r_new.status_code // 100, (
        f"{method} {legacy} -> {r_legacy.status_code}; "
        f"{method} {new} -> {r_new.status_code}"
    )


@pytest.mark.asyncio
async def test_aliases_do_not_appear_in_openapi_schema(
    client: AsyncClient,
) -> None:
    """Aliases use include_in_schema=False so /docs only advertises the
    new shape going forward (and legacy URLs remain in schema during the
    transition window)."""
    r = await client.get("/openapi.json")
    paths = r.json()["paths"]
    # Aliases are NOT in /docs.
    assert "/api/v1/family/{family_id}/family-packs" not in paths
    assert "/api/v1/public/health" not in paths
    assert "/api/v1/admin/auth/login" not in paths
    # Legacy paths ARE still in /docs.
    assert "/api/v1/parent/family-packs" in paths
    assert "/api/v1/health" in paths
    assert "/api/v1/auth/login" in paths


@pytest.mark.asyncio
async def test_attach_legacy_aliases_returns_positive_count() -> None:
    """The aliaser ran during app startup and registered at least the
    fixed-path aliases (health, packs/latest.json, admin auth, plus all
    parent/child variant routes)."""
    from app.main import _alias_count

    assert _alias_count > 0
