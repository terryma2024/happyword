"""Apex-domain landing E2E (PUB-6): / renders the public landing page.

Regression guard for the Vercel deploy returning ``{"detail":"Not Found"}``
at the apex (e.g. ``https://happyword.com.cn/``). The unit test in
``tests/test_parent_pages.py`` exercises the in-process ASGI app and
cannot catch deployment-layer breakage — a Vercel rewrite that
short-circuits ``/`` or the FastAPI preset loading the wrong entrypoint
(`api/index.py` vs `app.main.py`, see the comment in `server/api/index.py`).
The root route now serves the public marketing landing page, while the
parent login shell remains available at ``/family/login``.
"""

import httpx
import pytest


@pytest.mark.e2e
def test_root_renders_public_landing_and_parent_login_remains_available(
    http: httpx.Client,
) -> None:
    """GET / returns the marketing landing page and /family/login still works."""
    # Bare apex must NOT return FastAPI's default 404 JSON.
    r = http.get("/")
    assert r.status_code == 200, (
        f"apex / returned {r.status_code}; expected the public landing page. "
        f"Body preview: {r.text[:200]!r}"
    )
    assert "text/html" in r.headers.get("content-type", "")
    body = r.text
    assert 'data-page="landing"' in body
    assert "魔法背单词｜英语学习小冒险" in body
    assert "/features" in body
    assert "/family/login" in body

    # Parent shell still renders separately for the CTA and existing family flows.
    r = http.get("/family/login")
    assert r.status_code == 200
    assert "text/html" in r.headers.get("content-type", "")
    # Sanity check on the rendered body — these markers should be stable
    # even if Tailwind class names churn.
    body = r.text
    assert "<form" in body
    assert "/family/_/auth/request-code" in body
