"""V0.6.1 — /family/{family_id}/* HTML routes (login, verify, dashboard) behaviour contracts.

We use BeautifulSoup to make the assertions robust to whitespace / attribute
ordering changes in the templates.
"""

from __future__ import annotations

from pathlib import Path
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
async def test_root_renders_public_landing_page(
    html_client: tuple[AsyncClient, object],
) -> None:
    """Bare-domain visits should show the public product landing page."""
    ac, _ = html_client
    r = await ac.get("/")
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]

    soup = BeautifulSoup(r.text, "html.parser")
    assert soup.find("main", attrs={"data-page": "landing"}) is not None
    assert "魔法背单词" in r.text
    assert "把英语练习变成一场小小冒险" in r.text
    assert soup.find("a", href="/family/login") is not None
    assert soup.find("img", attrs={"src": "/static/landing-hero.png"}) is not None
    assert "沪ICP备2026023209号-1" in r.text


@pytest.mark.asyncio
async def test_landing_page_styles_shared_icp_footer(
    html_client: tuple[AsyncClient, object],
) -> None:
    """Landing CSS should style the shared ICP footer without Tailwind."""
    ac, _ = html_client
    r = await ac.get("/")
    assert r.status_code == 200

    soup = BeautifulSoup(r.text, "html.parser")
    footer = soup.find("footer")
    assert footer is not None
    assert footer.find("a", href="https://beian.miit.gov.cn/") is not None

    css = (Path(__file__).resolve().parents[1] / "app/static/landing.css").read_text()
    assert "body > footer > div" in css
    assert "text-align: center" in css


@pytest.mark.asyncio
async def test_landing_page_has_app_download_options(
    html_client: tuple[AsyncClient, object],
) -> None:
    """Landing page should expose iOS download and coming-soon placeholders."""
    ac, _ = html_client
    r = await ac.get("/")
    assert r.status_code == 200

    soup = BeautifulSoup(r.text, "html.parser")
    download = soup.find(id="download")
    assert download is not None
    ios = download.find(
        "a",
        href="https://apps.apple.com/cn/app/%E9%AD%94%E6%B3%95%E8%83%8C%E5%8D%95%E8%AF%8D/id6768499286",
    )
    assert ios is not None
    assert ios.get("target") == "_blank"
    assert ios.get("rel") == ["noopener"]

    placeholders = download.find_all("button", attrs={"data-coming-soon": "true"})
    assert {button.get_text(strip=True) for button in placeholders} == {
        "AndroidComing soon",
        "HarmonyOSComing soon",
    }
    assert download.find(id="download-status") is not None
    assert "Coming soon" in r.text


@pytest.mark.asyncio
async def test_landing_page_has_mobile_reachable_features_link(
    html_client: tuple[AsyncClient, object],
) -> None:
    """Feature page entry should remain available when mobile CSS hides nav links."""
    ac, _ = html_client
    r = await ac.get("/")
    assert r.status_code == 200

    soup = BeautifulSoup(r.text, "html.parser")
    hero_actions = soup.find("div", class_="hero-actions")
    assert hero_actions is not None
    features_link = hero_actions.find("a", href="/features")
    assert features_link is not None
    assert "功能介绍" in features_link.get_text(strip=True)


@pytest.mark.asyncio
async def test_happyword_cool_redirects_permanently_to_com_cn(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = html_client

    r = await ac.get(
        "/api/v1/public/health?source=cool",
        headers={"host": "happyword.cool"},
    )

    assert r.status_code == 301
    assert r.headers["location"] == "https://happyword.com.cn/api/v1/public/health?source=cool"


@pytest.mark.asyncio
async def test_happyword_com_cn_does_not_self_redirect(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = html_client

    r = await ac.get(
        "/api/v1/public/health",
        headers={"host": "happyword.com.cn"},
    )

    assert r.status_code == 200


@pytest.mark.asyncio
async def test_legacy_scoped_login_redirects_to_canonical(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = html_client
    r = await ac.get("/family/_/login")
    assert r.status_code == 308
    assert r.headers["location"] == "/family/login"


@pytest.mark.asyncio
async def test_login_page_has_email_form(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = html_client
    r = await ac.get("/family/login")
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
    assert r.headers["location"] == "/family/login"


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
    assert r.headers["location"] == "/family/login"
    sc = r.headers.get("set-cookie", "")
    assert "wm_session=" in sc
    assert "Max-Age=0" in sc or "expires=" in sc.lower()


@pytest.mark.asyncio
async def test_login_shows_google_when_configured(
    html_client: tuple[AsyncClient, object],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "test-client")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_SECRET", "test-secret")
    monkeypatch.setenv("OAUTH_CANONICAL_BASE_URL", "http://test")
    from app.config import get_settings

    get_settings.cache_clear()
    ac, _ = html_client
    r = await ac.get("/family/login")
    soup = BeautifulSoup(r.text, "html.parser")
    link = soup.find("a", href=lambda href: href and href.startswith("/v1/oauth/google/start?"))
    assert link is not None
    assert "return_origin=http%3A%2F%2Ftest" in link["href"]
    assert "Continue with Google" in link.get_text()
    assert link.find("svg", attrs={"aria-hidden": "true"}) is not None


@pytest.mark.asyncio
async def test_login_shows_apple_when_configured(
    html_client: tuple[AsyncClient, object],
    monkeypatch: pytest.MonkeyPatch,
    apple_test_private_key_pem: str,
) -> None:
    monkeypatch.setenv("APPLE_OAUTH_CLIENT_ID", "com.happyword.parent")
    monkeypatch.setenv("APPLE_OAUTH_TEAM_ID", "TEAM123456")
    monkeypatch.setenv("APPLE_OAUTH_KEY_ID", "KEY123456")
    monkeypatch.setenv("APPLE_OAUTH_PRIVATE_KEY", apple_test_private_key_pem)
    from app.config import get_settings

    get_settings.cache_clear()
    ac, _ = html_client
    r = await ac.get("/family/login")
    soup = BeautifulSoup(r.text, "html.parser")
    link = soup.find("a", href=lambda href: href and href.startswith("/v1/oauth/apple/start?"))
    assert link is not None
    assert "return_origin=https%3A%2F%2Fhappyword.com.cn" in link["href"]
    assert "Continue with Apple" in link.get_text()


@pytest.mark.asyncio
async def test_login_hides_google_without_credentials(
    html_client: tuple[AsyncClient, object],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_SECRET", "")
    from app.config import get_settings

    get_settings.cache_clear()
    ac, _ = html_client
    r = await ac.get("/family/login")
    assert "Continue with Google" not in r.text
