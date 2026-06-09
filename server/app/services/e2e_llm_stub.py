"""Request-scoped deterministic LLM stub for deployed E2E tests.

The stub is disabled unless the server has ``E2E_LLM_STUB_SECRET`` configured
and an individual request sends the matching ``x-happyword-e2e-llm-stub``
header. Production traffic without that header uses the real configured LLM
providers.
"""

from __future__ import annotations

import hashlib
import secrets
from contextvars import ContextVar, Token
from typing import Any

from app.config import get_settings

HEADER_NAME = "x-happyword-e2e-llm-stub"
MODEL_NAME = "e2e-llm-stub"
STUB_URL_PREFIX = "stub://e2e/llm/"

_enabled: ContextVar[bool] = ContextVar("e2e_llm_stub_enabled", default=False)


class E2ELlmStubAuthError(RuntimeError):
    """Raised when a request attempts to use the E2E LLM stub without auth."""


def enabled() -> bool:
    return _enabled.get()


def enable() -> Token[bool]:
    return _enabled.set(True)


def disable(token: Token[bool]) -> None:
    _enabled.reset(token)


def enable_for_header(header_value: str | None) -> Token[bool] | None:
    if not header_value:
        return None
    expected = get_settings().e2e_llm_stub_secret.strip()
    supplied = header_value.strip()
    if not expected or not secrets.compare_digest(supplied, expected):
        raise E2ELlmStubAuthError("Invalid E2E LLM stub header")
    return enable()


def source_image_url(image_bytes: bytes, mime: str) -> str:
    digest = hashlib.sha256(image_bytes).hexdigest()[:16]
    ext = mime.removeprefix("image/") or "jpg"
    return f"{STUB_URL_PREFIX}{digest}.{ext}"


def fetch_image(url: str) -> tuple[bytes, str] | None:
    if enabled() and url.startswith(STUB_URL_PREFIX):
        return b"e2e-llm-stub-image", "image/jpeg"
    return None


def lesson_payload() -> dict[str, Any]:
    return {
        "category_id": "fruit-market",
        "label_en": "Fruit Market",
        "label_zh": "水果集市",
        "story_en": "Apple and banana open a tiny market.",
        "story_zh": "苹果和香蕉开了一间小小集市。",
        "words": [
            {
                "source_no": 1,
                "word": "apple",
                "meaningZh": "苹果",
                "category": "fruit-market",
                "difficulty": 1,
                "example_en": "I eat an apple.",
                "example_zh": "我吃一个苹果。",
            },
            {
                "source_no": 2,
                "word": "banana",
                "meaningZh": "香蕉",
                "category": "fruit-market",
                "difficulty": 1,
                "example_en": "The banana is yellow.",
                "example_zh": "香蕉是黄色的。",
            },
        ],
    }


def scan_payload() -> dict[str, Any]:
    return {
        "words": [
            {"word": "apple", "gloss_zh": "苹果"},
            {"word": "banana", "gloss_zh": "香蕉"},
        ],
        "note": "e2e stub vocabulary list",
    }


def story_payload() -> dict[str, str]:
    return {
        "story_en": "Apple and banana open a tiny market.",
        "story_zh": "苹果和香蕉开了一间小小集市。",
    }


def distractors() -> list[str]:
    return ["pear", "grape", "orange"]


def example_sentence(word: str) -> dict[str, str]:
    target = word.strip().lower() or "apple"
    if target == "apple":
        return {"en": "I eat an apple.", "zh": "我吃一个苹果。"}
    return {"en": f"I can see {target}.", "zh": f"我能看到{target}。"}
