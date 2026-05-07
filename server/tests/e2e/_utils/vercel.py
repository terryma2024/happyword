"""Vercel deployment-protection helpers for the E2E test driver.

When the deployed target is a Vercel preview with **Vercel Authentication**
or **Password Protection** enabled, every API call is intercepted with an
HTTP 401 + an HTML auth page — the test suite would then fail with
``assert 401 == 200`` across the board.

To let an automated client through, Vercel issues a per-project
**Protection Bypass for Automation** secret. When supplied as the
request header ``x-vercel-protection-bypass: <secret>``, the deployment
protection layer waves the request through to the real Function.

We deliberately do **NOT** send the optional ``x-vercel-set-bypass-cookie``
header. Per Vercel docs, that header instructs the edge to set a
``_vercel_jwt`` bypass cookie via a **307 redirect with a Set-Cookie
header**. Because the test client uses ``follow_redirects=False`` (so
that auth flows like ``/parent/auth/verify-code`` see real ``Set-Cookie``
responses and not whatever the redirect target returns), every API call
would short-circuit at the cookie-setting redirect and tests would
see ``307 Redirecting...`` instead of the expected status code. Sending
the bypass header on every request is enough — we don't need a cookie
because every ``httpx.Client`` in the suite is configured with the
header from this helper, and short-lived anonymous clients constructed
inside helper code (``device_redeem``, the pair-flow tests) also
attach the header explicitly.

Usage in the suite is uniform: ``vercel_bypass_headers()`` returns
either an empty dict (no bypass configured / not needed) or just the
single ``x-vercel-protection-bypass`` header. It is folded into the
shared ``http`` fixture in ``conftest.py`` and into every short-lived
anonymous ``httpx.Client`` constructed by helper code.

The bypass secret comes from the ``E2E_VERCEL_PROTECTION_BYPASS``
environment variable. When unset, the helper is a no-op so local
runs against an unprotected backend (e.g. ``uvicorn`` on
``127.0.0.1:8000``) keep working.

Docs: https://vercel.com/docs/deployment-protection/methods-to-bypass-deployment-protection/protection-bypass-automation
"""

from __future__ import annotations

import os
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import httpx

# Substring that appears in the body of the Vercel deployment-protection
# auth page (served as 401 with ``content-type: text/html``). Matching either
# the page <title> or the link to ``vercel.com/sso-api`` is sufficient — both
# are stable parts of the SSO redirect template that ships with Vercel
# Authentication / Password Protection.
_PROTECTION_PAGE_MARKERS = (
    "<title>Authentication Required</title>",
    "vercel.com/sso-api",
)


def looks_like_protection_page(response: httpx.Response) -> bool:
    """Return True if the response is Vercel's deployment-protection HTML.

    Used by the session-level preflight in ``conftest.py`` to turn the
    "every API call returns the SSO page" failure mode into a single,
    actionable pytest error, instead of leaking 50 copies of the auth
    page into the test report.
    """
    if response.status_code != 401:
        return False
    ctype = response.headers.get("content-type", "")
    if "text/html" not in ctype.lower():
        return False
    body = response.text
    return any(marker in body for marker in _PROTECTION_PAGE_MARKERS)


def vercel_bypass_headers() -> dict[str, str]:
    """Return the Vercel Protection Bypass headers, or ``{}`` when unset.

    Reads ``E2E_VERCEL_PROTECTION_BYPASS``. The value is the
    "Protection Bypass for Automation" secret minted by Vercel under
    *Project → Settings → Deployment Protection*.

    Only the ``x-vercel-protection-bypass`` header is returned —
    intentionally NOT ``x-vercel-set-bypass-cookie``. The latter would
    make Vercel respond with a 307 redirect carrying ``Set-Cookie``
    (see module docstring), and our test driver uses
    ``follow_redirects=False`` so it would never reach the actual
    Function. Sending the bypass header on every individual request
    waves it straight through to the upstream handler.
    """
    secret = os.environ.get("E2E_VERCEL_PROTECTION_BYPASS", "").strip()
    if not secret:
        return {}
    return {
        "x-vercel-protection-bypass": secret,
    }
