"""Vercel deployment-protection bypass helpers for E2E tests.

When ``E2E_BASE_URL`` points at a Vercel Preview deployment that has
deployment protection enabled (the default for non-public projects),
unauthenticated requests are intercepted before they reach the FastAPI
function and return an HTML SSO redirect with status 401. This blocks
the entire E2E suite.

Vercel exposes a "Protection Bypass for Automation" mechanism: the
project owner generates a long-lived secret in the Vercel dashboard
(Project → Settings → Deployment Protection → Protection Bypass for
Automation) and CI passes it as the ``x-vercel-protection-bypass``
header on every request. With ``x-vercel-set-bypass-cookie: true`` the
edge also sets a session cookie so subsequent requests on the same
client (including 302 redirects to ``/p/<token>``) are authenticated
without re-sending the header.

We read the secret from the environment variable
``E2E_VERCEL_BYPASS_TOKEN`` (provisioned in the GitHub Actions
workflow). When unset — e.g. when running E2E against a local uvicorn
or against a public deployment — the helpers no-op and behavior is
unchanged.

Reference:
https://vercel.com/docs/deployment-protection/methods-to-bypass-deployment-protection/protection-bypass-automation
"""

from __future__ import annotations

import os
from typing import Any

import httpx

ENV_VAR = "E2E_VERCEL_BYPASS_TOKEN"


def _token() -> str:
    return os.environ.get(ENV_VAR, "").strip()


def bypass_headers() -> dict[str, str]:
    """Headers to inject on every request to a protected Vercel preview.

    Returns an empty dict when no token is configured so callers can
    blindly merge this into their own header maps.
    """
    token = _token()
    if not token:
        return {}
    return {
        "x-vercel-protection-bypass": token,
        # Ask the edge to set a session cookie on the first response so we
        # don't have to attach the header on every single request (and so
        # follow_redirects=True does not lose the bypass on the redirect
        # leg).
        "x-vercel-set-bypass-cookie": "true",
    }


def make_client(base_url: str, **kwargs: Any) -> httpx.Client:
    """Build an ``httpx.Client`` pre-wired with the Vercel bypass headers.

    All E2E tests should use this instead of ``httpx.Client(...)`` so the
    bypass is applied uniformly. Caller-supplied ``headers`` are merged
    on top of (and therefore override) the bypass headers.
    """
    headers = dict(bypass_headers())
    headers.update(kwargs.pop("headers", {}) or {})
    return httpx.Client(base_url=base_url, headers=headers, **kwargs)
