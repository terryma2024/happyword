"""Admin categories CRUD E2E (ACAT-1..6)."""

import httpx
import pytest

from tests.e2e._utils.auth import admin_headers


def _category_payload(category_id: str) -> dict[str, object]:
    return {
        "id": category_id,
        "label_en": "Fruit (E2E)",
        "label_zh": "水果（端到端）",
        "story_zh": "测试故事",
    }


@pytest.mark.e2e
def test_categories_list_includes_seeded_rows(
    http: httpx.Client, admin_token: str
) -> None:
    """ACAT-1: bootstrap seeds at least the manual category set."""
    r = http.get("/api/v1/admin/categories", headers=admin_headers(admin_token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert isinstance(body["items"], list)
    assert body["total"] >= 5
    # Every row has the required envelope fields.
    sample = body["items"][0]
    for key in ("id", "label_en", "label_zh", "source", "created_at", "updated_at"):
        assert key in sample


@pytest.mark.e2e
def test_categories_create_then_get(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """ACAT-2: POST then GET returns the created category."""
    headers = admin_headers(admin_token)
    cat_id = f"e2e-cat-{run_id[:6]}-create"

    r = http.post(
        "/api/v1/admin/categories",
        headers=headers,
        json=_category_payload(cat_id),
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["id"] == cat_id
    assert body["source"] == "manual"

    g = http.get(f"/api/v1/admin/categories/{cat_id}", headers=headers)
    assert g.status_code == 200
    assert g.json()["label_en"] == "Fruit (E2E)"


@pytest.mark.e2e
def test_categories_duplicate_id_returns_409(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """ACAT-3: re-create same id → 409 DUPLICATE_ID."""
    headers = admin_headers(admin_token)
    cat_id = f"e2e-cat-{run_id[:6]}-dup"
    http.post("/api/v1/admin/categories", headers=headers, json=_category_payload(cat_id))

    r = http.post(
        "/api/v1/admin/categories",
        headers=headers,
        json=_category_payload(cat_id),
    )
    assert r.status_code == 409
    assert r.json()["detail"]["error"]["code"] == "DUPLICATE_ID"


@pytest.mark.e2e
def test_categories_update_labels(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """ACAT-4: PUT updates only supplied fields and bumps updated_at."""
    headers = admin_headers(admin_token)
    cat_id = f"e2e-cat-{run_id[:6]}-update"
    http.post("/api/v1/admin/categories", headers=headers, json=_category_payload(cat_id))

    r = http.put(
        f"/api/v1/admin/categories/{cat_id}",
        headers=headers,
        json={"label_en": "Updated EN"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["label_en"] == "Updated EN"
    assert body["label_zh"] == "水果（端到端）"


@pytest.mark.e2e
def test_categories_delete_blocked_by_word_reference(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """ACAT-5: deleting a category referenced by an active word → 409 CATEGORY_IN_USE."""
    headers = admin_headers(admin_token)
    cat_id = f"e2e-cat-{run_id[:6]}-inuse"
    http.post("/api/v1/admin/categories", headers=headers, json=_category_payload(cat_id))
    # Create a word in this category so it's "in use".
    http.post(
        "/api/v1/admin/words",
        headers=headers,
        json={
            "id": f"e2e-{run_id}-blocker",
            "word": "blocker",
            "meaningZh": "阻塞词",
            "category": cat_id,
            "difficulty": 1,
        },
    )

    r = http.delete(f"/api/v1/admin/categories/{cat_id}", headers=headers)
    assert r.status_code == 409
    assert r.json()["detail"]["error"]["code"] == "CATEGORY_IN_USE"


@pytest.mark.e2e
def test_categories_delete_succeeds_when_empty(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """ACAT-6: deleting an unreferenced category → 204 + subsequent GET 404."""
    headers = admin_headers(admin_token)
    cat_id = f"e2e-cat-{run_id[:6]}-empty"
    http.post("/api/v1/admin/categories", headers=headers, json=_category_payload(cat_id))

    r = http.delete(f"/api/v1/admin/categories/{cat_id}", headers=headers)
    assert r.status_code == 204
    g = http.get(f"/api/v1/admin/categories/{cat_id}", headers=headers)
    assert g.status_code == 404
    assert g.json()["detail"]["error"]["code"] == "CATEGORY_NOT_FOUND"
