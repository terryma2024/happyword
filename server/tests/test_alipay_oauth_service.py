"""Alipay OAuth service signing tests."""

from __future__ import annotations

import base64

import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

from app.services.alipay_oauth_service import _verify_alipay_response_signature


def _signed_alipay_response(payload: str) -> tuple[str, str]:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    signature = private_key.sign(
        payload.encode("utf-8"),
        padding.PKCS1v15(),
        hashes.SHA256(),
    )
    public_key_pem = (
        private_key.public_key()
        .public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        .decode("utf-8")
    )
    encoded_signature = base64.b64encode(signature).decode("ascii")
    response = (
        '{"alipay_system_oauth_token_response":'
        + payload
        + f',"sign":"{encoded_signature}"}}'
    )
    return response, public_key_pem


def test_verify_alipay_response_signature_accepts_valid_response() -> None:
    payload = '{"code":"10000","msg":"Success","access_token":"tok","user_id":"2088"}'
    response, public_key_pem = _signed_alipay_response(payload)

    _verify_alipay_response_signature(
        response,
        response_key="alipay_system_oauth_token_response",
        public_key_pem=public_key_pem,
    )


def test_verify_alipay_response_signature_rejects_tampered_response() -> None:
    payload = '{"code":"10000","msg":"Success","access_token":"tok","user_id":"2088"}'
    response, public_key_pem = _signed_alipay_response(payload)

    with pytest.raises(ValueError, match="signature invalid"):
        _verify_alipay_response_signature(
            response.replace('"2088"', '"2099"'),
            response_key="alipay_system_oauth_token_response",
            public_key_pem=public_key_pem,
        )
