"""V0.6.1 — FastAPI dependency seam for the EmailProvider.

Tests override this via `app.dependency_overrides[get_email_provider] = ...`
to inject a `RecordingEmailProvider` without monkeypatching SMTP.
"""

from typing import cast

from fastapi import Request

from app.services.email_provider import EmailProvider


def get_email_provider(request: Request) -> EmailProvider:
    """Resolve the EmailProvider instance attached to app.state at startup."""
    provider = getattr(request.app.state, "email_provider", None)
    if provider is None:
        raise RuntimeError(
            "app.state.email_provider not initialized; check main.lifespan setup"
        )
    return cast("EmailProvider", provider)
