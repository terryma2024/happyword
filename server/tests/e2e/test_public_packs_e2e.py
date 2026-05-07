"""Public pack endpoint E2E (PUB-2..5): ETag round-trip + 304 + stale handling."""

import httpx
import pytest


@pytest.mark.e2e
@pytest.mark.smoke
def test_packs_latest_returns_etag_and_304_round_trip(http: httpx.Client) -> None:
    """PUB-2 + PUB-4: latest.json returns 200 + ETag; If-None-Match → 304."""
    r = http.get("/api/v1/packs/latest.json")
    assert r.status_code == 200
    etag = r.headers.get("ETag")
    assert etag is not None and etag.startswith('"')

    r2 = http.get("/api/v1/packs/latest.json", headers={"If-None-Match": etag})
    assert r2.status_code == 304
    # 304 responses must echo the same ETag and have an empty body.
    assert r2.headers.get("ETag") == etag
    assert r2.content == b""


@pytest.mark.e2e
def test_packs_latest_stale_etag_returns_full_body(http: httpx.Client) -> None:
    """PUB-5: a stale If-None-Match falls back to a full 200 + new ETag."""
    r = http.get(
        "/api/v1/packs/latest.json",
        headers={"If-None-Match": '"stale-version-99999"'},
    )
    assert r.status_code == 200
    assert r.headers.get("ETag") is not None
    assert r.content  # non-empty body
