"""Admin pack publish / rollback / pointer E2E (APACK-2..7).

The DB is shared across tests in this module, so version numbers are
asserted *relatively* (``new > previous``) rather than against a fixed
value. The pack pointer is global (no family scoping), so the pre-suite
``e2e_reset_db.py`` is what guarantees a clean starting point per CI run.
"""

import httpx
import pytest

from tests.e2e._utils.auth import admin_headers


def _create_word(http: httpx.Client, token: str, word_id: str) -> None:
    r = http.post(
        "/api/v1/admin/words",
        headers=admin_headers(token),
        json={
            "id": word_id,
            "word": word_id,
            "meaningZh": "测试",
            "category": "test",
            "difficulty": 1,
        },
    )
    # 201 on first write; 409 means a previous test in this session already
    # created the same id — both are acceptable preconditions for publish.
    assert r.status_code in (201, 409), r.text


def _current_pointer_version(http: httpx.Client, token: str) -> int:
    r = http.get("/api/v1/admin/packs/current", headers=admin_headers(token))
    if r.status_code == 404:
        return 0
    assert r.status_code == 200, r.text
    return int(r.json()["current_version"])


@pytest.mark.e2e
def test_pack_publish_increments_version(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """APACK-2/3: publishing produces a strictly increasing version + schema_version >= 1."""
    headers = admin_headers(admin_token)
    _create_word(http, admin_token, f"w-e2e-{run_id}-pack-1")

    before = _current_pointer_version(http, admin_token)
    r = http.post(
        "/api/v1/admin/packs/publish",
        headers=headers,
        json={"notes": f"e2e-{run_id}"},
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["version"] > before
    assert body["schema_version"] >= 1
    assert body["word_count"] >= 1
    assert body["notes"] == f"e2e-{run_id}"


@pytest.mark.e2e
def test_pack_current_pointer_after_publish(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """APACK-4: GET /admin/packs/current reflects the latest publish."""
    headers = admin_headers(admin_token)
    _create_word(http, admin_token, f"w-e2e-{run_id}-pack-current")
    publish = http.post(
        "/api/v1/admin/packs/publish",
        headers=headers,
        json={"notes": "current"},
    )
    assert publish.status_code == 201, publish.text
    new_version = publish.json()["version"]

    r = http.get("/api/v1/admin/packs/current", headers=headers)
    assert r.status_code == 200, r.text
    assert r.json()["current_version"] == new_version


@pytest.mark.e2e
def test_pack_rollback_flips_pointer(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """APACK-5: rollback swaps current_version <-> previous_version."""
    headers = admin_headers(admin_token)
    # Need at least two publishes to have something to roll back to.
    _create_word(http, admin_token, f"w-e2e-{run_id}-rb-a")
    http.post(
        "/api/v1/admin/packs/publish",
        headers=headers,
        json={"notes": "rb-prep"},
    )
    _create_word(http, admin_token, f"w-e2e-{run_id}-rb-b")
    second = http.post(
        "/api/v1/admin/packs/publish",
        headers=headers,
        json={"notes": "rb-target"},
    )
    assert second.status_code == 201, second.text
    v_after_second = second.json()["version"]

    r = http.post("/api/v1/admin/packs/rollback", headers=headers)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["current_version"] < v_after_second
    assert body["previous_version"] == v_after_second


@pytest.mark.e2e
def test_pack_get_unknown_version_returns_404(
    http: httpx.Client, admin_token: str
) -> None:
    """APACK-8: GET /admin/packs/{huge_version} → 404 PACK_NOT_FOUND."""
    r = http.get("/api/v1/admin/packs/9999999", headers=admin_headers(admin_token))
    assert r.status_code == 404
    assert r.json()["detail"]["error"]["code"] == "PACK_NOT_FOUND"
