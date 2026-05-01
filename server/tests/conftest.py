from collections.abc import AsyncIterator

import pytest
from beanie import init_beanie
from httpx import ASGITransport, AsyncClient
from mongomock_motor import AsyncMongoMockClient


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("MONGODB_URI", "mongodb://test")
    monkeypatch.setenv("MONGO_DB_NAME", "happyword_test")
    monkeypatch.setenv("JWT_SECRET", "test-secret-32-bytes-please-pad-x")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_USER", "testadmin")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_PASS", "testpw1234")
    monkeypatch.setenv("OPENAI_API_KEY", "")
    # V0.6.1: ensure SMTP is unconfigured in the default test env so
    # GmailSmtpProvider.send no-ops with a warning instead of trying to talk
    # to Gmail. Tests that need to assert email behaviour install a recording
    # provider via dependency injection (see test fixtures).
    monkeypatch.setenv("SMTP_USERNAME", "")
    monkeypatch.setenv("SMTP_PASSWORD", "")
    monkeypatch.setenv("SMTP_FROM_EMAIL", "")
    # ensure each test starts with a fresh Settings cache
    from app.config import get_settings

    get_settings.cache_clear()


@pytest.fixture
async def db() -> AsyncIterator[object]:
    """Beanie-initialized mongomock database for tests."""
    from app.models.category import Category  # noqa: PLC0415
    from app.models.child_profile import ChildProfile  # noqa: PLC0415
    from app.models.device_binding import DeviceBinding  # noqa: PLC0415
    from app.models.email_verification import EmailVerification  # noqa: PLC0415
    from app.models.family import Family  # noqa: PLC0415
    from app.models.family_pack_definition import FamilyPackDefinition  # noqa: PLC0415
    from app.models.family_pack_draft import FamilyPackDraft  # noqa: PLC0415
    from app.models.family_pack_pointer import FamilyPackPointer  # noqa: PLC0415
    from app.models.family_word_pack import FamilyWordPack  # noqa: PLC0415
    from app.models.lesson_import_draft import LessonImportDraft  # noqa: PLC0415
    from app.models.llm_draft import LlmDraft  # noqa: PLC0415
    from app.models.pack_pointer import PackPointer  # noqa: PLC0415
    from app.models.pair_token import PairToken  # noqa: PLC0415
    from app.models.user import User  # noqa: PLC0415 - lazy to avoid early import
    from app.models.word import Word  # noqa: PLC0415
    from app.models.word_pack import WordPack  # noqa: PLC0415

    mock = AsyncMongoMockClient()
    await init_beanie(
        database=mock["happyword_test"],
        document_models=[
            User,
            Word,
            WordPack,
            PackPointer,
            LlmDraft,
            Category,
            LessonImportDraft,
            Family,
            EmailVerification,
            PairToken,
            DeviceBinding,
            ChildProfile,
            FamilyPackDefinition,
            FamilyPackDraft,
            FamilyPackPointer,
            FamilyWordPack,
        ],
    )
    yield mock["happyword_test"]


@pytest.fixture
async def client(db: object) -> AsyncIterator[AsyncClient]:
    from app.main import app  # noqa: PLC0415

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
