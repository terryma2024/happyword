"""Unit-level coverage for the SSO-challenge detector used by the E2E
preflight in ``conftest.py``. Runs offline; no ``@pytest.mark.e2e``."""

from __future__ import annotations

import httpx

from tests.e2e.conftest import _looks_like_vercel_sso_challenge


def _resp(
    status: int,
    *,
    content_type: str = "text/html",
    body: str = "",
) -> httpx.Response:
    return httpx.Response(
        status_code=status,
        headers={"content-type": content_type},
        text=body,
    )


def test_sso_challenge_detected_by_authentication_required_title() -> None:
    body = (
        "<!doctype html><html><head><title>Authentication Required</title>"
        "</head><body>...</body></html>"
    )
    assert _looks_like_vercel_sso_challenge(_resp(401, body=body)) is True


def test_sso_challenge_detected_by_sso_api_marker() -> None:
    body = (
        "<noscript><meta http-equiv=refresh content='1; "
        "URL=https://vercel.com/sso-api?url=...&nonce=abc'></noscript>"
    )
    assert _looks_like_vercel_sso_challenge(_resp(401, body=body)) is True


def test_legitimate_401_json_is_not_sso_challenge() -> None:
    """Real API 401s (e.g. /parent/me without cookie) must not be flagged."""
    resp = _resp(
        401,
        content_type="application/json",
        body='{"detail":"Not authenticated"}',
    )
    assert _looks_like_vercel_sso_challenge(resp) is False


def test_non_401_html_is_not_sso_challenge() -> None:
    """A 200 HTML page (e.g. landing page) is not an SSO challenge."""
    assert _looks_like_vercel_sso_challenge(_resp(200, body="<html/>")) is False


def test_401_without_html_body_is_not_sso_challenge() -> None:
    """An empty 401 (no html, no markers) is not the SSO page."""
    assert _looks_like_vercel_sso_challenge(_resp(401, body="")) is False
