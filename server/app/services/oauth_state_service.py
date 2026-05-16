"""Signed OAuth CSRF state (itsdangerous)."""

from __future__ import annotations

import secrets

from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer

from app.config import get_settings


class OAuthStateError(Exception):
    """Invalid or expired OAuth state."""


def issue_state(*, return_origin: str, provider: str, redirect_uri: str) -> str:
    settings = get_settings()
    serializer = URLSafeTimedSerializer(settings.jwt_secret, salt="oauth-state-v1")
    payload = {
        "nonce": secrets.token_urlsafe(16),
        "return_origin": return_origin,
        "provider": provider,
        "redirect_uri": redirect_uri,
    }
    return serializer.dumps(payload)


def verify_state(token: str) -> dict[str, str]:
    settings = get_settings()
    serializer = URLSafeTimedSerializer(settings.jwt_secret, salt="oauth-state-v1")
    try:
        payload: object = serializer.loads(token, max_age=settings.oauth_state_ttl_seconds)
    except SignatureExpired as exc:
        raise OAuthStateError("state expired") from exc
    except BadSignature as exc:
        raise OAuthStateError("state signature invalid") from exc
    if not isinstance(payload, dict):
        raise OAuthStateError("state payload malformed")
    return {str(k): str(v) for k, v in payload.items()}
