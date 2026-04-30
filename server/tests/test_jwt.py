import time

import pytest

from app.services.auth_service import (
    JwtError,
    create_access_token,
    decode_access_token,
)


def test_create_then_decode_yields_subject() -> None:
    token = create_access_token(subject="alice", expires_in=60)
    payload = decode_access_token(token)
    assert payload["sub"] == "alice"
    assert payload["exp"] > int(time.time())


def test_decode_rejects_tampered_token() -> None:
    token = create_access_token(subject="alice", expires_in=60)
    bad = token[:-2] + ("AA" if not token.endswith("AA") else "BB")
    with pytest.raises(JwtError):
        decode_access_token(bad)


def test_decode_rejects_expired_token() -> None:
    token = create_access_token(subject="alice", expires_in=-1)
    with pytest.raises(JwtError):
        decode_access_token(token)
