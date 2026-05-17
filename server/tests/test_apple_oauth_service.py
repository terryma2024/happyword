"""Apple client_secret JWT generation."""

from __future__ import annotations

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from jose import jwt

from app.config import get_settings
from app.services.apple_oauth_service import generate_apple_client_secret


@pytest.fixture
def apple_key_env(monkeypatch: pytest.MonkeyPatch) -> str:
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("utf-8")
    monkeypatch.setenv("APPLE_OAUTH_CLIENT_ID", "com.happyword.parent")
    monkeypatch.setenv("APPLE_OAUTH_TEAM_ID", "TEAM123456")
    monkeypatch.setenv("APPLE_OAUTH_KEY_ID", "KEY123456")
    monkeypatch.setenv("APPLE_OAUTH_PRIVATE_KEY", pem)
    get_settings.cache_clear()
    return pem


def test_generate_apple_client_secret(apple_key_env: str) -> None:
    _ = apple_key_env
    settings = get_settings()
    secret = generate_apple_client_secret(settings)
    headers = jwt.get_unverified_header(secret)
    assert headers["alg"] == "ES256"
    assert headers["kid"] == "KEY123456"
    claims = jwt.get_unverified_claims(secret)
    assert claims["iss"] == "TEAM123456"
    assert claims["sub"] == "com.happyword.parent"
    assert claims["aud"] == "https://appleid.apple.com"
