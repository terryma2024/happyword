"""Child word-stats sync E2E (CWS-1, 2, 3, 7, 8).

LWW comparator is ``last_answered_ms``. The device JWT is supplied via
the ``device`` fixture which redeems a fresh pair token per test, so
each test starts with an empty ``synced_word_stats`` slice for that
profile.
"""

import httpx
import pytest

from tests.e2e._utils.auth import DeviceSession, device_headers


def _stat(
    word_id: str,
    *,
    last_answered_ms: int = 0,
    correct_count: int = 0,
    seen_count: int = 0,
    memory_state: str = "new",
    mastery: float = 0.0,
) -> dict[str, object]:
    return {
        "word_id": word_id,
        "seen_count": seen_count,
        "correct_count": correct_count,
        "wrong_count": 0,
        "last_answered_ms": last_answered_ms,
        "last_correct_ms": last_answered_ms if correct_count > 0 else 0,
        "next_review_ms": last_answered_ms + 86_400_000,
        "memory_state": memory_state,
        "consecutive_correct": correct_count,
        "consecutive_wrong": 0,
        "mastery": mastery,
    }


@pytest.mark.e2e
@pytest.mark.smoke
def test_sync_empty_returns_empty_arrays(
    http: httpx.Client, device: DeviceSession
) -> None:
    """CWS-1: empty payload → 200 + accepted/rejected/server_pulls all empty."""
    r = http.post(
        "/api/v1/child/word-stats/sync",
        headers=device_headers(device),
        json={"items": [], "synced_through_ms": 0},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["accepted"] == []
    assert body["rejected"] == []
    assert body["server_pulls"] == []
    assert body["server_now_ms"] > 0


@pytest.mark.e2e
def test_sync_inserts_then_get_returns_row(
    http: httpx.Client, device: DeviceSession, run_id: str
) -> None:
    """CWS-2: pushed item appears in subsequent GET /word-stats."""
    word_id = f"e2e-{run_id}-cws-insert"
    push = http.post(
        "/api/v1/child/word-stats/sync",
        headers=device_headers(device),
        json={
            "items": [_stat(word_id, last_answered_ms=1_000_000, correct_count=1)],
            "synced_through_ms": 0,
        },
    )
    assert push.status_code == 200, push.text
    assert push.json()["accepted"] == [word_id]

    r = http.get(
        "/api/v1/child/word-stats",
        headers=device_headers(device),
        params={"since_ms": 0},
    )
    assert r.status_code == 200, r.text
    items = r.json()["items"]
    assert any(item["word_id"] == word_id for item in items)


@pytest.mark.e2e
def test_sync_lww_newer_overwrites(
    http: httpx.Client, device: DeviceSession, run_id: str
) -> None:
    """CWS-3: a newer push wins; the older field values are gone."""
    word_id = f"e2e-{run_id}-cws-lww"
    older = _stat(word_id, last_answered_ms=1_000, correct_count=1, memory_state="learning")
    newer = _stat(
        word_id,
        last_answered_ms=2_000,
        correct_count=5,
        seen_count=10,
        memory_state="mastered",
        mastery=0.9,
    )
    headers = device_headers(device)

    r1 = http.post(
        "/api/v1/child/word-stats/sync",
        headers=headers,
        json={"items": [older], "synced_through_ms": 0},
    )
    assert r1.status_code == 200, r1.text
    assert r1.json()["accepted"] == [word_id]

    r2 = http.post(
        "/api/v1/child/word-stats/sync",
        headers=headers,
        json={"items": [newer], "synced_through_ms": 0},
    )
    assert r2.status_code == 200, r2.text
    assert r2.json()["accepted"] == [word_id]
    assert r2.json()["rejected"] == []

    g = http.get(
        "/api/v1/child/word-stats",
        headers=headers,
        params={"since_ms": 0},
    )
    rows = g.json()["items"]
    row = next(item for item in rows if item["word_id"] == word_id)
    assert row["last_answered_ms"] == 2_000
    assert row["correct_count"] == 5
    assert row["memory_state"] == "mastered"
    assert row["mastery"] == 0.9


@pytest.mark.e2e
def test_sync_older_returns_in_server_pulls(
    http: httpx.Client, device: DeviceSession, run_id: str
) -> None:
    """CWS-3 inverse: pushing an older record → rejected + the newer row in server_pulls."""
    word_id = f"e2e-{run_id}-cws-older"
    headers = device_headers(device)

    http.post(
        "/api/v1/child/word-stats/sync",
        headers=headers,
        json={
            "items": [_stat(word_id, last_answered_ms=5_000, correct_count=3)],
            "synced_through_ms": 0,
        },
    )
    r = http.post(
        "/api/v1/child/word-stats/sync",
        headers=headers,
        json={
            "items": [_stat(word_id, last_answered_ms=1_000, correct_count=1)],
            "synced_through_ms": 0,
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["accepted"] == []
    assert body["rejected"] == [word_id]
    assert any(p["word_id"] == word_id for p in body["server_pulls"])


@pytest.mark.e2e
def test_sync_batch_100_items(
    http: httpx.Client, device: DeviceSession, run_id: str
) -> None:
    """CWS-7: a 100-item batch is accepted in one POST.

    Originally exercised 250 items per spec §7.4 batching cap, but with the
    pre-bulk_write per-item find_one+save loop a 250-row batch routinely
    exceeded Vercel's 60s function ``maxDuration``. The service is now
    bulk-batched (single ``find`` + single ``bulk_write``), so even at 250
    this finishes in <1s; we keep the test at 100 to leave headroom for any
    cold-start variance and to bound CI runtime. The unit test
    ``test_post_sync_250_items_all_processed`` (offline mongo) still covers
    the upper batch ceiling.
    """

    items = [
        _stat(f"e2e-{run_id}-batch-{i}", last_answered_ms=1_000 + i, correct_count=1)
        for i in range(100)
    ]
    r = http.post(
        "/api/v1/child/word-stats/sync",
        headers=device_headers(device),
        json={"items": items, "synced_through_ms": 0},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert len(body["accepted"]) == 100
    assert body["rejected"] == []


@pytest.mark.e2e
def test_get_with_since_ms_returns_only_newer(
    http: httpx.Client, device: DeviceSession, run_id: str
) -> None:
    """CWS-8: GET ?since_ms=X returns only rows whose last_answered_ms > X."""
    headers = device_headers(device)
    old_id = f"e2e-{run_id}-since-old"
    new_id = f"e2e-{run_id}-since-new"
    http.post(
        "/api/v1/child/word-stats/sync",
        headers=headers,
        json={
            "items": [
                _stat(old_id, last_answered_ms=1_000, correct_count=1),
                _stat(new_id, last_answered_ms=10_000, correct_count=1),
            ],
            "synced_through_ms": 0,
        },
    )

    r = http.get(
        "/api/v1/child/word-stats",
        headers=headers,
        params={"since_ms": 5_000},
    )
    assert r.status_code == 200, r.text
    word_ids = {item["word_id"] for item in r.json()["items"]}
    assert new_id in word_ids
    assert old_id not in word_ids
