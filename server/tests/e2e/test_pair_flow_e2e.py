"""Pair flow E2E (PAIR-1, 2, 5, 7, 9, 12).

Covers parent token creation, status polling, anonymous device redeem,
double-redeem 409, parent cancel, and the public landing page render.
"""

import httpx
import pytest

from tests.e2e._utils.auth import ParentSession


@pytest.mark.e2e
def test_pair_create_returns_token_and_short_code(
    http: httpx.Client, parent: ParentSession
) -> None:
    """PAIR-1: parent /pair/create → 201 + token / short_code / qr_payload_url."""
    r = http.post("/api/v1/parent/pair/create")
    assert r.status_code == 201, r.text
    body = r.json()
    assert isinstance(body["token"], str) and len(body["token"]) >= 16
    assert isinstance(body["short_code"], str) and len(body["short_code"]) == 6
    assert body["qr_payload_url"].endswith("/p/" + body["token"][:12])
    assert body["status"] == "pending"


@pytest.mark.e2e
def test_pair_status_pending_then_redeemed(
    http: httpx.Client, parent: ParentSession, base_url: str, run_id: str
) -> None:
    """PAIR-2 + PAIR-5: status flips from pending → redeemed after device claim."""
    create = http.post("/api/v1/parent/pair/create")
    assert create.status_code == 201, create.text
    token = create.json()["token"]

    status = http.get(f"/api/v1/parent/pair/status/{token}")
    assert status.status_code == 200
    assert status.json()["status"] == "pending"

    with httpx.Client(base_url=base_url, timeout=15.0) as anon:
        redeem = anon.post(
            "/api/v1/pair/redeem",
            json={"token": token, "device_id": f"e2e-{run_id}-redeem-1"},
        )
    assert redeem.status_code == 200, redeem.text
    body = redeem.json()
    assert body["device_token"]
    assert body["binding_id"]
    assert body["family_id"] == parent.family_id

    status2 = http.get(f"/api/v1/parent/pair/status/{token}")
    assert status2.status_code == 200
    assert status2.json()["status"] == "redeemed"
    assert status2.json()["redeemed_binding_id"] == body["binding_id"]


@pytest.mark.e2e
def test_pair_double_redeem_returns_409(
    http: httpx.Client, parent: ParentSession, base_url: str, run_id: str
) -> None:
    """PAIR-7: a second redeem on the same token → 409 TOKEN_REDEEMED."""
    create = http.post("/api/v1/parent/pair/create")
    token = create.json()["token"]

    with httpx.Client(base_url=base_url, timeout=15.0) as anon:
        first = anon.post(
            "/api/v1/pair/redeem",
            json={"token": token, "device_id": f"e2e-{run_id}-d1"},
        )
        assert first.status_code == 200, first.text

        second = anon.post(
            "/api/v1/pair/redeem",
            json={"token": token, "device_id": f"e2e-{run_id}-d2"},
        )
    assert second.status_code == 409
    assert second.json()["detail"]["error"]["code"] == "TOKEN_REDEEMED"


@pytest.mark.e2e
def test_pair_redeem_unknown_token_returns_404(
    http: httpx.Client, base_url: str, run_id: str
) -> None:
    """PAIR-3 (anon variant): unknown token → 404 TOKEN_INVALID."""
    with httpx.Client(base_url=base_url, timeout=15.0) as anon:
        r = anon.post(
            "/api/v1/pair/redeem",
            json={
                "token": f"no-such-token-{run_id}-padding",
                "device_id": f"e2e-{run_id}-x",
            },
        )
    assert r.status_code == 404
    assert r.json()["detail"]["error"]["code"] == "TOKEN_INVALID"


@pytest.mark.e2e
def test_pair_cancel_pending_token(
    http: httpx.Client, parent: ParentSession
) -> None:
    """PAIR-9: DELETE pending token flips status to cancelled."""
    create = http.post("/api/v1/parent/pair/create")
    token = create.json()["token"]

    r = http.request("DELETE", f"/api/v1/parent/pair/{token}")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["status"] == "cancelled"
    assert body["cancelled_at"] is not None


@pytest.mark.e2e
def test_pair_landing_page_renders(http: httpx.Client) -> None:
    """PAIR-12: public landing page renders even without a real token."""
    r = http.get("/p/abcdef123456")
    assert r.status_code == 200
    assert "text/html" in r.headers.get("content-type", "")
