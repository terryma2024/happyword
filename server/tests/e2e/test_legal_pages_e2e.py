"""E2E: public legal pages must render HTML without a parent session.

Regression guard for Vercel deployments where templates under
``app/templates/public/`` were omitted from the serverless bundle
(``public`` is reserved for static assets). Pages now live under
``app/templates/legal/``.
"""

import httpx
import pytest


@pytest.mark.e2e
@pytest.mark.parametrize(
    ("path", "title_marker"),
    [
        ("/privacy", "魔法背单词隐私政策"),
        ("/terms", "魔法背单词用户协议"),
        ("/support", "魔法背单词支持"),
    ],
)
def test_legal_pages_render_without_login(
    http: httpx.Client, path: str, title_marker: str
) -> None:
    response = http.get(path)

    assert response.status_code == 200, (
        f"{path} returned {response.status_code}; body preview: {response.text[:200]!r}"
    )
    assert "text/html" in response.headers.get("content-type", "")
    assert title_marker in response.text
    assert "退出登录" not in response.text
