import pytest

from app.config import Settings


def test_settings_reads_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost:27017")
    monkeypatch.setenv("MONGO_DB_NAME", "happyword_test")
    monkeypatch.setenv("JWT_SECRET", "test-secret-32-bytes-please-pad")
    monkeypatch.setenv("JWT_EXPIRE_HOURS", "24")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_USER", "admin")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_PASS", "pw")

    s = Settings()  # type: ignore[call-arg]

    assert s.mongo_uri == "mongodb://localhost:27017"
    assert s.mongo_db_name == "happyword_test"
    assert s.jwt_secret == "test-secret-32-bytes-please-pad"
    assert s.jwt_expire_hours == 24
    assert s.admin_bootstrap_user == "admin"
    assert s.admin_bootstrap_pass == "pw"


def test_settings_accepts_legacy_mongo_uri_alias(monkeypatch: pytest.MonkeyPatch) -> None:
    """`MONGO_URI` must keep working for developers with existing .env.local files."""
    monkeypatch.delenv("MONGODB_URI", raising=False)
    monkeypatch.setenv("MONGO_URI", "mongodb://legacy:27017")
    monkeypatch.setenv("MONGO_DB_NAME", "happyword_test")
    monkeypatch.setenv("JWT_SECRET", "test-secret-32-bytes-please-pad")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_USER", "admin")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_PASS", "pw")

    s = Settings()  # type: ignore[call-arg]

    assert s.mongo_uri == "mongodb://legacy:27017"


def test_settings_expands_preview_db_from_cli_pr_env(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Fallback CLI previews pass PR metadata through HappyWord-specific env vars."""
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost:27017")
    monkeypatch.setenv("MONGO_DB_NAME", "happyword_pr_{pr}_e2e")
    monkeypatch.setenv("JWT_SECRET", "test-secret-32-bytes-please-pad")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_USER", "admin")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_PASS", "pw")
    monkeypatch.delenv("VERCEL_GIT_PULL_REQUEST_ID", raising=False)
    monkeypatch.setenv("HAPPYWORD_PREVIEW_PR_ID", "45")
    monkeypatch.setenv("HAPPYWORD_PREVIEW_BRANCH", "cursor/devmenu-bypass-secret-automation")

    s = Settings()  # type: ignore[call-arg]

    assert s.mongo_db_name == "happyword_pr_45_e2e"


def test_settings_defaults_when_optional_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    for k in (
        "MONGODB_URI",
        "MONGO_DB_NAME",
        "JWT_SECRET",
        "ADMIN_BOOTSTRAP_USER",
        "ADMIN_BOOTSTRAP_PASS",
    ):
        monkeypatch.setenv(k, "x")
    monkeypatch.delenv("JWT_EXPIRE_HOURS", raising=False)
    monkeypatch.delenv("LOG_LEVEL", raising=False)

    s = Settings()  # type: ignore[call-arg]
    assert s.jwt_expire_hours == 24
    assert s.log_level == "info"


def test_settings_defaults_to_openai_llm_provider(monkeypatch: pytest.MonkeyPatch) -> None:
    for k in (
        "MONGODB_URI",
        "MONGO_DB_NAME",
        "JWT_SECRET",
        "ADMIN_BOOTSTRAP_USER",
        "ADMIN_BOOTSTRAP_PASS",
    ):
        monkeypatch.setenv(k, "x")
    monkeypatch.delenv("LLM_PROVIDER", raising=False)

    s = Settings()  # type: ignore[call-arg]

    assert s.llm_provider == "openai"
    assert s.qwen_model_vision == "qwen3.6-plus"
    assert s.doubao_model_vision == "doubao-seed-2-0-pro-260215"
    assert s.kimi_model_vision == "kimi-k2.6"


def test_settings_accepts_kimi_api_key_alias(monkeypatch: pytest.MonkeyPatch) -> None:
    for k in (
        "MONGODB_URI",
        "MONGO_DB_NAME",
        "JWT_SECRET",
        "ADMIN_BOOTSTRAP_USER",
        "ADMIN_BOOTSTRAP_PASS",
    ):
        monkeypatch.setenv(k, "x")
    monkeypatch.delenv("MOONSHOT_API_KEY", raising=False)
    monkeypatch.setenv("KIMI_API_KEY", "kimi-test-key")

    s = Settings()  # type: ignore[call-arg]

    assert s.moonshot_api_key == "kimi-test-key"
