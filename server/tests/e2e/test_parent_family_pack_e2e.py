"""Parent family-pack lifecycle E2E (PFP-1, 2, 3, 4, 6, 7, 8, 10, 11, 13)."""

import httpx
import pytest

from tests.e2e._utils.auth import DeviceSession, ParentSession, device_headers


def _custom_prefix(family_id: str) -> str:
    """Mirror app.services.family_pack_service.CustomIdContract.prefix.

    family_id is ``fam-<8hex>``; the prefix uses the 8-hex slice as the
    second segment, e.g. ``fam-AbCdEfGh-``.
    """
    return f"fam-{family_id.removeprefix('fam-')[:8]}-"


def _custom_word_payload(word: str = "lemon", meaning: str = "柠檬") -> dict[str, object]:
    return {
        "source": "custom",
        "word": word,
        "meaning_zh": meaning,
        "category": "fruit",
        "difficulty": 1,
    }


@pytest.mark.e2e
def test_pack_create_returns_201(
    http: httpx.Client, parent: ParentSession, run_id: str
) -> None:
    """PFP-1: parent creates pack → 201 + state == active."""
    r = http.post(
        "/api/v1/family/_/family-packs",
        json={"name": f"E2E {run_id} create", "description": "e2e"},
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["name"] == f"E2E {run_id} create"
    assert body["state"] == "active"
    assert body["family_id"] == parent.family_id


@pytest.mark.e2e
def test_pack_create_duplicate_name_returns_409(
    http: httpx.Client, parent: ParentSession, run_id: str
) -> None:
    """PFP-2: a second active pack with the same name → 409 NAME_TAKEN."""
    name = f"E2E {run_id} dup-name"
    first = http.post("/api/v1/family/_/family-packs", json={"name": name})
    assert first.status_code == 201, first.text

    second = http.post("/api/v1/family/_/family-packs", json={"name": name})
    assert second.status_code == 409
    assert second.json()["detail"]["error"]["code"] == "NAME_TAKEN"


@pytest.mark.e2e
def test_pack_list_excludes_archived_by_default(
    http: httpx.Client, parent: ParentSession, run_id: str
) -> None:
    """PFP-3 + PFP-11: archive removes the pack from the default list, but
    ``?include_archived=true`` brings it back."""
    create = http.post(
        "/api/v1/family/_/family-packs",
        json={"name": f"E2E {run_id} archived"},
    )
    pack_id = create.json()["pack_id"]

    arch = http.post(f"/api/v1/family/_/family-packs/{pack_id}/archive")
    assert arch.status_code == 200
    assert arch.json()["state"] == "archived"

    default = http.get("/api/v1/family/_/family-packs")
    assert default.status_code == 200
    ids_default = {item["definition"]["pack_id"] for item in default.json()["items"]}
    assert pack_id not in ids_default

    inclusive = http.get(
        "/api/v1/family/_/family-packs",
        params={"include_archived": "true"},
    )
    ids_all = {item["definition"]["pack_id"] for item in inclusive.json()["items"]}
    assert pack_id in ids_all


@pytest.mark.e2e
def test_pack_draft_upsert_and_delete_word(
    http: httpx.Client, parent: ParentSession, run_id: str
) -> None:
    """PFP-4 + PFP-6: PUT increases draft word_count; DELETE drops it back."""
    create = http.post(
        "/api/v1/family/_/family-packs",
        json={"name": f"E2E {run_id} draft"},
    )
    pack_id = create.json()["pack_id"]
    word_id = f"{_custom_prefix(parent.family_id)}{run_id[:6]}-strawberry"

    upsert = http.put(
        f"/api/v1/family/_/family-packs/{pack_id}/draft/words/{word_id}",
        json=_custom_word_payload(word="strawberry", meaning="草莓"),
    )
    assert upsert.status_code == 200, upsert.text
    assert upsert.json()["word_count"] == 1

    delete = http.delete(
        f"/api/v1/family/_/family-packs/{pack_id}/draft/words/{word_id}"
    )
    assert delete.status_code == 200
    assert delete.json()["word_count"] == 0


@pytest.mark.e2e
def test_pack_publish_empty_returns_409(
    http: httpx.Client, parent: ParentSession, run_id: str
) -> None:
    """PFP-7: publishing a pack with no draft words → 409 EMPTY_PACK."""
    create = http.post(
        "/api/v1/family/_/family-packs",
        json={"name": f"E2E {run_id} empty-publish"},
    )
    pack_id = create.json()["pack_id"]

    r = http.post(
        f"/api/v1/family/_/family-packs/{pack_id}/publish",
        json={"notes": None},
    )
    assert r.status_code == 409
    assert r.json()["detail"]["error"]["code"] == "EMPTY_PACK"


@pytest.mark.e2e
def test_pack_publish_then_rollback_lifecycle(
    http: httpx.Client, parent: ParentSession, run_id: str
) -> None:
    """PFP-8 + PFP-10 + PFP-13: v1 → v2 → rollback flips pointer; versions list
    returns both rows."""
    create = http.post(
        "/api/v1/family/_/family-packs",
        json={"name": f"E2E {run_id} lifecycle"},
    )
    pack_id = create.json()["pack_id"]
    prefix = _custom_prefix(parent.family_id)

    # Publish v1.
    http.put(
        f"/api/v1/family/_/family-packs/{pack_id}/draft/words/{prefix}{run_id[:6]}-w1",
        json=_custom_word_payload(word="w1", meaning="一"),
    )
    publish_v1 = http.post(
        f"/api/v1/family/_/family-packs/{pack_id}/publish",
        json={"notes": "v1"},
    )
    assert publish_v1.status_code == 201, publish_v1.text
    assert publish_v1.json()["version"] == 1
    assert publish_v1.json()["word_count"] == 1

    # Add another word and publish v2.
    http.put(
        f"/api/v1/family/_/family-packs/{pack_id}/draft/words/{prefix}{run_id[:6]}-w2",
        json=_custom_word_payload(word="w2", meaning="二"),
    )
    publish_v2 = http.post(
        f"/api/v1/family/_/family-packs/{pack_id}/publish",
        json={"notes": "v2"},
    )
    assert publish_v2.status_code == 201, publish_v2.text
    assert publish_v2.json()["version"] == 2

    # Rollback flips current/previous.
    rb = http.post(f"/api/v1/family/_/family-packs/{pack_id}/rollback")
    assert rb.status_code == 200, rb.text
    body = rb.json()
    assert body["current_version"] == 1
    assert body["previous_version"] == 2

    # Versions endpoint returns both versions, newest first.
    versions = http.get(f"/api/v1/family/_/family-packs/{pack_id}/versions")
    assert versions.status_code == 200, versions.text
    items = versions.json()["items"]
    assert [v["version"] for v in items] == [2, 1]


@pytest.mark.e2e
def test_pack_split_move_publish_then_child_latest_groups_words(
    http: httpx.Client,
    parent: ParentSession,
    device: DeviceSession,
    run_id: str,
) -> None:
    """Split selected draft words, publish both packs, then verify child latest grouping."""
    create = http.post(
        "/api/v1/family/_/family-packs",
        json={"name": f"E2E {run_id} split-source"},
    )
    assert create.status_code == 201, create.text
    source_pack_id = create.json()["pack_id"]
    prefix = _custom_prefix(parent.family_id)
    ids = {
        "apple": f"{prefix}{run_id[:6]}-split-apple",
        "banana": f"{prefix}{run_id[:6]}-split-banana",
        "carrot": f"{prefix}{run_id[:6]}-split-carrot",
    }
    for word, word_id in ids.items():
        upsert = http.put(
            f"/api/v1/family/_/family-packs/{source_pack_id}/draft/words/{word_id}",
            json=_custom_word_payload(word=word, meaning=f"{word} zh"),
        )
        assert upsert.status_code == 200, upsert.text

    split = http.post(
        f"/api/v1/family/_/family-packs/{source_pack_id}/draft/split",
        json={
            "mode": "move",
            "word_ids": [ids["apple"], ids["banana"]],
            "new_pack": {"name": f"E2E {run_id} split-new"},
        },
    )
    assert split.status_code == 201, split.text
    new_pack_id = split.json()["new_pack"]["pack_id"]

    source_publish = http.post(
        f"/api/v1/family/_/family-packs/{source_pack_id}/publish",
        json={"notes": "source after split"},
    )
    assert source_publish.status_code == 201, source_publish.text
    new_publish = http.post(
        f"/api/v1/family/_/family-packs/{new_pack_id}/publish",
        json={"notes": "new after split"},
    )
    assert new_publish.status_code == 201, new_publish.text

    latest = http.get(
        "/api/v1/family/_/family-packs/latest.json",
        headers=device_headers(device),
    )
    assert latest.status_code == 200, latest.text
    packs = {pack["pack_id"]: pack for pack in latest.json()["packs"]}
    assert [w["id"] for w in packs[source_pack_id]["words"]] == [ids["carrot"]]
    assert [w["id"] for w in packs[new_pack_id]["words"]] == [
        ids["apple"],
        ids["banana"],
    ]
