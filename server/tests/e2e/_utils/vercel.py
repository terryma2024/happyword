"""Vercel deployment-protection helpers for the E2E test driver.

When the deployed target is a Vercel preview with **Vercel Authentication**
or **Password Protection** enabled, every API call is intercepted with an
HTTP 401 + an HTML auth page — the test suite would then fail with
``assert 401 == 200`` across the board.

To let an automated client through, Vercel issues a per-project
**Protection Bypass for Automation** secret. When supplied as a
request header (``x-vercel-protection-bypass: <secret>``) — optionally
together with ``x-vercel-set-bypass-cookie: true`` so the same client
reuses the bypass cookie on subsequent requests — the deployment
protection layer waves the request through to the real Function.

Usage in the suite is uniform: ``vercel_bypass_headers()`` returns
either an empty dict (no bypass configured / not needed) or the two
headers above. It is folded into the shared ``http`` fixture in
``conftest.py`` and into every short-lived anonymous ``httpx.Client``
constructed by helper code (e.g. ``device_redeem``, the pair-flow
tests).

The bypass secret comes from the ``E2E_VERCEL_PROTECTION_BYPASS``
environment variable. When unset, the helper is a no-op so local
runs against an unprotected backend (e.g. ``uvicorn`` on
``127.0.0.1:8000``) keep working.

Docs: https://vercel.com/docs/deployment-protection/methods-to-bypass-deployment-protection/protection-bypass-automation
"""

from __future__ import annotations

import os


def vercel_bypass_headers() -> dict[str, str]:
    """Return the Vercel Protection Bypass headers, or ``{}`` when unset.

    Reads ``E2E_VERCEL_PROTECTION_BYPASS``. The value is the
    "Protection Bypass for Automation" secret minted by Vercel under
    *Project → Settings → Deployment Protection*.

    The companion ``x-vercel-set-bypass-cookie: true`` header tells the
    Vercel edge to drop a ``_vercel_jwt`` cookie on the response so the
    same ``httpx.Client`` reuses it on subsequent requests instead of
    re-authenticating per call (which would also re-issue cookies that
    can collide with the app's own ``Set-Cookie``).
    """
    secret = os.environ.get("E2E_VERCEL_PROTECTION_BYPASS", "").strip()
    if not secret:
        return {}
    return {
        "x-vercel-protection-bypass": secret,
        "x-vercel-set-bypass-cookie": "true",
    }
