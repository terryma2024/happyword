from __future__ import annotations

import httpx

from tests.e2e._utils import auth


class _RequestCodeClient:
    def __init__(self, statuses: list[int]) -> None:
        self._statuses = statuses
        self.attempts = 0

    def post(self, url: str, *, json: dict[str, str]) -> httpx.Response:
        assert url == "/api/v1/family/_/auth/request-code"
        assert json == {"email": "parent@example.com"}
        status = self._statuses[self.attempts]
        self.attempts += 1
        return httpx.Response(status, text=f"status {status}")


def test_request_parent_login_code_retries_transient_5xx() -> None:
    client = _RequestCodeClient([500, 202])

    response = auth._request_parent_login_code(  # pyright: ignore[reportPrivateUsage]
        client, email="parent@example.com", sleep=lambda _: None
    )

    assert response.status_code == 202
    assert client.attempts == 2


def test_request_parent_login_code_does_not_retry_client_errors() -> None:
    client = _RequestCodeClient([409, 202])

    response = auth._request_parent_login_code(  # pyright: ignore[reportPrivateUsage]
        client, email="parent@example.com", sleep=lambda _: None
    )

    assert response.status_code == 409
    assert client.attempts == 1
