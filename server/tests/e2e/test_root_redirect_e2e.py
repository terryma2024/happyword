"""Apex-domain landing E2E (PUB-6): / -> /parent/ -> /parent/login.

Regression guard for the Vercel deploy returning ``{"detail":"Not Found"}``
at the apex (e.g. ``https://happyword.vercel.app/``). The unit test in
``tests/test_parent_pages.py`` exercises the in-process ASGI app and
cannot catch deployment-layer breakage — a Vercel rewrite that
short-circuits ``/``, the FastAPI preset loading the wrong entrypoint
(`api/index.py` vs `app/main.py`, see the comment in
`server/api/index.py`), or the `/parent/` router silently dropping out.
This test walks the full redirect chain over real HTTP so any of those
failures surface as a red CI gate instead of a broken-looking domain in
production.
"""

import httpx
import pytest


@pytest.mark.e2e
def test_root_redirects_to_parent_login_chain(http: httpx.Client) -> None:
    """GET / -> 3xx /parent/ -> 3xx /parent/login -> 200 HTML.

    The shared ``http`` fixture has ``follow_redirects=False`` so each hop
    is asserted explicitly. We accept any 3xx redirect status (303/307/308)
    because the chosen status is an implementation detail and the suite
    should not over-specify it.
    """
    # Hop 1: bare apex must NOT return FastAPI's default 404 JSON.
    r = http.get("/")
    assert r.status_code in (303, 307, 308), (
        f"apex / returned {r.status_code}; expected a redirect to the "
        f"parent shell. Body preview: {r.text[:200]!r}"
    )
    assert r.headers["location"] == "/parent/"

    # Hop 2: /parent/ without a session cookie redirects to /parent/login.
    r = http.get("/parent/")
    assert r.status_code in (303, 307, 308)
    assert r.headers["location"] == "/parent/login"

    # Hop 3: /parent/login renders the actual HTML landing page.
    r = http.get("/parent/login")
    assert r.status_code == 200
    assert "text/html" in r.headers.get("content-type", "")
    # Sanity check on the rendered body — these markers should be stable
    # even if Tailwind class names churn.
    body = r.text
    assert "<form" in body
    assert "/parent/auth/request-code" in body
