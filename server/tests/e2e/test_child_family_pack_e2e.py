"""Child-side family-pack merge E2E (PFP-CHILD-1).

Validates the device-facing ``/api/v1/child/family-packs/latest.json``
contract: 204 when the family has no published packs, 200 + ETag once a
pack is published, and 304 on revalidation with ``If-None-Match``.
"""

import httpx
import pytest

from tests.e2e._utils.auth import DeviceSession, ParentSession, device_headers


def _custom_prefix(family_id: str) -> str:
    return f"fam-{family_id.removeprefix('fam-')[:8]}-"


@pytest.mark.e2e
def test_child_merged_204_when_no_packs(
    http: httpx.Client, device: DeviceSession
) -> None:
    """No published family packs in the family → 204."""
    r = http.get(
        "/api/v1/child/family-packs/latest.json",
        headers=device_headers(device),
    )
    assert r.status_code == 204


@pytest.mark.e2e
def test_child_merged_200_then_304_with_etag(
    http: httpx.Client,
    parent: ParentSession,
    device: DeviceSession,
    run_id: str,
) -> None:
    """Publish a pack, fetch it, then re-fetch with If-None-Match → 304."""
    create = http.post(
        "/api/v1/parent/family-packs",
        json={"name": f"E2E {run_id} child-merge"},
    )
    assert create.status_code == 201, create.text
    pack_id = create.json()["pack_id"]

    word_id = f"{_custom_prefix(parent.family_id)}{run_id[:6]}-mango"
    upsert = http.put(
        f"/api/v1/parent/family-packs/{pack_id}/draft/words/{word_id}",
        json={
            "source": "custom",
            "word": "mango",
            "meaning_zh": "芒果",
            "category": "fruit",
            "difficulty": 2,
        },
    )
    assert upsert.status_code == 200, upsert.text

    publish = http.post(
        f"/api/v1/parent/family-packs/{pack_id}/publish",
        json={"notes": "child-fetch test"},
    )
    assert publish.status_code == 201, publish.text

    # First fetch: 200 + ETag + body containing our pack.
    r1 = http.get(
        "/api/v1/child/family-packs/latest.json",
        headers=device_headers(device),
    )
    assert r1.status_code == 200, r1.text
    etag = r1.headers.get("ETag")
    assert etag, "ETag header must be present on first fetch"
    body = r1.json()
    assert body["family_id"] == parent.family_id
    pack_ids = {p["pack_id"] for p in body["packs"]}
    assert pack_id in pack_ids

    # Second fetch with If-None-Match → 304.
    r2 = http.get(
        "/api/v1/child/family-packs/latest.json",
        headers={**device_headers(device), "If-None-Match": etag},
    )
    assert r2.status_code == 304
    assert r2.headers.get("ETag") == etag
