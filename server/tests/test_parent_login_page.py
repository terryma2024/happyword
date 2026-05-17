"""Content-presence regression for the parent login page consent UI.

Locks the privacy + terms consent checkbox in place against future
template refactors. Does not depend on any OAuth env var: the consent
markup is unconditional, so the test passes with all OAuth providers
disabled (the default in conftest.py).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from httpx import AsyncClient


@pytest.mark.asyncio
async def test_login_page_renders_privacy_consent_checkbox(
    client: AsyncClient,
) -> None:
    response = await client.get("/family/login")

    assert response.status_code == 200
    body = response.text

    # Checkbox element (id used by the JS gate and the label `for=`).
    assert 'id="privacy-consent"' in body
    assert 'type="checkbox"' in body

    # Both legal docs are linked, opening in a new tab.
    assert 'href="/terms"' in body
    assert 'href="/privacy"' in body
    assert 'target="_blank"' in body
    assert 'rel="noopener noreferrer"' in body

    # Label copy uses the approved Chinese wording with 《》 punctuation.
    assert "我已阅读并同意" in body
    assert "《用户协议》" in body
    assert "《隐私协议》" in body

    # Inline error <p> is present (initially hidden) with the required
    # ARIA live attribute and the approved prompt text.
    assert 'id="privacy-consent-error"' in body
    assert 'role="alert"' in body
    assert 'aria-live="polite"' in body
    assert "请先阅读并同意《用户协议》和《隐私协议》后再继续登录。" in body

    # JS gate marker: the script must reference the checkbox id so we know
    # the interception logic is wired, not just dead markup.
    assert "privacy-consent" in body
    assert "preventDefault" in body
    # OAuth and password-login links are gated by the consent script.
    assert "/v1/oauth/" in body
    assert "/family/login/password" in body
