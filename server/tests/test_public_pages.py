from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

import pytest
from bs4 import BeautifulSoup

if TYPE_CHECKING:
    from httpx import AsyncClient


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("path", "expected"),
    [
        ("/privacy", "魔法背单词隐私政策"),
        ("/terms", "魔法背单词用户协议"),
        ("/support", "魔法背单词支持"),
        ("/report_and_appeal", "投诉与举报入口"),
    ],
)
async def test_public_store_pages_are_reachable_without_login(
    client: AsyncClient, path: str, expected: str
) -> None:
    response = await client.get(path)

    assert response.status_code == 200
    assert expected in response.text
    assert "退出登录" not in response.text


@pytest.mark.asyncio
async def test_report_and_appeal_page_includes_contact_email(client: AsyncClient) -> None:
    response = await client.get("/report_and_appeal")

    assert response.status_code == 200
    assert "matianyi2023@gmail.com" in response.text
    assert "投诉" in response.text
    assert "举报" in response.text


@pytest.mark.asyncio
async def test_public_pages_include_icp_footer(client: AsyncClient) -> None:
    response = await client.get("/privacy")

    assert response.status_code == 200
    assert "沪ICP备2026023209号-1" in response.text
    assert 'href="https://beian.miit.gov.cn/"' in response.text


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "path",
    ["/privacy", "/terms", "/report_and_appeal"],
)
async def test_legal_pages_match_landing_visual_shell(client: AsyncClient, path: str) -> None:
    response = await client.get(path)

    assert response.status_code == 200
    soup = BeautifulSoup(response.text, "html.parser")

    assert soup.find("link", href=lambda value: value and value.startswith("/static/landing.css"))
    assert soup.find("main", attrs={"data-page": "legal"}) is not None
    assert soup.find("article", class_="legal-panel") is not None

    brand = soup.find("a", class_="brand")
    assert brand is not None
    assert brand["href"] == "/"
    assert "魔法背单词" in brand.get_text(" ", strip=True)


@pytest.mark.asyncio
async def test_features_page_uses_ios_screenshots(client: AsyncClient) -> None:
    response = await client.get("/features")

    assert response.status_code == 200
    assert "功能介绍" in response.text
    assert "iOS 实机截图" in response.text
    assert "feature-ios-battle.png" in response.text
    assert "feature-ios-parent-admin.png" in response.text
    assert "https://apps.apple.com/cn/app/%E9%AD%94%E6%B3%95%E8%83%8C%E5%8D%95%E8%AF%8D/id6768499286" in response.text
    assert "沪ICP备2026023209号-1" in response.text

    soup = BeautifulSoup(response.text, "html.parser")
    assert soup.find("main", attrs={"data-page": "features"}) is not None
    assert soup.find("a", href="/") is not None
    screenshot_images = soup.find_all("img", attrs={"data-ios-screenshot": "true"})
    assert len(screenshot_images) >= 4
    battle_image = soup.find("img", src=lambda value: value and value.startswith("/static/feature-ios-battle.png"))
    parent_admin_image = soup.find(
        "img",
        src=lambda value: value and value.startswith("/static/feature-ios-parent-admin.png"),
    )
    assert battle_image["width"] == "2472"
    assert battle_image["height"] == "1206"
    assert parent_admin_image["width"] == "1206"
    assert parent_admin_image["height"] == "2622"


@pytest.mark.asyncio
async def test_features_page_includes_extended_ios_screenshots(client: AsyncClient) -> None:
    response = await client.get("/features")

    assert response.status_code == 200
    soup = BeautifulSoup(response.text, "html.parser")

    assert "计划、报告和打卡" in response.text
    assert "图鉴和愿望单" in response.text

    expected_images = {
        "feature-ios-study-plan.jpg": ("1206", "2622"),
        "feature-ios-learning-report.jpg": ("1206", "2622"),
        "feature-ios-checkin-calendar.jpg": ("1206", "2622"),
        "feature-ios-spellbook-codex.jpg": ("2622", "1206"),
        "feature-ios-monster-codex.jpg": ("2622", "1206"),
        "feature-ios-magic-wishlist.jpg": ("2622", "1206"),
    }
    for filename, (width, height) in expected_images.items():
        image = soup.find("img", src=lambda value: value and f"/static/{filename}" in value)
        assert image is not None, filename
        assert image["width"] == width
        assert image["height"] == height
        assert image["data-ios-screenshot"] == "true"

        static_path = Path(__file__).resolve().parents[1] / f"app/static/{filename}"
        source_path = Path(__file__).resolve().parents[2] / f"assets/screenshots/ios/{filename}"
        assert static_path.exists()
        assert source_path.exists()


@pytest.mark.asyncio
async def test_features_page_uses_restrained_heading_scale(client: AsyncClient) -> None:
    response = await client.get("/features")

    assert response.status_code == 200
    css = (Path(__file__).resolve().parents[1] / "app/static/features.css").read_text()
    assert "clamp(3rem, 6vw, 5.4rem)" in css
    assert "clamp(1.85rem, 3.2vw, 3.2rem)" in css
    assert "clamp(4rem, 9vw, 8.4rem)" not in css
    assert "clamp(2.2rem, 5vw, 5.1rem)" not in css


@pytest.mark.asyncio
async def test_privacy_page_matches_current_cloudbase_stack(client: AsyncClient) -> None:
    response = await client.get("/privacy")

    assert response.status_code == 200
    assert "最后更新：2026-06-03" in response.text
    assert "腾讯云 CloudBase Run" in response.text
    assert "腾讯 COS" in response.text
    assert "上海 Lighthouse MongoDB" in response.text
    assert "通义千问（Qwen）视觉能力" in response.text
    assert "Vercel 托管和对象存储" not in response.text
    assert "OpenAI 视觉能力" not in response.text
