"""V0.6.1 — /family/{family_id}/* HTML routes (login, verify, dashboard) behaviour contracts.

We use BeautifulSoup to make the assertions robust to whitespace / attribute
ordering changes in the templates.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest
from bs4 import BeautifulSoup
from httpx import ASGITransport, AsyncClient

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@pytest.fixture
async def html_client(db: object) -> AsyncIterator[tuple[AsyncClient, object]]:
    from app.deps_email import get_email_provider
    from app.main import app
    from app.services.email_provider import RecordingEmailProvider

    provider = RecordingEmailProvider()
    app.dependency_overrides[get_email_provider] = lambda: provider

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", follow_redirects=False
    ) as ac:
        yield ac, provider

    app.dependency_overrides.pop(get_email_provider, None)


@pytest.mark.asyncio
async def test_root_redirects_to_parent_shell(
    html_client: tuple[AsyncClient, object],
) -> None:
    """Bare-domain visits should land on the parent shell, not a 404 JSON."""
    ac, _ = html_client
    r = await ac.get("/")
    assert r.status_code in (303, 307, 308)
    assert r.headers["location"] == "/family/_/login"


@pytest.mark.asyncio
async def test_login_page_has_email_form(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = html_client
    r = await ac.get("/family/_/login")
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    soup = BeautifulSoup(r.text, "html.parser")
    form = soup.find("form", action="/family/_/auth/request-code")
    assert form is not None
    assert form.find("input", attrs={"name": "email", "type": "email"}) is not None
    page_text = r.text
    assert "tailwindcss" in page_text.lower()
    assert "htmx" in page_text.lower()
    assert "登录" in page_text or "邮箱" in page_text


@pytest.mark.asyncio
async def test_verify_page_renders_email_in_form(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = html_client
    r = await ac.get("/family/_/verify", params={"email": "alice@example.com"})
    assert r.status_code == 200
    soup = BeautifulSoup(r.text, "html.parser")
    form = soup.find("form", action="/family/_/auth/verify-code")
    assert form is not None
    email_field = form.find("input", attrs={"name": "email"})
    assert email_field is not None
    assert email_field.get("value") == "alice@example.com"
    code_field = form.find("input", attrs={"name": "code"})
    assert code_field is not None
    assert code_field.get("maxlength") == "6"


@pytest.mark.asyncio
async def test_request_code_form_renders_verify_page(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, provider = html_client
    r = await ac.post(
        "/family/_/auth/request-code",
        data={"email": "form@example.com"},
    )
    assert r.status_code == 200
    soup = BeautifulSoup(r.text, "html.parser")
    form = soup.find("form", action="/family/_/auth/verify-code")
    assert form is not None
    assert "form@example.com" in r.text
    assert len(provider.outbox) == 1  # type: ignore[attr-defined]


@pytest.mark.asyncio
async def test_verify_code_form_redirects_to_dashboard_with_cookie(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, provider = html_client
    await ac.post("/family/_/auth/request-code", data={"email": "redir@example.com"})
    code = "".join(c for c in provider.outbox[-1]["text"] if c.isdigit())[:6]  # type: ignore[attr-defined]
    r = await ac.post(
        "/family/_/auth/verify-code",
        data={"email": "redir@example.com", "code": code},
    )
    assert r.status_code == 303
    loc = r.headers["location"]
    assert loc.startswith("/family/") and loc.endswith("/")
    assert "wm_session=" in r.headers.get("set-cookie", "")


@pytest.mark.asyncio
async def test_verify_code_form_wrong_re_renders_with_error(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = html_client
    await ac.post("/family/_/auth/request-code", data={"email": "bad@example.com"})
    r = await ac.post(
        "/family/_/auth/verify-code",
        data={"email": "bad@example.com", "code": "000000"},
    )
    assert r.status_code == 400
    soup = BeautifulSoup(r.text, "html.parser")
    form = soup.find("form", action="/family/_/auth/verify-code")
    assert form is not None
    assert "验证码" in r.text or "错误" in r.text


@pytest.mark.asyncio
async def test_dashboard_without_cookie_redirects_to_login(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = html_client
    r = await ac.get("/family/_/")
    assert r.status_code == 303
    assert r.headers["location"] == "/family/_/login"


@pytest.mark.asyncio
async def test_dashboard_with_cookie_renders_skeleton(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, provider = html_client
    await ac.post("/family/_/auth/request-code", data={"email": "dash@example.com"})
    code = "".join(c for c in provider.outbox[-1]["text"] if c.isdigit())[:6]  # type: ignore[attr-defined]
    r = await ac.post(
        "/family/_/auth/verify-code",
        data={"email": "dash@example.com", "code": code},
    )
    assert r.status_code == 303
    dash_home = r.headers["location"]
    r = await ac.get(dash_home)
    assert r.status_code == 200
    soup = BeautifulSoup(r.text, "html.parser")
    assert soup.find(id="devices-grid") is not None
    assert "dash" in r.text


@pytest.mark.asyncio
async def test_logout_form_clears_cookie_and_redirects(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, provider = html_client
    await ac.post("/family/_/auth/request-code", data={"email": "out@example.com"})
    code = "".join(c for c in provider.outbox[-1]["text"] if c.isdigit())[:6]  # type: ignore[attr-defined]
    r_login = await ac.post(
        "/family/_/auth/verify-code",
        data={"email": "out@example.com", "code": code},
    )
    assert r_login.status_code == 303
    fid = r_login.headers["location"].strip("/").split("/")[-1]
    r = await ac.post(f"/family/{fid}/auth/logout")
    assert r.status_code == 303
    assert r.headers["location"] == "/family/_/login"
    sc = r.headers.get("set-cookie", "")
    assert "wm_session=" in sc
    assert "Max-Age=0" in sc or "expires=" in sc.lower()
