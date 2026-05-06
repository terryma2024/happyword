"""Admin words CRUD E2E (AWORD-1..8)."""

import httpx
import pytest

from tests.e2e._utils.auth import admin_headers


def _word_payload(word_id: str, *, category: str = "fruit") -> dict[str, object]:
    return {
        "id": word_id,
        "word": "apple",
        "meaningZh": "苹果",
        "category": category,
        "difficulty": 2,
    }


@pytest.mark.e2e
def test_admin_word_create_then_get(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """AWORD-1 + AWORD-3: POST then GET round-trip."""
    headers = admin_headers(admin_token)
    word_id = f"e2e-{run_id}-create"

    r = http.post("/api/v1/admin/words", headers=headers, json=_word_payload(word_id))
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["id"] == word_id
    assert body["word"] == "apple"
    assert body["difficulty"] == 2
    assert body["deleted_at"] is None

    g = http.get(f"/api/v1/admin/words/{word_id}", headers=headers)
    assert g.status_code == 200
    assert g.json()["id"] == word_id


@pytest.mark.e2e
def test_admin_word_create_duplicate_returns_409(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """AWORD-2: re-creating the same id → 409 DUPLICATE_ID."""
    headers = admin_headers(admin_token)
    word_id = f"e2e-{run_id}-dup"
    http.post("/api/v1/admin/words", headers=headers, json=_word_payload(word_id))

    r = http.post("/api/v1/admin/words", headers=headers, json=_word_payload(word_id))
    assert r.status_code == 409
    assert r.json()["detail"]["error"]["code"] == "DUPLICATE_ID"


@pytest.mark.e2e
def test_admin_word_get_unknown_returns_404(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """AWORD-7 negative: GET /admin/words/{unknown} → 404."""
    headers = admin_headers(admin_token)
    r = http.get(f"/api/v1/admin/words/no-such-{run_id}", headers=headers)
    assert r.status_code == 404
    assert r.json()["detail"]["error"]["code"] == "WORD_NOT_FOUND"


@pytest.mark.e2e
def test_admin_word_partial_update(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """AWORD-4: PATCH-style PUT updates only supplied fields."""
    headers = admin_headers(admin_token)
    word_id = f"e2e-{run_id}-update"
    http.post("/api/v1/admin/words", headers=headers, json=_word_payload(word_id))

    r = http.put(
        f"/api/v1/admin/words/{word_id}",
        headers=headers,
        json={"difficulty": 5},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["difficulty"] == 5
    # Untouched fields preserved.
    assert body["word"] == "apple"
    assert body["category"] == "fruit"


@pytest.mark.e2e
def test_admin_word_list_filters_and_pagination(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """AWORD-5 + AWORD-6: ?category= filter + page/size pagination."""
    headers = admin_headers(admin_token)
    cat = f"e2e-cat-{run_id[:6]}"
    for i in range(3):
        http.post(
            "/api/v1/admin/words",
            headers=headers,
            json=_word_payload(f"e2e-{run_id}-list-{i}", category=cat),
        )

    r = http.get(
        "/api/v1/admin/words",
        headers=headers,
        params={"category": cat, "page": 1, "size": 2},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["page"] == 1
    assert body["size"] == 2
    assert body["total"] >= 3
    assert len(body["items"]) == 2
    assert all(item["category"] == cat for item in body["items"])


@pytest.mark.e2e
def test_admin_word_soft_delete_then_excluded(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """AWORD-7: DELETE soft-deletes; subsequent GET 404; ?include_deleted=true returns it."""
    headers = admin_headers(admin_token)
    word_id = f"e2e-{run_id}-soft-del"
    http.post("/api/v1/admin/words", headers=headers, json=_word_payload(word_id))

    r = http.delete(f"/api/v1/admin/words/{word_id}", headers=headers)
    assert r.status_code == 204

    r = http.get(f"/api/v1/admin/words/{word_id}", headers=headers)
    assert r.status_code == 404

    r = http.get(
        f"/api/v1/admin/words/{word_id}",
        headers=headers,
        params={"include_deleted": "true"},
    )
    assert r.status_code == 200
    assert r.json()["deleted_at"] is not None


@pytest.mark.e2e
def test_admin_word_update_after_delete_returns_404(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """AWORD-8: PUT on a soft-deleted word → 404."""
    headers = admin_headers(admin_token)
    word_id = f"e2e-{run_id}-update-after-del"
    http.post("/api/v1/admin/words", headers=headers, json=_word_payload(word_id))
    http.delete(f"/api/v1/admin/words/{word_id}", headers=headers)

    r = http.put(
        f"/api/v1/admin/words/{word_id}",
        headers=headers,
        json={"difficulty": 4},
    )
    assert r.status_code == 404


@pytest.mark.e2e
def test_admin_word_double_delete_returns_404(
    http: httpx.Client, admin_token: str, run_id: str
) -> None:
    """AWORD-7 follow-up: a second DELETE on the same id → 404."""
    headers = admin_headers(admin_token)
    word_id = f"e2e-{run_id}-double-del"
    http.post("/api/v1/admin/words", headers=headers, json=_word_payload(word_id))

    r1 = http.delete(f"/api/v1/admin/words/{word_id}", headers=headers)
    assert r1.status_code == 204
    r2 = http.delete(f"/api/v1/admin/words/{word_id}", headers=headers)
    assert r2.status_code == 404
