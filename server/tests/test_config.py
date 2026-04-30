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
