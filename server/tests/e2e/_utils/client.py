"""HTTP client factory for the E2E test driver.

Centralizes httpx.Client construction so that every request — fixture or
ad-hoc anonymous client — automatically attaches the Vercel deployment
protection bypass headers when ``VERCEL_AUTOMATION_BYPASS_SECRET`` is
set in the environment.

Background:
    Vercel preview deployments default to "Vercel Authentication" (SSO)
    on personal / Hobby projects. Without a bypass, the preview returns
    a 401 with an HTML SSO page for every request, which makes every E2E
    test fail at the network layer (the HTML response can't be parsed as
    JSON, and the status code is never the expected 200/201/204/etc.).

    Vercel ships a "Protection Bypass for Automation" feature that lets
    callers attach a shared secret as a request header to skip the SSO
    challenge. See:
    https://vercel.com/docs/deployment-protection/methods-to-bypass-deployment-protection/protection-bypass-automation

    We optionally read the secret from ``VERCEL_AUTOMATION_BYPASS_SECRET``
    (the standard Vercel env var name). When unset, clients are built
    without the headers — useful for local runs against an unprotected
    target like ``http://127.0.0.1:8000``.
"""

from __future__ import annotations

import os
from typing import Any

import httpx

# Vercel's documented header names. Both must be set so that responses
# carrying ``Set-Cookie`` (e.g. /parent/auth/verify-code → wm_session) are
# also accepted: ``x-vercel-set-bypass-cookie`` instructs Vercel to
# include the bypass cookie on the response so subsequent requests in
# the same client session are accepted even if the header were stripped.
_BYPASS_HEADER = "x-vercel-protection-bypass"
_SET_BYPASS_COOKIE_HEADER = "x-vercel-set-bypass-cookie"


def vercel_bypass_headers() -> dict[str, str]:
    """Return ``{}`` if no bypass secret is configured, else the two
    headers required to bypass Vercel deployment protection.

    ``samesitenone`` is required because the E2E driver runs cross-site
    relative to the Vercel preview domain.
    """
    token = os.environ.get("VERCEL_AUTOMATION_BYPASS_SECRET", "").strip()
    if not token:
        return {}
    return {
        _BYPASS_HEADER: token,
        _SET_BYPASS_COOKIE_HEADER: "samesitenone",
    }


def make_client(
    base_url: str,
    *,
    timeout: float = 15.0,
    follow_redirects: bool = False,
    **kwargs: Any,
) -> httpx.Client:
    """Build an ``httpx.Client`` pre-wired with Vercel bypass headers.

    Use this anywhere the E2E suite previously constructed
    ``httpx.Client(base_url=..., timeout=...)`` directly. Extra keyword
    arguments (e.g. ``headers={"X-Custom": "..."}``) are merged on top of
    the default bypass headers.
    """
    extra_headers = dict(kwargs.pop("headers", {}) or {})
    headers = vercel_bypass_headers()
    headers.update(extra_headers)
    return httpx.Client(
        base_url=base_url,
        timeout=timeout,
        follow_redirects=follow_redirects,
        headers=headers,
        **kwargs,
    )
