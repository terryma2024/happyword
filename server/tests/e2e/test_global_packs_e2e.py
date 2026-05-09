"""APACK-G: global pack publish + public latest.json (V0.6.5).

Mirrors `test_admin_packs_e2e` but for the new `/api/v1/admin/global-packs/*`
and `/api/v1/public/global-packs/latest.json` surfaces. Uses a per-run
`pack_id` so multiple PRs can run the suite concurrently against the same
preview DB without colliding.

Per `.cursor/rules/server-e2e-pytest-marker.mdc`, every test in this file
carries `@pytest.mark.e2e` so the GitHub Actions `server / e2e (preview)`
job collects them.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

from tests.e2e._utils.auth import admin_headers

if TYPE_CHECKING:
    import httpx


@pytest.mark.e2e
def test_global_pack_publish_then_appears_in_public_latest_json(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """Full happy path: admin creates definition, drafts a word, publishes;
    the public latest.json must include the new pack with `pack_id`."""
    pack_id = f"e2e-gpk-{run_id}"

    create = http.post(
        "/api/v1/admin/global-packs",
        headers=admin_headers(admin_token),
        json={
            "name": f"E2E {run_id}",
            "pack_id": pack_id,
            "description": f"e2e {run_id}",
            "scene": {"bossName": f"E2E Boss {run_id}"},
        },
    )
    assert create.status_code in (201, 200), create.text

    word_id = f"e2e-w-{run_id}"
    upsert = http.put(
        f"/api/v1/admin/global-packs/{pack_id}/draft/words/{word_id}",
        headers=admin_headers(admin_token),
        json={
            "id": word_id,
            "word": "ant",
            "meaningZh": "蚂蚁",
            "category": "animal",
            "difficulty": 1,
        },
    )
    assert upsert.status_code == 200, upsert.text

    pub = http.post(
        f"/api/v1/admin/global-packs/{pack_id}/publish",
        headers=admin_headers(admin_token),
        json={"notes": f"e2e {run_id}"},
    )
    assert pub.status_code == 201, pub.text
    assert pub.json()["version"] >= 1

    latest = http.get("/api/v1/public/global-packs/latest.json")
    assert latest.status_code == 200, latest.text
    assert "etag" in {k.lower() for k in latest.headers}
    body = latest.json()
    assert any(p["pack_id"] == pack_id for p in body["packs"])
    pack = next(p for p in body["packs"] if p["pack_id"] == pack_id)
    assert pack["scene"]["bossName"] == f"E2E Boss {run_id}"
    assert any(w["id"] == word_id for w in pack["words"])


@pytest.mark.e2e
def test_global_packs_latest_etag_returns_304(http: httpx.Client) -> None:
    """If-None-Match contract: same ETag back -> 304 Not Modified."""
    r1 = http.get("/api/v1/public/global-packs/latest.json")
    if r1.status_code == 204:
        pytest.skip("no published global packs in preview DB yet")
    assert r1.status_code == 200, r1.text
    etag = r1.headers["etag"]
    r2 = http.get(
        "/api/v1/public/global-packs/latest.json",
        headers={"If-None-Match": etag},
    )
    assert r2.status_code == 304


@pytest.mark.e2e
def test_global_packs_latest_head_returns_etag_only(http: httpx.Client) -> None:
    """HEAD probe returns the same ETag with no body."""
    r = http.head("/api/v1/public/global-packs/latest.json")
    if r.status_code == 204:
        pytest.skip("no published global packs in preview DB yet")
    assert r.status_code == 200
    assert "etag" in {k.lower() for k in r.headers}
    assert r.text == ""


@pytest.mark.e2e
def test_global_packs_anonymous_call_succeeds(http: httpx.Client) -> None:
    """Public endpoint requires NO authentication; admin headers are absent."""
    r = http.get("/api/v1/public/global-packs/latest.json")
    assert r.status_code in (200, 204)


@pytest.mark.e2e
def test_admin_global_packs_anonymous_call_returns_401(
    http: httpx.Client,
) -> None:
    """Admin endpoint requires Bearer + role=ADMIN. Anonymous → 401."""
    r = http.post("/api/v1/admin/global-packs", json={"name": "x"})
    assert r.status_code == 401
