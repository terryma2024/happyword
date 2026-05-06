import time

import httpx
import pytest


@pytest.mark.e2e
@pytest.mark.smoke
def test_e2e_health_returns_ok(http: httpx.Client) -> None:
    """PUB-1: GET /api/v1/health returns 200 with the expected envelope."""
    resp = http.get("/api/v1/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["ok"] is True
    assert isinstance(body["ts"], int)
    # Server clock should be within ±5 minutes of the runner clock.
    assert abs(int(time.time()) - body["ts"]) < 5 * 60
